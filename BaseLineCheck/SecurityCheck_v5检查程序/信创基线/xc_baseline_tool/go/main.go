package main

import (
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

	if *flagApplyAll || *flagCheckFix {
		fmt.Fprintln(os.Stderr, "自动修复已禁用")
		return
	}

	if *flagApply != "" {
		fmt.Fprintln(os.Stderr, "自动修复已禁用")
		return
	}

	printHelp()
}

func printHelp() {
	fmt.Println("用法:")
	fmt.Println("  xc-baseline-go --check [--json] [--output FILE]")
	fmt.Println("  xc-baseline-go --apply ITEM_ID  (已禁用)")
	fmt.Println("  xc-baseline-go --apply-all      (已禁用)")
	fmt.Println("  xc-baseline-go --check-fix      (已禁用)")
	fmt.Println("  xc-baseline-go --list")
}

func buildItems() []Item {
	// Baseline catalog: wire checks + auto-fix handlers here.
	return []Item{
		{
			ID:        "ftp_service",
			Name:      "FTP服务禁用",
			Desc:      "检查是否存在FTP服务运行，基线要求禁用。",
			Expected:  "FTP服务未运行且已禁用",
			CanApply:  false,
			CheckFunc: checkFTPService,
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
			ID:        "usb_autoplay",
			Name:      "U盘自动播放",
			Desc:      "检查桌面环境自动挂载/自动打开策略。",
			Expected:  "自动挂载/自动打开关闭",
			CanApply:  false,
			CheckFunc: checkUSBAutoplay,
		},
		{
			ID:        "ipv6_disabled",
			Name:      "IPv6禁用状态",
			Desc:      "检查IPv6禁用是否生效。",
			Expected:  "IPv6已禁用",
			CanApply:  false,
			CheckFunc: checkIPv6Disabled,
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
			Expected:  "最小长度>=10，最短1天，最长90天，复杂度>=4类，失败锁定",
			CanApply:  false,
			CheckFunc: checkPasswordPolicy,
		},
		{
			ID:        "lock_screen",
			Name:      "锁屏策略",
			Desc:      "检查锁屏开启与自动锁定时间。",
			Expected:  "锁屏启用，空闲15分钟内锁定",
			CanApply:  false,
			CheckFunc: checkLockScreen,
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
		// Stable machine-readable output for batch collection.
		payload := Output{OS: readOSRelease(), Items: results}
		enc := json.NewEncoder(out)
		enc.SetEscapeHTML(false)
		enc.SetIndent("", "  ")
		if err := enc.Encode(payload); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
		}
		return
	}

	fmt.Fprintf(out, "系统识别: %s\n", readOSRelease())
	fmt.Fprintln(out, "============================================================")
	checkedNames := []string{}
	manualNames := []string{}
	for _, item := range results {
		checkedNames = append(checkedNames, item.Name)
		if !item.CanApply || item.Status == "manual" {
			manualNames = append(manualNames, item.Name)
		}
		name := item.Name
		if item.Status == "fail" {
			name = colorize("red", name)
		}
		fmt.Fprintf(out, "[%s] %s\n", item.ID, name)
		fmt.Fprintf(out, "状态: %s\n", item.Status)
		fmt.Fprintf(out, "当前: %s\n", item.Current)
		fmt.Fprintf(out, "期望: %s\n", item.Expected)
		if item.Status == "fail" {
			if hint := manualFixHint(item.ID); hint != "" {
				fmt.Fprintf(out, "修复指引: %s\n", hint)
			}
		}
		fmt.Fprintln(out, "------------------------------------------------------------")
	}
	if len(checkedNames) > 0 {
		fmt.Fprintf(out, "已检查项: %s\n", strings.Join(checkedNames, "、"))
	}
	if len(manualNames) > 0 {
		fmt.Fprintf(out, "需人工确认项: %s\n", strings.Join(manualNames, "、"))
	}
	fmt.Fprintln(out, "============================================================")
}

func checkAndRepair(items []Item) error {
	fmt.Println("自动修复已禁用，仅执行检查。")
	runCheck(items, false, "")
	return nil
}

func applyOne(items []Item, id string) error {
	return errors.New("自动修复已禁用")
}

