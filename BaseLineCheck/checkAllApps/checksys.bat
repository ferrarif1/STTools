@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$os = Get-WmiObject -Class Win32_OperatingSystem; ^
$formattedSystemInfo = $os.Caption; ^
$sysFile = '.\\MySYSInfo.txt'; ^
if (Test-Path $sysFile) { ^
    $existingContent = Get-Content -Path $sysFile; ^
    Set-Content -Path $sysFile -Value $formattedSystemInfo; ^
    Add-Content -Path $sysFile -Value $existingContent ^
} else { ^
    Set-Content -Path $sysFile -Value $formattedSystemInfo ^
}; ^
Invoke-Item $sysFile"
exit