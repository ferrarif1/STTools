package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

type Item struct {
	ID        string
	Name      string
	Desc      string
	Expected  string
	CanApply  bool
	CheckFunc func() Result
	ApplyFunc func() error
}

type Result struct {
	Status  string `json:"status"`
	Current string `json:"current"`
}

type OutputItem struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Desc     string `json:"description"`
	Expected string `json:"expected"`
	CanApply bool   `json:"can_apply"`
	Status   string `json:"status"`
	Current  string `json:"current"`
}

type Output struct {
	OS    string       `json:"os"`
	Items []OutputItem `json:"items"`
}

type OSInfo struct {
	ID      string
	Name    string
	Version string
	Pretty  string
	IDLike  string
}

func main() {
	var (
		flagCheck    = flag.Bool("check", false, "执行全部基线检查")
		flagApply    = flag.String("apply", "", "应用指定基线项")
		flagApplyAll = flag.Bool("apply-all", false, "应用所有可设置项")
		flagCheckFix = flag.Bool("check-fix", false, "检查后按提示修复失败项")
		flagList     = flag.Bool("list", false, "列出基线项")
		flagJSON     = flag.Bool("json", false, "JSON输出")
		flagOutput   = flag.String("output", "", "输出到文件")
	)
	flag.Parse()

	if runtime.GOOS != "linux" {
		fmt.Fprintln(os.Stderr, "仅支持Linux系统运行")
		os.Exit(1)
	}

	items := buildItems()

	if *flagList {
		for _, item := range items {
			fmt.Printf("%s\t%s\n", item.ID, item.Name)
		}
		return
	}

	if *flagCheck {
		runCheck(items, *flagJSON, *flagOutput)
		return
	}

	if *flagCheckFix {
		if err := checkAndRepair(items); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		return
	}

	if *flagApply != "" {
		if err := applyOne(items, *flagApply); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		return
	}

	if *flagApplyAll {
		if err := applyAll(items); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		return
	}

	printHelp()
}

func printHelp() {
	fmt.Println("用法:")
	fmt.Println("  xc-baseline-go --check [--json] [--output FILE]")
	fmt.Println("  xc-baseline-go --check-fix")
	fmt.Println("  xc-baseline-go --apply ITEM_ID")
	fmt.Println("  xc-baseline-go --apply-all")
	fmt.Println("  xc-baseline-go --list")
}

func buildItems() []Item {
	return []Item{
		{
			ID:        "ftp_service",
			Name:      "FTP服务禁用",
			Desc:      "检查是否存在FTP服务运行，基线要求禁用。",
			Expected:  "FTP服务未运行且已禁用",
			CanApply:  true,
			CheckFunc: checkFTPService,
			ApplyFunc: applyFTPService,
		},
		{
			ID:        "nic_info",
			Name:      "网卡信息检查",
			Desc:      "展示当前网卡与IP信息。",
			Expected:  "仅展示信息",
			CanApply:  false,
			CheckFunc: checkNICInfo,
		},
		{
			ID:        "risky_ports",
			Name:      "高危端口状态检测",
			Desc:      "检测22/23/135/137/138/139/445/455/3389/4899监听状态。",
			Expected:  "无高危端口监听",
			CanApply:  false,
			CheckFunc: checkRiskyPorts,
		},
		{
			ID:        "ipv6_disabled",
			Name:      "IPv6禁用状态",
			Desc:      "检查IPv6禁用是否生效。",
			Expected:  "IPv6已禁用",
			CanApply:  true,
			CheckFunc: checkIPv6Disabled,
			ApplyFunc: applyIPv6Disabled,
		},
		{
			ID:        "patch_updates",
			Name:      "高危漏洞修复",
			Desc:      "检测系统更新状态（离线环境基于本地缓存判断）。",
			Expected:  "无待更新补丁",
			CanApply:  false,
			CheckFunc: checkPatchUpdates,
		},
		{
			ID:        "password_policy",
			Name:      "密码策略",
			Desc:      "检查密码最小长度/复杂度/有效期策略。",
			Expected:  "最小长度>=8，最短1天，最长90天，复杂度开启",
			CanApply:  true,
			CheckFunc: checkPasswordPolicy,
			ApplyFunc: applyPasswordPolicy,
		},
		{
			ID:        "guest_user",
			Name:      "Guest用户状态",
			Desc:      "检查guest账号是否禁用。",
			Expected:  "guest账号不存在或已锁定",
			CanApply:  true,
			CheckFunc: checkGuestUser,
			ApplyFunc: applyGuestUser,
		},
		{
			ID:        "usb_autoplay",
			Name:      "U盘自动播放",
			Desc:      "检查桌面环境自动挂载/自动打开策略。",
			Expected:  "自动挂载/自动打开关闭",
			CanApply:  true,
			CheckFunc: checkUSBAutoplay,
			ApplyFunc: applyUSBAutoplay,
		},
		{
			ID:        "chrome_version",
			Name:      "浏览器版本检测",
			Desc:      "检测Chrome/Chromium版本。",
			Expected:  "仅展示信息",
			CanApply:  false,
			CheckFunc: checkChromeVersion,
		},
		{
			ID:        "lock_screen",
			Name:      "锁屏策略",
			Desc:      "检查锁屏开启与自动锁定时间。",
			Expected:  "锁屏启用，空闲15分钟内锁定",
			CanApply:  true,
			CheckFunc: checkLockScreen,
			ApplyFunc: applyLockScreen,
		},
	}
}

