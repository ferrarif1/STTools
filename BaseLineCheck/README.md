
# 🛡️ 安全基线检查工具 🔍

## 📋 概述

此工具集包含两个独立的可执行程序，用于检查系统安全基线配置。它们能自动检测并报告系统中可能存在的安全风险，同时提供相应的修复建议。

## 🧰 工具列表

1. **🔒 SecurityCheck_v5.exe** - 全面的安全基线检测工具，在win7-win8中依赖[Windows Management Framework 5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616)
2. **🐍 checkline_requirePython.exe** - 依赖Python环境的基线检测工具

## 🚀 SecurityCheck_v5.exe

### ✨ 主要功能

1. **📡 FTP 服务与传输功能检查**
   - 检查 FTP 服务安装状态
   - 验证 FTP 客户端功能是否启用
   - 检测 FTP 端口(21)开放状态
   - 审查允许 FTP 流量的防火墙入站规则

2. **💻 网卡信息检查**
   - 详细输出所有网卡信息
   - 检测无线网卡启用状态

3. **⚠️ 高危端口状态检测**
   - 检查高危端口(22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899等)的防火墙策略

4. **🌐 IPv6 禁用状态检查**
   - 验证 IPv6 是否通过注册表方式正确禁用

5. **🛠️ 高危漏洞修复检查**
   - 审查最近已安装的系统更新
   - 提示核实是否包含关键高危漏洞补丁

6. **🔑 密码策略检查**
   - 验证密码策略合规性
   - 检查密码有效期限设置

7. **👤 Guest 用户状态检查**
   - 确认 Guest 用户是否已禁用

8. **💾 U盘自动播放功能设置检查**
   - 验证 U盘自动播放功能禁用状态

9. **🌐 Google 浏览器版本检测**
   - 检查 Google Chrome 浏览器安装状态及版本信息

10. **🔐 锁屏策略检查**
    - 验证锁屏策略是否符合安全要求

### 📝 使用方法

1. **▶️ 运行程序**
   - 双击 `SecurityCheck_v5.exe` 文件启动程序
   - 程序将自动执行安全检查并在控制台输出结果

2. **👁️‍🗨️ 查看结果**
   - 检查完成后，程序会生成详细的检查报告
   - 报告包含合规项✅、不合规项❌及相应修复建议
   - 根据报告建议手动调整系统配置以提高安全性

3. **🚪 退出程序**
   - 检查结束后按回车键退出程序

### 🔄 脚本更新与重新打包

如需修改脚本并重新打包为exe文件，请按以下步骤操作：

#### 🔧 编码修复
```powershell
$content = Get-Content -Path ".\check5.ps1" -Raw
$utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText(".\check5.ps1", $content, $utf8NoBomEncoding)
```


#### 🧪 测试运行脚本
```powershell
powershell -ExecutionPolicy ByPass -File ".\check5.ps1" -Encoding UTF8
```


#### 📦 打包为可执行文件
```powershell
cd C:\Path\To\BaseLineCheck
powershell -ExecutionPolicy ByPass -File ".\build.ps1"
```


## 🐍 checkline_requirePython.exe  
### 主要功能与 SecurityCheck_v5.exe基本相同，有部分系统依赖，但检测较快  

### 📝 使用方法

1. **▶️ 运行程序**
   - 以管理员权限运行 `checkline_requirePython.exe`
   - 程序将自动执行安全检查并输出结果和修复建议
