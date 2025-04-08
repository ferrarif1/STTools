# === 密钥和安全设置 ===
$AuthorizedKey = ConvertTo-SecureString "Hzdsz@2025#" -AsPlainText -Force
$EncryptionKey = ConvertTo-SecureString "cxrHzfMfQuihZSE4XRP7rumqZY2mNaCU3BXKYL3TKE3DeNxFJ" -AsPlainText -Force
$MaxTimestampMinutes = 10

# 脚本路径检测
try {
    $ScriptDirectory = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
    if ([string]::IsNullOrEmpty($ScriptDirectory)) {
        $ScriptDirectory = [System.IO.Directory]::GetCurrentDirectory()
    }
} catch {
    $ScriptDirectory = [System.IO.Directory]::GetCurrentDirectory()
}

# 定义配置文件路径
$ipConfigPath = [System.IO.Path]::Combine($ScriptDirectory, "ip_set_config.json")

# === 辅助函数区 ===

# 将安全字符串转换为明文
function Convert-SecureStringToPlainText {
    param([System.Security.SecureString]$SecureString)
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

# 脚本暂停
function Pause-Script {
    Write-Host "按回车键继续..." -ForegroundColor Yellow
    Read-Host
}

# 日志记录函数（支持事件日志）
function Write-LogEntry {
    param(
        [string]$Message,
        [string]$EventType = "Information",
        [int]$EventId = 1000
    )
    Write-Host $Message
    try {
        Write-EventLog -LogName "Application" -Source "SecurityCheck" -EventId $EventId -EntryType $EventType -Message $Message -ErrorAction SilentlyContinue
    } catch {
        # 出错则忽略
    }
}

# 添加 ProtectedData 类所需的程序集引用
Add-Type -AssemblyName System.Security

# --- 加密与解密函数 ---
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
        $aes.Key = $keyBytes[0..31]    # 前32字节作为密钥
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($contentBytes, 0, $contentBytes.Length)
        # 组合IV和加密内容，并转换为 Base64
        $combinedBytes = $iv + $encryptedBytes
        $encryptedBase64 = [Convert]::ToBase64String($combinedBytes)
        # 创建带有时间戳的JSON结构
        $protectedData = @{
            ipset     = $Content
            Content   = $encryptedBase64
            Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        }
        return ($protectedData | ConvertTo-Json)
    } catch {
        Write-Host "加密配置文件失败: $_" -ForegroundColor Red
        throw
    } finally {
        if ($aes) { $aes.Dispose() }
        if ($rng) { $rng.Dispose() }
    }
}

function Unprotect-ConfigContent {
    param([string]$ProtectedContent)
    try {
        $protectedData = $ProtectedContent | ConvertFrom-Json
        # 验证时间戳
        try {
            $timestamp = [DateTime]::ParseExact($protectedData.Timestamp, "yyyy-MM-ddTHH:mm:ss", $null)
            $timeSpan = (Get-Date) - $timestamp
            if ($timeSpan.TotalMinutes -gt $MaxTimestampMinutes) {
                Write-Host "配置文件时间戳已过期" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "时间戳格式无效，跳过验证" -ForegroundColor Yellow
        }
        $keyPlainText = Convert-SecureStringToPlainText -SecureString $EncryptionKey
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyPlainText)
        $combinedBytes = [Convert]::FromBase64String($protectedData.Content)
        $iv = $combinedBytes[0..15]
        $encryptedBytes = $combinedBytes[16..($combinedBytes.Length-1)]
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31]
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        $decryptedContent = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
        return $decryptedContent
    }
    catch {
        Write-Host "解密配置文件失败: $_" -ForegroundColor Red
        return '{"ipList":[]}'
    }
    finally {
        if ($aes) { $aes.Dispose() }
    }
}

# --- 辅助函数：将 IP 与子网掩码转换为 CIDR 格式 ---
function ConvertTo-CIDR {
    param(
        [string]$IPAddress,
        [string]$SubnetMask
    )
    $maskBytes = $SubnetMask.Split('.') | ForEach-Object { [int]$_ }
    $binary = $maskBytes | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8,"0") }
    $prefix = (($binary -join "") -ToCharArray() | Where-Object { $_ -eq "1" }).Count
    # 计算网络地址（逐位与运算）
    $ipBytes = $IPAddress.Split('.') | ForEach-Object { [int]$_ }
    $networkBytes = for ($i=0; $i -lt 4; $i++) { $ipBytes[$i] -band $maskBytes[$i] }
    $networkAddress = $networkBytes -join "."
    return "$networkAddress/$prefix"
}

