# ==========================================
# YourApp.ps1 （最终整合版：授权 + 校验 + 基线检查 + 上传）
# - 未检测到有效授权 => 授权模式（读取私钥、输入网段/到期、签名生成 license.json）
# - 授权有效 => 直接执行「基线检查 + 结果上传」（已整合自 SecurityCheck.ps1）
# - Win7/Win8 兼容：网络信息使用 WMI
# ==========================================

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Security

# ======= 内置公钥（请粘贴你的 public_key.xml 内容） =======
$PublicKeyXml = @"
<RSAKeyValue><Modulus>piWMBFZTdjnEe2TiDDkayOOb1lSPTE1q9qnyc0hxsJhxQ9leo6XYvxjPSfNZ5WKfUIUR891XO9xJbb4nyCoYuEUTfGf8VdOOCQpp9nMhPG4BYoJVQXe91Ls8Gv3HIxAemlVx1+NBmnOQR5aitf/pTti21Q7KLVqxvrKfUfqWRaK46/q16OZIw+rknwIbsBDkxK8C83fnHJYq120dRLJQC6xgNL9qGKT+kI9T0KI4Ro4f7wvgg5ssRJACZEw/agU3onVor9+s16WSytPaTv2Ga/0tbM3uimPxtOx1R5N5tzjIXR2uCwe5SEold32IcdQ7+G/q+zUzrRF+lLq9KfhmZQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>
"@

# ======= 文件路径 =======
$LicenseFile = "license.json"          # 授权文件（签发/校验用）
$DefaultPrivateKey = "private_key.xml" # 授权模式下优先尝试当前目录

# ======= 输出工具 =======
function I([string]$m){ Write-Host $m -ForegroundColor Cyan }
function G([string]$m){ Write-Host $m -ForegroundColor Green }
function E([string]$m){ Write-Host $m -ForegroundColor Red }

# ======= 工具函数（签名、CIDR、网卡/IP） =======
function Get-CanonicalString {
    param([string]$Expire, [string[]]$AllowedSubnets)
    $subs = @($AllowedSubnets | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Sort-Object)
    return "$Expire|$($subs -join ',')"
}

function Test-IpInCidr {
    param([string]$Ip, [string]$Cidr)
    if ($Cidr -eq "0.0.0.0/0") { return $true }
    $parts = $Cidr.Split("/")
    if ($parts.Count -ne 2) { return $false }
    $subnetIp  = [System.Net.IPAddress]::Parse($parts[0])
    $prefixLen = [int]$parts[1]
    $mask = [uint32]0
    for ($i=0; $i -lt $prefixLen; $i++) { $mask = $mask -bor (1 -shl (31 - $i)) }
    $ipAddr     = [BitConverter]::ToUInt32(([IPAddress]$Ip).GetAddressBytes(),0)
    $subnetAddr = [BitConverter]::ToUInt32($subnetIp.GetAddressBytes(),0)
    return (($ipAddr -band $mask) -eq ($subnetAddr -band $mask))
}

function Get-ActiveIPv4 {
    $ips = @()
    try {
        $cfgs = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction Stop |
                Where-Object { $_.IPEnabled -eq $true -and $_.IPAddress }
        foreach ($cfg in $cfgs) {
            foreach ($ip in $cfg.IPAddress) {
                if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -and $ip -notlike '169.254.*') { $ips += $ip }
            }
        }
    } catch {}
    return ($ips | Sort-Object -Unique)
}

function Test-LicenseValid {
    param([psobject]$License)

    $rsaPub = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
    $rsaPub.PersistKeyInCsp = $false
    $rsaPub.FromXmlString($PublicKeyXml)

    $expire = [string]$License.Data.Expire
    $subs   = [string[]]$License.Data.AllowedSubnets
    $canonical = Get-CanonicalString -Expire $expire -AllowedSubnets $subs
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    $sig   = [Convert]::FromBase64String($License.Signature)
    $sha   = [System.Security.Cryptography.SHA256CryptoServiceProvider]::new()

    if (-not ($rsaPub.VerifyData($bytes, $sha, $sig))) { E "授权验签失败（签名不匹配/被篡改）。"; return $false }

    try { $expireDate = [datetime]::ParseExact($expire, "yyyy-MM-dd", $null) }
    catch { E "授权到期日格式错误，应为 yyyy-MM-dd。"; return $false }
    if ((Get-Date).Date -gt $expireDate.Date) { E "授权已过期：$expire"; return $false }

    $ips = Get-ActiveIPv4
    if (-not $ips -or $ips.Count -eq 0) { E "未检测到有效 IPv4 地址。"; return $false }
    foreach ($ip in $ips) {
        $covered = $false
        foreach ($cidr in $subs) { if (Test-IpInCidr -Ip $ip -Cidr $cidr) { $covered = $true; break } }
        if (-not $covered) { E "本机 IP $ip 不在授权网段内。"; return $false }
    }
    return $true
}

