@echo off
echo �������� Security Check ������...
taskkill /f /im python.exe /fi "WINDOWTITLE eq SecurityCheckServer*" > nul 2>&1
timeout /t 3 /nobreak > nul
schtasks /run /tn SecurityCheckServer
if %errorlevel% equ 0 (
    echo ���������ɹ�
    echo ���ʵ�ַ: http://localhost:8000/
) else (
    echo ��������ʧ��
)
pause