func runCheck(items []Item, jsonOut bool, outputFile string) {
	results := make([]OutputItem, 0, len(items))
	for _, item := range items {
		res := item.CheckFunc()
		results = append(results, OutputItem{
			ID:       item.ID,
			Name:     item.Name,
			Desc:     item.Desc,
			Expected: item.Expected,
			CanApply: item.CanApply,
			Status:   res.Status,
			Current:  res.Current,
		})
	}

	var out io.Writer = os.Stdout
	if outputFile != "" {
		file, err := os.Create(outputFile)
		if err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		defer file.Close()
		out = file
	}

	if jsonOut {
		payload := Output{OS: readOSRelease(), Items: results}
		enc := json.NewEncoder(out)
		enc.SetEscapeHTML(false)
		enc.SetIndent("", "  ")
		if err := enc.Encode(payload); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
		}
		return
	}

	fmt.Fprintf(out, "系统识别: %s\n\n", readOSRelease())
	for _, item := range results {
		name := item.Name
		if item.Status == "fail" {
			name = colorize("red", name)
		}
		fmt.Fprintf(out, "[%s] %s\n- 结果: %s\n- 当前: %s\n- 期望: %s\n",
			item.ID, name, item.Status, item.Current, item.Expected)
		if item.Status == "fail" {
			if hint := manualFixHint(item.ID); hint != "" {
				fmt.Fprintf(out, "- 手动修复参考: %s\n", hint)
			}
		}
		fmt.Fprintln(out)
	}
}

func checkAndRepair(items []Item) error {
	if os.Geteuid() != 0 {
		return errors.New("需要root权限执行设置操作")
	}

	results := make(map[string]Result, len(items))
	for _, item := range items {
		results[item.ID] = item.CheckFunc()
	}

	failItems := []Item{}
	for _, item := range items {
		res := results[item.ID]
		if res.Status == "fail" && item.CanApply && item.ApplyFunc != nil {
			failItems = append(failItems, item)
		}
	}

	if len(failItems) == 0 {
		fmt.Println("未发现需要修复的基线项。")
		return nil
	}

	fmt.Println("需要修复的基线项：")
	for _, item := range failItems {
		fmt.Printf("- %s (%s)\n", colorize("red", item.Name), item.ID)
		hint := manualFixHint(item.ID)
		if hint != "" {
			fmt.Printf("  手动修复参考：%s\n", hint)
		}
	}
	fmt.Println()

	reader := bufio.NewReader(os.Stdin)
	applyRest := false

	for _, item := range failItems {
		if applyRest {
			_ = item.ApplyFunc()
			continue
		}

		for {
			fmt.Printf("是否修复[%s] %s ? (y/n/all): ", item.ID, item.Name)
			input, _ := reader.ReadString('\n')
			answer := strings.TrimSpace(input)
			switch strings.ToLower(answer) {
			case "y":
				_ = item.ApplyFunc()
				goto nextItem
			case "n":
				goto nextItem
			case "all":
				fmt.Print("确认要对剩余所有可设置项执行吗？(y/n): ")
				input, _ := reader.ReadString('\n')
				confirm := strings.TrimSpace(input)
				if strings.EqualFold(confirm, "y") {
					applyRest = true
					_ = item.ApplyFunc()
				}
				goto nextItem
			default:
				fmt.Println("请输入 y / n / all")
			}
		}

	nextItem:
	}

	fmt.Println("修复流程已完成。")
	return nil
}

func applyOne(items []Item, id string) error {
	item, ok := findItem(items, id)
	if !ok {
		return fmt.Errorf("未找到基线项: %s", id)
	}
	if !item.CanApply || item.ApplyFunc == nil {
		return fmt.Errorf("该项仅检查，不支持设置: %s", id)
	}
	if os.Geteuid() != 0 {
		return errors.New("需要root权限执行设置操作")
	}
	if err := item.ApplyFunc(); err != nil {
		return err
	}
	fmt.Printf("已应用: %s\n", id)
	return nil
}

func applyAll(items []Item) error {
	if os.Geteuid() != 0 {
		return errors.New("需要root权限执行设置操作")
	}
	applyRest := false
	reader := bufio.NewReader(os.Stdin)

	for _, item := range items {
		if !item.CanApply || item.ApplyFunc == nil {
			continue
		}
		if applyRest {
			_ = item.ApplyFunc()
			continue
		}

		for {
			fmt.Printf("是否应用[%s] %s ? (y/n/all): ", item.ID, item.Name)
			input, _ := reader.ReadString('\n')
			answer := strings.TrimSpace(input)
			switch strings.ToLower(answer) {
			case "y":
				_ = item.ApplyFunc()
				goto nextItem
			case "n":
				goto nextItem
			case "all":
				fmt.Print("确认要对剩余所有可设置项执行吗？(y/n): ")
				input, _ := reader.ReadString('\n')
				confirm := strings.TrimSpace(input)
				if strings.EqualFold(confirm, "y") {
					applyRest = true
					_ = item.ApplyFunc()
				}
				goto nextItem
			default:
				fmt.Println("请输入 y / n / all")
			}
		}

	nextItem:
	}
	fmt.Println("已完成可设置项处理")
	return nil
}

func findItem(items []Item, id string) (Item, bool) {
	for _, item := range items {
		if item.ID == id {
			return item, true
		}
	}
	return Item{}, false
}

func readOSRelease() string {
	info := detectOSInfo()
	if info.Pretty != "" {
		return info.Pretty
	}
	if info.Name != "" {
		return info.Name
	}
	return "Linux"
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func runCommand(name string, args ...string) (string, int) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return strings.TrimSpace(string(out)), exitErr.ExitCode()
		}
		return strings.TrimSpace(string(out)), 1
	}
	return strings.TrimSpace(string(out)), 0
}