# --- 获取当前网段（使用 WMI 兼容 Windows 7/8） ---
function Get-CurrentSubnet {
    $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" 2>$null
    if ($adapters) {
        # 优先选择具有默认网关的适配器
        $adapter = $adapters | Where-Object { $_.DefaultIPGateway } | Select-Object -First 1
        if (-not $adapter) {
            $adapter = $adapters | Select-Object -First 1
        }
        if ($adapter.IPAddress.Count -gt 0 -and $adapter.IPSubnet.Count -gt 0) {
            $ipAddress = $adapter.IPAddress[0]
            $subnetMask = $adapter.IPSubnet[0]
            $cidr = ConvertTo-CIDR -IPAddress $ipAddress -SubnetMask $subnetMask
            Write-Host "使用适配器: $($adapter.Description), IP: $ipAddress" -ForegroundColor Cyan
            return $cidr
        }
    }
    Write-Host "无法获取当前 IP 地址，请检查网络连接。" -ForegroundColor Red
    Pause-Script
    Exit
}

# --- 设置文件权限 ---
function Set-SecureFilePermissions {
    param([string]$FilePath)
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $systemAccount = "NT AUTHORITY\SYSTEM"
        $acl = Get-Acl $FilePath
        $acl.SetAccessRuleProtection($true, $false)  # 禁用继承
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
        $rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "Allow")
        $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($systemAccount, "FullControl", "Allow")
        $acl.AddAccessRule($rule1)
        $acl.AddAccessRule($rule2)
        Set-Acl -Path $FilePath -AclObject $acl
    }
    catch {
        Write-EventLog -LogName "Application" -Source "SecurityCheck" -EntryType Error -EventId 1003 -Message "设置文件权限失败: $_"
        throw
    }
}

# --- 读取和添加已授权的 IP ---
function Get-AuthorizedIPs {
    if (Test-Path $ipConfigPath) {
        try {
            $encryptedContent = Get-Content $ipConfigPath -Raw
            $decryptedContent = Unprotect-ConfigContent $encryptedContent
            $ipConfig = $decryptedContent | ConvertFrom-Json
            $currentDate = Get-Date
            $validIPs = @()
            foreach ($ip in $ipConfig.ipList) {
                $expiryDate = [DateTime]::ParseExact($ip.expiryDate, "yyyy-MM-dd", $null)
                if ($currentDate -le $expiryDate) {
                    $validIPs += $ip.subnet
                }
            }
            return $validIPs
        }
        catch {
            Write-EventLog -LogName "Application" -Source "SecurityCheck" -EntryType Error -EventId 1004 -Message "配置文件读取失败，重新创建。"
            return @()
        }
    }
    else {
        $newConfig = @{ ipList = @() } | ConvertTo-Json
        $encryptedConfig = Protect-ConfigContent $newConfig
        $encryptedConfig | Set-Content -Path $ipConfigPath -Encoding UTF8
        Set-SecureFilePermissions $ipConfigPath
        return @()
    }
}

