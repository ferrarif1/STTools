# 定义白名单应用程序
$whitelist = @()

# 获取所有可能包含已安装程序信息的注册表路径
$registryPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# 查询所有路径以获取已安装的程序列表
$installedApps = $registryPaths | ForEach-Object {
    Get-ItemProperty $_ -ErrorAction SilentlyContinue |
    Select-Object DisplayName, DisplayVersion, Publisher
} | Where-Object { $_.DisplayName -ne $null }

# 过滤不在白名单上的程序，并排除非“Office”且由 Microsoft Corporation 发布的程序
$nonWhitelistedApps = $installedApps | Where-Object {
    $whitelist -notcontains $_.DisplayName -and ($_.Publisher -ne "Microsoft Corporation" -or $_.DisplayName -like "*Office*")
}

# 输出不在白名单上的程序
$nonWhitelistedApps | ForEach-Object {
    "$($_.DisplayName) - Version: $($_.DisplayVersion) - Publisher: $($_.Publisher)"
} | Out-File -FilePath .\NonWhitelistedApps.txt


# 定义要排除的关键字列表
$exclusionList = @("Python", "SDK", "Headers", "Metadata", "Visual C++", "Tools", "Java", "Visual Studio", ".NET", "WinRT", "WinAppDeploy", "CMake", "HP")



# 已安装的程序列表，再次进行过滤
$installedApps | Where-Object {
    # 检查是否为用户程序（不包含排除列表中的关键字）
    $isUserApp = $true
    foreach ($exclusion in $exclusionList) {
        if ($_.DisplayName -like "*$exclusion*") {
            $isUserApp = $false
            break
        }
    }
    # 保留名称包含 'Office' 的 Microsoft Corporation 程序
    $isUserApp -and ($whitelist -notcontains $_.DisplayName) -and ($_.Publisher -ne "Microsoft Corporation" -or $_.DisplayName -like "*Office*")
} | ForEach-Object {
    "$($_.DisplayName) - Version: $($_.DisplayVersion) - Publisher: $($_.Publisher)"
} | Out-File -FilePath .\NonWhitelistedApps.txt



# 获取系统信息（使用WMI替代Get-ComputerInfo）
$os = Get-WmiObject -Class Win32_OperatingSystem
$formattedSystemInfo = "System: $($os.Caption) `r`n $($os.Version)`r`n"

# 将系统信息写入文件顶部
$existingContent = Get-Content -Path .\NonWhitelistedApps.txt
Set-Content -Path .\NonWhitelistedApps.txt -Value $formattedSystemInfo
Add-Content -Path .\NonWhitelistedApps.txt -Value $existingContent

# 打开输出文件（可选）
Invoke-Item .\NonWhitelistedApps.txt