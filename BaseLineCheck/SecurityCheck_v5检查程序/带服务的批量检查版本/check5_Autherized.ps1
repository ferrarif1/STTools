# 配置文件路径
$ipConfigPath = Join-Path $PSScriptRoot "ip_set_config.json"

# 授权密钥（可以更复杂，防止暴力破解）
$AuthorizedKey = "Hzdsz@roundone9a7b7b3a5d50781b4f4768cd7ce223168f6"

# 读取已授权的 IP 网段
function Get-AuthorizedIPs {
    if (Test-Path $ipConfigPath) {
        try {
            $ipConfig = Get-Content $ipConfigPath -Raw | ConvertFrom-Json
            return $ipConfig.ipList
        } catch {
            Write-Host "配置文件格式错误，重新创建。" -ForegroundColor Yellow
            return @()
        }
    } else {
        # 如果文件不存在，创建空配置
        @{} | ConvertTo-Json | Set-Content -Path $ipConfigPath -Encoding UTF8
        return @()
    }
}

# 保存授权的 IP 网段
function Add-AuthorizedIP {
    param (
        [string]$newSubnet
    )
    $authorizedIPs = Get-AuthorizedIPs
    if ($authorizedIPs -notcontains $newSubnet) {
        $authorizedIPs += $newSubnet
        $ipConfig = @{ipList = $authorizedIPs}
        $ipConfig | ConvertTo-Json | Set-Content -Path $ipConfigPath -Encoding UTF8
        Write-Host "已添加新授权网段：$newSubnet" -ForegroundColor Green
    } else {
        Write-Host "网段 $newSubnet 已授权，无需重复添加。" -ForegroundColor Cyan
    }
}

# 获取当前网段信息
function Get-CurrentSubnet {
    $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" } | Select-Object -ExpandProperty IPAddress)[0]
    $subnetMask = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" } | Select-Object -ExpandProperty PrefixLength)[0]

    if (-not $ipAddress) {
        Write-Host "无法获取当前 IP 地址，请检查网络连接。" -ForegroundColor Red
        Exit
    }

    # 计算网段
    $ipParts = $ipAddress -split "\."
    $subnetCIDR = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$subnetMask"
    return $subnetCIDR
}

# 主逻辑：检查 IP 是否已授权
$currentSubnet = Get-CurrentSubnet
$authorizedIPs = Get-AuthorizedIPs

if ($authorizedIPs -contains $currentSubnet) {
    Write-Host "当前网段 ($currentSubnet) 已授权，开始执行安全检查。" -ForegroundColor Green
} else {
    # 如果未授权，提示输入授权密钥
    $UserInputKey = Read-Host "请输入授权密钥"
    if ($UserInputKey -eq $AuthorizedKey) {
        Write-Host "授权成功，添加当前网段到授权列表。" -ForegroundColor Green
        Add-AuthorizedIP -newSubnet $currentSubnet
    } else {
        Write-Host "授权失败，无法执行脚本。" -ForegroundColor Red
        Exit
    }
}

# ============================
# 这里是原来的核心检查逻辑
# ============================
Write-Host "开始执行安全检查..."

# Windows 10/11 客户端安全检查脚本

# 读取配置文件
$configPath = Join-Path $PSScriptRoot "config.json"
try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ScriptPath = $config.scriptPath
    $UploadUrl = $config.uploadUrl
    $FailCache = $config.failCache
} catch {
    Write-Host "无法读取配置文件，使用默认配置" -ForegroundColor Yellow
    # 默认配置
    $ScriptPath = "C:\SecurityCheck_v5.exe"
    $UploadUrl = "http://172.16.1.20:8000/log"
    $FailCache = "C:\check_fail.json"
}

