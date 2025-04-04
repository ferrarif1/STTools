# 密钥和安全设置 (需保持顶部)
$AuthorizedKey = ConvertTo-SecureString "Hzdsz@2025#" -AsPlainText -Force
$EncryptionKey = ConvertTo-SecureString "cxrHzfMfQuihZSE4XRP7rumqZY2mNaCU3BXKYL3TKE3DeNxFJ" -AsPlainText -Force
$MaxTimestampMinutes = 10

#region 兼容性初始化
# 强制启用 TLS 1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# 检查 PowerShell 版本
if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "需要 PowerShell 3.0 或更高版本" -ForegroundColor Red
    Exit
}

# 管理员权限检查
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "请以管理员身份运行此脚本" -ForegroundColor Red
    Exit
}

# 编码设置
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    chcp 65001 > $null
}
#endregion

#region 路径处理
# 脚本路径检测 (兼容旧系统)
try {
    $ScriptDirectory = Split-Path $MyInvocation.MyCommand.Path -Parent
    if (-not $ScriptDirectory) { $ScriptDirectory = Get-Location }
} catch {
    $ScriptDirectory = [System.IO.Directory]::GetCurrentDirectory()
}

# 定义配置文件路径
$ipConfigPath = Join-Path $ScriptDirectory "ip_set_config.json"
$configPath = Join-Path $ScriptDirectory "config.json"
#endregion

#region 通用功能
# 安全字符串转明文
function Convert-SecureStringToPlainText {
    param([System.Security.SecureString]$SecureString)
    
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

# 暂停函数
function Pause-Script {
    Write-Host "按回车键继续..." -ForegroundColor Yellow
    $null = Read-Host
}

# 兼容性JSON解析
function Parse-JsonLegacy {
    param([string]$json)
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        return $serializer.DeserializeObject($json)
    } catch {
        try {
            return $json | ConvertFrom-Json
        } catch {
            throw "无法解析 JSON 数据: $_"
        }
    }
}
#endregion

#region 加密模块
# 加密函数
function Protect-ConfigContent {
    param([string]$Content)
    try {
        $keyPlainText = Convert-SecureStringToPlainText -SecureString $EncryptionKey
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyPlainText)
        
        # 创建随机IV
        $iv = New-Object byte[] 16
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $rng.GetBytes($iv)
        
        # 使用AES加密
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31]
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        # 加密内容
        $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $encryptedBytes = $aes.CreateEncryptor().TransformFinalBlock($contentBytes, 0, $contentBytes.Length)
        
        # 组合数据
        $combinedBytes = $iv + $encryptedBytes
        $encryptedBase64 = [Convert]::ToBase64String($combinedBytes)
        
        # 时间戳处理
        $protectedData = @{
            ipset = $Content
            Content = $encryptedBase64
            Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        }

        return ($protectedData | ConvertTo-Json)
    } finally {
        if ($aes) { $aes.Dispose() }
        if ($rng) { $rng.Dispose() }
    }
}

# 解密函数
function Unprotect-ConfigContent {
    param([string]$ProtectedContent)
    try {
        $protectedData = $ProtectedContent | ConvertFrom-Json
        
        # 多格式时间戳解析
        $formats = @("yyyy-MM-ddTHH:mm:ss", "yyyy/MM/dd HH:mm:ss", "MM/dd/yyyy HH:mm:ss")
        $parsed = $false
        foreach ($fmt in $formats) {
            try {
                $timestamp = [DateTime]::ParseExact($protectedData.Timestamp, $fmt, $null)
                $parsed = $true
                break
            } catch {}
        }
        
        # 解密处理
        $keyPlainText = Convert-SecureStringToPlainText -SecureString $EncryptionKey
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyPlainText)
        $combinedBytes = [Convert]::FromBase64String($protectedData.Content)
        
        $iv = $combinedBytes[0..15]
        $encryptedBytes = $combinedBytes[16..($combinedBytes.Length-1)]
        
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31]
        $aes.IV = $iv
        $decryptedBytes = $aes.CreateDecryptor().TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        
        return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    } catch {
        return '{"ipList":[]}'
    }
}
#endregion

