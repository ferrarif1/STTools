@echo off
echo ��� Security Check ������״̬...
schtasks /query /tn SecurityCheckServer
echo.
echo ������������...
tasklist /fi "imagename eq python.exe" /fi "WINDOWTITLE eq SecurityCheckServer*"
echo.
echo ���ʵ�ַ: http://localhost:8000/health
pause
