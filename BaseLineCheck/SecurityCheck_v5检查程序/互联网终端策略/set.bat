@echo off
:: 自动提权：不是管理员则重新以管理员运行
openfiles >nul 2>&1
if %errorlevel% NEQ 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo ===============================
echo 正在设置 Windows 密码策略...
echo ===============================

:: 设置密码最大有效期为 90 天
echo [1] 设置密码最大有效期...
net accounts /maxpwage:90

:: 构建临时策略配置文件
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

:: 应用安全策略
echo [2] 应用密码复杂性与历史策略...
secedit /configure /db secedit.sdb /cfg "%_inf%" /areas SECURITYPOLICY >nul

:: 清理临时文件
del "%_inf%" >nul

echo.
echo ✅ 所有密码策略已成功应用！
pause