func checkFTPService() Result {
	services := []string{"vsftpd", "proftpd", "pure-ftpd", "ftpd"}
	active := []string{}
	if commandExists("systemctl") {
		for _, svc := range services {
			out, code := runCommand("systemctl", "is-active", svc)
			if code == 0 && strings.TrimSpace(out) == "active" {
				active = append(active, svc)
			}
		}
	} else if commandExists("pgrep") {
		for _, svc := range services {
			_, code := runCommand("pgrep", "-x", svc)
			if code == 0 {
				active = append(active, svc)
			}
		}
	}
	if len(active) == 0 {
		return Result{Status: "pass", Current: "未发现运行中的FTP服务"}
	}
	return Result{Status: "fail", Current: "运行中: " + strings.Join(active, ", ")}
}

func checkNICInfo() Result {
	if commandExists("ip") {
		out, _ := runCommand("ip", "-o", "addr", "show")
		if out == "" {
			out = "未获取到网卡信息"
		}
		out = strings.ReplaceAll(out, "\n", "; ")
		return Result{Status: "info", Current: out}
	}
	return Result{Status: "manual", Current: "缺少ip命令，无法获取"}
}

func checkRiskyPorts() Result {
	var out string
	if commandExists("ss") {
		out, _ = runCommand("ss", "-lntp")
	} else if commandExists("netstat") {
		out, _ = runCommand("netstat", "-lntp")
	}
	ports := parseListeningPorts(out)
	risky := []int{22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899}
	opened := []int{}
	for _, p := range risky {
		if ports[p] {
			opened = append(opened, p)
		}
	}
	firewallStatus, missingBlocks := checkFirewallBlocks(risky)
	status := "pass"
	details := []string{}
	if len(opened) > 0 {
		status = "fail"
		parts := []string{}
		for _, p := range opened {
			parts = append(parts, fmt.Sprintf("%d", p))
		}
		details = append(details, "监听端口: "+strings.Join(parts, ", "))
	} else {
		details = append(details, "无高危端口监听")
	}
	if firewallStatus == "absent" {
		status = "fail"
		details = append(details, "防火墙未启用")
	} else if len(missingBlocks) > 0 {
		status = "fail"
		details = append(details, "未封禁: "+strings.Join(missingBlocks, ", "))
	} else {
		details = append(details, "高危端口已配置封禁策略")
	}
	return Result{Status: status, Current: strings.Join(details, " | ")}
}

func parseListeningPorts(output string) map[int]bool {
	ports := make(map[int]bool)
	re := regexp.MustCompile(`:(\d+)\s`)
	for _, line := range strings.Split(output, "\n") {
		match := re.FindStringSubmatch(line)
		if len(match) == 2 {
			var p int
			fmt.Sscanf(match[1], "%d", &p)
			if p > 0 {
				ports[p] = true
			}
		}
	}
	return ports
}

func checkFirewallBlocks(ports []int) (string, []string) {
	if commandExists("firewall-cmd") && isServiceActive("firewalld") {
		return checkFirewalldBlocks(ports)
	}
	if commandExists("nft") {
		return checkNftBlocks(ports)
	}
	if commandExists("iptables") {
		return checkIptablesBlocks(ports)
	}
	return "absent", portsToProtoList(ports)
}

func isServiceActive(service string) bool {
	if !commandExists("systemctl") {
		return false
	}
	out, code := runCommand("systemctl", "is-active", service)
	return code == 0 && strings.TrimSpace(out) == "active"
}

func checkFirewalldBlocks(ports []int) (string, []string) {
	missing := []string{}
	richRules, _ := runCommand("firewall-cmd", "--list-rich-rules")
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			if firewalldPortAllowed(port, proto) {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
				missing = append(missing, fmt.Sprintf("%d/%s(out)", port, proto))
				continue
			}
			if !firewalldHasDenyRule(richRules, port, proto, "in") {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
			}
			if !firewalldHasDenyRule(richRules, port, proto, "out") {
				missing = append(missing, fmt.Sprintf("%d/%s(out)", port, proto))
			}
		}
	}
	return "firewalld", dedupeStrings(missing)
}

func firewalldPortAllowed(port int, proto string) bool {
	out, _ := runCommand("firewall-cmd", "--query-port", fmt.Sprintf("%d/%s", port, proto))
	return strings.TrimSpace(out) == "yes"
}

func firewalldHasDenyRule(rules string, port int, proto string, direction string) bool {
	dir := ""
	if direction == "out" {
		dir = `direction="out".*`
	}
	patterns := []string{
		fmt.Sprintf(`%sport port="%d" protocol="%s".*reject`, dir, port, proto),
		fmt.Sprintf(`%sport port="%d" protocol="%s".*drop`, dir, port, proto),
		fmt.Sprintf(`%sport port="%d" protocol="%s".*deny`, dir, port, proto),
	}
	for _, p := range patterns {
		re := regexp.MustCompile(p)
		if re.MatchString(rules) {
			return true
		}
	}
	return false
}

func checkIptablesBlocks(ports []int) (string, []string) {
	inputRules, _ := runCommand("iptables", "-S", "INPUT")
	outputRules, _ := runCommand("iptables", "-S", "OUTPUT")
	missing := []string{}
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			if !iptablesHasDrop(inputRules, port, proto) {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
			}
			if !iptablesHasDrop(outputRules, port, proto) {
				missing = append(missing, fmt.Sprintf("%d/%s(out)", port, proto))
			}
		}
	}
	return "iptables", dedupeStrings(missing)
}