function Enter-AuthorizationMode {
    I "进入授权模式：未检测到有效授权。"

    $privPath = $DefaultPrivateKey
    if (-not (Test-Path $privPath)) { $privPath = Read-Host "请输入私钥路径（private_key.xml）" }
    if (-not (Test-Path $privPath)) { E "未找到私钥：$privPath"; exit 11 }

    $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString((Get-Content -Raw $privPath))

    Write-Host ""
    Write-Host "请输入授权网段：" -ForegroundColor Yellow
    Write-Host "  - 输入 0.0.0.0 表示全网段（等同 0.0.0.0/0）" -ForegroundColor Yellow
    Write-Host "  - 或输入 CIDR（如 10.136.2.0/24）" -ForegroundColor Yellow
    Write-Host "  - 或仅输入网段地址（如 10.136.2.0，将自动补 /24）" -ForegroundColor Yellow
    $inputSubnet = (Read-Host "网段").Trim()
    if ([string]::IsNullOrWhiteSpace($inputSubnet)) { E "输入为空，授权终止。"; exit 12 }
    if ($inputSubnet -eq "0.0.0.0") { $allowed = @("0.0.0.0/0") }
    elseif ($inputSubnet -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$') { $allowed = @($inputSubnet) }
    elseif ($inputSubnet -match '^\d{1,3}(\.\d{1,3}){3}$') { $allowed = @("$inputSubnet/24"); I "未指定掩码，已自动补齐为：$($allowed[0])" }
    else { E "网段格式无效。示例：0.0.0.0 或 10.136.2.0/24 或 10.136.2.0"; exit 13 }

    $expire = (Read-Host "请输入到期日期（YYYY-MM-DD）").Trim()
    try { [void][datetime]::ParseExact($expire, "yyyy-MM-dd", $null) } catch { E "日期格式无效，应为 YYYY-MM-DD。"; exit 14 }

    $canonical = Get-CanonicalString -Expire $expire -AllowedSubnets $allowed
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    $sha   = [System.Security.Cryptography.SHA256CryptoServiceProvider]::new()
    $sig   = $rsa.SignData($bytes, $sha)
    $sigB64= [Convert]::ToBase64String($sig)

    $licenseObj = [pscustomobject]@{
        Data = @{
            IssuedAt       = (Get-Date).ToString("o")
            Expire         = $expire
            AllowedSubnets = $allowed
            Version        = "1"
        }
        Signature = $sigB64
    }

    $licenseObj | ConvertTo-Json -Depth 10 | Set-Content -Path $LicenseFile -Encoding UTF8
    G "已生成/更新授权文件：$LicenseFile"
}

# ======= 基线检查（整合自 SecurityCheck.ps1：从 config.json 读取上传地址并发送结果） =======
function Start-BaselineCheck {
# ==== BEGIN: Embedded from your original SecurityCheck.ps1 (config.json + upload + checks) ====
$configPath = "config.json"

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ScriptPath = $config.scriptPath
    $UploadUrl = $config.uploadUrl
    $FailCache = $config.failCache
} catch {
    Write-Host "无法读取配置文件，使用默认配置" -ForegroundColor Yellow
    # 默认配置
    $ScriptPath = "SecurityCheck_v5.exe"
    $UploadUrl = "http://10.136.72.59:8000/log"
    $FailCache = "check_fail.json"
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
        Write-Host "上传地址:$UploadUrl"
        Send-CheckResult -JsonData $cached
    }
}

# function Add-Task {
#     if (-not (Get-ScheduledTask -TaskName "SecurityCheck_v5_Task" -ErrorAction SilentlyContinue)) {
#         $Action = New-ScheduledTaskAction -Execute "C:\SecurityCheck_v5.exe"
#         #每周二触发
#         $trigger = New-ScheduledTaskTrigger -Monthly -At "14:12" -DaysOfMonth 1
#         #设置此计划任务仅对指定用户生效,同时指定任务优先级
#         $Principal = New-ScheduledTaskPrincipal -UserId (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty UserName) -RunLevel Highest
#         #任务设置,包括电池电源状态时是否保持任务有效
#         $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
#         #可能需要管理员权限才能顺利运行
#         Register-ScheduledTask -TaskName "SecurityCheck_v5_Task" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
#     }
# }

# Add-Task

Retry-FailedUpload