#region 网络检查模块
# 获取当前网段
function Get-CurrentSubnet {
    $networkAdapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
    
    if ($networkAdapters) {
        $adapter = $networkAdapters | Select-Object -First 1
        $ipv4Address = $adapter.IPAddress[0]
        $subnetMask = $adapter.IPSubnet[0]
        
        $ipParts = $ipv4Address -split "\."
        return "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$subnetMask"
    }
    
    Write-Host "无法获取当前 IP 地址，请检查网络连接。" -ForegroundColor Red
    Pause-Script
    Exit
}

# 检查无线网卡状态 (WMI兼容方案)
function Check-WirelessStatus {
    $adapters = Get-WmiObject Win32_NetworkAdapter | Where-Object { 
        $_.Name -match "Wi[- ]?Fi" -or $_.Description -match "Wireless"
    }
    
    if ($adapters) {
        $active = $adapters | Where-Object { $_.NetConnectionStatus -eq 2 }
        if ($active) {
            Write-Host "存在未禁用的无线网卡：" -ForegroundColor Red
            $active | ForEach-Object { Write-Host "  - $($_.Name)" }
            return $false
        }
    }
    return $true
}
#endregion

#region 计划任务模块
# 创建半小时任务 (兼容方案)
function Add-HalfHourTask {
    param([string]$ScriptPath)
    
    $taskName = "SecurityCheckTask"
    $actionScript = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    
    try {
        # 尝试使用 PowerShell 模块
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
        $trigger.Repetition = @{ Interval = 'PT30M'; Duration = 'P999D' }
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount) `
            -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable) -Force
    } catch {
        # 使用 schtasks 后备方案
        $xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT30M</Interval>
      </Repetition>
      <StartBoundary>$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")</StartBoundary>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>SYSTEM</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$ScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
        $tempFile = [System.IO.Path]::GetTempFileName()
        $xmlContent | Out-File $tempFile -Encoding Unicode
        schtasks /Create /XML $tempFile /TN $taskName /F
        Remove-Item $tempFile
    }
}
#endregion

#region 主检查流程

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
function Invoke-SecurityCheck {
    # 获取授权信息
    $currentSubnet = Get-CurrentSubnet
    $authorizedIPs = Get-AuthorizedIPs
    
    # 授权验证
    if (-not ($authorizedIPs -contains $currentSubnet)) {
        $inputKey = Read-Host "请输入授权密钥"
        if ((Convert-SecureStringToPlainText $AuthorizedKey) -ne $inputKey) {
            Write-Host "授权失败" -ForegroundColor Red
            Pause-Script
            Exit
        }
        Add-AuthorizedIP -newSubnet $currentSubnet
    }

    # 执行安全检查
    $results = @()
    
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

 

    try {
        Write-Host "========== 安全检查报告 =========="

        # 1. FTP 服务与传输功能检查
        Write-Host "`n【1】FTP服务与传输功能检查："
        try {
            $ftpService = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
            
            $ftpClientInstalled = $false
            try {
                $ftpCommand = Get-Command "ftp.exe" -ErrorAction SilentlyContinue
                $ftpClientInstalled = ($ftpCommand -ne $null)
            } catch {
                $ftpClientInstalled = $false
            }
            
            $ftpPort = $false
            try {
                $netstatOutput = netstat -ano | Select-String -Pattern ":21\s+"
                if ($netstatOutput) { $ftpPort = $true }
            } catch {
                $ftpPort = $false
            }
            
            # 利用 netsh 检查防火墙中是否存在与 FTP 相关的入站规则
            $fwOutput = netsh advfirewall firewall show rule name=all 2>$null
            $ftpInboundRules = $fwOutput | Select-String -Pattern "FTP"
            
            if ($ftpService) {
                Write-ErrorMsg "检测到FTP服务 (FTPSVC) 已安装且状态为: $($ftpService.Status)"
                Write-Instruction "建议禁用FTP服务，可在【服务】管理器中将FTP服务设置为禁用。"
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
                Write-Instruction "请检查是否有应用使用FTP端口，并停止相关服务。"
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
                Write-ErrorMsg "检测到防火墙中存在与FTP相关的规则："
                $ftpInboundRules | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
                Write-Instruction "请进入【控制面板】>【Windows防火墙】>【高级设置】检查相关规则，建议禁用或设置为阻止。"
                $Results += @{
                    Item       = "FTP防火墙规则"
                    Issue      = "存在与FTP相关的防火墙规则"
                    Suggestion = "请关闭或调整FTP相关规则"
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
                Write-Instruction "建议禁用FTP客户端功能，如在【控制面板】>【程序和功能】中调整。"
                $Results += @{
                    Item       = "FTP客户端"
                    Issue      = "FTP客户端功能已启用"
                    Suggestion = "请取消FTP客户端功能（若环境允许）"
                }
            } else {
                Write-Success "FTP客户端功能未启用，符合安全要求。"
                $Results += @{
                    Item       = "FTP客户端"
                    Issue      = "FTP客户端未启用"
                    Suggestion = "无"
                }
            }
            
            if (-not $ftpService -and -not $ftpPort -and (-not $ftpInboundRules) -and (-not $ftpClientInstalled)) {
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

        # 2. 网卡信息及无线网卡状态检查（使用WMI获取）
        Write-Host "`n【2】网卡信息："
        try {
            $nicConfigs = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"
            if ($nicConfigs) {
                Write-Host "检测到的网卡信息："
                $nicConfigs | ForEach-Object {
                    Write-Host "网卡: $($_.Description) | IP: $($_.IPAddress -join ', ')"
                    $Results += @{
                        Item       = "网卡详情"
                        Issue      = "描述: $($_.Description), IP: $($_.IPAddress -join ', ')"
                        Suggestion = "无"
                    }
                }
                $Results += @{
                    Item       = "网卡信息"
                    Issue      = "检测到 $($nicConfigs.Count) 个IP启用网卡"
                    Suggestion = "请确认网卡状态是否符合预期"
                }
            } else {
                Write-ErrorMsg "未检测到任何IP启用的网卡。"
                $Results += @{
                    Item       = "网卡信息"
                    Issue      = "未检测到IP启用的网卡"
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
        
        # 检查无线网卡状态（利用netsh wlan）
        Write-Host "`n【2-2】无线网卡状态检查："
        try {
            $wlanOutput = netsh wlan show interfaces 2>$null
            if ($wlanOutput -and ($wlanOutput -notmatch "无线接口不存在")) {
                Write-ErrorMsg "检测到无线网卡处于启用状态："
                Write-Host $wlanOutput -ForegroundColor Red
                Write-Instruction "如无线网卡不需要，请在【网络连接】中禁用。"
                $Results += @{
                    Item       = "无线网卡"
                    Issue      = "存在启用的无线网卡"
                    Suggestion = "请禁用未使用的无线网卡"
                }
            } else {
                Write-Success "未检测到启用的无线网卡。"
                $Results += @{
                    Item       = "无线网卡"
                    Issue      = "无线网卡均已禁用或不存在"
                    Suggestion = "无"
                }
            }
        } catch {
            Write-ErrorMsg "检测无线网卡状态时出错: $_"
            $Results += @{
                Item       = "无线网卡"
                Issue      = "检测异常: $_"
                Suggestion = "请手动检查无线网卡状态"
            }
        }
        Write-Seperator

        # 3. 高危端口状态检测（防火墙规则检查，采用 netsh 方式）
        Write-Host "`n【3】高危端口状态检测（防火墙规则检查）："
        $ports = @(22,23,135,137,138,139,445,455,3389,4899)
        foreach ($port in $ports) {
            try {
                $fwRuleOutput = netsh advfirewall firewall show rule name=all 2>$null | Select-String -Pattern "LocalPort\s*:\s*$port"
                if ($fwRuleOutput) {
                    Write-Success "端口 $port 已被防火墙规则封禁（入站或出站）。"
                    $Results += @{
                        Item       = "端口 $port"
                        Issue      = "端口 $port 被封禁"
                        Suggestion = "无"
                    }
                } else {
                    Write-ErrorMsg "端口 $port 未被防火墙规则封禁。"
                    Write-Instruction "请通过【控制面板】>【Windows防火墙】>【高级设置】添加规则封禁该端口。"
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
                    Suggestion = "请检查防火墙配置"
                }
            }
        }
        Write-Seperator

        # 4. 检查 IPv6 是否被禁用（注册表方式）
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
                Write-Instruction "建议修改注册表：将 HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters 下的 DisabledComponents 设置为 255。"
                $Results += @{
                    Item       = "IPv6"
                    Issue      = "IPv6 未完全禁用 (DisabledComponents = $ipv6Value)"
                    Suggestion = "请设置 DisabledComponents = 255"
                }
            }
        } catch {
            Write-ErrorMsg "未检测到 IPv6 禁用相关的注册表设置。"
            Write-Instruction "请手动在注册表中创建 DisabledComponents 并设置为 255。"
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
                Write-Instruction "请进入【控制面板】>【Windows 更新】检查并安装重要更新。"
                $Results += @{
                    Item       = "更新补丁"
                    Issue      = "无法获取更新信息"
                    Suggestion = "请检查Windows更新"
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
            Write-Instruction "请进入【本地安全策略】或【组策略编辑器】调整密码策略，建议最长密码有效期不超过 90 天。"
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

        # 7. 检查 Guest 用户状态（使用 WMI）
        Write-Host "`n【7】Guest 用户状态："
        try {
            $guestUser = Get-WmiObject -Class Win32_UserAccount -Filter "Name='Guest' and LocalAccount=True" 2>$null
            if ($guestUser) {
                if ($guestUser.Disabled) {
                    Write-Success "Guest 用户已禁用。"
                    $Results += @{
                        Item       = "Guest 用户"
                        Issue      = "已禁用"
                        Suggestion = "无"
                    }
                } else {
                    Write-ErrorMsg "Guest 用户仍处于启用状态。"
                    Write-Instruction "请通过【控制面板】>【管理工具】>【计算机管理】中的本地用户和组禁用 Guest 用户。"
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
                Suggestion = "检查本地用户设置"
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
                Write-Instruction "请打开注册表编辑器，将 HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer 下的 NoDriveTypeAutoRun 修改为 255。"
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
                Suggestion = "请手动检查注册表设置"
            }
        }
        Write-Seperator

        # 9. 检查 Google Chrome 版本
        Write-Host "`n【9】Google 浏览器版本检测："
        $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        if (Test-Path $chromePath) {
            try {
                $chromeVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
                Write-Success "检测到 Google Chrome 版本：$chromeVersion。"
                Write-Host "请确认是否为最新版本，如有需要请访问 https://www.google.com/chrome/ 下载最新版本。"
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
                Suggestion = "如需使用，请安装 Google Chrome"
            }
        }
        Write-Seperator

        # 10. 检查锁屏策略（屏保超时及密码保护设置）
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
            Write-ErrorMsg "锁屏策略不符合安全要求！当前超时设置：$timeout 秒。"
            Write-Instruction "请通过组策略编辑器（gpedit.msc）设置屏保超时时间不超过600秒，并启用密码保护。"
            $Results += @{
                Item       = "锁屏策略"
                Issue      = "超时时间：$timeout 秒"
                Suggestion = "请设置超时时间≤600秒并启用密码保护"
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
    # 其他检查项可在此添加...

    # 生成报告
    $results | ConvertTo-Json | Send-CheckResult
}


#endregion

# 主程序入口
try {
    # 读取配置
    if (Test-Path $configPath) {
        $config = Parse-JsonLegacy (Get-Content $configPath -Raw)
        $ScriptPath = $config.scriptPath
        $UploadUrl = $config.uploadUrl
    } else {
        $ScriptPath = "C:\SecurityCheck_v5.exe"
        $UploadUrl = "http://172.16.1.20:8000/log"
    }

    # 创建计划任务
    Add-HalfHourTask -ScriptPath $MyInvocation.MyCommand.Path
    
    # 执行检查
    Invoke-SecurityCheck
}
catch {
    Write-Host "发生错误: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "错误堆栈: $($_.ScriptStackTrace)" -ForegroundColor DarkYellow
}
finally {
    Pause-Script
}