func iptablesHasDrop(rules string, port int, proto string) bool {
	patterns := []string{
		fmt.Sprintf(`-p %s .*--dport %d .* -j DROP`, proto, port),
		fmt.Sprintf(`-p %s .*--dport %d .* -j REJECT`, proto, port),
	}
	for _, p := range patterns {
		re := regexp.MustCompile(p)
		if re.MatchString(rules) {
			return true
		}
	}
	return false
}

func checkNftBlocks(ports []int) (string, []string) {
	out, code := runCommand("nft", "list", "ruleset")
	if code != 0 {
		return "nftables", portsToProtoList(ports)
	}
	missing := []string{}
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			if !nftHasDrop(out, port, proto, "in") {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
			}
			if !nftHasDrop(out, port, proto, "out") {
				missing = append(missing, fmt.Sprintf("%d/%s(out)", port, proto))
			}
		}
	}
	return "nftables", dedupeStrings(missing)
}

func nftHasDrop(rules string, port int, proto string, direction string) bool {
	chainHint := "input"
	if direction == "out" {
		chainHint = "output"
	}
	patterns := []string{
		fmt.Sprintf(`(?s)chain %s.*%s dport %d .* drop`, chainHint, proto, port),
		fmt.Sprintf(`(?s)chain %s.*%s dport %d .* reject`, chainHint, proto, port),
		fmt.Sprintf(`(?s)chain %s.*%s dport \\{[^}]*%d[^}]*\\} .* drop`, chainHint, proto, port),
		fmt.Sprintf(`(?s)chain %s.*%s dport \\{[^}]*%d[^}]*\\} .* reject`, chainHint, proto, port),
	}
	for _, p := range patterns {
		re := regexp.MustCompile(p)
		if re.MatchString(rules) {
			return true
		}
	}
	return false
}

func portsToProtoList(ports []int) []string {
	list := []string{}
	for _, port := range ports {
		list = append(list, fmt.Sprintf("%d/tcp(in)", port))
		list = append(list, fmt.Sprintf("%d/udp(in)", port))
		list = append(list, fmt.Sprintf("%d/tcp(out)", port))
		list = append(list, fmt.Sprintf("%d/udp(out)", port))
	}
	return list
}

func dedupeStrings(items []string) []string {
	seen := make(map[string]struct{})
	out := []string{}
	for _, item := range items {
		if _, ok := seen[item]; ok {
			continue
		}
		seen[item] = struct{}{}
		out = append(out, item)
	}
	return out
}

func checkIPv6Disabled() Result {
	data, err := os.ReadFile("/proc/sys/net/ipv6/conf/all/disable_ipv6")
	if err != nil {
		return Result{Status: "manual", Current: "无法读取IPv6状态"}
	}
	value := strings.TrimSpace(string(data))
	if value == "1" {
		return Result{Status: "pass", Current: "disable_ipv6=1"}
	}
	return Result{Status: "fail", Current: "disable_ipv6=" + value}
}

func checkPatchUpdates() Result {
	if commandExists("apt-get") {
		out, _ := runCommand("apt-get", "-s", "upgrade")
		if count, ok := parseAptUpgradeCount(out); ok {
			return parseUpgradeCount(count)
		}
		return Result{Status: "manual", Current: "无法解析更新数量"}
	}
	if commandExists("dnf") {
		_, code := runCommand("dnf", "check-update")
		switch code {
		case 0:
			return Result{Status: "pass", Current: "dnf check-update"}
		case 100:
			return Result{Status: "fail", Current: "dnf有可更新包"}
		default:
			return Result{Status: "manual", Current: "dnf检查失败"}
		}
	}
	if commandExists("yum") {
		_, code := runCommand("yum", "check-update")
		switch code {
		case 0:
			return Result{Status: "pass", Current: "yum check-update"}
		case 100:
			return Result{Status: "fail", Current: "yum有可更新包"}
		default:
			return Result{Status: "manual", Current: "yum检查失败"}
		}
	}
	return Result{Status: "manual", Current: "未检测到包管理器"}
}

func parseAptUpgradeCount(output string) (int, bool) {
	patterns := []string{
		`(?i)(\d+)\s+upgraded`,
		`(?i)(\d+)\s*升级`,
		`(?i)(\d+)\s*更新`,
	}
	for _, pattern := range patterns {
		re := regexp.MustCompile(pattern)
		match := re.FindStringSubmatch(output)
		if len(match) == 2 {
			return toInt(match[1]), true
		}
	}
	return 0, false
}

func parseUpgradeCount(count int) Result {
	if count == 0 {
		return Result{Status: "pass", Current: "待更新数量: 0"}
	}
	return Result{Status: "fail", Current: fmt.Sprintf("待更新数量: %d", count)}
}

