# == 终端安全配置检测脚本（严格模式）==
# 请以管理员身份运行
# 功能：检测系统安全配置是否符合8位+字母+数字+特殊符号等要求

# 配置日志文件路径
$logFile = "C:\SecurityCheck_$(Get-Date -Format 'yyyyMMddHHmmss').log"

# 日志记录函数
Function Write-Log {
    Param([string]$Message)
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
}

# 1. 操作系统激活检测
try {
    $os = Get-WmiObject Win32_OperatingSystem
    Write-Log $(if ($os.CSDVersion -eq "") { "✅ [系统激活] 已激活" } else { "❌ [系统激活] 未激活" })
} catch {
    Write-Log "❌ [系统激活] 检测失败"
}

# 2. Wifi功能检测
try {
    $wifiAdapters = Get-NetAdapter | Where-Object { $_.Name -like "*Wireless*" }
    if ($wifiAdapters) {
        $wifiAdapters | ForEach-Object {
            Write-Log $(if ($_.Status -eq "Up") { "⚠️ [无线网络] 接口开启：$($_.Name)" } else { "✅ [无线网络] 接口关闭：$($_.Name)" })
        }
    } else {
        Write-Log "✅ [无线网络] 未检测到无线网卡"
    }
} catch {
    Write-Log "❌ [无线网络] 检测失败"
}

# 3. 高危端口检测
$highRiskPorts = @(22,23,135,137,138,139,445,455,3389,4899)
try {
    $openPorts = Get-NetTCPConnection -LocalPort $highRiskPorts -ErrorAction SilentlyContinue | Select-Object -Unique LocalPort
    if ($openPorts) {
        Write-Log "⚠️ [高危端口] 开放端口：$($openPorts.LocalPort -join ',')"
    } else {
        Write-Log "✅ [高危端口] 所有端口已关闭"
    }
} catch {
    Write-Log "❌ [高危端口] 检测失败"
}

# 4. IPv6状态检测
try {
    Get-NetAdapter | ForEach-Object {
        $status = if ($_.IPv6Enabled) { "⚠️ [IPv6状态] 已启用" } else { "✅ [IPv6状态] 已禁用" }
        Write-Log "$status：$($_.Name)"
    }
} catch {
    Write-Log "❌ [IPv6状态] 检测失败"
}

# 5. 弱口令策略检测（严格模式）
$specialCharsRegex = [regex]::Escape('!@#$%^&*()_+-={}[]|\:;"<>,.?/')
try {
    # 基础策略检测
    $policy = Get-LocalSecurityPolicy
    $lengthCheck = $policy.MinPasswordLength -ge 8
    $complexityCheck = $policy.PasswordComplexity -eq 1

    # 增强检测：分析最近密码修改事件
    $hasSpecialCharUsage = $false
    $passwordEvents = Get-WinEvent -LogName Security -FilterXPath @"
        *[
            System[
                (EventID=4723) or 
                (EventID=4724)
            ]
        ]"@ -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($passwordEvents) {
        $hasSpecialCharUsage = $passwordEvents.Message -match "[$specialCharsRegex]"
    }

    # 生成报告
    $report = @()
    if (-not $lengthCheck)    { $report += "密码长度不足8位" }
    if (-not $complexityCheck){ $report += "未启用复杂度要求" }
    if (-not $hasSpecialCharUsage) { $report += "近期无特殊符号使用记录" }

    if ($report.Count -eq 0) {
        Write-Log "✅ [密码策略] 完全合规（长度≥8位+字母+数字+特殊符号）"
    } else {
        Write-Log "❌ [密码策略] 存在缺陷：$($report -join ' | ')"
        Write-Log "   |- 当前密码长度要求：$($policy.MinPasswordLength)位"
        Write-Log "   |- 复杂度要求启用状态：$($policy.PasswordComplexity -eq 1)"
        Write-Log "   |- 特殊符号使用验证：$($hasSpecialCharUsage)"
    }
} catch {
    Write-Log "❌ [密码策略] 检测失败：$_"
}

# 6. Guest账户检测
try {
    $guest = Get-WmiObject Win32_UserAccount -Filter "Name='Guest'" -ErrorAction Stop
    Write-Log $(if ($guest.Enabled) { "❌ [Guest账户] 未禁用" } else { "✅ [Guest账户] 已禁用" })
} catch {
    Write-Log "❌ [Guest账户] 检测失败"
}

# 7. U盘自动播放检测
try {
    $autoPlayKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AutoPlay"
    $regValue = Get-ItemProperty -Path $autoPlayKey -Name "Enabled" -ErrorAction SilentlyContinue
    Write-Log $(if ($regValue.Enabled -eq 0) { "✅ [自动播放] 已关闭" } else { "❌ [自动播放] 未关闭" })
} catch {
    Write-Log "❌ [自动播放] 检测失败"
}

# 输出汇总报告
Write-Host "`n===== 检测完成 =====`n"
Write-Host "日志文件路径：$logFile`n"
Write-Host "需人工处理的问题：" -ForegroundColor Yellow
Get-Content $logFile | Where-Object { $_ -match "❌|⚠️" } | ForEach-Object {
    Write-Host "  - $($_.Split(']')[1].Trim())" -ForegroundColor Red
}