function Add-AuthorizedIP {
    param ([string]$newSubnet)
    $expiryDate = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
    try {
        if (-not (Test-Path $ipConfigPath)) {
            $defaultConfig = @{ ipList = @() } | ConvertTo-Json -Depth 3
            $encryptedConfig = Protect-ConfigContent $defaultConfig
            $encryptedConfig | Set-Content -Path $ipConfigPath -Encoding UTF8
            try { Set-SecureFilePermissions $ipConfigPath } catch { Write-Host "无法设置文件权限，继续执行" -ForegroundColor Yellow }
        }
        $encryptedContent = Get-Content $ipConfigPath -Raw -ErrorAction Stop
        $decryptedContent = Unprotect-ConfigContent $encryptedContent
        try {
            $ipConfig = $decryptedContent | ConvertFrom-Json
            if (-not ($ipConfig.PSObject.Properties | Where-Object { $_.Name -eq "ipList" })) {
                $ipConfig = @{ ipList = @() } | ConvertTo-Json | ConvertFrom-Json
            }
        } catch {
            Write-Host "解析配置失败，创建新配置" -ForegroundColor Yellow
            $ipConfig = @{ ipList = @() } | ConvertTo-Json | ConvertFrom-Json
        }
        $ipListArray = @()
        if ($ipConfig.ipList -ne $null) {
            foreach ($item in $ipConfig.ipList) { $ipListArray += $item }
        }
        $existingIndex = -1
        for ($i=0; $i -lt $ipListArray.Count; $i++) {
            if ($ipListArray[$i].subnet -eq $newSubnet) { $existingIndex = $i; break }
        }
        if ($existingIndex -ge 0) {
            $ipListArray[$existingIndex].expiryDate = $expiryDate
            Write-Host "网段 $newSubnet 授权已更新，新的到期日期：$expiryDate" -ForegroundColor Cyan
        } else {
            $newIP = @{ subnet = $newSubnet; expiryDate = $expiryDate; addedDate = (Get-Date).ToString("yyyy-MM-dd") }
            $ipListArray += $newIP
            Write-Host "已添加新授权网段：$newSubnet，到期日期：$expiryDate" -ForegroundColor Green
        }
        $newConfig = @{ ipList = $ipListArray }
        $newConfigJson = $newConfig | ConvertTo-Json -Depth 3
        $encryptedConfig = Protect-ConfigContent $newConfigJson
        $encryptedConfig | Set-Content -Path $ipConfigPath -Encoding UTF8 -Force
        try { Set-SecureFilePermissions $ipConfigPath } catch { Write-Host "无法设置文件权限，继续执行" -ForegroundColor Yellow }
        return $true
    } catch {
        Write-Host "添加网段时发生错误: $_" -ForegroundColor Red
        try {
            $fallbackConfig = @{ 
                ipList = @(
                    @{ subnet = $newSubnet; expiryDate = $expiryDate; addedDate = (Get-Date).ToString("yyyy-MM-dd") }
                )
            }
            $fallbackJson = $fallbackConfig | ConvertTo-Json -Depth 3
            $encryptedFallback = Protect-ConfigContent $fallbackJson
            Set-Content -Path $ipConfigPath -Value $encryptedFallback -Encoding UTF8 -Force
            Write-Host "已创建应急配置文件" -ForegroundColor Yellow
            return $true
        } catch {
            Write-Host "创建应急配置失败: $_" -ForegroundColor Red
            return $false
        }
    }
}

# --- 计划任务创建（兼容 Windows 7/8，使用 schtasks 命令） ---
function Add-CorrectedHalfHourlyTaskForTesting {
    # 查询任务是否已存在（使用 schtasks 命令）
    $taskExists = schtasks /Query /TN "HalfHourlyTestTask" 2>$null
    if (-not $taskExists) {
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        $taskCreateCmd = "schtasks /Create /TN `"HalfHourlyTestTask`" /SC MINUTE /MO 30 /TR `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"`" /ST $startTime /RL HIGHEST /F"
        Invoke-Expression $taskCreateCmd
    }
}

# --- Guest 用户状态检测（使用 net user 命令） ---
function Get-GuestUserStatus {
    $result = net user Guest 2>$null | Out-String
    if ($result -match "Account active\s+No") {
        return $false
    } elseif ($result -match "Account active\s+Yes") {
        return $true
    } else {
        return $null
    }
}

