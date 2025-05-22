# === 密钥和安全设置 ===
$ErrorActionPreference = "Stop"  # 确保在发生错误时停止执行
$AuthorizedKey = ConvertTo-SecureString "Hzdsz@2025#" -AsPlainText -Force
$EncryptionKey = ConvertTo-SecureString "cxrHzfMfQuihZSE4XRP7rumqZY2mNaCU3BXKYL3TKE3DeNxFJ" -AsPlainText -Force
$MaxTimestampMinutes = 10

# 定义配置文件路径
$ipConfigPath = "ip_set_config.json"  # 使用相对路径

# === 获取当前 IP 地址的函数 ===
function Get-CurrentIPAddress {
    try {
        # 获取启用的网络适配器
        $networkAdapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        
        if ($networkAdapters) {
            foreach ($adapter in $networkAdapters) {
                $ipAddresses = $adapter.IPAddress
                if ($ipAddresses) {
                    return $ipAddresses[0]  # 返回第一个 IP 地址
                }
            }
        } else {
            Write-Host "未找到启用的网络适配器。" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "获取 IP 地址时发生错误: $_" -ForegroundColor Red
        return $null
    }
}

# === 检查无线网卡状态的函数 ===
function Check-WifiStatus {
    try {
        $wifiAdapters = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.Name -match "Wi[- ]?Fi" -or $_.Description -match "Wireless" }
        if ($wifiAdapters) {
            $activeWifi = $wifiAdapters | Where-Object { $_.NetConnectionStatus -eq 2 } # 2 表示连接状态
            if ($activeWifi) {
                $activeNames = $activeWifi | ForEach-Object { $_.Name } | Out-String
                Write-Host "存在未禁用的无线网卡：$activeNames" -ForegroundColor Yellow
                Write-Host "请进入【网络连接】界面，右键选择无线网卡并选择禁用。" -ForegroundColor Yellow
            } else {
                Write-Host "所有无线网卡均已禁用。" -ForegroundColor Green
            }
        } else {
            Write-Host "未检测到无线网卡。" -ForegroundColor Red
        }
    } catch {
        Write-Host "检查无线网卡状态时发生错误: $_" -ForegroundColor Red
    }
}

# === 主程序逻辑 ===

$currentIP = Get-CurrentIPAddress
if ($currentIP) {
    Write-Host "当前 IP 地址: $currentIP" -ForegroundColor Green
} else {
    Write-Host "无法获取当前 IP 地址。" -ForegroundColor Red
}


# 将安全字符串转换为明文的函数 - 置于顶层
function Convert-SecureStringToPlainText {
    param([System.Security.SecureString]$SecureString)
    
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

# 脚本结束时暂停执行的函数 - 置于顶层
function Pause-Script {
    Write-Host "按回车键继续..." -ForegroundColor Yellow
    Read-Host
}

# 检查并创建事件日志源（如不存在）
if (-not [System.Diagnostics.EventLog]::SourceExists("SecurityCheck")) {
    try {
        [System.Diagnostics.EventLog]::CreateEventSource("SecurityCheck", "Application")
    } catch {
        # 如果无法创建事件源，继续执行但不记录日志
        Write-Host "无法创建事件日志源，将继续执行但不记录日志。"
    }
}

# 支持有无事件日志的日志记录函数
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
        # 日志记录失败时继续执行
    }
}

# 配置时间戳验证机制
$MaxTimestampMinutes = 10

# 添加 ProtectedData 类所需的程序集引用
Add-Type -AssemblyName System.Security

# 加密函数
function Protect-ConfigContent {
    param([string]$Content)
    try {
        # 获取加密密钥的明文
        $keyPlainText = Convert-SecureStringToPlainText -SecureString $EncryptionKey
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyPlainText)
        
        # 创建随机IV
        $iv = New-Object byte[] 16
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $rng.GetBytes($iv)
        
        # 使用AES加密
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31] # 使用前32字节作为密钥
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        # 加密内容
        $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $encryptor = $aes.CreateEncryptor()
        $encryptedBytes = $encryptor.TransformFinalBlock($contentBytes, 0, $contentBytes.Length)
        
        # 组合IV和加密后的内容
        $combinedBytes = $iv + $encryptedBytes
        $encryptedBase64 = [Convert]::ToBase64String($combinedBytes)
        
        # 创建带有时间戳的JSON结构
        $protectedData = @{
            ipset = $Content
            Content = $encryptedBase64
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

# 解密函数
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
        
        # 获取加密密钥的明文
        $keyPlainText = Convert-SecureStringToPlainText -SecureString $EncryptionKey
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($keyPlainText)
        
        # 解码Base64
        $combinedBytes = [Convert]::FromBase64String($protectedData.Content)
        
        # 分离IV和加密内容
        $iv = $combinedBytes[0..15]
        $encryptedBytes = $combinedBytes[16..($combinedBytes.Length-1)]
        
        # 使用AES解密
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes[0..31] # 使用前32字节作为密钥
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        # 解密
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
        $decryptedContent = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
        
        return $decryptedContent
    }
    catch {
        Write-Host "解密配置文件失败: $_" -ForegroundColor Red
        # 返回默认的空配置以避免程序崩溃
        return '{"ipList":[]}'
    }
    finally {
        if ($aes) { $aes.Dispose() }
    }
}