func applyAll(items []Item) error {
	return errors.New("自动修复已禁用")
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

func pamFilesByDistro() ([]string, []string) {
	// Debian-like vs RHEL-like PAM layout detection.
	info := detectOSInfo()
	id := strings.ToLower(info.ID)
	name := strings.ToLower(info.Name)
	idLike := strings.ToLower(info.IDLike)
	isDebianLike := strings.Contains(idLike, "debian") || strings.Contains(id, "uos") || strings.Contains(name, "uos")
	if isDebianLike {
		return []string{"/etc/pam.d/common-password"}, []string{"/etc/pam.d/common-auth"}
	}
	isRhelLike := strings.Contains(idLike, "rhel") || strings.Contains(idLike, "fedora") || strings.Contains(name, "kylin") || strings.Contains(id, "kylin") || strings.Contains(id, "neokylin")
	if isRhelLike {
		return []string{"/etc/pam.d/system-auth", "/etc/pam.d/password-auth"}, []string{"/etc/pam.d/system-auth", "/etc/pam.d/password-auth"}
	}
	return []string{"/etc/pam.d/common-password", "/etc/pam.d/system-auth"}, []string{"/etc/pam.d/common-auth", "/etc/pam.d/system-auth"}
}

func firstExistingFile(paths []string) string {
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
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
	risky := riskyPorts()
	opened := []int{}
	for _, p := range risky {
		if ports[p] {
			opened = append(opened, p)
		}
	}
	// Combine runtime listening + firewall policy checks.
	firewallStatus, missingBlocks, hint, hintKind := checkFirewallBlocks(risky)
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
		details = append(details, "防火墙未安装")
	} else if firewallStatus == "inactive" {
		status = "fail"
		details = append(details, "防火墙未启用")
	} else if len(missingBlocks) > 0 {
		status = "fail"
		details = append(details, "未封禁: "+strings.Join(missingBlocks, ", "))
	} else {
		details = append(details, "高危端口已配置封禁策略")
	}
	if hint != "" {
		switch hintKind {
		case "install":
			details = append(details, "安装命令: "+hint)
		case "enable":
			details = append(details, "启用命令: "+hint)
		case "recommend":
			details = append(details, hint)
		}
	}
	return Result{Status: status, Current: strings.Join(details, " | ")}
}