func checkPasswordPolicy() Result {
	data, err := os.ReadFile("/etc/login.defs")
	if err != nil {
		return Result{Status: "manual", Current: "缺少/etc/login.defs"}
	}
	maxDays := parseLoginDefsAny(string(data), []string{"PASS_MAX_DAYS", "MAX_DAYS", "MAX"})
	minDays := parseLoginDefsAny(string(data), []string{"PASS_MIN_DAYS", "MIN_DAYS", "MIN"})
	minLen := parseLoginDefsAny(string(data), []string{"PASS_MIN_LEN", "MIN_LEN", "LEN"})
	pwqMinLen := ""
	pwqMinClass := ""
	if minLen == "" {
		pwqMinLen, pwqMinClass = readPwqualityConfig()
	}
	pamFile := "/etc/pam.d/system-auth"
	if _, err := os.Stat("/etc/pam.d/common-password"); err == nil {
		pamFile = "/etc/pam.d/common-password"
	}
	pamData, _ := os.ReadFile(pamFile)
	pamContent := string(pamData)
	pwquality := strings.Contains(pamContent, "pam_pwquality.so") || strings.Contains(pamContent, "pam_cracklib.so")
	if minLen == "" && pwqMinLen == "" {
		if val := parsePamValue(pamContent, "minlen"); val != "" {
			pwqMinLen = val
		}
	}
	if pwqMinClass == "" {
		if val := parsePamValue(pamContent, "minclass"); val != "" {
			pwqMinClass = val
		}
	}
	if minLen == "" {
		minLen = pwqMinLen
	}

	status := "pass"
	issues := []string{}
	if maxDays == "" || toInt(maxDays) > 90 {
		status = "fail"
		issues = append(issues, "PASS_MAX_DAYS")
	}
	if minDays == "" || toInt(minDays) < 1 {
		status = "fail"
		issues = append(issues, "PASS_MIN_DAYS")
	}
	if minLen == "" || toInt(minLen) < 8 {
		status = "fail"
		issues = append(issues, "PASS_MIN_LEN")
	}
	if !pwquality || (pwqMinClass != "" && toInt(pwqMinClass) < 3) {
		status = "fail"
		issues = append(issues, "PAM复杂度")
	}
	current := fmt.Sprintf("MAX=%s, MIN=%s, LEN=%s, PAM=%s", valueOrNA(maxDays), valueOrNA(minDays), valueOrNA(minLen), boolToStr(pwquality))
	if pwqMinClass != "" {
		current += fmt.Sprintf(", MINCLASS=%s", pwqMinClass)
	}
	if len(issues) > 0 {
		current += " | 缺失: " + strings.Join(issues, ", ")
	}
	return Result{Status: status, Current: current}
}

func parseLoginDefs(data, key string) string {
	re := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `\s+(\d+)`)
	match := re.FindStringSubmatch(data)
	if len(match) == 2 {
		return match[1]
	}
	return ""
}

func parseLoginDefsAny(data string, keys []string) string {
	for _, key := range keys {
		if value := parseLoginDefs(data, key); value != "" {
			return value
		}
	}
	return ""
}

func loginDefsKeys(content string) (string, string, string) {
	if content == "" {
		return "PASS_MAX_DAYS", "PASS_MIN_DAYS", "PASS_MIN_LEN"
	}
	if regexp.MustCompile(`(?m)^PASS_MAX_DAYS\b`).MatchString(content) {
		return "PASS_MAX_DAYS", "PASS_MIN_DAYS", "PASS_MIN_LEN"
	}
	maxKey := firstMatchKey(content, []string{"MAX_DAYS", "MAX"})
	minKey := firstMatchKey(content, []string{"MIN_DAYS", "MIN"})
	lenKey := firstMatchKey(content, []string{"MIN_LEN", "LEN"})
	if maxKey == "" {
		maxKey = "PASS_MAX_DAYS"
	}
	if minKey == "" {
		minKey = "PASS_MIN_DAYS"
	}
	if lenKey == "" {
		lenKey = "PASS_MIN_LEN"
	}
	return maxKey, minKey, lenKey
}

func firstMatchKey(content string, keys []string) string {
	for _, key := range keys {
		if regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `\b`).MatchString(content) {
			return key
		}
	}
	return ""
}

func readPwqualityConfig() (string, string) {
	content, err := os.ReadFile("/etc/security/pwquality.conf")
	if err != nil {
		return "", ""
	}
	lines := strings.Split(string(content), "\n")
	minlen := ""
	minclass := ""
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		switch key {
		case "minlen":
			minlen = val
		case "minclass":
			minclass = val
		}
	}
	return minlen, minclass
}

func parsePamValue(content, key string) string {
	re := regexp.MustCompile(key + `=([0-9]+)`)
	match := re.FindStringSubmatch(content)
	if len(match) == 2 {
		return match[1]
	}
	return ""
}

func ensurePwqualityConfig(minlen, minclass string) error {
	path := "/etc/security/pwquality.conf"
	if err := replaceOrAppendKV(path, "minlen", minlen, true); err != nil {
		return err
	}
	if err := replaceOrAppendKV(path, "minclass", minclass, true); err != nil {
		return err
	}
	return nil
}

func checkGuestUser() Result {
	if !commandExists("getent") {
		return Result{Status: "manual", Current: "缺少getent命令"}
	}
	out, code := runCommand("getent", "passwd", "guest")
	if code != 0 || out == "" {
		return Result{Status: "pass", Current: "guest不存在"}
	}
	parts := strings.Split(out, ":")
	shell := ""
	if len(parts) >= 7 {
		shell = parts[6]
	}
	locked := "unknown"
	if commandExists("passwd") {
		status, _ := runCommand("passwd", "-S", "guest")
		fields := strings.Fields(status)
		if len(fields) >= 2 {
			locked = fields[1]
		}
	}
	if strings.Contains(shell, "nologin") {
		return Result{Status: "pass", Current: fmt.Sprintf("guest存在, shell=%s, locked=%s", shell, locked)}
	}
	return Result{Status: "fail", Current: fmt.Sprintf("guest存在, shell=%s, locked=%s", shell, locked)}
}