function Send-CheckResult {
    param([string]$JsonData)
    try {
        # 使用UTF8编码转换JSON数据
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonData)
        
        # 创建Web请求
        $request = [System.Net.WebRequest]::Create($UploadUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json; charset=utf-8"
        $request.ContentLength = $utf8Bytes.Length
        
        # 发送数据
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
        $requestStream.Close()
        
        # 获取响应
        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseText = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        
        $responseJson = $responseText | ConvertFrom-Json
        if ($responseJson.status -ne "success") {
            throw "Upload failed"
        }
        
        if (Test-Path $FailCache) { Remove-Item $FailCache -Force }
    } catch {
        Write-Host "上传失败: $_" -ForegroundColor Red
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
            $ftpCommand = Get-Command "ftp.exe" -ErrorAction SilentlyContinue
            $ftpClientInstalled = ($ftpCommand -ne $null)
        } catch {
            $ftpClientInstalled = $false
        }

        # 检查FTP端口是否开放
        $ftpPort = $null
        try {
            $netstat = netstat -ano | Select-String -Pattern ":21\s+"
            $ftpPort = $netstat.Count -gt 0
        } catch {
            $ftpPort = $false
        }
        
        # 检查FTP防火墙规则（可能需要管理员权限）
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
                Item       = "FTP服务"
                Issue      = "FTP 服务已安装，状态为 $($ftpService.Status)"
                Suggestion = "请在【服务】中禁用 FTP 服务"
            }
        } else {
            Write-Success "未检测到FTP服务 (FTPSVC) 安装，符合安全要求。"
            $Results += @{
                Item       = "FTP服务"
                Issue      = "未检测到FTP服务"
                Suggestion = "无"
            }
        }
        
        if ($ftpPort) {
            Write-ErrorMsg "检测到TCP端口21（FTP默认端口）当前处于监听状态。"
            Write-Instruction "请检查是否有应用正在使用FTP端口，并停止相关服务。"
            $Results += @{
                Item       = "FTP端口"
                Issue      = "TCP 21 端口正在监听"
                Suggestion = "请停止相关FTP服务或释放端口"
            }
        } else {
            Write-Success "未检测到TCP端口21（FTP）正在使用。"
            $Results += @{
                Item       = "FTP端口"
                Issue      = "TCP 21 端口未监听"
                Suggestion = "无"
            }
        }
        
        if ($ftpInboundRules) {
            Write-ErrorMsg "检测到允许FTP流量的防火墙入站规则："
            foreach ($rule in $ftpInboundRules) {
                Write-Host "  - $($rule.DisplayName) (已启用)" -ForegroundColor Red
            }
            Write-Instruction "请进入【Windows Defender 防火墙】>【高级设置】禁用这些规则，或将其操作设置为阻止。"
            $Results += @{
                Item       = "FTP防火墙规则"
                Issue      = "存在启用的FTP入站防火墙规则"
                Suggestion = "请关闭这些规则或设置为阻止"
            }
        } else {
            Write-Success "未检测到允许FTP流量的防火墙入站规则。"
            $Results += @{
                Item       = "FTP防火墙规则"
                Issue      = "无FTP防火墙入站规则"
                Suggestion = "无"
            }
        }
        
        if ($ftpClientInstalled) {
            Write-ErrorMsg "FTP客户端功能已启用。"
            Write-Instruction "建议禁用FTP客户端功能。请在【控制面板】>【程序和功能】>【启用或关闭Windows功能】中取消勾选FTP客户端。"
            $Results += @{
                Item       = "FTP客户端"
                Issue      = "FTP客户端功能已启用"
                Suggestion = "请在系统功能中取消 FTP 客户端 勾选"
            }
        } else {
            Write-Success "FTP客户端功能未启用，符合安全要求。"
            $Results += @{
                Item       = "FTP客户端"
                Issue      = "FTP客户端未启用"
                Suggestion = "无"
            }
        }
        
        if (-not $ftpService -and -not $ftpPort -and -not $ftpInboundRules -and -not $ftpClientInstalled) {
            Write-Success "系统未启用FTP相关功能，符合安全基线要求。"
        }
    } catch {
        Write-ErrorMsg "检查FTP功能时发生错误: $_"
        Write-Instruction "请手动检查FTP服务和端口21的状态。"
        $Results += @{
            Item       = "FTP检查"
            Issue      = "检查过程中发生错误: $_"
            Suggestion = "请手动检查FTP服务和端口21的状态"
        }
    }
    Write-Seperator

    # 2. 网卡信息及无线网卡状态检查
    Write-Host "`n【2】网卡信息："
    try {
        $interfaces = Get-NetAdapter | Select-Object Name, Status, InterfaceDescription
        if ($interfaces) {
            Write-Host "检测到的网卡信息："
            $interfaces | Format-Table -AutoSize
            
            # 记录基本网卡摘要信息
            $Results += @{
                Item       = "网卡信息"
                Issue      = "检测到 $($interfaces.Count) 个网卡"
                Suggestion = "确认网卡状态是否符合预期"
            }
            
            # 添加每个网卡的详细信息
            foreach ($nic in $interfaces) {
                $Results += @{
                    Item       = "网卡详情"
                    Issue      = "网卡名称: $($nic.Name), 状态: $($nic.Status), 描述: $($nic.InterfaceDescription)"
                    Suggestion = "无"
                }
            }
            
            # 收集更多网卡参数信息
            $nicDetails = Get-NetAdapter | Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv6Address, DNSServer
            if ($nicDetails) {
                $Results += @{
                    Item       = "网卡IP配置"
                    Issue      = "已获取网卡IP配置信息"
                    Suggestion = "无"
                }
                
                foreach ($nicDetail in $nicDetails) {
                    $ipv4 = if ($nicDetail.IPv4Address) { $nicDetail.IPv4Address.IPAddress } else { "未配置" }
                    $dns = if ($nicDetail.DNSServer.ServerAddresses) { $nicDetail.DNSServer.ServerAddresses -join "," } else { "未配置" }
                    
                    $Results += @{
                        Item       = "网卡配置详情"
                        Issue      = "网卡: $($nicDetail.InterfaceAlias), IPv4: $ipv4, DNS: $dns"
                        Suggestion = "无"
                    }
                }
            }
        } else {
            Write-ErrorMsg "未检测到任何网卡。"
            $Results += @{
                Item       = "网卡信息"
                Issue      = "未检测到任何网卡"
                Suggestion = "请检查网络硬件"
            }
        }
    } catch {
        Write-ErrorMsg "获取网卡信息失败: $_"
        $Results += @{
            Item       = "网卡信息"
            Issue      = "获取网卡信息失败: $_"
            Suggestion = "请检查网络适配器"
        }
    }

    # 检查无线网卡状态
    $wifiAdapters = Get-NetAdapter | Where-Object { $_.Name -match "Wi[- ]?Fi" -or $_.InterfaceDescription -match "Wireless" }
    if ($wifiAdapters) {
        $activeWifi = $wifiAdapters | Where-Object { $_.Status -ne "Disabled" }
        if ($activeWifi) {
            $activeNames = $activeWifi | ForEach-Object { $_.Name } | Out-String
            Write-ErrorMsg "存在未禁用的无线网卡：$activeNames"
            Write-Instruction "请进入【网络连接】界面，右键选择无线网卡并选择禁用。"
            $Results += @{
                Item       = "无线网卡"
                Issue      = "存在未禁用的无线网卡: $activeNames"
                Suggestion = "请禁用未使用的无线网卡"
            }
        } else {
            Write-Success "所有无线网卡均已禁用。"
            $Results += @{
                Item       = "无线网卡"
                Issue      = "所有无线网卡均已禁用"
                Suggestion = "无"
            }
        }
    } else {
        Write-Host "未检测到无线网卡。"
        $Results += @{
            Item       = "无线网卡"
            Issue      = "未检测到无线网卡"
            Suggestion = "无"
        }
    }
    Write-Seperator

    # 3. 高危端口状态检测（防火墙规则检查）
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
                $Results += @{
                    Item       = "端口 $port"
                    Issue      = "端口 $port 被封禁"
                    Suggestion = "无"
                }
            } else {
                Write-ErrorMsg "端口 $port 未被防火墙策略封禁。"
                Write-Instruction "请进入【控制面板】>【Windows Defender 防火墙】>【高级设置】，添加入站规则封禁该端口。"
                $Results += @{
                    Item       = "端口 $port"
                    Issue      = "端口 $port 未封禁"
                    Suggestion = "请封禁该端口"
                }
            }
        } catch {
            Write-ErrorMsg "检测端口 $port 时发生异常: $_"
            $Results += @{
                Item       = "端口 $port"
                Issue      = "检测异常: $_"
                Suggestion = "检查防火墙配置"
            }
        }
    }
    Write-Seperator

    # 4. 检查 IPv6 是否被禁用
    Write-Host "`n【4】IPv6 禁用状态："
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
    try {
        $ipv6Value = (Get-ItemProperty -Path $regPath -Name "DisabledComponents" -ErrorAction SilentlyContinue).DisabledComponents
        if ($ipv6Value -eq 255) {
            Write-Success "IPv6 已通过注册表方式禁用 (DisabledComponents = $ipv6Value)。"
            $Results += @{
                Item       = "IPv6"
                Issue      = "IPv6 已禁用 (DisabledComponents = $ipv6Value)"
                Suggestion = "无"
            }
        } else {
            Write-ErrorMsg "IPv6 可能未完全禁用 (DisabledComponents = $ipv6Value)。"
            Write-Instruction "建议使用注册表方式禁用 IPv6：打开【注册表编辑器】，定位到 HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters，创建或修改 DisabledComponents 的值为 255。"
            $Results += @{
                Item       = "IPv6"
                Issue      = "IPv6 未完全禁用 (DisabledComponents = $ipv6Value)"
                Suggestion = "请设置 DisabledComponents = 255"
            }
        }
    } catch {
        Write-ErrorMsg "未检测到 IPv6 禁用相关的注册表设置。"
        Write-Instruction "请打开【注册表编辑器】，定位到 HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters，创建 DisabledComponents 并设置值为 255。"
        $Results += @{
            Item       = "IPv6"
            Issue      = "未检测到相关注册表设置"
            Suggestion = "请手动设置 DisabledComponents = 255"
        }
    }
    Write-Seperator

    # 5. 高危漏洞修复检查（更新情况）
    Write-Host "`n【5】高危漏洞修复检查（更新情况）："
    try {
        $hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending
        if ($hotfixes) {
            $latest = $hotfixes | Select-Object -First 1
            Write-Success "最新已安装的更新：$($latest.HotFixID)，安装日期：$($latest.InstalledOn)。"
            Write-Host "请核查更新是否包含近期针对高危漏洞的补丁。"
            $Results += @{
                Item       = "更新补丁"
                Issue      = "最新更新：$($latest.HotFixID)，日期：$($latest.InstalledOn)"
                Suggestion = "请核查补丁内容"
            }
        } else {
            Write-ErrorMsg "无法获取已安装更新信息。"
            Write-Instruction "请进入【设置】>【更新与安全】检查 Windows 更新，并安装所有重要更新。"
            $Results += @{
                Item       = "更新补丁"
                Issue      = "无法获取更新信息"
                Suggestion = "请检查 Windows 更新"
            }
        }
    } catch {
        Write-ErrorMsg "获取更新信息失败: $_"
        $Results += @{
            Item       = "更新补丁"
            Issue      = "获取更新信息失败: $_"
            Suggestion = "请手动检查更新"
        }
    }
    Write-Seperator

    # 6. 检查密码策略
    Write-Host "`n【6】密码策略检查："
    try {
        $netAccOutput = net accounts
        Write-Host "【net accounts】输出如下："
        $netAccOutput -split "`n" | ForEach-Object { Write-Host $_.Trim() }
        Write-Instruction "请进入【本地安全策略】或【组策略编辑器】，调整密码策略，将最长密码有效期设置为不超过 90 天。"
        $Results += @{
            Item       = "密码策略"
            Issue      = "net accounts 输出: $netAccOutput"
            Suggestion = "将最长密码有效期设置为不超过 90 天"
        }
    } catch {
        Write-ErrorMsg "获取密码策略信息失败: $_"
        $Results += @{
            Item       = "密码策略"
            Issue      = "获取失败: $_"
            Suggestion = "检查本地安全策略"
        }
    }
    Write-Seperator

    # 7. 检查 Guest 用户状态
    Write-Host "`n【7】Guest 用户状态："
    try {
        $guest = Get-LocalUser -Name Guest -ErrorAction SilentlyContinue
        if ($guest) {
            if ($guest.Enabled -eq $false) {
                Write-Success "Guest 用户已禁用。"
                $Results += @{
                    Item       = "Guest 用户"
                    Issue      = "已禁用"
                    Suggestion = "无"
                }
            } else {
                Write-ErrorMsg "Guest 用户仍处于启用状态。"
                Write-Instruction "请打开【计算机管理】>【本地用户和组】禁用 Guest 用户。"
                $Results += @{
                    Item       = "Guest 用户"
                    Issue      = "仍启用"
                    Suggestion = "请禁用 Guest 用户"
                }
            }
        } else {
            Write-Success "未检测到 Guest 用户（可能已删除）。"
            $Results += @{
                Item       = "Guest 用户"
                Issue      = "未检测到"
                Suggestion = "无"
            }
        }
    } catch {
        Write-ErrorMsg "获取 Guest 用户信息失败: $_"
        $Results += @{
            Item       = "Guest 用户"
            Issue      = "获取信息失败: $_"
            Suggestion = "检查本地用户"
        }
    }
    Write-Seperator

    # 8. 检查 U盘自动播放功能设置
    Write-Host "`n【8】U盘自动播放功能设置："
    $regPathUSB = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer"
    try {
        $noDriveValue = (Get-ItemProperty -Path $regPathUSB -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
        if ($noDriveValue -eq 255) {
            Write-Success "U盘自动播放已禁用 (NoDriveTypeAutoRun = $noDriveValue)。"
            $Results += @{
                Item       = "U盘自动播放"
                Issue      = "已禁用 (NoDriveTypeAutoRun = $noDriveValue)"
                Suggestion = "无"
            }
        } else {
            Write-ErrorMsg "U盘自动播放可能未完全禁用 (NoDriveTypeAutoRun = $noDriveValue)。"
            Write-Instruction "请打开【注册表编辑器】，定位到 HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer，将 NoDriveTypeAutoRun 的值修改为 255。"
            $Results += @{
                Item       = "U盘自动播放"
                Issue      = "未完全禁用 (NoDriveTypeAutoRun = $noDriveValue)"
                Suggestion = "请修改为 255"
            }
        }
    } catch {
        Write-ErrorMsg "获取 U盘自动播放设置失败: $_"
        $Results += @{
            Item       = "U盘自动播放"
            Issue      = "获取设置失败: $_"
            Suggestion = "请手动检查注册表"
        }
    }
    Write-Seperator

    # 9. 检查 Google 浏览器版本
    Write-Host "`n【9】Google 浏览器版本检测："
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromePath) {
        try {
            $chromeVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
            Write-Success "检测到 Google Chrome 版本：$chromeVersion。"
            Write-Host "请确认该版本是否为最新版本，如有必要请访问 https://www.google.com/chrome/ 下载最新版本。"
            $Results += @{
                Item       = "Google Chrome"
                Issue      = "版本：$chromeVersion"
                Suggestion = "请确认是否为最新版本"
            }
        } catch {
            Write-ErrorMsg "获取 Google Chrome 版本信息失败: $_"
            $Results += @{
                Item       = "Google Chrome"
                Issue      = "获取版本信息失败: $_"
                Suggestion = "请手动检查Chrome版本"
            }
        }
    } else {
        Write-Host "未检测到 Google Chrome。"
        $Results += @{
            Item       = "Google Chrome"
            Issue      = "未检测到"
            Suggestion = "如需使用，请安装Google Chrome"
        }
    }
    Write-Seperator

    # 10. 检查锁屏策略
    Write-Host "`n【10】锁屏策略检查："
    $regPathLock = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
    $timeout = (Get-ItemProperty -Path $regPathLock -Name "ScreenSaveTimeOut" -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    $isSecure = (Get-ItemProperty -Path $regPathLock -Name "ScreenSaverIsSecure" -ErrorAction SilentlyContinue).ScreenSaverIsSecure

    if (-not $timeout) {
        $regPathUser = "HKCU:\Control Panel\Desktop"
        $timeout = (Get-ItemProperty -Path $regPathUser -Name "ScreenSaveTimeOut" -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    }
    if (-not $isSecure) {
        $regPathUser = "HKCU:\Control Panel\Desktop"
        $isSecure = (Get-ItemProperty -Path $regPathUser -Name "ScreenSaverIsSecure" -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    }
    if ($timeout) { $timeout = [int]$timeout }
    if ($isSecure) { $isSecure = [int]$isSecure }

    if ($timeout -and $timeout -le 600) {
        Write-Success "锁屏策略符合要求（超时时间：$timeout 秒）。"
        $Results += @{
            Item       = "锁屏策略"
            Issue      = "超时时间：$timeout 秒"
            Suggestion = "无"
        }
    } else {
        Write-ErrorMsg "锁屏策略不符合安全要求！当前设置：超时时间=$timeout 秒"
        Write-Instruction "请打开组策略编辑器（gpedit.msc），依次导航至【计算机配置】>【管理模板】>【控制面板】>【个性化】，将屏幕保护程序超时时间设置为不超过 600 秒，并启用屏幕保护程序需要密码。"
        $Results += @{
            Item       = "锁屏策略"
            Issue      = "超时时间=$timeout 秒"
            Suggestion = "请设置超时时间不超过600秒并启用密码保护"
        }
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
