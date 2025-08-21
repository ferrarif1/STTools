@echo off
echo 快速启动 Security Check 服务器...
echo 注意：这是直接启动，不是作为任务计划运行
echo.
cd /d "C:\Users\revan\Desktop\STTools\BaseLineCheck\SecurityCheck_v5检查程序\带授权+服务的批量检查版本\release\release2.0\server"
python server_enhanced.py
pause
