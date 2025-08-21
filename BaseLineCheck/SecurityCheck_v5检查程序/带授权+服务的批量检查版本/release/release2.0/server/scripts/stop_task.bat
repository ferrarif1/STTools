@echo off
echo 正在停止 Security Check 服务器...
taskkill /f /im python.exe /fi "WINDOWTITLE eq SecurityCheckServer*" > nul 2>&1
echo 任务停止成功
pause
