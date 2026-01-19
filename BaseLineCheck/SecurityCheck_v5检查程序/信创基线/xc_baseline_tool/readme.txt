信创基线工具（Go 静态单文件）
================================

适用系统
- UOS (DDE)
- 银河麒麟 (UKUI/Kylin Desktop)
- 中标麒麟 (GNOME/UKUI)
- 仅使用系统自带命令与配置文件（无 Python/Node 依赖）

运行说明
- 仅提供检查功能（已移除自动修复/应用）
- 检查通常无需 root 权限，部分系统信息受权限影响可能显示为空
- 无需安装图形组件，双击会自动打开终端交互（若未执行请先赋予执行权限）
- 程序会根据系统版本/组件自动选择包管理器与防火墙检测方式

构建（Go 静态单文件）
构建系统要求
- macOS / Linux 均可构建
- Go 1.20+（在 PATH 中）
- 交叉编译无需额外依赖（CGO 已关闭）

构建命令
cd /Users/zhangyuanyi/Downloads/工作文件/STTools/BaseLineCheck/SecurityCheck_v5检查程序/信创基线/xc_baseline_tool/go
./build.sh
输出文件：xc-baseline-go-amd64 / xc-baseline-go-arm64

macOS 交叉编译示例
GOOS=linux ./build.sh

运行命令
1) 列出基线项
   ./xc-baseline-go --list
2) 执行检查（文本输出）
   ./xc-baseline-go --check
3) 执行检查（JSON 输出）
   ./xc-baseline-go --check --json --output result.json
4) 本工具不提供自动修复/应用，仅输出检查结果与手动修复参考

输出说明
- 文本输出直接显示在控制台
- JSON 输出便于批量汇总与上传

双击运行（普通用户）
1) 将以下文件放在同一目录
   - xc-baseline-go-amd64
   - xc-baseline-go-arm64
   - run.sh
2) 双击 run.sh
   - 回车：立即检查
   - 输入数字：检查/查看项等
3) 若双击无反应，请先执行：
   chmod +x run.sh
4) 如遇 AT-SPI 警告（mate-terminal 打印提示）可忽略，不影响执行
5) 运行将强制在当前终端交互

手动修复参考（非工具功能）
按防火墙类型操作：

1) firewalld（推荐，需服务开启）
- 启用服务：systemctl enable --now firewalld
- 封禁示例（以 22 端口为例）
  入站：
  firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" port port=\"22\" protocol=\"tcp\" reject'
  firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" port port=\"22\" protocol=\"udp\" reject'
  出站：
  firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" direction=\"out\" port port=\"22\" protocol=\"tcp\" reject'
  firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" direction=\"out\" port port=\"22\" protocol=\"udp\" reject'
  firewall-cmd --reload

2) nftables
- 查看规则集：nft list ruleset
- 示例（需按实际链名添加）：nft add rule inet filter input tcp dport 22 drop

3) iptables
- 示例：
  iptables -A INPUT -p tcp --dport 22 -j DROP
  iptables -A INPUT -p udp --dport 22 -j DROP

各检查项手动修复参考

1) FTP 服务禁用
- 查看服务：systemctl status vsftpd
- 停止并禁用：
  systemctl stop vsftpd
  systemctl disable vsftpd

2) 网卡信息检查
- 仅信息展示，无需修复

3) 高危端口状态检测
- 参见上文“高危端口封禁”

4) IPv6 禁用状态
- 临时禁用：
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  sysctl -w net.ipv6.conf.lo.disable_ipv6=1
- 永久生效（写入 /etc/sysctl.d/99-xc-baseline.conf 后执行 sysctl -p）

5) 高危漏洞修复
- 统一更新（根据系统选择包管理器）：
  apt-get update && apt-get upgrade
  dnf update
  yum update

6) 密码策略
- 编辑 /etc/login.defs：
  PASS_MAX_DAYS 90
  PASS_MIN_DAYS 1
  PASS_MIN_LEN  8
- PAM 复杂度（/etc/pam.d/common-password 或 /etc/pam.d/system-auth）：
  password requisite pam_pwquality.so retry=3 minlen=8 minclass=3

7) Guest 用户状态
- 锁定并禁止登录：
  usermod -L guest
  usermod -s /sbin/nologin guest

8) U 盘自动播放
- 编辑 /etc/dconf/db/local.d/00-xc-baseline：
  [org/gnome/desktop/media-handling]
  automount=false
  automount-open=false
- 锁定（/etc/dconf/db/local.d/locks/00-xc-baseline）：
  /org/gnome/desktop/media-handling/automount
  /org/gnome/desktop/media-handling/automount-open
- 执行：dconf update

9) 浏览器版本检测
- 仅信息展示，无需修复

10) 锁屏策略
- 编辑 /etc/dconf/db/local.d/00-xc-baseline：
  [org/gnome/desktop/session]
  idle-delay=uint32 900
  [org/gnome/desktop/screensaver]
  lock-enabled=true
  lock-delay=uint32 0
- 锁定（/etc/dconf/db/local.d/locks/00-xc-baseline）：
  /org/gnome/desktop/session/idle-delay
  /org/gnome/desktop/screensaver/lock-enabled
  /org/gnome/desktop/screensaver/lock-delay
- 执行：dconf update
