# 获取系统信息（使用WMI替代Get-ComputerInfo）
$os = Get-WmiObject -Class Win32_OperatingSystem
$formattedSystemInfo = "$($os.Caption)"

# 将系统信息写入文件顶部
$existingContent = Get-Content -Path .\MySYSInfo.txt
Set-Content -Path .\MySYSInfo.txt -Value $formattedSystemInfo
Add-Content -Path .\MySYSInfo.txt -Value $existingContent

# 打开输出文件（可选）
Invoke-Item .\MySYSInfo.txt