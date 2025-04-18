@echo off

echo ===============================
echo Setting Windows password policy...
echo ===============================

echo [1] Setting guest account to inactive...
net user guest /active:no
:: Set maximum password age to 90 days
echo [2] Setting maximum password age...
net accounts /maxpwage:90

echo [3] Enabling password expiration for Administrator...
wmic useraccount where "name='Administrator'" set PasswordExpires=True

:: Build temporary policy configuration file
set "_inf=%temp%\pass_policy.inf"
> "%_inf%" (
    echo [Unicode]
    echo Unicode=yes
    echo [System Access]
    echo MinimumPasswordLength = 8
    echo PasswordComplexity = 1
    echo PasswordHistorySize = 3
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