func checkUSBAutoplay() Result {
	config := "/etc/dconf/db/local.d/00-xc-baseline"
	data, err := os.ReadFile(config)
	if err != nil {
		return Result{Status: "manual", Current: "未发现dconf配置"}
	}
	content := string(data)
	automount := strings.Contains(content, "automount=false")
	automountOpen := strings.Contains(content, "automount-open=false")
	if automount && automountOpen {
		return Result{Status: "pass", Current: "automount=false, automount-open=false"}
	}
	return Result{Status: "fail", Current: fmt.Sprintf("automount=%t, automount-open=%t", automount, automountOpen)}
}

func checkChromeVersion() Result {
	candidates := []string{"google-chrome", "chromium", "chromium-browser"}
	for _, bin := range candidates {
		if commandExists(bin) {
			out, _ := runCommand(bin, "--version")
			if out == "" {
				out = bin + "已安装"
			}
			return Result{Status: "info", Current: out}
		}
	}
	return Result{Status: "info", Current: "未安装Chrome/Chromium"}
}

func checkLockScreen() Result {
	config := "/etc/dconf/db/local.d/00-xc-baseline"
	data, err := os.ReadFile(config)
	if err != nil {
		return checkLockScreenGsettings()
	}
	content := string(data)
	lockEnabled := strings.Contains(content, "lock-enabled=true")
	idleDelayRaw := findConfigValue(content, "idle-delay")
	lockDelayRaw := findConfigValue(content, "lock-delay")
	idleDelayNum, idleOK := parseTrailingInt(idleDelayRaw)
	lockDelayNum, lockOK := parseTrailingInt(lockDelayRaw)
	if lockEnabled && idleOK && idleDelayNum <= 900 && lockOK && lockDelayNum == 0 {
		return Result{Status: "pass", Current: fmt.Sprintf("lock-enabled=true, idle-delay=%s, lock-delay=%s", valueOrNA(idleDelayRaw), valueOrNA(lockDelayRaw))}
	}
	fallback := checkLockScreenGsettings()
	if fallback.Status != "manual" {
		return fallback
	}
	return Result{Status: "fail", Current: fmt.Sprintf("lock-enabled=%t, idle-delay=%s, lock-delay=%s", lockEnabled, valueOrNA(idleDelayRaw), valueOrNA(lockDelayRaw))}
}

func findConfigValue(content, key string) string {
	re := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `\s*=\s*(.+)$`)
	matches := re.FindAllStringSubmatch(content, -1)
	if len(matches) > 0 {
		return strings.TrimSpace(matches[len(matches)-1][1])
	}
	return ""
}

func parseTrailingInt(s string) (int, bool) {
	re := regexp.MustCompile(`(\d+)\s*$`)
	match := re.FindStringSubmatch(strings.TrimSpace(s))
	if len(match) == 2 {
		return toInt(match[1]), true
	}
	return 0, false
}

func checkLockScreenGsettings() Result {
	if !commandExists("gsettings") {
		return Result{Status: "manual", Current: "未发现dconf配置"}
	}
	type schemaSet struct {
		SessionSchema string
		ScreensSchema string
	}
	candidates := []schemaSet{
		{SessionSchema: "org.gnome.desktop.session", ScreensSchema: "org.gnome.desktop.screensaver"},
		{SessionSchema: "org.ukui.session", ScreensSchema: "org.ukui.screensaver"},
	}
	for _, cand := range candidates {
		idleRaw, okIdle := gsettingsGet(cand.SessionSchema, "idle-delay")
		lockEnabledRaw, okLock := gsettingsGet(cand.ScreensSchema, "lock-enabled")
		lockDelayRaw, okDelay := gsettingsGet(cand.ScreensSchema, "lock-delay")
		if !okIdle || !okLock || !okDelay {
			continue
		}
		idleNum, idleOK := parseTrailingInt(idleRaw)
		lockDelayNum, lockOK := parseTrailingInt(lockDelayRaw)
		lockEnabled := strings.TrimSpace(lockEnabledRaw) == "true"
		if lockEnabled && idleOK && idleNum <= 900 && lockOK && lockDelayNum == 0 {
			return Result{Status: "pass", Current: fmt.Sprintf("lock-enabled=true, idle-delay=%s, lock-delay=%s", valueOrNA(idleRaw), valueOrNA(lockDelayRaw))}
		}
		return Result{Status: "fail", Current: fmt.Sprintf("lock-enabled=%t, idle-delay=%s, lock-delay=%s", lockEnabled, valueOrNA(idleRaw), valueOrNA(lockDelayRaw))}
	}
	return Result{Status: "manual", Current: "未发现dconf配置"}
}

func gsettingsGet(schema, key string) (string, bool) {
	out, code := runCommand("gsettings", "get", schema, key)
	if code != 0 {
		return "", false
	}
	return strings.TrimSpace(out), true
}

func applyFTPService() error {
	services := []string{"vsftpd", "proftpd", "pure-ftpd", "ftpd"}
	for _, svc := range services {
		if commandExists("systemctl") {
			_, _ = runCommand("systemctl", "stop", svc)
			_, _ = runCommand("systemctl", "disable", svc)
		} else if commandExists("service") {
			_, _ = runCommand("service", svc, "stop")
		}
	}
	return nil
}

