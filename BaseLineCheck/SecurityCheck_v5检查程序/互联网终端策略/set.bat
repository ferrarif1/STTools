@echo off
:: Automatically elevate: if not an administrator, re-run as administrator
openfiles >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo ===============================
echo Setting Windows password policy...
echo ===============================

:: Set maximum password age to 90 days
echo [1] Setting maximum password age...
net accounts /maxpwage:90

:: Build temporary policy configuration file
set "_inf=%temp%\pass_policy.inf"
> "%_inf%" (
    echo [Unicode]
    echo Unicode=yes
    echo [System Access]
    echo MinimumPasswordLength = 8
    echo PasswordComplexity = 1
    echo PasswordHistorySize = 1
    echo MaximumPasswordAge = 90
    echo MinimumPasswordAge = 1
    echo [Version]
    echo signature="$CHICAGO$"
)

:: Apply security policy
echo [2] Applying password complexity and history policy...
secedit /configure /db secedit.sdb /cfg "%_inf%" /areas SECURITYPOLICY >nul

:: Clean up temporary file
del "%_inf%" >nul

echo.
echo ✅ All password policies have been successfully applied!
pause
