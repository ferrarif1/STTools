
# Windows 10/11 客户端安全检查脚本

$ScriptPath = "C:\SecurityCheck_v5.exe"
$UploadUrl = "http://172.16.1.20:8000/log"
$FailCache = "C:\check_fail.json"

function Send-CheckResult {
    param([string]$JsonData)
    try {
        $response = Invoke-RestMethod -Uri $UploadUrl -Method POST -Body $JsonData -ContentType "application/json"
        if ($response.status -ne "success") {
            throw "Upload failed"
        }
        if (Test-Path $FailCache) { Remove-Item $FailCache -Force }
    } catch {
        Set-Content -Path $FailCache -Value $JsonData -Encoding UTF8
    }
}

function Retry-FailedUpload {
    if (Test-Path $FailCache) {
        $cached = Get-Content $FailCache -Raw
        Send-CheckResult -JsonData $cached
    }
}


function Add-MonthlyTaskIfNotExists {
    if (-not (Get-ScheduledTask -TaskName "MonthlyCheckTask" -ErrorAction SilentlyContinue)) {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 9am
        Register-ScheduledTask -TaskName "MonthlyCheckTask" -Action $action -Trigger $trigger -RunLevel Highest -Force
    }
}


function Self-CopyIfNeeded {
    if (-not (Test-Path $ScriptPath)) {
        Copy-Item -Path "SecurityCheck_v5.exe" -Destination $ScriptPath -Force
        Add-MonthlyTaskIfNotExists
        exit
    }
}


Self-CopyIfNeeded
Retry-FailedUpload

$Results = @()
# ========== 原始检查逻辑 ==========
# 在脚本最开头添加编码设置
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 定义辅助函数，用于输出成功、错误及修复建议信息
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

