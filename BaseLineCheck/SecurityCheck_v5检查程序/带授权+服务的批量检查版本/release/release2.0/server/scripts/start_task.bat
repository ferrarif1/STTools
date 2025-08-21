@echo off
echo 正在启动 Security Check 服务器...
schtasks /run /tn SecurityCheckServer
if %errorlevel% equ 0 (
    echo 任务启动成功
    echo 访问地址: http://localhost:8000/
    echo 健康检查: http://localhost:8000/health
    timeout /t 5 /nobreak > nul
    echo 检查服务器状态...
    powershell -Command "try { Invoke-WebRequest -Uri 'http://localhost:8000/health' -UseBasicParsing | Out-Null; Write-Host '服务器运行正常' } catch { Write-Host '服务器可能未完全启动，请稍后检查' }"
    pause
) else (
    echo 任务启动失败
    pause
)
