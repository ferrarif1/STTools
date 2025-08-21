@echo off
chcp 65001 >nul
title Security Check Server Launcher

echo.
echo ========================================
echo    Security Check Server Launcher
echo ========================================
echo.

:: 切换到脚本所在目录
cd /d "%~dp0"

:: 检查Python是否安装
python --version >nul 2>&1
if errorlevel 1 (
    echo Error: Python not found, please install Python 3.7+
    pause
    exit /b 1
)

:: 检查依赖包
echo Checking dependencies...
python -c "import pandas, requests, chardet, openpyxl" >nul 2>&1
if errorlevel 1 (
    echo Warning: Missing dependencies, installing...
    python install_dependencies.py
    if errorlevel 1 (
        echo Error: Failed to install dependencies
        pause
        exit /b 1
    )
)

:: 启动服务器
echo Starting Security Check server...
echo.
echo Server Information:
echo    Address: http://localhost:8000
echo    Homepage: http://localhost:8000/index.html
echo    Health Check: http://localhost:8000/health
echo.
echo Tips:
echo    - Press Ctrl+C to stop server
echo    - Visit homepage to download client and docs
echo    - Check logs directory for detailed logs
echo.

python server_enhanced.py

pause 