func applyIPv6Disabled() error {
	path := "/etc/sysctl.d/99-xc-baseline.conf"
	lines := readLines(path)
	lines = upsertKVAllowComment(lines, "net.ipv6.conf.all.disable_ipv6", "1", false)
	lines = upsertKVAllowComment(lines, "net.ipv6.conf.default.disable_ipv6", "1", false)
	lines = upsertKVAllowComment(lines, "net.ipv6.conf.lo.disable_ipv6", "1", false)
	if err := writeLines(path, lines); err != nil {
		return err
	}
	if commandExists("sysctl") {
		_, _ = runCommand("sysctl", "-p", path)
		_, _ = runCommand("sysctl", "-w", "net.ipv6.conf.all.disable_ipv6=1")
		_, _ = runCommand("sysctl", "-w", "net.ipv6.conf.default.disable_ipv6=1")
		_, _ = runCommand("sysctl", "-w", "net.ipv6.conf.lo.disable_ipv6=1")
		_, _ = runCommand("sysctl", "--system")
	}
	writeProcValue("/proc/sys/net/ipv6/conf/all/disable_ipv6", "1")
	writeProcValue("/proc/sys/net/ipv6/conf/default/disable_ipv6", "1")
	writeProcValue("/proc/sys/net/ipv6/conf/lo/disable_ipv6", "1")
	return nil
}

func applyPasswordPolicy() error {
	loginDefs := "/etc/login.defs"
	content := readFile(loginDefs)
	maxKey, minKey, lenKey := loginDefsKeys(content)
	if err := replaceOrAppendKV(loginDefs, maxKey, "90", false); err != nil {
		return err
	}
	if err := replaceOrAppendKV(loginDefs, minKey, "1", false); err != nil {
		return err
	}
	if err := replaceOrAppendKV(loginDefs, lenKey, "8", false); err != nil {
		return err
	}

	// Some Kylin builds honor pwquality.conf over PASS_MIN_LEN.
	if err := ensurePwqualityConfig("8", "3"); err != nil {
		return err
	}

	pamFile := "/etc/pam.d/system-auth"
	if _, err := os.Stat("/etc/pam.d/common-password"); err == nil {
		pamFile = "/etc/pam.d/common-password"
	}
	target := "password requisite pam_pwquality.so retry=3 minlen=8 minclass=3"
	pamLines := readLines(pamFile)
	found := false
	for i, line := range pamLines {
		if strings.Contains(line, "pam_pwquality.so") || strings.Contains(line, "pam_cracklib.so") {
			pamLines[i] = target
			found = true
		}
	}
	if !found {
		pamLines = append(pamLines, target)
	}
	return writeLines(pamFile, pamLines)
}

func applyGuestUser() error {
	if commandExists("usermod") {
		_, _ = runCommand("usermod", "-L", "guest")
		_, _ = runCommand("usermod", "-s", "/sbin/nologin", "guest")
		return nil
	}
	if commandExists("passwd") {
		_, _ = runCommand("passwd", "-l", "guest")
	}
	return nil
}

func applyUSBAutoplay() error {
	config := "/etc/dconf/db/local.d/00-xc-baseline"
	lockFile := "/etc/dconf/db/local.d/locks/00-xc-baseline"
	if err := os.MkdirAll(filepath.Dir(lockFile), 0755); err != nil {
		return err
	}
	content := readFile(config)
	content = ensureSection(content, "org/gnome/desktop/media-handling")
	content = upsertKey(content, "automount", "false")
	content = upsertKey(content, "automount-open", "false")
	if err := os.WriteFile(config, []byte(content), 0644); err != nil {
		return err
	}
	lockContent := readFile(lockFile)
	lockContent = ensureLock(lockContent, "/org/gnome/desktop/media-handling/automount")
	lockContent = ensureLock(lockContent, "/org/gnome/desktop/media-handling/automount-open")
	if err := os.WriteFile(lockFile, []byte(lockContent), 0644); err != nil {
		return err
	}
	if commandExists("dconf") {
		_, _ = runCommand("dconf", "update")
	}
	return nil
}

func applyLockScreen() error {
	config := "/etc/dconf/db/local.d/00-xc-baseline"
	lockFile := "/etc/dconf/db/local.d/locks/00-xc-baseline"
	if err := os.MkdirAll(filepath.Dir(lockFile), 0755); err != nil {
		return err
	}
	content := readFile(config)
	content = ensureSection(content, "org/gnome/desktop/session")
	content = upsertKey(content, "idle-delay", "uint32 900")
	content = ensureSection(content, "org/gnome/desktop/screensaver")
	content = upsertKey(content, "lock-enabled", "true")
	content = upsertKey(content, "lock-delay", "uint32 0")
	if err := os.WriteFile(config, []byte(content), 0644); err != nil {
		return err
	}
	lockContent := readFile(lockFile)
	lockContent = ensureLock(lockContent, "/org/gnome/desktop/session/idle-delay")
	lockContent = ensureLock(lockContent, "/org/gnome/desktop/screensaver/lock-enabled")
	lockContent = ensureLock(lockContent, "/org/gnome/desktop/screensaver/lock-delay")
	if err := os.WriteFile(lockFile, []byte(lockContent), 0644); err != nil {
		return err
	}
	if commandExists("dconf") {
		_, _ = runCommand("dconf", "update")
	}
	return nil
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return []string{}
	}
	lines := strings.Split(string(data), "\n")
	if len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}

func writeLines(path string, lines []string) error {
	data := strings.Join(lines, "\n") + "\n"
	return os.WriteFile(path, []byte(data), 0644)
}

func upsertKV(lines []string, key, value string) []string {
	found := false
	for i, line := range lines {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, key) {
			sep := "   "
			if strings.Contains(trim, "=") {
				sep = " = "
			}
			lines[i] = fmt.Sprintf("%s%s%s", key, sep, value)
			found = true
		}
	}
	if !found {
		lines = append(lines, fmt.Sprintf("%s   %s", key, value))
	}
	return lines
}

