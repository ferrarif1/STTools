# 密钥和安全设置
$AuthorizedKey = ConvertTo-SecureString "Hzdsz@2025#" -AsPlainText -Force
$EncryptionKey = ConvertTo-SecureString "cxrHzfMfQuihZSE4XRP7rumqZY2mNaCU3BXKYL3TKE3DeNxFJ" -AsPlainText -Force
$MaxTimestampMinutes = 10

# 脚本路径检测
try {
    # 获取脚本所在目录
    $ScriptDirectory = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
    if ([string]::IsNullOrEmpty($ScriptDirectory)) {
        $ScriptDirectory = [System.IO.Directory]::GetCurrentDirectory()
    }
} catch {
    # 获取失败时使用当前目录
    $ScriptDirectory = [System.IO.Directory]::GetCurrentDirectory()
}

# 定义配置文件路径
$ipConfigPath = [System.IO.Path]::Combine($ScriptDirectory, "ip_set_config.json")


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
    $ethernetAdapters = Get-NetAdapter | Where-Object { 
        $_.Name -like "*以太网*" -or $_.Name -eq "以太网" -or $_.Name -eq "Ethernet" -and 
        $_.Status -eq "Up" 
    }
    
    if ($ethernetAdapters) {
        # 优先使用以太网适配器
        $adapter = $ethernetAdapters | Select-Object -First 1
        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
        
        if ($ipConfig -and $ipConfig.IPv4Address) {
            $ipv4Address = $ipConfig.IPv4Address.IPAddress
            $subnetMask = $ipConfig.IPv4Address.PrefixLength
            
            # 计算出网段 (CIDR表示法)
            $ipParts = $ipv4Address -split "\."
            $subnetCIDR = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$subnetMask"
            
            Write-Host "使用以太网适配器: $($adapter.Name), IP: $ipv4Address" -ForegroundColor Cyan
            return $subnetCIDR
        }
    }
    
    # 如果没找到以太网或者以太网没有IPv4地址，找一个有默认网关的适配器
    $connectedAdapter = Get-NetIPConfiguration | 
                         Where-Object { 
                            $_.IPv4Address -ne $null -and 
                            $_.IPv4DefaultGateway -ne $null 
                         } | 
                         Select-Object -First 1
    
    if ($connectedAdapter) {
        $ipAddress = $connectedAdapter.IPv4Address.IPAddress
        $subnetMask = $connectedAdapter.IPv4Address.PrefixLength
        
        # 计算出网段 (CIDR表示法)
        $ipParts = $ipAddress -split "\."
        $subnetCIDR = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$subnetMask"
        
        Write-Host "使用适配器: $($connectedAdapter.InterfaceAlias), IP: $ipAddress" -ForegroundColor Yellow
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
    
    $expiryDate = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
    
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
$configPath = Join-Path $ScriptDirectory "config.json"
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
# 需要管理员权限运行此脚本
# 请确保$ScriptPath变量已正确设置（指向您的脚本路径）
$ScriptPath = "C:\Path\To\Your\Script.ps1"

# 修正后的每月任务（每月1号9点执行）
function Add-CorrectedMonthlyTaskIfNotExists {
    if (-not (Get-ScheduledTask -TaskName "MonthlyCheckTask" -ErrorAction SilentlyContinue)) {
        # 创建操作
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        # 创建触发器（每月第一天9:00）
        $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 9:00am
        
        # 配置任务设置
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        # 配置用户上下文（SYSTEM账户）
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # 注册任务
        Register-ScheduledTask `
            -TaskName "MonthlyCheckTask" `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force
    }
}

# 修正后的半小时任务（每30分钟重复执行）
function Add-CorrectedHalfHourlyTaskForTesting {
    if (-not (Get-ScheduledTask -TaskName "HalfHourlyTestTask" -ErrorAction SilentlyContinue)) {
        # 创建操作
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        # 创建触发器（立即开始，每30分钟重复，无限期持续）
        $trigger = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date).AddMinutes(1) `  # 1分钟后开始以避免立即触发
            -RepetitionInterval (New-TimeSpan -Minutes 30) `
            -RepetitionDuration ([System.TimeSpan]::MaxValue)
        
        # 配置任务设置
        $settings = New-ScheduledTaskSettingsSet `
            -DontStopIfGoingOnBatteries `
            -AllowStartIfOnBatteries `
            -MultipleInstances IgnoreNew
        
        # 配置用户上下文
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # 注册任务
        Register-ScheduledTask `
            -TaskName "HalfHourlyTestTask" `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force
    }
}

# 执行任务创建
Add-CorrectedMonthlyTaskIfNotExists
Add-CorrectedHalfHourlyTaskForTesting

Retry-FailedUpload

# 创建空数组用于存储所有安全检查的结果
$Results = @()

# ========== 检查逻辑 ==========
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

