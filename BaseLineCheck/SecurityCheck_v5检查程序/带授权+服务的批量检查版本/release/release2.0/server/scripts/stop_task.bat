@echo off
echo ����ֹͣ Security Check ������...
taskkill /f /im python.exe /fi "WINDOWTITLE eq SecurityCheckServer*" > nul 2>&1
echo ����ֹͣ�ɹ�
pause