# 获取当前网段信息
function Get-CurrentSubnet {
    # 首先尝试获取以太网适配器
    $ethernetAdapters = Get-WmiObject Win32_NetworkAdapter | Where-Object { 
        $_.Name -like "*以太网*" -or $_.Name -eq "以太网" -or $_.Name -eq "Ethernet" -and 
        $_.NetConnectionStatus -eq 2 
    }
    
    if ($ethernetAdapters) {
        # 优先使用以太网适配器
        $adapter = $ethernetAdapters | Select-Object -First 1
        $ipConfig = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.Index -eq $adapter.Index }
        
        if ($ipConfig -and $ipConfig.IPAddress) {
            $ipv4Address = $ipConfig.IPAddress[0]
            $subnetMask = $ipConfig.IPSubnet[0]
            
            # 计算出网段 (CIDR表示法)
            $ipParts = $ipv4Address -split "\."
            $subnetCIDR = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$subnetMask"
            
            Write-Host "使用以太网适配器: $($adapter.Name), IP: $ipv4Address" -ForegroundColor Cyan
            return $subnetCIDR
        }
    }
    
    # 如果没找到以太网或者以太网没有IPv4地址，找一个有默认网关的适配器
    $connectedAdapter = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { 
        $_.IPAddress -ne $null -and 
        $_.DefaultIPGateway -ne $null 
    } | Select-Object -First 1
    
    if ($connectedAdapter) {
        $ipAddress = $connectedAdapter.IPAddress[0]
        $subnetMask = $connectedAdapter.IPSubnet[0]
        
        # 计算出网段 (CIDR表示法)
        $ipParts = $ipAddress -split "\."
        $subnetCIDR = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$subnetMask"
        
        Write-Host "使用适配器: $($connectedAdapter.Description), IP: $ipAddress" -ForegroundColor Yellow
        return $subnetCIDR
    }
    
    Write-Host "无法获取当前 IP 地址，请检查网络连接。" -ForegroundColor Red
    Pause-Script
    Exit
}

# 设置文件权限
function Set-SecureFilePermissions {
    param([string]$FilePath)
    try {
        # 获取当前用户和SYSTEM账户
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $systemAccount = "NT AUTHORITY\SYSTEM"
        
        # 创建新的访问规则
        $acl = Get-Acl $FilePath
        $acl.SetAccessRuleProtection($true, $false) # 禁用继承
        
        # 清除所有现有规则
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
        
        # 添加新规则
        $rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser, "FullControl", "Allow"
        )
        $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $systemAccount, "FullControl", "Allow"
        )
        
        $acl.AddAccessRule($rule1)
        $acl.AddAccessRule($rule2)
        
        # 应用新的权限
        Set-Acl -Path $FilePath -AclObject $acl
    }
    catch {
        Write-EventLog -LogName "Application" -Source "SecurityCheck" -EntryType Error -EventId 1003 -Message "设置文件权限失败: $_"
        throw
    }
}

