@echo off
echo �������� Security Check ������...
schtasks /run /tn SecurityCheckServer
if %errorlevel% equ 0 (
    echo ���������ɹ�
    echo ���ʵ�ַ: http://localhost:8000/
    echo �������: http://localhost:8000/health
    timeout /t 5 /nobreak > nul
    echo ��������״̬...
    powershell -Command "try { Invoke-WebRequest -Uri 'http://localhost:8000/health' -UseBasicParsing | Out-Null; Write-Host '��������������' } catch { Write-Host '����������δ��ȫ���������Ժ���' }"
    pause
) else (
    echo ��������ʧ��
    pause
)