try {
    Write-Host "========== 安全检查报告 =========="

    # 1. 检查是否开启或使用FTP传输功能
    Write-Host "`n【1】FTP服务与传输功能检查："
    try {
        # 检查FTP服务是否安装
        $ftpService = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
        
        # 简化FTP客户端功能检查（不需要管理员权限）
        $ftpClientInstalled = $false
        try {
            # 直接检查FTP客户端程序是否存在
            $ftpCommand = Get-Command "ftp.exe" -ErrorAction SilentlyContinue
            $ftpClientInstalled = ($ftpCommand -ne $null)
        } catch {
            # 出错时假设未安装
            $ftpClientInstalled = $false
        }

        # 检查FTP端口是否开放
        $ftpPort = $null
        try {
            # 使用netstat检查21端口（不需要管理员权限）
            $netstat = netstat -ano | Select-String -Pattern ":21\s+"
            $ftpPort = $netstat.Count -gt 0
        } catch {
            # 出错时假设端口未开放
            $ftpPort = $false
        }
        
        # 检查FTP防火墙规则（这部分可能仍然需要管理员权限）
        $ftpInboundRules = $null
        try {
            $ftpInboundRules = Get-NetFirewallRule -DisplayName "*FTP*" -Direction Inbound -Enabled True -ErrorAction SilentlyContinue
        } catch {
            Write-Host "无法获取防火墙规则，可能需要管理员权限。" -ForegroundColor Yellow
        }
        
        if ($ftpService) {
            Write-ErrorMsg "检测到FTP服务 (FTPSVC) 已安装且状态为: $($ftpService.Status)"
            Write-Instruction "出于安全考虑，建议禁用FTP服务。请在【服务】管理器中将FTP服务设置为禁用。"
        
    $Results += @{
        Item = "FTP服务"
        Issue = "FTP 服务已安装，状态为 $($ftpService.Status)"
        Suggestion = "请在【服务】中禁用 FTP 服务"
    }
} else {
            Write-Success "未检测到FTP服务 (FTPSVC) 安装，符合安全要求。"
        }
        
        if ($ftpPort) {
            Write-ErrorMsg "检测到TCP端口21（FTP默认端口）当前处于监听状态。"
            Write-Instruction "请检查是否有应用正在使用FTP端口，并停止相关服务。"
        
    $Results += @{
        Item = "FTP端口"
        Issue = "TCP 21 端口正在监听"
        Suggestion = "请停止相关FTP服务或释放端口"
    }
} else {
            Write-Success "未检测到TCP端口21（FTP）正在使用。"
        }
        
        if ($ftpInboundRules) {
            Write-ErrorMsg "检测到允许FTP流量的防火墙入站规则："
            foreach ($rule in $ftpInboundRules) {
                Write-Host "  - $($rule.DisplayName) (已启用)" -ForegroundColor Red
            
    $Results += @{
        Item = "FTP防火墙规则"
        Issue = "存在启用的FTP入站防火墙规则"
        Suggestion = "请关闭这些规则或设置为阻止"
    }
}
            Write-Instruction "请进入【Windows Defender 防火墙】>【高级设置】禁用这些规则，或将其操作设置为阻止。"
        } else {
            Write-Success "未检测到允许FTP流量的防火墙入站规则。"
        }
        
        if ($ftpClientInstalled) {
            Write-ErrorMsg "FTP客户端功能已启用。"
            Write-Instruction "建议禁用FTP客户端功能。请在【控制面板】>【程序和功能】>【启用或关闭Windows功能】中取消勾选FTP客户端。"
        
    $Results += @{
        Item = "FTP客户端"
        Issue = "FTP客户端功能已启用"
        Suggestion = "请在系统功能中取消 FTP 客户端 勾选"
    }
} else {
            Write-Success "FTP客户端功能未启用，符合安全要求。"
        }
        
        if (-not $ftpService -and -not $ftpPort -and -not $ftpInboundRules -and -not $ftpClientInstalled) {
            Write-Success "系统未启用FTP相关功能，符合安全基线要求。"
        }
    } catch {
        Write-ErrorMsg "检查FTP功能时发生错误: $_"
        Write-Instruction "请手动检查FTP服务和端口21的状态。"
    }
    Write-Seperator

    # 3. 输出所有网卡信息，并检查无线网卡状态
    Write-Host "`n【2】网卡信息："
    try {
        $interfaces = Get-NetAdapter | Select-Object Name, Status, InterfaceDescription
        if ($interfaces) {
            Write-Host "检测到的网卡信息："
            $interfaces | Format-Table -AutoSize
        } else {
            Write-ErrorMsg "未检测到任何网卡。"
        }
    } catch {
        Write-ErrorMsg "获取网卡信息失败: $_"
    }

    # 检查无线网卡状态
    $wifiAdapters = Get-NetAdapter | Where-Object { $_.Name -match "Wi[- ]?Fi" -or $_.InterfaceDescription -match "Wireless" }
    if ($wifiAdapters) {
        $activeWifi = $wifiAdapters | Where-Object { $_.Status -ne "Disabled" }
        if ($activeWifi) {
            $activeNames = $activeWifi | ForEach-Object { $_.Name } | Out-String
            Write-ErrorMsg "存在未禁用的无线网卡：$activeNames"
            Write-Instruction "请进入【网络连接】界面，右键选择无线网卡并选择禁用。"
        } else {
            Write-Success "所有无线网卡均已禁用。"
        }
    } else {
        Write-Host "未检测到无线网卡。"
    }
    Write-Seperator


    # 4. 检查高危端口状态及防火墙策略（仅检测防火墙规则）
    Write-Host "`n【3】高危端口状态检测（防火墙规则检查）："
    $ports = @(22,23,135,137,138,139,445,455,3389,4899)
    foreach ($port in $ports) {
        try {
            $fwInbound = Get-NetFirewallRule -Direction Inbound -Action Block -Enabled True -ErrorAction SilentlyContinue | 
                        Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | 
                        Where-Object { $_.LocalPort -eq "$port" }
            
            $fwOutbound = Get-NetFirewallRule -Direction Outbound -Action Block -Enabled True -ErrorAction SilentlyContinue | 
                        Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | 
                        Where-Object { $_.LocalPort -eq "$port" }
            
            if ($fwInbound -or $fwOutbound) {
                Write-Success "端口 $port 已被防火墙策略封禁（入站或出站）。"
            } else {
                Write-ErrorMsg "端口 $port 未被防火墙策略封禁。"
    Write-Instruction "请进入【控制面板】>【Windows Defender 防火墙】>【高级设置】，添加入站规则封禁该端口。"
    $Results += @{
        Item = "端口封禁"
        Issue = "端口 $port 未封禁"
        Suggestion = "请进入【控制面板】>【Windows Defender 防火墙】>【高级设置】，添加入站规则封禁该端口。"
    }
            }
        } catch {
            Write-ErrorMsg "检测端口 $port 时发生异常: $_"
        }
    }
    Write-Seperator

    # 5. 检查 IPv6 是否被禁用
    Write-Host "`n【4】IPv6 禁用状态："
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
    try {
        $ipv6Value = (Get-ItemProperty -Path $regPath -Name "DisabledComponents" -ErrorAction SilentlyContinue).DisabledComponents
        if ($ipv6Value -eq 255) {
            Write-Success "IPv6 已通过注册表方式禁用 (DisabledComponents = $ipv6Value)。"
        } else {
            Write-ErrorMsg "IPv6 可能未完全禁用 (DisabledComponents = $ipv6Value)。"
            Write-Instruction "建议使用注册表方式禁用 IPv6：打开【注册表编辑器】，定位到 HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters，创建或修改 DisabledComponents 的值为 255。注意：仅在网卡属性中取消 IPv6 勾选并不能彻底禁用 IPv6。"
        }
    } catch {
        Write-ErrorMsg "未检测到 IPv6 禁用相关的注册表设置。"
        Write-Instruction "请打开【注册表编辑器】，定位到 HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters，创建 DisabledComponents 并设置值为 255。"
    }
    Write-Seperator

    # 6. 检查高危漏洞修复情况（查看最近已安装更新）
    Write-Host "`n【5】高危漏洞修复检查（更新情况）："
    try {
        $hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending
        if ($hotfixes) {
            $latest = $hotfixes | Select-Object -First 1
            Write-Success "最新已安装的更新：$($latest.HotFixID)，安装日期：$($latest.InstalledOn)。"
            Write-Host "请核查更新是否包含近期针对高危漏洞的补丁。"
        } else {
            Write-ErrorMsg "无法获取已安装更新信息。"
            Write-Instruction "请进入【设置】>【更新与安全】检查 Windows 更新，并安装所有重要更新。"
        }
    } catch {
        Write-ErrorMsg "获取更新信息失败: $_"
    }
    Write-Seperator

    # 7. 检查密码策略（弱口令检测及口令有效期）
    Write-Host "`n【6】密码策略检查："
    try {
        $netAccOutput = net accounts
        Write-Host "【net accounts】输出如下："
        # 按行输出，去除首尾空白字符
        $netAccOutput -split "`n" | ForEach-Object { Write-Host $_.Trim() }

        Write-Instruction "请进入【本地安全策略】或【组策略编辑器】，调整密码策略，将最长密码有效期设置为不超过 90 天。"
    } catch {
        Write-ErrorMsg "获取密码策略信息失败: $_"
    }
    
    Write-Seperator


    # 8. 检查 Guest 用户状态
    Write-Host "`n【7】Guest 用户状态："
    try {
        $guest = Get-LocalUser -Name Guest -ErrorAction SilentlyContinue
        if ($guest) {
            if ($guest.Enabled -eq $false) {
                Write-Success "Guest 用户已禁用。"
            } else {
                Write-ErrorMsg "Guest 用户仍处于启用状态。"
                Write-Instruction "请打开【计算机管理】>【本地用户和组】禁用 Guest 用户。"
            }
        } else {
            Write-Success "未检测到 Guest 用户（可能已删除）。"
        }
    } catch {
        Write-ErrorMsg "获取 Guest 用户信息失败: $_"
    }
    Write-Seperator

    # 9. 检查 U盘自动播放功能设置
    Write-Host "`n【8】U盘自动播放功能设置："
    $regPathUSB = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer"
    try {
        $noDriveValue = (Get-ItemProperty -Path $regPathUSB -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
        if ($noDriveValue -eq 255) {
            Write-Success "U盘自动播放已禁用 (NoDriveTypeAutoRun = $noDriveValue)。"
        } else {
            Write-ErrorMsg "U盘自动播放可能未完全禁用 (NoDriveTypeAutoRun = $noDriveValue)。"
            Write-Instruction "请打开【注册表编辑器】，定位到 HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer，将 NoDriveTypeAutoRun 的值修改为 255。"
        }
    } catch {
        Write-ErrorMsg "获取 U盘自动播放设置失败: $_"
    }
    Write-Seperator

    # 10. 检查 Google 浏览器版本
    Write-Host "`n【9】Google 浏览器版本检测："
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromePath) {
        try {
            $chromeVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
            Write-Success "检测到 Google Chrome 版本：$chromeVersion。"
            Write-Host "请确认该版本是否为最新版本，如有必要请访问 https://www.google.com/chrome/ 下载最新版本。"
        } catch {
            Write-ErrorMsg "获取 Google Chrome 版本信息失败: $_"
        }
    } else {
        Write-Host "未检测到 Google Chrome。"
    }
    Write-Seperator

   # 11. 检查锁屏策略
    Write-Host "`n【10】锁屏策略检查："

    # 先尝试从组策略路径获取设置
    $regPathLock = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
    $timeout = (Get-ItemProperty -Path $regPathLock -Name "ScreenSaveTimeOut" -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    $isSecure = (Get-ItemProperty -Path $regPathLock -Name "ScreenSaverIsSecure" -ErrorAction SilentlyContinue).ScreenSaverIsSecure

    # 如果组策略路径中未配置，则尝试从当前用户的注册表路径获取（很多情况下设置存放在 HKCU）
    if (-not $timeout) {
        $regPathUser = "HKCU:\Control Panel\Desktop"
        $timeout = (Get-ItemProperty -Path $regPathUser -Name "ScreenSaveTimeOut" -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    }
    if (-not $isSecure) {
        $regPathUser = "HKCU:\Control Panel\Desktop"
        $isSecure = (Get-ItemProperty -Path $regPathUser -Name "ScreenSaverIsSecure" -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    }

    # 转换为整数（有时注册表中保存的是字符串）
    if ($timeout) { $timeout = [int]$timeout }
    if ($isSecure) { $isSecure = [int]$isSecure }

    if ($timeout -and $timeout -le 600) {
        Write-Success "锁屏策略符合要求（超时时间：$timeout 秒）。"
    } else {
        Write-ErrorMsg "锁屏策略不符合安全要求！当前设置：超时时间=$timeout 秒"
        Write-Instruction "请打开组策略编辑器（gpedit.msc），依次导航至【计算机配置】>【管理模板】>【控制面板】>【个性化】，将屏幕保护程序超时时间设置为不超过 600 秒，并启用屏幕保护程序需要密码。"
    }
    Write-Seperator


    Write-Host "`n========== 检查结束 =========="
    Read-Host "按回车键退出..."
} catch {
    Write-Host "发生未捕获错误：$_" -ForegroundColor Red
    Read-Host "按回车键退出..."
}

# ========== 原始检查逻辑 END ==========

if ($Results.Count -gt 0) {
    $Json = $Results | ConvertTo-Json -Depth 5 -Compress
    Send-CheckResult -JsonData $Json
}