# 创建空数组用于存储所有安全检查的结果
$Results = @()

# ========== 检查逻辑 ==========
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


try {
    Write-Host "========== 安全检查报告 =========="

    # 1. 检查是否开启或使用FTP传输功能
    Write-Host "`n【1】FTP服务与传输功能检查："
    try {
        # 检查 FTP 服务状态
        $ftpService = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue

        # 检查 FTP 端口是否被监听
        $netstat = netstat -an | Select-String ":21\s+"

        if ($netstat) {
            Write-ErrorMsg "检测到 FTP 端口 (21) 被监听。"
            Write-Instruction "请停止使用 FTP 的相关服务或软件。"
            $Results += @{
                Item       = "FTP服务"
                Issue      = "检测到 FTP 端口 (21) 被监听"
            }
        } else {
            Write-Success "端口 21 未被监听。"
        }

        if ($ftpService) {
            Write-ErrorMsg "检测到 FTP 服务已安装，状态: $($ftpService.Status)"
            Write-Instruction "建议禁用 FTP 服务（在服务管理器中设置为禁用）。"
            $Results += @{
                Item       = "FTP服务"
                Issue      = "检测到 FTP 服务已安装，状态: $($ftpService.Status)"
            }
        } else {
            Write-Success "系统未安装 FTP 服务。"
        }

       
        # 检查注册表中的 FTP 服务状态
        $ftpRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\FTPSVC"
        if (Test-Path $ftpRegPath) {
            $ftpServiceStatus = Get-ItemProperty -Path $ftpRegPath -Name "Start" -ErrorAction SilentlyContinue
            if ($ftpServiceStatus.Start -eq 2) {
                Write-ErrorMsg "FTP 服务已设置为自动启动。"
                $Results += @{
                    Item       = "FTP服务注册表"
                    Issue      = "FTP 服务已设置为自动启动。"
                }
            } elseif ($ftpServiceStatus.Start -eq 3) {
                Write-Success "FTP 服务已设置为手动启动。"
            } else {
                Write-Success "FTP 服务未设置为启动。"
            }
        } else {
            Write-Host "未找到 FTP 服务的注册表项。"
        }

    } catch {
        Write-ErrorMsg "检测 FTP 状态时出错：$_"
        $Results += @{
            Item       = "FTP服务"
            Issue      = "检查过程中发生错误: $_"
        }
    }
    Write-Seperator

    # 2. 网卡信息及无线网卡状态检查
    Write-Host "`n【2】网卡信息："
    try {
        $interfaces = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true }
        if ($interfaces) {
            Write-Host "检测到以下启用的网卡："
            $interfaces | Select-Object Name, NetConnectionStatus, Description | Format-Table -AutoSize
           
             # 添加每个网卡的详细信息
            foreach ($nic in $interfaces) {
                $Results += @{
                    Item       = "网卡详情"
                    Issue      = "网卡名称: $($nic.Name), 状态: $($nic.Status), 描述: $($nic.InterfaceDescription)"
                }
            }
        } else {
            Write-ErrorMsg "未检测到启用的网卡。"
        }
    
        $wifi = $interfaces | Where-Object { $_.Description -match "Wireless|Wi-Fi" }
        if ($wifi) {
            Write-ErrorMsg "检测到启用的无线网卡。"
            Write-Instruction "建议禁用无线网卡以加强安全性。"
            $Results += @{
                Item       = "网卡信息"
                Issue      = "检测到启用的无线网卡"
            }
        } else {
            Write-Success "无线网卡已禁用或不存在。"
        }
    } catch {
        Write-ErrorMsg "获取网卡信息失败：$_"
        $Results += @{
            Item       = "网卡信息"
            Issue      = "获取网卡信息失败: $_"
        }
    }

    Write-Seperator

   # 3. 高危端口状态检测（防火墙规则检查）
    Write-Host "`n【3】高危端口状态检测（防火墙规则检查）："
    # 定义要检测的端口列表
    $ports = @(22, 23, 135, 137, 138, 139, 445, 455, 3389)

    # 获取入站和出站防火墙规则文本，并以连续空行作为分隔符拆分成规则块
    $inboundRulesText = netsh advfirewall firewall show rule name=all dir=in | Out-String
    $outboundRulesText = netsh advfirewall firewall show rule name=all dir=out | Out-String
    $inboundRuleBlocks = $inboundRulesText -split "(\r?\n){2,}"
    $outboundRuleBlocks = $outboundRulesText -split "(\r?\n){2,}"

    # 辅助函数：判断单个规则块中是否存在对指定端口的阻止规则  
    # 采用正则表达式提取"LocalPorts/RemotePorts/Port"后面的端口列表（支持逗号、分号或空格分隔）
    # 并检查该规则块中是否同时含有阻止动作（Action: Block、操作: 阻止 或 Deny）
    function IsPortBlockedInRule {
        param(
            [string]$ruleBlock,
            [int]$port
        )
        # 匹配端口列表的正则表达式
        $portListPattern = "(Local\s*Ports?|Remote\s*Ports?|[Pp]ort)[\s:]+(?<ports>(\d+([\s,;]+)?)+)"
        if ($ruleBlock -match $portListPattern) {
            $portsMatched = $matches['ports']
            # 以逗号、分号或空格分隔，过滤掉非数字部分并转换为整数数组
            $portNumbers = $portsMatched -split "[,;\s]+" | Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ }
            if ($portNumbers -contains $port) {
                # 判断规则块是否含有阻止动作（支持 Action: Block、操作: 阻止 或 Deny）
                if ($ruleBlock -match "(Action|操作)[\s:]+(Block|阻止|Deny)") {
                    return $true
                }
            }
        }
        return $false
    }


    foreach ($port in $ports) {
        $inboundBlocked = $false
        $outboundBlocked = $false

        # 检查入站规则块
        foreach ($block in $inboundRuleBlocks) {
            if (IsPortBlockedInRule -ruleBlock $block -port $port) {
                $inboundBlocked = $true
                break
            }
        }
        # 检查出站规则块
        foreach ($block in $outboundRuleBlocks) {
            if (IsPortBlockedInRule -ruleBlock $block -port $port) {
                $outboundBlocked = $true
                break
            }
        }

        if ($inboundBlocked -or $outboundBlocked) {
            Write-Host "端口 $port 已被防火墙封禁 (入站：$inboundBlocked, 出站：$outboundBlocked)" -ForegroundColor Green
        }
        else {
            Write-Host "端口 $port 未被防火墙封禁。" -ForegroundColor Red
            Write-Host "建议在控制面板 -> 防火墙 -> 高级设置中添加入站和出站规则封禁该端口：$port" -ForegroundColor Yellow
            $Results += @{
                Item       = "端口 $port"
                Issue      = "端口未被封禁"
            }
        }
    }

    Write-Seperator


    # 4. 检查 IPv6 是否被禁用
    Write-Host "`n【4】IPv6 禁用状态："
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
        $ipv6Value = (Get-ItemProperty -Path $regPath -Name "DisabledComponents" -ErrorAction SilentlyContinue).DisabledComponents
        if ($ipv6Value -eq 255) {
            Write-Success "IPv6 已禁用。"
        } else {
            Write-ErrorMsg "IPv6 未完全禁用。"
            Write-Instruction "建议设置注册表 DisabledComponents=255 完全禁用 IPv6，通过PowerShell以管理员权限执行: "
            Write-Host 'Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 255 -Type DWord'
            $Results += @{
                Item       = "IPv6"
                Issue      = "IPv6 未完全禁用 (DisabledComponents = $ipv6Value)"
            }
        }
    } catch {
        Write-ErrorMsg "未检测到 IPv6 注册表设置。"
    }
    Write-Seperator

    # 5. 高危漏洞修复检查（更新情况）
    Write-Host "`n【5】高危漏洞修复检查（更新情况）："
    try {
        $hotfix = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($hotfix) {
            Write-Success "最近安装的更新：$($hotfix.HotFixID)，时间：$($hotfix.InstalledOn)"
            $Results += @{
                Item       = "高危漏洞修复检查"
                Issue      = "最近安装的更新：$($hotfix.HotFixID)，时间：$($hotfix.InstalledOn)"
            }
        } else {
            Write-ErrorMsg "未获取到更新信息。"
        }
    } catch {
        Write-ErrorMsg "检查更新失败：$_"
        $Results += @{
            Item       = "高危漏洞修复检查"
            Issue      = "检查更新失败"
        }
    }
    Write-Seperator

    # 6. 检查密码策略
    Write-Host "`n【6】密码策略检查："
    try {
        $netAccOutput = net accounts
        Write-Host "【net accounts】输出如下："
        $netAccOutput -split "`n" | ForEach-Object { Write-Host $_.Trim() }
        Write-Instruction "查看以上输出的Maximum password age (days)值，若大于90，则不符合要求，需设置为90天。"
        $Results += @{
            Item       = "密码策略"
            Issue      = "net accounts 输出: $netAccOutput"
        }
    } catch {
        Write-ErrorMsg "获取密码策略信息失败: $_"
        $Results += @{
            Item       = "密码策略"
            Issue      = "获取失败: $_"
        }
    }
    Write-Seperator

    # 7. 检查 Guest 用户状态
    Write-Host "`n【7】Guest 用户状态："
    try {
        $guest = Get-WmiObject -Class Win32_UserAccount | Where-Object { $_.Name -eq "Guest" }
        if ($guest) {
            if ($guest.Disabled) {
                Write-Success "Guest 用户已禁用。"
            } else {
                Write-ErrorMsg "Guest 用户仍处于启用状态。"
                Write-Instruction "请打开【计算机管理】>【本地用户和组】禁用 Guest 用户。"
                $Results += @{
                    Item       = "Guest 用户"
                    Issue      = "Guest 用户启用"
                }
            }
        } else {
            Write-Success "未检测到 Guest 用户（可能已删除）。"
        }
    } catch {
        Write-ErrorMsg "获取 Guest 用户信息失败: $_"
        $Results += @{
            Item       = "Guest 用户"
            Issue      = "获取信息失败: $_"
        }
    }
    Write-Seperator

    # 8. 检查 U盘自动播放功能设置
    Write-Host "`n【8】U盘自动播放功能设置："
    try {
        
        # 检查注册表中的 NoDriveTypeAutoRun 值（优先看HKLM，其次HKCU）
        function Get-AutoPlaySetting {
            $regPaths = @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            )
        
            foreach ($path in $regPaths) {
                if (Test-Path $path) {
                    $value = Get-ItemProperty -Path $path -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue
                    if ($value -ne $null) {
                        return [int]$value.NoDriveTypeAutoRun
                    }
                }
            }
        
            return $null
        }
        
        # 判断 NoDriveTypeAutoRun 设置的值
        $autoPlayValue = Get-AutoPlaySetting
        
        if ($autoPlayValue -eq $null) {
            Write-Host "未找到 AutoPlay 策略配置，可能未设置。" -ForegroundColor Yellow
        } else {
            $hexValue = "{0:X}" -f $autoPlayValue
            Write-Host "当前 NoDriveTypeAutoRun 值为：$autoPlayValue (Hex: 0x$hexValue)"
        
            # 判断是否禁用U盘自动播放（移除驱动器：0x04）
            if (($autoPlayValue -band 0x04) -ne 0) {
                Write-Success "已禁用可移动驱动器（U盘）的自动播放。" -ForegroundColor Green
            } else {
                Write-ErrorMsg "未禁用 U盘自动播放，建议修改为禁用。" -ForegroundColor Red
            }
        }
    } catch {
        Write-ErrorMsg "读取 U盘 自动播放设置失败。"
        $Results += @{
            Item       = "U盘自动播放"
            Issue      = "获取设置失败: $_"
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
            }
        } catch {
            Write-ErrorMsg "获取 Google Chrome 版本信息失败: $_"
            $Results += @{
                Item       = "Google Chrome"
                Issue      = "获取版本信息失败: $_"
            }
        }
    } else {
        Write-Host "未检测到 Google Chrome。"
        $Results += @{
            Item       = "Google Chrome"
            Issue      = "未检测到"
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
    } else {
        Write-ErrorMsg "锁屏策略不符合安全要求！当前设置：超时时间=$timeout 秒"
        Write-Instruction "请打开组策略编辑器（gpedit.msc），依次导航至【计算机配置】>【管理模板】>【控制面板】>【个性化】，将屏幕保护程序超时时间设置为不超过 600 秒，并启用屏幕保护程序需要密码。"
        $Results += @{
            Item       = "锁屏策略"
            Issue      = "超时时间=$timeout 秒"
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
    Write-Host "上传地址:$UploadUrl"
    Send-CheckResult -JsonData $Json
}


# ==== END: Embedded section ====
}

# ================= 主流程 =================
$needAuth = $true
if (Test-Path $LicenseFile) {
    try {
        $lic = Get-Content -Raw $LicenseFile | ConvertFrom-Json
        $needAuth = -not (Test-LicenseValid -License $lic)
    } catch {
        $needAuth = $true
    }
}

if ($needAuth) {
    Enter-AuthorizationMode
    try { $lic = Get-Content -Raw $LicenseFile | ConvertFrom-Json } catch { E "授权文件无效。"; Read-Host "按回车键退出..."; exit 15 }
    if (-not (Test-LicenseValid -License $lic)) {
        E "授权生成后校验仍失败，请检查私钥/时间/网段。"
        Read-Host "按回车键退出..."
        exit 16
    }
}

G "授权校验通过：有效期至 $($lic.Data.Expire)，允许网段：$($lic.Data.AllowedSubnets -join ', ')"
Start-BaselineCheck
