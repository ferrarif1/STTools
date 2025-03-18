# 安全基线检查工具

## 概述
该工具集包含两个独立的可执行文件，用于检查系统中的安全基线配置。它们会自动检测并报告系统中可能存在的安全风险，并提供修复建议。

## 工具列表
1. **SecurityCheck_v5.exe**
2. **checkline_requirePython.exe**

## SecurityCheck_v5.exe

### 主要功能
1. **FTP 服务与传输功能检查**
   - 检查 FTP 服务是否安装及状态。
   - 检查 FTP 客户端功能是否启用。
   - 检查 FTP 端口（21）是否开放。
   - 检查允许 FTP 流量的防火墙入站规则。

2. **网卡信息检查**
   - 输出所有网卡信息。
   - 检查无线网卡是否启用。

3. **高危端口状态检测**
   - 检查高危端口（如 22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899）的防火墙策略。

4. **IPv6 禁用状态检查**
   - 检查 IPv6 是否通过注册表方式禁用。

5. **高危漏洞修复检查**
   - 检查最近已安装的更新，提示核查是否包含高危漏洞补丁。

6. **密码策略检查**
   - 检查密码策略，包括最长密码有效期。

7. **Guest 用户状态检查**
   - 检查 Guest 用户是否启用。

8. **U盘自动播放功能设置检查**
   - 检查 U盘自动播放功能是否禁用。

9. **Google 浏览器版本检测**
   - 检查 Google Chrome 浏览器是否安装及版本。

10. **锁屏策略检查**
    - 检查锁屏策略是否符合安全要求。

### 使用方法
1. **运行程序**
   - 双击 `SecurityCheck_v5.exe` 文件以运行程序。
   - 程序会自动执行安全检查，并在控制台中输出检查结果和修复建议。

2. **查看结果**
   - 检查结束后，程序会输出详细的检查报告，包括成功项、错误项及修复建议。
   - 根据报告中的修复建议，手动调整系统配置以提高安全性。

3. **退出程序**
   - 检查结束后，按回车键退出程序。

### 脚本更新后重新打包为exe：
编码修复：
$content = Get-Content -Path ".\check1.ps1" -Raw
$utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText(".\check1.ps1", $content, $utf8NoBomEncoding)

运行：
powershell -ExecutionPolicy ByPass -File ".\check1.ps1" -Encoding UTF8


打包：
cd C:\Users\revan\Desktop\MyWorkNote\Tools\BaseLineCheck
powershell -ExecutionPolicy ByPass -File ".\build.ps1"


## checkline_requirePython.exe

### 主要功能
1. **系统激活状态检查**
   - 检查系统是否已激活。

2. **网卡状态检查**
   - 输出所有网卡的详细信息，包括管理员状态、连接状态、类型和接口名称。

3. **高危端口状态检测**
   - 检查高危端口（如 4899）是否在防火墙规则中封堵。

4. **IPv6 禁用状态检查**
   - 检查以太网的 IPv6 是否禁用。

5. **密码策略检查**
   - 检查密码策略，包括密码最短使用期限、最长使用期限、密码长度最小值等。

6. **Guest 用户状态检查**
   - 检查 Guest 用户是否启用。

7. **U盘自动播放功能设置检查**
   - 检查 U盘自动播放功能是否配置。

### 使用方法
1. **运行程序**
   - 管理员权限打开 `checkline_requirePython.exe` 文件以运行程序。
   - 程序会自动执行安全检查，并在控制台中输出检查结果和修复建议。


