@echo off
echo 正在重启 Security Check 服务器...
taskkill /f /im python.exe /fi "WINDOWTITLE eq SecurityCheckServer*" > nul 2>&1
timeout /t 3 /nobreak > nul
schtasks /run /tn SecurityCheckServer
if %errorlevel% equ 0 (
    echo 任务重启成功
    echo 访问地址: http://localhost:8000/
) else (
    echo 任务重启失败
)
pause
