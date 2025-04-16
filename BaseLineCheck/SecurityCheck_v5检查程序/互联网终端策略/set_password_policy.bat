@echo off
:: ====== 自动提权段落 ======
openfiles >nul 2>&1
if %errorlevel% NEQ 0 (
    echo 正在请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo ================================
echo   设置密码策略为强安全要求
echo ================================
echo.

:: 1. 设置最大密码使用期限为 90 天
echo [1] 设置全局密码策略为每90天修改...
net accounts /maxpwage:90

:: 2. 强制所有本地用户密码必须过期
echo [2] 设置所有本地用户“密码必须过期”...
for /f "tokens=*" %%i in ('wmic useraccount where "LocalAccount=True and Disabled=False" get Name ^| findstr /r /v "^$"') do (
    echo     处理用户：%%i
    wmic useraccount where name="%%i" set PasswordExpires=TRUE >nul
)

:: 3. 启用密码复杂度策略（强密码策略）
echo [3] 启用密码复杂度要求（强密码策略）...
:: 创建临时 INF 文件
set "_tmpinf=%temp%\pwd_policy.inf"
> "%_tmpinf%" (
    echo [Unicode]
    echo Unicode=yes
    echo [System Access]
    echo MinimumPasswordLength = 8
    echo PasswordComplexity = 1
    echo MaximumPasswordAge = 90
    echo MinimumPasswordAge = 1
    echo LockoutBadCount = 0
    echo [Version]
    echo signature="$CHICAGO$"
)

:: 应用 INF 到系统策略
secedit /configure /db secedit.sdb /cfg "%_tmpinf%" /areas SECURITYPOLICY >nul

:: 删除临时文件
del "%_tmpinf%" >nul

echo.
echo 所有策略设置完成！
pause