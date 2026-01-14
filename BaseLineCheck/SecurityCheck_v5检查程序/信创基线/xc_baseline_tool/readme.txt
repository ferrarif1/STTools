本目录仅保留Go版静态单文件方案，适合直接拷贝到目标机器批量运行。

适用系统
- UOS(DDE)、银河麒麟(UKUI/Kylin Desktop)、中标麒麟(GNOME/UKUI)
- 仅使用系统自带命令与配置文件（无Python/Node依赖）

运行前说明
- 检查无需root权限
- 设置项需要root权限（sudo）
- 若使用图形界面交互，请确保已安装 zenity 或 kdialog

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
6) 原生图形界面交互（自动选择zenity/kdialog）：
   sudo ./xc-baseline-go --apply-all --ui
7) 查看桌面环境与UI组件检测结果：
   ./xc-baseline-go --ui-info

输出说明
- 文本输出直接在控制台显示
- JSON输出可用于批量汇总与上传

双击运行（给普通用户）
1) 将以下文件放在同一目录：
   - xc-baseline-go-amd64
   - xc-baseline-go-arm64
   - run_gui.sh
2) 双击 run_gui.sh 即可自动检测架构并执行
   - 自动完成检查并展示结果
   - 提示用户是否执行修复（应用全部可设置项）
   - 若缺少 zenity/kdialog，将把结果保存到桌面文件并尝试打开
3) 可选：生成桌面快捷方式
   ./install_desktop.sh

桌面快捷方式模板
如需手工编辑，请参考：
xc-baseline.desktop
