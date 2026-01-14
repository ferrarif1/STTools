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

type UIInfo struct {
	Desktop string
	Display string
	Backend string
}

func main() {
	var (
		flagCheck    = flag.Bool("check", false, "执行全部基线检查")
		flagApply    = flag.String("apply", "", "应用指定基线项")
		flagApplyAll = flag.Bool("apply-all", false, "应用所有可设置项")
		flagList     = flag.Bool("list", false, "列出基线项")
		flagJSON     = flag.Bool("json", false, "JSON输出")
		flagOutput   = flag.String("output", "", "输出到文件")
		flagUI       = flag.Bool("ui", false, "启用原生图形交互")
		flagUIInfo   = flag.Bool("ui-info", false, "输出桌面环境与UI组件检测结果")
	)
	flag.Parse()

	if runtime.GOOS != "linux" {
		fmt.Fprintln(os.Stderr, "仅支持Linux系统运行")
		os.Exit(1)
	}

	items := buildItems()

	if *flagUIInfo {
		info := detectUI()
		fmt.Printf("desktop=%s\n", info.Desktop)
		fmt.Printf("display=%s\n", info.Display)
		fmt.Printf("ui_backend=%s\n", info.Backend)
		return
	}

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

	if *flagApply != "" {
		if err := applyOne(items, *flagApply); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		return
	}

	if *flagApplyAll {
		if err := applyAll(items, *flagUI); err != nil {
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
	fmt.Println("  xc-baseline-go --apply ITEM_ID")
	fmt.Println("  xc-baseline-go --apply-all [--ui]")
	fmt.Println("  xc-baseline-go --list")
	fmt.Println("  xc-baseline-go --ui-info")
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
		fmt.Fprintf(out, "[%s] %s\n- 结果: %s\n- 当前: %s\n- 期望: %s\n\n",
			item.ID, item.Name, item.Status, item.Current, item.Expected)
	}
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

func applyAll(items []Item, useUI bool) error {
	if os.Geteuid() != 0 {
		return errors.New("需要root权限执行设置操作")
	}
	applyRest := false
	ui := UIInfo{}
	if useUI {
		ui = detectUI()
		if ui.Backend == "" {
			fmt.Println("未检测到可用图形界面组件，将使用命令行交互。")
			useUI = false
		}
	}
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
			answer := ""
			if useUI {
				answer = uiPromptAction(ui, item)
			} else {
				fmt.Printf("是否应用[%s] %s ? (y/n/all): ", item.ID, item.Name)
				input, _ := reader.ReadString('\n')
				answer = strings.TrimSpace(input)
			}
			switch strings.ToLower(answer) {
			case "y":
				_ = item.ApplyFunc()
				goto nextItem
			case "n":
				goto nextItem
			case "all":
				confirm := "n"
				if useUI {
					confirm = uiConfirmAll(ui)
				} else {
					fmt.Print("确认要对剩余所有可设置项执行吗？(y/n): ")
					input, _ := reader.ReadString('\n')
					confirm = strings.TrimSpace(input)
				}
				if strings.EqualFold(confirm, "y") {
					applyRest = true
					_ = item.ApplyFunc()
				}
				goto nextItem
			default:
				if !useUI {
					fmt.Println("请输入 y / n / all")
				}
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
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "Linux"
	}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "PRETTY_NAME=") {
			return strings.Trim(strings.TrimPrefix(line, "PRETTY_NAME="), "\"")
		}
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
	if len(opened) == 0 {
		return Result{Status: "pass", Current: "无高危端口监听"}
	}
	parts := []string{}
	for _, p := range opened {
		parts = append(parts, fmt.Sprintf("%d", p))
	}
	return Result{Status: "fail", Current: "监听端口: " + strings.Join(parts, ", ")}
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
	maxDays := parseLoginDefs(string(data), "PASS_MAX_DAYS")
	minDays := parseLoginDefs(string(data), "PASS_MIN_DAYS")
	minLen := parseLoginDefs(string(data), "PASS_MIN_LEN")
	pamFile := "/etc/pam.d/system-auth"
	if _, err := os.Stat("/etc/pam.d/common-password"); err == nil {
		pamFile = "/etc/pam.d/common-password"
	}
	pamData, _ := os.ReadFile(pamFile)
	pwquality := strings.Contains(string(pamData), "pam_pwquality.so") || strings.Contains(string(pamData), "pam_cracklib.so")

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
	if !pwquality {
		status = "fail"
		issues = append(issues, "PAM复杂度")
	}
	current := fmt.Sprintf("MAX=%s, MIN=%s, LEN=%s, PAM=%s", valueOrNA(maxDays), valueOrNA(minDays), valueOrNA(minLen), boolToStr(pwquality))
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
		return Result{Status: "manual", Current: "未发现dconf配置"}
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
	lines = upsertKV(lines, "net.ipv6.conf.all.disable_ipv6", "1")
	lines = upsertKV(lines, "net.ipv6.conf.default.disable_ipv6", "1")
	lines = upsertKV(lines, "net.ipv6.conf.lo.disable_ipv6", "1")
	if err := writeLines(path, lines); err != nil {
		return err
	}
	if commandExists("sysctl") {
		_, _ = runCommand("sysctl", "-p", path)
	}
	return nil
}

func applyPasswordPolicy() error {
	loginDefs := "/etc/login.defs"
	lines := readLines(loginDefs)
	lines = upsertKV(lines, "PASS_MAX_DAYS", "90")
	lines = upsertKV(lines, "PASS_MIN_DAYS", "1")
	lines = upsertKV(lines, "PASS_MIN_LEN", "8")
	if err := writeLines(loginDefs, lines); err != nil {
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
			lines[i] = fmt.Sprintf("%s   %s", key, value)
			found = true
		}
	}
	if !found {
		lines = append(lines, fmt.Sprintf("%s   %s", key, value))
	}
	return lines
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

func detectUI() UIInfo {
	info := UIInfo{Desktop: "unknown", Display: "unknown", Backend: ""}
	desktop := strings.ToLower(os.Getenv("XDG_CURRENT_DESKTOP"))
	if desktop == "" {
		desktop = strings.ToLower(os.Getenv("DESKTOP_SESSION"))
	}
	if desktop == "" {
		desktop = "unknown"
	}
	info.Desktop = desktop
	if os.Getenv("WAYLAND_DISPLAY") != "" {
		info.Display = "wayland"
	} else if os.Getenv("DISPLAY") != "" {
		info.Display = "x11"
	} else {
		info.Display = "none"
	}
	if info.Display == "none" {
		return info
	}
	if strings.Contains(desktop, "dde") || strings.Contains(desktop, "ukui") || strings.Contains(desktop, "gnome") {
		if commandExists("zenity") {
			info.Backend = "zenity"
			return info
		}
	}
	if strings.Contains(desktop, "kde") {
		if commandExists("kdialog") {
			info.Backend = "kdialog"
			return info
		}
	}
	if commandExists("zenity") {
		info.Backend = "zenity"
	} else if commandExists("kdialog") {
		info.Backend = "kdialog"
	}
	return info
}

func uiPromptAction(info UIInfo, item Item) string {
	if info.Backend == "zenity" {
		cmd := exec.Command("zenity", "--list", "--radiolist",
			"--title=基线设置",
			"--text=是否应用【"+item.Name+"】\n\n"+item.Desc+"\n\n期望: "+item.Expected,
			"--column=选择", "--column=操作",
			"TRUE", "y", "FALSE", "n", "FALSE", "all",
		)
		out, err := cmd.Output()
		if err != nil {
			return "n"
		}
		return strings.TrimSpace(string(out))
	}
	if info.Backend == "kdialog" {
		cmd := exec.Command("kdialog", "--title", "基线设置",
			"--radiolist", "是否应用【"+item.Name+"】\n"+item.Desc+"\n期望: "+item.Expected,
			"y", "应用此项", "on",
			"n", "跳过此项", "off",
			"all", "应用剩余全部", "off",
		)
		out, err := cmd.Output()
		if err != nil {
			return "n"
		}
		return strings.TrimSpace(string(out))
	}
	return "n"
}

func uiConfirmAll(info UIInfo) string {
	if info.Backend == "zenity" {
		cmd := exec.Command("zenity", "--question", "--title=确认", "--text=确认要对剩余所有可设置项执行吗？")
		if err := cmd.Run(); err == nil {
			return "y"
		}
		return "n"
	}
	if info.Backend == "kdialog" {
		cmd := exec.Command("kdialog", "--yesno", "确认要对剩余所有可设置项执行吗？")
		if err := cmd.Run(); err == nil {
			return "y"
		}
		return "n"
	}
	return "n"
}