# --- 防火墙规则检测辅助函数 ---
function Test-FirewallPortBlock {
    param([int]$port)
    try {
        $fwRulesOutput = netsh advfirewall firewall show rule name=all /v /fo list 2>$null | Out-String
        if ($fwRulesOutput -match "LocalPort\s*:\s*$port" -and $fwRulesOutput -match "Action\s*:\s*Block") {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

# --- 主流程 ---
try {
    # 获取当前网段并检测授权
    $currentSubnet = Get-CurrentSubnet
    Write-Host "当前网段: $currentSubnet" -ForegroundColor Cyan
    $authorizedIPs = Get-AuthorizedIPs
    Write-Host "已授权网段: $($authorizedIPs -join ', ')" -ForegroundColor Cyan
    if ($authorizedIPs -contains $currentSubnet) {
        Write-Host "当前网段 ($currentSubnet) 已授权，开始执行安全检查。" -ForegroundColor Green
    } else {
        $UserInputKey = Read-Host "请输入授权密钥"
        $AuthKeyPlainText = Convert-SecureStringToPlainText -SecureString $AuthorizedKey
        if ($AuthKeyPlainText -eq $UserInputKey) {
            Write-Host "授权成功，添加当前网段到授权列表。" -ForegroundColor Green
            Add-AuthorizedIP -newSubnet $currentSubnet
        } else {
            Write-Host "授权失败，无法执行脚本。" -ForegroundColor Red
            Pause-Script
            Exit
        }
    }
} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Write-Host "错误位置: $($_.ScriptStackTrace)" -ForegroundColor Red
    Pause-Script
    Exit
}

# 脚本最后保持窗口打开
Pause-Script

# === Windows 10/11 客户端安全检查脚本（兼容 Windows 7/8 改写版本） ===

# 读取配置文件
$configPath = Join-Path $ScriptDirectory "config.json"
try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ScriptPath = $config.scriptPath
    $UploadUrl = $config.uploadUrl
    $FailCache = $config.failCache
} catch {
    Write-Host "无法读取配置文件，使用默认配置" -ForegroundColor Yellow
    $ScriptPath = "SecurityCheck_v5.exe"
    $UploadUrl = "http://10.136.72.59:8000/log"
    $FailCache = "check_fail.json"
}

function Send-CheckResult {
    param([string]$JsonData)
    try {
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonData)
        $request = [System.Net.WebRequest]::Create($UploadUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json; charset=utf-8"
        $request.ContentLength = $utf8Bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
        $requestStream.Close()
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

# 创建计划任务（可选，如需开启半小时重复任务请取消注释）
# Add-CorrectedHalfHourlyTaskForTesting

Retry-FailedUpload

# 用于存储所有安全检查结果的数组
$Results = @()

# 设置输出编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 输出辅助函数
function Write-Success($msg) { Write-Host "✔ $msg" -ForegroundColor Green }
function Write-ErrorMsg($msg) { Write-Host "✖ $msg" -ForegroundColor Red }
function Write-Instruction($msg) { Write-Host "修复建议：$msg" -ForegroundColor Yellow }
function Write-Seperator { Write-Host "--------" }

# ==== 检查逻辑 ====

# 【1】FTP服务与传输功能检查
Write-Host "`n【1】FTP服务与传输功能检查："
try {
    $ftpService = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
    $ftpClientInstalled = $false
    try {
        $ftpCommand = Get-Command "ftp.exe" -ErrorAction SilentlyContinue
        $ftpClientInstalled = ($ftpCommand -ne $null)
    } catch { $ftpClientInstalled = $false }
    $ftpPortActive = $false
    try {
        $netstat = netstat -ano | Select-String -Pattern ":21\s+"
        $ftpPortActive = $netstat.Count -gt 0
    } catch { $ftpPortActive = $false }
    
    # 检查防火墙规则（使用 netsh 命令）
    $ftpFirewallOutput = netsh advfirewall firewall show rule name=all 2>$null | Out-String
    $ftpInboundRules = ($ftpFirewallOutput -match "FTP") 
    
    if ($ftpService) {
        Write-ErrorMsg "检测到FTP服务 (FTPSVC) 已安装且状态为: $($ftpService.Status)"
        Write-Instruction "建议禁用 FTP 服务，请在【服务】中设置为禁用。"
        $Results += @{ Item = "FTP服务"; Issue = "FTP 服务已安装，状态为 $($ftpService.Status)"; Suggestion = "请在【服务】中禁用 FTP 服务" }
    } else {
        Write-Success "未检测到FTP服务 (FTPSVC) 安装，符合安全要求。"
        $Results += @{ Item = "FTP服务"; Issue = "未检测到FTP服务"; Suggestion = "无" }
    }
    if ($ftpPortActive) {
        Write-ErrorMsg "检测到TCP端口21处于监听状态。"
        Write-Instruction "检查是否有应用使用FTP端口，并停止相关服务。"
        $Results += @{ Item = "FTP端口"; Issue = "TCP 21 端口正在监听"; Suggestion = "请停止相关 FTP 服务或释放端口" }
    } else {
        Write-Success "未检测到TCP端口21处于监听状态。"
        $Results += @{ Item = "FTP端口"; Issue = "TCP 21 端口未监听"; Suggestion = "无" }
    }
    if ($ftpInboundRules) {
        Write-ErrorMsg "检测到防火墙中可能允许FTP流量的规则。"
        Write-Instruction "请检查 Windows 防火墙设置，禁用与FTP相关的入站规则。"
        $Results += @{ Item = "FTP防火墙规则"; Issue = "存在可能允许FTP流量的规则"; Suggestion = "请关闭或调整防火墙规则" }
    } else {
        Write-Success "未检测到FTP防火墙入站规则。"
        $Results += @{ Item = "FTP防火墙规则"; Issue = "无FTP防火墙入站规则"; Suggestion = "无" }
    }
    if ($ftpClientInstalled) {
        Write-ErrorMsg "FTP客户端功能已启用。"
        Write-Instruction "建议禁用 FTP 客户端，请在【控制面板】>【程序和功能】>【启用或关闭Windows功能】中取消 FTP 客户端。"
        $Results += @{ Item = "FTP客户端"; Issue = "FTP客户端已启用"; Suggestion = "请取消 FTP 客户端选项" }
    } else {
        Write-Success "FTP客户端功能未启用，符合安全要求。"
        $Results += @{ Item = "FTP客户端"; Issue = "未启用FTP客户端"; Suggestion = "无" }
    }
} catch {
    Write-ErrorMsg "检查FTP功能时发生错误: $_"
    Write-Instruction "请手动检查FTP服务和端口21状态。"
    $Results += @{ Item = "FTP检查"; Issue = "错误: $_"; Suggestion = "请手动检查FTP服务和端口21的状态" }
}
Write-Seperator

# 【2】网卡信息及无线网卡状态检查（使用 WMI）
Write-Host "`n【2】网卡信息："
try {
    $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" 2>$null
    if ($adapters) {
        Write-Host "检测到的网卡信息："
        $adapters | ForEach-Object {
            $ip = if ($_.IPAddress) { $_.IPAddress -join ", " } else { "未配置" }
            Write-Host "  - 描述: $($_.Description); IP: $ip"
            $Results += @{ Item = "网卡详情"; Issue = "描述: $($_.Description), IP: $ip"; Suggestion = "无" }
        }
        $Results += @{ Item = "网卡信息"; Issue = "检测到 $($adapters.Count) 个网卡"; Suggestion = "确认网络状态" }
    } else {
        Write-ErrorMsg "未检测到网卡信息。"
        $Results += @{ Item = "网卡信息"; Issue = "未检测到任何网卡"; Suggestion = "请检查网络硬件" }
    }
    # 检查无线网卡（根据描述中是否包含关键词）
    $wifiAdapters = $adapters | Where-Object { $_.Description -match "Wireless|Wi[- ]?Fi" }
    if ($wifiAdapters) {
        # 判断是否有无线网卡未禁用（本示例中仅判断是否存在IP配置）
        $activeWifi = $wifiAdapters | Where-Object { $_.IPEnabled -eq $true }
        if ($activeWifi) {
            $activeNames = $activeWifi | ForEach-Object { $_.Description } | Out-String
            Write-ErrorMsg "存在未禁用的无线网卡：$activeNames"
            Write-Instruction "请在【网络连接】中禁用不使用的无线网卡。"
            $Results += @{ Item = "无线网卡"; Issue = "存在未禁用无线网卡: $activeNames"; Suggestion = "请禁用不使用的无线网卡" }
        } else {
            Write-Success "所有无线网卡均已禁用。"
            $Results += @{ Item = "无线网卡"; Issue = "无线网卡均已禁用"; Suggestion = "无" }
        }
    } else {
        Write-Host "未检测到无线网卡。"
        $Results += @{ Item = "无线网卡"; Issue = "未检测到无线网卡"; Suggestion = "无" }
    }
} catch {
    Write-ErrorMsg "获取网卡信息失败: $_"
    $Results += @{ Item = "网卡信息"; Issue = "获取失败: $_"; Suggestion = "请检查网络适配器" }
}
Write-Seperator

# 【3】高危端口状态检测（防火墙规则检查，通过 netsh 检测）
Write-Host "`n【3】高危端口状态检测（防火墙规则检查）："
$ports = @(22,23,135,137,138,139,445,455,3389,4899)
foreach ($port in $ports) {
    try {
        if (Test-FirewallPortBlock -port $port) {
            Write-Success "端口 $port 已被防火墙策略封禁。"
            $Results += @{ Item = "端口 $port"; Issue = "端口已封禁"; Suggestion = "无" }
        } else {
            Write-ErrorMsg "端口 $port 未被防火墙策略封禁。"
            Write-Instruction "请在【控制面板】>【Windows 防火墙】中添加入站规则封禁该端口。"
            $Results += @{ Item = "端口 $port"; Issue = "端口未封禁"; Suggestion = "请封禁该端口" }
        }
    } catch {
        Write-ErrorMsg "检测端口 $port 时发生异常: $_"
        $Results += @{ Item = "端口 $port"; Issue = "检测异常: $_"; Suggestion = "检查防火墙配置" }
    }
}
Write-Seperator

# 【4】IPv6 禁用状态检查（使用注册表）
Write-Host "`n【4】IPv6 禁用状态："
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
try {
    $ipv6Value = (Get-ItemProperty -Path $regPath -Name "DisabledComponents" -ErrorAction SilentlyContinue).DisabledComponents
    if ($ipv6Value -eq 255) {
        Write-Success "IPv6 已禁用 (DisabledComponents = $ipv6Value)。"
        $Results += @{ Item = "IPv6"; Issue = "已禁用 (DisabledComponents = $ipv6Value)"; Suggestion = "无" }
    } else {
        Write-ErrorMsg "IPv6 可能未完全禁用 (DisabledComponents = $ipv6Value)。"
        Write-Instruction "建议设置 DisabledComponents 为 255。"
        $Results += @{ Item = "IPv6"; Issue = "IPv6 未完全禁用 (DisabledComponents = $ipv6Value)"; Suggestion = "请设置 DisabledComponents = 255" }
    }
} catch {
    Write-ErrorMsg "未检测到 IPv6 禁用相关注册表设置。"
    Write-Instruction "请在注册表中创建或修改 DisabledComponents 为 255。"
    $Results += @{ Item = "IPv6"; Issue = "未检测到相关注册表设置"; Suggestion = "请设置 DisabledComponents = 255" }
}
Write-Seperator

# 【5】高危漏洞修复检查（更新情况）
Write-Host "`n【5】高危漏洞修复检查（更新情况）："
try {
    $hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending
    if ($hotfixes) {
        $latest = $hotfixes | Select-Object -First 1
        Write-Success "最新更新：$($latest.HotFixID)，安装日期：$($latest.InstalledOn)。"
        Write-Host "请核查更新是否包含近期针对高危漏洞的补丁。"
        $Results += @{ Item = "更新补丁"; Issue = "最新更新：$($latest.HotFixID)，日期：$($latest.InstalledOn)"; Suggestion = "请核查补丁内容" }
    } else {
        Write-ErrorMsg "无法获取已安装更新信息。"
        Write-Instruction "请检查 Windows 更新，并安装所有重要补丁。"
        $Results += @{ Item = "更新补丁"; Issue = "无法获取更新信息"; Suggestion = "请检查 Windows 更新" }
    }
} catch {
    Write-ErrorMsg "获取更新信息失败: $_"
    $Results += @{ Item = "更新补丁"; Issue = "获取更新信息失败: $_"; Suggestion = "请手动检查更新" }
}
Write-Seperator

# 【6】密码策略检查（使用 net accounts）
Write-Host "`n【6】密码策略检查："
try {
    $netAccOutput = net accounts 2>$null
    Write-Host "【net accounts】输出如下："
    $netAccOutput -split "`n" | ForEach-Object { Write-Host $_.Trim() }
    Write-Instruction "请调整密码策略，将最长密码有效期设置为不超过 90 天。"
    $Results += @{ Item = "密码策略"; Issue = "net accounts 输出: $netAccOutput"; Suggestion = "最长密码有效期不超过 90 天" }
} catch {
    Write-ErrorMsg "获取密码策略信息失败: $_"
    $Results += @{ Item = "密码策略"; Issue = "获取失败: $_"; Suggestion = "请检查本地安全策略" }
}
Write-Seperator

# 【7】Guest 用户状态检查（使用 net user）
Write-Host "`n【7】Guest 用户状态："
try {
    $guestStatus = Get-GuestUserStatus
    if ($guestStatus -eq $false) {
        Write-Success "Guest 用户已禁用。"
        $Results += @{ Item = "Guest 用户"; Issue = "已禁用"; Suggestion = "无" }
    } elseif ($guestStatus -eq $true) {
        Write-ErrorMsg "Guest 用户处于启用状态。"
        Write-Instruction "请在【计算机管理】>【本地用户和组】中禁用 Guest 用户。"
        $Results += @{ Item = "Guest 用户"; Issue = "处于启用状态"; Suggestion = "请禁用 Guest 用户" }
    } else {
        Write-Host "未检测到 Guest 用户信息（可能已删除）。"
        $Results += @{ Item = "Guest 用户"; Issue = "未检测到"; Suggestion = "无" }
    }
} catch {
    Write-ErrorMsg "获取 Guest 用户信息失败: $_"
    $Results += @{ Item = "Guest 用户"; Issue = "获取失败: $_"; Suggestion = "请检查本地用户" }
}
Write-Seperator

# 【8】U盘自动播放功能设置检查（注册表）
Write-Host "`n【8】U盘自动播放功能设置："
$regPathUSB = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer"
try {
    $noDriveValue = (Get-ItemProperty -Path $regPathUSB -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
    if ($noDriveValue -eq 255) {
        Write-Success "U盘自动播放已禁用 (NoDriveTypeAutoRun = $noDriveValue)。"
        $Results += @{ Item = "U盘自动播放"; Issue = "已禁用 (NoDriveTypeAutoRun = $noDriveValue)"; Suggestion = "无" }
    } else {
        Write-ErrorMsg "U盘自动播放可能未完全禁用 (NoDriveTypeAutoRun = $noDriveValue)。"
        Write-Instruction "请将 NoDriveTypeAutoRun 值修改为 255。"
        $Results += @{ Item = "U盘自动播放"; Issue = "未完全禁用 (NoDriveTypeAutoRun = $noDriveValue)"; Suggestion = "修改为 255" }
    }
} catch {
    Write-ErrorMsg "获取 U盘自动播放设置失败: $_"
    $Results += @{ Item = "U盘自动播放"; Issue = "获取失败: $_"; Suggestion = "请手动检查注册表" }
}
Write-Seperator

# 【9】Google 浏览器版本检测
Write-Host "`n【9】Google 浏览器版本检测："
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (Test-Path $chromePath) {
    try {
        $chromeVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
        Write-Success "检测到 Google Chrome 版本：$chromeVersion。"
        Write-Host "如有必要，请访问 https://www.google.com/chrome/ 更新至最新版本。"
        $Results += @{ Item = "Google Chrome"; Issue = "版本：$chromeVersion"; Suggestion = "确认是否最新版本" }
    } catch {
        Write-ErrorMsg "获取 Google Chrome 版本信息失败: $_"
        $Results += @{ Item = "Google Chrome"; Issue = "获取版本信息失败: $_"; Suggestion = "请手动检查Chrome版本" }
    }
} else {
    Write-Host "未检测到 Google Chrome。"
    $Results += @{ Item = "Google Chrome"; Issue = "未检测到"; Suggestion = "如有需要，请安装Google Chrome" }
}
Write-Seperator

# 【10】锁屏策略检查（注册表）
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
    $Results += @{ Item = "锁屏策略"; Issue = "超时时间：$timeout 秒"; Suggestion = "无" }
} else {
    Write-ErrorMsg "锁屏策略不符合要求！当前超时时间：$timeout 秒"
    Write-Instruction "请设置屏幕保护程序超时时间不超过600秒，并启用密码保护。"
    $Results += @{ Item = "锁屏策略"; Issue = "超时时间=$timeout 秒"; Suggestion = "请设置超时时间不超过600秒并启用密码" }
}
Write-Seperator

Write-Host "`n========== 检查结束 =========="
Read-Host "按回车键退出..."

# 上传检查结果（若有）
if ($Results.Count -gt 0) {
    $Json = $Results | ConvertTo-Json -Depth 5 -Compress
    Write-Host "上传地址: $UploadUrl"
    Send-CheckResult -JsonData $Json
}
