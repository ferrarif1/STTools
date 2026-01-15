适用系统
- UOS(DDE)、银河麒麟(UKUI/Kylin Desktop)、中标麒麟(GNOME/UKUI)
- 仅使用系统自带命令与配置文件（无Python/Node依赖）

运行前说明
- 检查无需root权限
- 设置项需要root权限（sudo）
- 无需安装图形组件（zenity/kdialog），双击会自动打开终端交互

构建静态单文件（Go，无运行时依赖）
构建系统要求
- macOS / Linux 均可构建
- 需要 Go 1.20+（已安装并在PATH中）
- 交叉编译无需额外依赖（CGO已关闭）

cd /Users/zhangyuanyi/Downloads/工作文件/STTools/BaseLineCheck/SecurityCheck_v5检查程序/信创基线/xc_baseline_tool/go
./build.sh
输出文件：xc-baseline-go-amd64 / xc-baseline-go-arm64

macOS 交叉编译示例
GOOS=linux ./build.sh

运行示例
1) 列出基线项：
   ./xc-baseline-go --list
2) 执行检查（文本输出）：
   ./xc-baseline-go --check
3) 执行检查（JSON输出）：
   ./xc-baseline-go --check --json --output result.json
4) 应用单项设置：
   sudo ./xc-baseline-go --apply password_policy
5) 应用所有可设置项（逐项y/n/all）：
   sudo ./xc-baseline-go --apply-all

输出说明
- 文本输出直接在控制台显示
- JSON输出可用于批量汇总与上传

手动修复参考（高危端口封禁）
如需手动封禁高危端口（TCP/UDP），可按防火墙类型操作：

1) firewalld（推荐，需服务开启）
   - 启用服务：systemctl enable --now firewalld
   - 封禁示例（以 22 端口为例）：
     firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" port port=\"22\" protocol=\"tcp\" reject'
     firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" port port=\"22\" protocol=\"udp\" reject'
     firewall-cmd --reload

2) nftables
   - 查看规则集：nft list ruleset
   - 示例（需按实际链名添加）：nft add rule inet filter input tcp dport 22 drop

3) iptables
   - 示例：
     iptables -A INPUT -p tcp --dport 22 -j DROP
     iptables -A INPUT -p udp --dport 22 -j DROP

各检查项手动修复参考

1) FTP服务禁用
- 查看服务：systemctl status vsftpd
- 停止并禁用：
  systemctl stop vsftpd
  systemctl disable vsftpd

2) 网卡信息检查
- 仅信息展示，无需修复

3) 高危端口状态检测
- 参见上文“高危端口封禁”

4) IPv6禁用状态
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
- PAM复杂度（/etc/pam.d/common-password 或 /etc/pam.d/system-auth）：
  password requisite pam_pwquality.so retry=3 minlen=8 minclass=3

7) Guest用户状态
- 锁定并禁止登录：
  usermod -L guest
  usermod -s /sbin/nologin guest

8) U盘自动播放
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

双击运行（给普通用户）
1) 将以下文件放在同一目录：
   - xc-baseline-go-amd64
   - xc-baseline-go-arm64
   - run_gui.sh
2) 双击 run_gui.sh 即可自动检测架构并执行
   - 默认回车即开始检查
   - 输入 1-4 选择检查/修复/查看项等功能
   - 若无法打开终端，将把结果保存到桌面文件
3) 可选：生成桌面快捷方式
   ./install_desktop.sh

桌面快捷方式模板
如需手工编辑，请参考：
xc-baseline.desktop