# 读取已授权的 IP 网段
function Get-AuthorizedIPs {
    if (Test-Path $ipConfigPath) {
        try {
            # 读取加密的配置文件
            $encryptedContent = Get-Content $ipConfigPath -Raw
            $decryptedContent = Unprotect-ConfigContent $encryptedContent
            $ipConfig = $decryptedContent | ConvertFrom-Json
            
            # 过滤出未过期的IP
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
        # 创建新的加密配置文件
        $newConfig = @{ ipList = @() } | ConvertTo-Json
        
        $encryptedConfig = Protect-ConfigContent $newConfig
        $encryptedConfig | Set-Content -Path $ipConfigPath -Encoding UTF8
        Set-SecureFilePermissions $ipConfigPath
        return @()
    }
}

# 改进的添加授权IP函数
function Add-AuthorizedIP {
    param ([string]$newSubnet)
    
    $expiryDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd")
    
    try {
        # 如果需要，创建新的配置文件
        if (-not (Test-Path $ipConfigPath)) {
            # 创建默认配置结构
            $defaultConfig = @{ 
                ipList = @() 
            } | ConvertTo-Json -Depth 3
            
            $encryptedConfig = Protect-ConfigContent $defaultConfig
            $encryptedConfig | Set-Content -Path $ipConfigPath -Encoding UTF8
            
            try { Set-SecureFilePermissions $ipConfigPath } catch { 
                Write-Host "无法设置文件权限，继续执行" -ForegroundColor Yellow
            }
        }
        
        # 尝试读取现有配置
        $encryptedContent = Get-Content $ipConfigPath -Raw -ErrorAction Stop
        $decryptedContent = Unprotect-ConfigContent $encryptedContent
        
        # 安全解析JSON
        try {
            $ipConfig = $decryptedContent | ConvertFrom-Json
            # 如果ipList属性不存在则创建
            if (-not ($ipConfig.PSObject.Properties | Where-Object { $_.Name -eq "ipList" })) {
                $ipConfig = @{ ipList = @() } | ConvertTo-Json | ConvertFrom-Json
            }
        } catch {
            # 如果解析失败，创建新配置
            Write-Host "解析配置失败，创建新配置" -ForegroundColor Yellow
            $ipConfig = @{ ipList = @() } | ConvertTo-Json | ConvertFrom-Json
        }
        
        # 如果ipList不是数组，将其转换为数组
        $ipListArray = @()
        if ($ipConfig.ipList -ne $null) {
            foreach ($item in $ipConfig.ipList) {
                $ipListArray += $item
            }
        }
        
        # 检查网段是否已存在于数组中
        $existingIndex = -1
        for ($i = 0; $i -lt $ipListArray.Count; $i++) {
            if ($ipListArray[$i].subnet -eq $newSubnet) {
                $existingIndex = $i
                break
            }
        }
        
        if ($existingIndex -ge 0) {
            # 更新现有网段
            $ipListArray[$existingIndex].expiryDate = $expiryDate
            Write-Host "网段 $newSubnet 授权已更新，新的到期日期：$expiryDate" -ForegroundColor Cyan
        } else {
            # 添加新网段
            $newIP = @{
                subnet = $newSubnet
                expiryDate = $expiryDate
                addedDate = (Get-Date).ToString("yyyy-MM-dd")
            }
            $ipListArray += $newIP
            Write-Host "已添加新授权网段：$newSubnet，到期日期：$expiryDate" -ForegroundColor Green
        }
        
        # 使用数组创建新的配置对象
        $newConfig = @{ ipList = $ipListArray }
        $newConfigJson = $newConfig | ConvertTo-Json -Depth 3
        
        # 加密并保存
        $encryptedConfig = Protect-ConfigContent $newConfigJson
        $encryptedConfig | Set-Content -Path $ipConfigPath -Encoding UTF8 -Force
        
        try { Set-SecureFilePermissions $ipConfigPath } catch { 
            Write-Host "无法设置文件权限，继续执行" -ForegroundColor Yellow
        }
        
        return $true
    } catch {
        Write-Host "添加网段时发生错误: $_" -ForegroundColor Red
        
        # 紧急备用方案 - 创建简单配置
        try {
            $fallbackConfig = @{ 
                ipList = @(
                    @{
                        subnet = $newSubnet
                        expiryDate = $expiryDate
                        addedDate = (Get-Date).ToString("yyyy-MM-dd")
                    }
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

# 存储正确的密码哈希值
$PasswordHash = "c1d243817f27fe6aa2811fd98e2f090e9eff9cf42e08ca5de5b430a5cf1ee8f3"

# 为关键函数添加错误处理
try {
    # 获取当前网段信息
    $currentSubnet = Get-CurrentSubnet
    Write-Host "当前网段: $currentSubnet" -ForegroundColor Cyan
    
    $authorizedIPs = Get-AuthorizedIPs
    Write-Host "已授权网段: $($authorizedIPs -join ', ')" -ForegroundColor Cyan
    
    # 检查当前网段是否已授权
    if ($authorizedIPs -contains $currentSubnet) {
        Write-Host "当前网段 ($currentSubnet) 已授权，开始执行安全检查。" -ForegroundColor Green
    } else {
        # 如果未授权，提示输入授权密钥
        $UserInputKey = ""
        Write-Host "请输入授权密钥: " -NoNewline
        while ($true) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($key.VirtualKeyCode -eq 13) { # Enter key
                Write-Host ""
                break
            } elseif ($key.VirtualKeyCode -eq 8) { # Backspace key
                if ($UserInputKey.Length -gt 0) {
                    $UserInputKey = $UserInputKey.Substring(0, $UserInputKey.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
            } else {
                $UserInputKey += $key.Character
                Write-Host "*" -NoNewline
            }
        }

        Write-Host "正在验证授权密钥..."

        # 计算输入密码的哈希值
        $UserInputHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($UserInputKey))
        $UserInputHashString = [System.BitConverter]::ToString($UserInputHash).Replace("-", "").ToLower()

        # 比较哈希值
        if ($PasswordHash -eq $UserInputHashString) {
            Write-Host "授权成功，添加当前网段到授权列表。" -ForegroundColor Green
            Add-AuthorizedIP -newSubnet $currentSubnet
        } else {
            Write-Host "授权失败，无法执行脚本。" -ForegroundColor Red
            Pause-Script
            Exit
        }
    }
    
    # 脚本其余部分继续执行...
    
} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Write-Host "错误位置: $($_.ScriptStackTrace)" -ForegroundColor Red
    Pause-Script
    Exit
}

# 在脚本最后添加此行以保持窗口打开
Pause-Script


# Windows 10/11 客户端安全检查脚本

# 读取配置文件
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
    $ports = @(22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899)

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

