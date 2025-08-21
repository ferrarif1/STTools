@echo off
echo 检查 Security Check 服务器状态...
schtasks /query /tn SecurityCheckServer
echo.
echo 检查服务器进程...
tasklist /fi "imagename eq python.exe" /fi "WINDOWTITLE eq SecurityCheckServer*"
echo.
echo 访问地址: http://localhost:8000/health
pause