func riskyPorts() []int {
	return []int{22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899}
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

func checkFirewallBlocks(ports []int) (string, []string, string, string) {
	info := detectOSInfo()
	kind := detectDistroKind(info)
	if kind.IsUOS {
		if commandExists("ufw") {
			status, missing := checkUFWBlocks(ports)
			if status == "inactive" {
				return "inactive", missing, "sudo ufw enable", "enable"
			}
			return status, missing, "", ""
		}
		if commandExists("iptables") {
			status, missing := checkIptablesBlocksInputOnly(ports)
			return status, missing, "建议安装UFW: " + pkgInstallCmd("ufw"), "recommend"
		}
		return "absent", portsToProtoListInputOnly(ports), pkgInstallCmd("ufw"), "install"
	}
	if kind.IsKylin || kind.IsNeoKylin {
		if commandExists("firewall-cmd") {
			if !isServiceActive("firewalld") {
				return "inactive", portsToProtoListInputOnly(ports), "sudo systemctl enable --now firewalld", "enable"
			}
			status, missing := checkFirewalldBlocksInputOnly(ports)
			return status, missing, "", ""
		}
		if commandExists("iptables") {
			status, missing := checkIptablesBlocksInputOnly(ports)
			return status, missing, "", ""
		}
		return "absent", portsToProtoListInputOnly(ports), pkgInstallCmd("firewalld"), "install"
	}
	// Prefer native firewall tooling when available.
	if commandExists("firewall-cmd") && isServiceActive("firewalld") {
		status, missing := checkFirewalldBlocks(ports)
		return status, missing, "", ""
	}
	if commandExists("nft") {
		status, missing := checkNftBlocks(ports)
		return status, missing, "", ""
	}
	if commandExists("iptables") {
		status, missing := checkIptablesBlocks(ports)
		return status, missing, "", ""
	}
	return "absent", portsToProtoList(ports), firewallInstallHint(), "install"
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

func checkFirewalldBlocksInputOnly(ports []int) (string, []string) {
	missing := []string{}
	richRules, _ := runCommand("firewall-cmd", "--list-rich-rules")
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			if firewalldPortAllowed(port, proto) {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
				continue
			}
			if !firewalldHasDenyRule(richRules, port, proto, "in") {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
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

func checkUFWBlocks(ports []int) (string, []string) {
	out, code := runCommand("ufw", "status", "verbose")
	if code != 0 {
		return "ufw", portsToProtoListInputOnly(ports)
	}
	if strings.Contains(out, "Status: inactive") {
		return "inactive", portsToProtoListInputOnly(ports)
	}
	blocked := make(map[string]bool)
	allowed := make(map[string]bool)
	defaultDenyIn := false
	denyRe := regexp.MustCompile(`(?i)^\s*(\d+)/(tcp|udp).*\b(deny|reject)\b`)
	allowRe := regexp.MustCompile(`(?i)^\s*(\d+)/(tcp|udp).*\b(allow|limit)\b`)
	for _, line := range strings.Split(out, "\n") {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "Default:") && strings.Contains(trim, "deny (incoming)") {
			defaultDenyIn = true
		}
		if match := denyRe.FindStringSubmatch(line); len(match) == 4 {
			portStr := match[1]
			proto := strings.ToLower(match[2])
			blocked[fmt.Sprintf("%s/%s", portStr, proto)] = true
			continue
		}
		if match := allowRe.FindStringSubmatch(line); len(match) == 4 {
			portStr := match[1]
			proto := strings.ToLower(match[2])
			allowed[fmt.Sprintf("%s/%s", portStr, proto)] = true
		}
	}
	missing := []string{}
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			key := fmt.Sprintf("%d/%s", port, proto)
			if blocked[key] {
				continue
			}
			if defaultDenyIn && !allowed[key] {
				continue
			}
			if !blocked[key] {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
			}
		}
	}
	return "ufw", dedupeStrings(missing)
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

func checkIptablesBlocksInputOnly(ports []int) (string, []string) {
	inputRules, _ := runCommand("iptables", "-S", "INPUT")
	missing := []string{}
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			if !iptablesHasDrop(inputRules, port, proto) {
				missing = append(missing, fmt.Sprintf("%d/%s(in)", port, proto))
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

func portsToProtoListInputOnly(ports []int) []string {
	list := []string{}
	for _, port := range ports {
		list = append(list, fmt.Sprintf("%d/tcp(in)", port))
		list = append(list, fmt.Sprintf("%d/udp(in)", port))
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
	content := string(data)
	maxKey, minKey, lenKey := loginDefsKeys(content)
	maxDays := parseLoginDefsAny(content, []string{maxKey, "PASS_MAX_DAYS", "MAX_DAYS", "MAX"})
	minDays := parseLoginDefsAny(content, []string{minKey, "PASS_MIN_DAYS", "MIN_DAYS", "MIN"})
	minLen := parseLoginDefsAny(content, []string{lenKey, "PASS_MIN_LEN", "MIN_LEN", "LEN"})
	pwqMinLen := ""
	pwqMinClass := ""
	if minLen == "" {
		pwqMinLen, pwqMinClass = readPwqualityConfig()
	}
	pamFiles, authFiles := pamFilesByDistro()
	pamFile := firstExistingFile(pamFiles)
	authFile := firstExistingFile(authFiles)
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
	pamMinClass := pwqMinClass
	if pamMinClass == "" {
		pamMinClass = parsePamValue(pamContent, "minclass")
	}
	enforceRoot := strings.Contains(pamContent, "enforce_for_root")
	rememberOK := strings.Contains(pamContent, "remember=5")
	faillockOK := false
	if authFile != "" {
		authContent := readFile(authFile)
		faillockOK = strings.Contains(authContent, "pam_faillock.so") || strings.Contains(authContent, "pam_tally2.so")
	}

	status := "pass"
	issues := []string{}
	if maxDays == "" || toInt(maxDays) > 90 {
		status = "fail"
		issues = append(issues, maxKey)
	}
	if minDays == "" || toInt(minDays) < 1 {
		status = "fail"
		issues = append(issues, minKey)
	}
	if minLen == "" || toInt(minLen) < 10 {
		status = "fail"
		issues = append(issues, lenKey)
	}
	if !pwquality || (pamMinClass != "" && toInt(pamMinClass) < 4) || !enforceRoot {
		status = "fail"
		issues = append(issues, "PAM复杂度")
	}
	if !rememberOK {
		status = "fail"
		issues = append(issues, "PAM历史密码")
	}
	if !faillockOK {
		status = "fail"
		issues = append(issues, "登录失败锁定")
	}
	current := fmt.Sprintf("MAX=%s, MIN=%s, LEN=%s, PAM=%s", valueOrNA(maxDays), valueOrNA(minDays), valueOrNA(minLen), boolToStr(pwquality))
	if pamMinClass != "" {
		current += fmt.Sprintf(", MINCLASS=%s", pamMinClass)
	}
	current += fmt.Sprintf(", ENFORCE_ROOT=%t, REMEMBER=%t, FAILLOCK=%t", enforceRoot, rememberOK, faillockOK)
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
	if maxKey != "" || minKey != "" {
		if lenKey == "" {
			lenKey = "LEN"
		}
	}
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

func applyRiskyPorts() error {
	// Auto-fix via the first available firewall backend.
	ports := riskyPorts()
	if commandExists("firewall-cmd") {
		return applyFirewalldBlocks(ports)
	}
	if commandExists("nft") {
		if err := applyNftBlocks(ports); err == nil {
			return nil
		}
	}
	if commandExists("iptables") {
		return applyIptablesBlocks(ports)
	}
	return errors.New("未检测到可用防火墙组件")
}

func applyFirewalldBlocks(ports []int) error {
	if commandExists("systemctl") {
		_, _ = runCommand("systemctl", "enable", "--now", "firewalld")
	}
	if !isServiceActive("firewalld") {
		return errors.New("firewalld 未运行")
	}
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			for _, family := range []string{"ipv4", "ipv6"} {
				_, _ = runCommand("firewall-cmd", "--permanent", "--add-rich-rule",
					fmt.Sprintf("rule family=\"%s\" port port=\"%d\" protocol=\"%s\" reject", family, port, proto))
				_, _ = runCommand("firewall-cmd", "--permanent", "--add-rich-rule",
					fmt.Sprintf("rule family=\"%s\" direction=\"out\" port port=\"%d\" protocol=\"%s\" reject", family, port, proto))
			}
		}
	}
	_, _ = runCommand("firewall-cmd", "--reload")
	return nil
}

func applyIptablesBlocks(ports []int) error {
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			ensureIptablesRule("iptables", "INPUT", proto, port)
			ensureIptablesRule("iptables", "OUTPUT", proto, port)
			if commandExists("ip6tables") {
				ensureIptablesRule("ip6tables", "INPUT", proto, port)
				ensureIptablesRule("ip6tables", "OUTPUT", proto, port)
			}
		}
	}
	return nil
}

func ensureIptablesRule(bin, chain, proto string, port int) {
	args := []string{"-C", chain, "-p", proto, "--dport", fmt.Sprintf("%d", port), "-j", "DROP"}
	_, code := runCommand(bin, args...)
	if code == 0 {
		return
	}
	addArgs := []string{"-A", chain, "-p", proto, "--dport", fmt.Sprintf("%d", port), "-j", "DROP"}
	_, _ = runCommand(bin, addArgs...)
}

func applyNftBlocks(ports []int) error {
	_, _ = runCommand("nft", "add", "table", "inet", "filter")
	_, _ = runCommand("nft", "add", "chain", "inet", "filter", "input",
		"{", "type", "filter", "hook", "input", "priority", "0", ";", "}")
	_, _ = runCommand("nft", "add", "chain", "inet", "filter", "output",
		"{", "type", "filter", "hook", "output", "priority", "0", ";", "}")
	for _, port := range ports {
		for _, proto := range []string{"tcp", "udp"} {
			_, _ = runCommand("nft", "add", "rule", "inet", "filter", "input", proto, "dport", fmt.Sprintf("%d", port), "drop")
			_, _ = runCommand("nft", "add", "rule", "inet", "filter", "output", proto, "dport", fmt.Sprintf("%d", port), "drop")
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
	if readProcValue("/proc/sys/net/ipv6/conf/all/disable_ipv6") != "1" {
		return errors.New("IPv6禁用未生效，请确认系统未被策略覆盖")
	}
	return nil
}

func applyPasswordPolicy() error {
	// Password policy differs by distro family; detect and write the right PAM files.
	loginDefs := "/etc/login.defs"
	content := readFile(loginDefs)
	maxKey, minKey, lenKey := loginDefsKeys(content)
	if err := replaceOrAppendKV(loginDefs, maxKey, "90", false); err != nil {
		return err
	}
	if err := replaceOrAppendKV(loginDefs, minKey, "1", false); err != nil {
		return err
	}
	if err := replaceOrAppendKV(loginDefs, lenKey, "10", false); err != nil {
		return err
	}
	_ = replaceOrAppendKV(loginDefs, "PASS_WARN_AGE", "7", false)

	// Some Kylin builds honor pwquality.conf over PASS_MIN_LEN.
	if err := ensurePwqualityConfig("10", "4"); err != nil {
		return err
	}

	pamFiles, authFiles := pamFilesByDistro()
	pamFile := firstExistingFile(pamFiles)
	authFile := firstExistingFile(authFiles)
	if pamFile == "" {
		return errors.New("未找到PAM密码配置文件")
	}
	target := "password requisite pam_pwquality.so retry=3 enforce_for_root minlen=10 minclass=4"
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
	if err := writeLines(pamFile, pamLines); err != nil {
		return err
	}
	pamLines = readLines(pamFile)
	unixLine := "password sufficient pam_unix.so sha512 shadow remember=5 use_authtok"
	unixFound := false
	for i, line := range pamLines {
		if strings.Contains(line, "pam_unix.so") && strings.Contains(line, "password") {
			pamLines[i] = unixLine
			unixFound = true
		}
	}
	if !unixFound {
		pamLines = append(pamLines, unixLine)
	}
	if err := writeLines(pamFile, pamLines); err != nil {
		return err
	}

	if authFile != "" {
		authLines := readLines(authFile)
		if pamModuleExists("pam_faillock.so") {
			authLines = ensurePamLine(authLines, "pam_faillock.so preauth", "auth required pam_faillock.so preauth silent deny=5 unlock_time=600")
			authLines = ensurePamLine(authLines, "pam_faillock.so authfail", "auth [default=die] pam_faillock.so authfail deny=5 unlock_time=600")
			authLines = ensurePamLine(authLines, "account required pam_faillock.so", "account required pam_faillock.so")
		} else if pamModuleExists("pam_tally2.so") {
			authLines = ensurePamLine(authLines, "pam_tally2.so", "auth required pam_tally2.so deny=5 unlock_time=600")
			authLines = ensurePamLine(authLines, "pam_tally2.so", "account required pam_tally2.so")
		}
		if err := writeLines(authFile, authLines); err != nil {
			return err
		}
	}

	// Verify effective values after write.
	updated := readFile(loginDefs)
	vMax := parseLoginDefsAny(updated, []string{maxKey, "PASS_MAX_DAYS", "MAX_DAYS", "MAX"})
	vMin := parseLoginDefsAny(updated, []string{minKey, "PASS_MIN_DAYS", "MIN_DAYS", "MIN"})
	vLen := parseLoginDefsAny(updated, []string{lenKey, "PASS_MIN_LEN", "MIN_LEN", "LEN"})
	if vMax != "90" || vMin != "1" || toInt(vLen) < 10 {
		return errors.New("login.defs 未按预期更新")
	}
	pwMinLen, pwMinClass := readPwqualityConfig()
	if toInt(pwMinLen) < 10 || toInt(pwMinClass) < 4 {
		return errors.New("pwquality.conf 未按预期更新")
	}
	pamContent := readFile(pamFile)
	if parsePamValue(pamContent, "minlen") == "" || parsePamValue(pamContent, "minclass") == "" {
		return errors.New("PAM 复杂度参数未写入")
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

func ensurePamLine(lines []string, needle string, line string) []string {
	for i, existing := range lines {
		if strings.Contains(existing, needle) {
			lines[i] = line
			return lines
		}
	}
	return append(lines, line)
}

func pamModuleExists(module string) bool {
	paths := []string{
		"/lib/security/" + module,
		"/lib64/security/" + module,
		"/lib/x86_64-linux-gnu/security/" + module,
		"/usr/lib/security/" + module,
		"/usr/lib64/security/" + module,
	}
	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return true
		}
	}
	return false
}

func readProcValue(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
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
	info := detectOSInfo()
	kind := detectDistroKind(info)
	guiPrefix := "系统设置"
	if kind.IsUOS {
		guiPrefix = "控制中心"
	}
	switch id {
	case "ftp_service":
		return "在“服务管理”中停用 FTP 服务（vsftpd/proftpd 等）"
	case "risky_ports":
		if kind.IsUOS {
			return "UOS建议使用UFW: " + pkgInstallCmd("ufw") + "（未安装时）。示例: sudo ufw default deny incoming; sudo ufw allow 80/tcp; sudo ufw allow 443/tcp; sudo ufw deny 21/tcp 3389/tcp 445/tcp; sudo ufw enable; sudo ufw status verbose。或使用iptables: sudo iptables -A INPUT -p tcp --dport 21 -j DROP 等。"
		}
		if kind.IsKylin || kind.IsNeoKylin {
			return "麒麟建议使用iptables或firewalld。iptables示例: sudo iptables -A INPUT -p tcp --dport 139 -j DROP; sudo iptables -A INPUT -p tcp --dport 445 -j DROP。firewalld示例: sudo systemctl enable --now firewalld; sudo firewall-cmd --zone=public --remove-port=139/tcp --permanent; sudo firewall-cmd --zone=public --remove-port=445/tcp --permanent; sudo firewall-cmd --reload。未安装防火墙时: " + pkgInstallCmd("firewalld") + "。"
		}
		return guiPrefix + " → 防火墙 → 端口规则 → 添加拒绝规则"
	case "usb_autoplay":
		if kind.IsUOS {
			return guiPrefix + " → 设备与驱动 → 可移动存储 → 关闭自动播放/自动挂载"
		}
		if kind.IsKylin || kind.IsNeoKylin {
			return guiPrefix + " → 设备 → 可移动存储 → 关闭自动挂载/自动打开"
		}
		return guiPrefix + " → 设备 → 可移动存储 → 关闭自动挂载/自动打开"
	case "ipv6_disabled":
		if kind.IsUOS {
			return guiPrefix + " → 网络 → 高级设置 → 关闭 IPv6"
		}
		if kind.IsKylin || kind.IsNeoKylin {
			return guiPrefix + " → 网络 → 高级 → 关闭 IPv6"
		}
		return guiPrefix + " → 网络 → 高级 → 关闭 IPv6"
	case "patch_updates":
		if kind.IsUOS {
			return guiPrefix + " → 更新 → 检查更新 → 全部更新"
		}
		if kind.IsKylin || kind.IsNeoKylin {
			return guiPrefix + " → 更新管理 → 检查更新 → 安装更新"
		}
		return guiPrefix + " → 更新管理 → 检查更新 → 安装更新"
	case "password_policy":
		if kind.IsUOS {
			return guiPrefix + " → 账户与安全 → 密码策略 → 长度>=10/复杂度>=4/历史5次/锁定"
		}
		if kind.IsKylin || kind.IsNeoKylin {
			return guiPrefix + " → 安全中心 → 账户策略 → 密码复杂度与锁定策略"
		}
		return guiPrefix + " → 账户策略 → 密码复杂度与锁定策略"
	case "lock_screen":
		if kind.IsUOS {
			return guiPrefix + " → 个性化 → 锁屏 → 开启锁屏并设置 15 分钟内自动锁定"
		}
		if kind.IsKylin || kind.IsNeoKylin {
			return guiPrefix + " → 个性化 → 锁屏 → 开启并设置 15 分钟内自动锁定"
		}
		return guiPrefix + " → 个性化 → 锁屏 → 开启并设置 15 分钟内自动锁定"
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

type DistroKind struct {
	IsUOS      bool
	IsKylin    bool
	IsNeoKylin bool
}

func detectDistroKind(info OSInfo) DistroKind {
	idLower := strings.ToLower(info.ID)
	nameLower := strings.ToLower(info.Name)
	return DistroKind{
		IsUOS:      strings.Contains(idLower, "uos") || strings.Contains(nameLower, "uos"),
		IsKylin:    strings.Contains(idLower, "kylin") || strings.Contains(nameLower, "kylin"),
		IsNeoKylin: strings.Contains(idLower, "neokylin") || strings.Contains(nameLower, "neokylin"),
	}
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

func firewallInstallHint() string {
	return pkgInstallCmd("firewalld")
}

func pkgInstallCmd(pkg string) string {
	switch detectPkgManager() {
	case "apt":
		return "sudo apt install -y " + pkg
	case "dnf":
		return "sudo dnf install -y " + pkg
	case "yum":
		return "sudo yum install -y " + pkg
	default:
		return "请使用系统包管理器安装 " + pkg
	}
}
