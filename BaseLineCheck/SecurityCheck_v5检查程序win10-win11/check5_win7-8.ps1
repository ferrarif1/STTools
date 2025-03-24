
# 设置 PowerShell 控制台输出编码为 UTF8（兼容 Win7/8）
$OutputEncoding = New-Object -typename System.Text.UTF8Encoding
[Console]::OutputEncoding = New-Object -typename System.Text.UTF8Encoding

function Write-Success($msg) {
    Write-Host "✔ $msg" -ForegroundColor Green
}
function Write-ErrorMsg($msg) {
    Write-Host "✖ $msg" -ForegroundColor Red
}
function Write-Instruction($msg) {
    Write-Host "修复建议：$msg" -ForegroundColor Yellow
}
function Write-Seperator {
    Write-Host "--------"
}

Write-Host "========== 安全检查报告 =========="

# 检查 FTP 服务状态
Write-Host "`n【1】FTP服务与传输功能检查："
try {
    $ftpService = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue

    $ftpClientInstalled = Get-Command "ftp.exe" -ErrorAction SilentlyContinue
    if ($ftpClientInstalled) {
        Write-ErrorMsg "FTP客户端功能已启用。"
        Write-Instruction "建议在‘控制面板’>‘启用或关闭Windows功能’中禁用 FTP 客户端。"
    } else {
        Write-Success "FTP 客户端未启用。"
    }

    $netstat = netstat -an | Select-String ":21\s+"
    if ($netstat) {
        Write-ErrorMsg "检测到 FTP 端口 (21) 被监听。"
        Write-Instruction "请停止使用 FTP 的相关服务或软件。"
    } else {
        Write-Success "端口 21 未被监听。"
    }

    if ($ftpService) {
        Write-ErrorMsg "检测到 FTP 服务已安装，状态: $($ftpService.Status)"
        Write-Instruction "建议禁用 FTP 服务（在服务管理器中设置为禁用）。"
    } else {
        Write-Success "系统未安装 FTP 服务。"
    }
} catch {
    Write-ErrorMsg "检测 FTP 状态时出错：$_"
}
Write-Seperator

# 网卡信息检查
Write-Host "`n【2】网卡信息检查："
try {
    $interfaces = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true }
    if ($interfaces) {
        Write-Host "检测到以下启用的网卡："
        $interfaces | Select-Object Name, NetConnectionStatus, Description | Format-Table -AutoSize
    } else {
        Write-ErrorMsg "未检测到启用的网卡。"
    }

    $wifi = $interfaces | Where-Object { $_.Description -match "Wireless|Wi-Fi" }
    if ($wifi) {
        Write-ErrorMsg "检测到启用的无线网卡。"
        Write-Instruction "建议禁用无线网卡以加强安全性。"
    } else {
        Write-Success "无线网卡已禁用或不存在。"
    }
} catch {
    Write-ErrorMsg "获取网卡信息失败：$_"
}
Write-Seperator

# 高危端口检测（使用 netsh 替代 Get-NetFirewallRule）
Write-Host "`n【3】高危端口检测："
$ports = @(22,23,135,137,138,139,445,455,3389,4899)
foreach ($port in $ports) {
    $ruleCheck = netsh advfirewall firewall show rule name=all | Select-String "Port: $port"
    if ($ruleCheck) {
        Write-Success "端口 $port 存在防火墙规则。"
    } else {
        Write-ErrorMsg "端口 $port 未设置防火墙封禁。"
        Write-Instruction "建议手动设置防火墙封禁该端口。"
    }
}
Write-Seperator

# IPv6 禁用检查
Write-Host "`n【4】IPv6 禁用状态："
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
    $ipv6Value = (Get-ItemProperty -Path $regPath -Name "DisabledComponents" -ErrorAction SilentlyContinue).DisabledComponents
    if ($ipv6Value -eq 255) {
        Write-Success "IPv6 已禁用。"
    } else {
        Write-ErrorMsg "IPv6 未完全禁用。"
        Write-Instruction "建议设置注册表 DisabledComponents=255 完全禁用 IPv6。"
    }
} catch {
    Write-ErrorMsg "未检测到 IPv6 注册表设置。"
}
Write-Seperator

# 最近系统更新
Write-Host "`n【5】系统更新检查："
try {
    $hotfix = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($hotfix) {
        Write-Success "最近安装的更新：$($hotfix.HotFixID)，时间：$($hotfix.InstalledOn)"
    } else {
        Write-ErrorMsg "未获取到更新信息。"
    }
} catch {
    Write-ErrorMsg "检查更新失败：$_"
}
Write-Seperator

# Guest 用户状态
Write-Host "`n【6】Guest 用户状态："
try {
    $guest = Get-WmiObject -Class Win32_UserAccount | Where-Object { $_.Name -eq "Guest" }
    if ($guest) {
        if (-not $guest.Disabled) {
            Write-ErrorMsg "Guest 用户已启用。"
            Write-Instruction "请在‘计算机管理’中禁用 Guest 用户。"
        } else {
            Write-Success "Guest 用户已禁用。"
        }
    } else {
        Write-Success "系统无 Guest 用户。"
    }
} catch {
    Write-ErrorMsg "获取 Guest 用户失败：$_"
}
Write-Seperator

# USB 自动播放设置
Write-Host "`n【7】U盘自动播放设置："
try {
    $regPathUSB = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer"
    $noDriveValue = (Get-ItemProperty -Path $regPathUSB -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
    if ($noDriveValue -eq 255) {
        Write-Success "U盘自动播放已禁用。"
    } else {
        Write-ErrorMsg "U盘自动播放未禁用 (当前值: $noDriveValue)。"
    }
} catch {
    Write-ErrorMsg "读取 U盘 自动播放设置失败。"
}
Write-Seperator

# 锁屏策略检查
Write-Host "`n【8】锁屏策略检查："
$regPath = "HKCU:\Control Panel\Desktop"
try {
    $timeout = (Get-ItemProperty -Path $regPath -Name "ScreenSaveTimeOut" -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    $secure = (Get-ItemProperty -Path $regPath -Name "ScreenSaverIsSecure" -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    if ($timeout -and [int]$timeout -le 600 -and $secure -eq "1") {
        Write-Success "锁屏策略符合要求（$timeout 秒，需输入密码）"
    } else {
        Write-ErrorMsg "锁屏策略不符合要求（当前值: $timeout 秒，密码保护: $secure）"
        Write-Instruction "建议设置超时≤600秒，且启用密码保护。"
    }
} catch {
    Write-ErrorMsg "读取锁屏设置失败。"
}
Write-Seperator

Write-Host "`n========== 检查结束 =========="
Read-Host "按回车退出..."