func upsertKVAllowComment(lines []string, key, value string, useEquals bool) []string {
	found := false
	for i, line := range lines {
		trim := strings.TrimSpace(line)
		trim = strings.TrimPrefix(trim, "#")
		trim = strings.TrimSpace(trim)
		if strings.HasPrefix(trim, key) {
			sep := "   "
			if useEquals || strings.Contains(line, "=") {
				sep = " = "
			}
			lines[i] = fmt.Sprintf("%s%s%s", key, sep, value)
			found = true
		}
	}
	if !found {
		sep := "   "
		if useEquals {
			sep = " = "
		}
		lines = append(lines, fmt.Sprintf("%s%s%s", key, sep, value))
	}
	return lines
}

func writeProcValue(path, value string) {
	_ = os.WriteFile(path, []byte(value), 0644)
}

func replaceOrAppendKV(path, key, value string, useEquals bool) error {
	lines := readLines(path)
	re := regexp.MustCompile(`(?i)^\s*#?\s*` + regexp.QuoteMeta(key) + `\b.*`)
	replaced := false
	for i, line := range lines {
		if re.MatchString(line) {
			sep := "   "
			if useEquals || strings.Contains(line, "=") {
				sep = " = "
			}
			lines[i] = fmt.Sprintf("%s%s%s", key, sep, value)
			replaced = true
		}
	}
	if !replaced {
		sep := "   "
		if useEquals {
			sep = " = "
		}
		lines = append(lines, fmt.Sprintf("%s%s%s", key, sep, value))
	}
	return writeLines(path, lines)
}

func readFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(data)
}

func ensureSection(content, section string) string {
	marker := "[" + section + "]"
	if strings.Contains(content, marker) {
		return content
	}
	if !strings.HasSuffix(content, "\n") && content != "" {
		content += "\n"
	}
	content += "\n" + marker + "\n"
	return content
}

func upsertKey(content, key, value string) string {
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), key+"=") {
			lines[i] = fmt.Sprintf("%s=%s", key, value)
			return strings.Join(lines, "\n")
		}
	}
	lines = append(lines, fmt.Sprintf("%s=%s", key, value))
	return strings.Join(lines, "\n")
}

func ensureLock(content, key string) string {
	for _, line := range strings.Split(content, "\n") {
		if strings.TrimSpace(line) == key {
			return content
		}
	}
	if !strings.HasSuffix(content, "\n") && content != "" {
		content += "\n"
	}
	content += key + "\n"
	return content
}

func toInt(value string) int {
	var n int
	fmt.Sscanf(value, "%d", &n)
	return n
}

func valueOrNA(value string) string {
	if value == "" {
		return "na"
	}
	return value
}

func boolToStr(value bool) string {
	if value {
		return "ok"
	}
	return "missing"
}

func isTerminal() bool {
	info, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return (info.Mode() & os.ModeCharDevice) != 0
}

func colorize(color, text string) string {
	if !isTerminal() {
		return text
	}
	switch color {
	case "red":
		return "\033[31m" + text + "\033[0m"
	case "yellow":
		return "\033[33m" + text + "\033[0m"
	case "green":
		return "\033[32m" + text + "\033[0m"
	default:
		return text
	}
}

func manualFixHint(id string) string {
	switch id {
	case "ftp_service":
		return "systemctl stop vsftpd && systemctl disable vsftpd"
	case "risky_ports":
		return firewallFixHint()
	case "ipv6_disabled":
		return "sysctl -w net.ipv6.conf.all.disable_ipv6=1 ..."
	case "patch_updates":
		return patchFixHint()
	case "password_policy":
		return "编辑 /etc/login.defs 与 PAM 配置（minlen/minclass）"
	case "guest_user":
		return "usermod -L guest && usermod -s /sbin/nologin guest"
	case "usb_autoplay":
		return "编辑 /etc/dconf/db/local.d/00-xc-baseline 并执行 dconf update"
	case "lock_screen":
		return "设置 idle-delay=uint32 900, lock-enabled=true, lock-delay=uint32 0"
	default:
		return ""
	}
}

func detectOSInfo() OSInfo {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return OSInfo{}
	}
	info := OSInfo{}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "ID=") {
			info.ID = trimOSValue(line)
		} else if strings.HasPrefix(line, "NAME=") {
			info.Name = trimOSValue(line)
		} else if strings.HasPrefix(line, "VERSION_ID=") {
			info.Version = trimOSValue(line)
		} else if strings.HasPrefix(line, "PRETTY_NAME=") {
			info.Pretty = trimOSValue(line)
		} else if strings.HasPrefix(line, "ID_LIKE=") {
			info.IDLike = trimOSValue(line)
		}
	}
	return info
}

func trimOSValue(line string) string {
	parts := strings.SplitN(line, "=", 2)
	if len(parts) != 2 {
		return ""
	}
	return strings.Trim(parts[1], "\"")
}

func patchFixHint() string {
	switch detectPkgManager() {
	case "apt":
		return "apt-get update && apt-get upgrade"
	case "dnf":
		return "dnf update"
	case "yum":
		return "yum update"
	default:
		return "根据系统包管理器执行更新（apt/dnf/yum）"
	}
}

func detectPkgManager() string {
	if commandExists("apt-get") {
		return "apt"
	}
	if commandExists("dnf") {
		return "dnf"
	}
	if commandExists("yum") {
		return "yum"
	}
	return ""
}

func firewallFixHint() string {
	if commandExists("firewall-cmd") {
		return "firewalld：in/out 规则（参见README示例）"
	}
	if commandExists("nft") {
		return "nftables：input/output 链封禁 dport"
	}
	if commandExists("iptables") {
		return "iptables：INPUT/OUTPUT 链 DROP/REJECT"
	}
	return "未检测到防火墙组件，请联系管理员"
}
