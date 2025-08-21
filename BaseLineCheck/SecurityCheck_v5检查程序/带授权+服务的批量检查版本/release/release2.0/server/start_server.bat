@echo off
chcp 65001 >nul
title Security Check 服务器启动器

echo.
echo ========================================
echo    Security Check 服务器启动器
echo ========================================
echo.

:: 检查Python是否安装
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 错误：未找到Python，请先安装Python 3.7+
    pause
    exit /b 1
)

:: 检查依赖包
echo 🔍 检查依赖包...
python -c "import pandas, requests, chardet, openpyxl" >nul 2>&1
if errorlevel 1 (
    echo ⚠️  检测到缺少依赖包，正在安装...
    python install_dependencies.py
    if errorlevel 1 (
        echo ❌ 依赖包安装失败，请检查网络连接或手动安装
        pause
        exit /b 1
    )
)


:: 启动服务器
echo 🚀 启动Security Check服务器...
echo.
echo 📋 服务器信息：
echo    地址: http://localhost:8000
echo    主页: http://localhost:8000/index.html
echo    健康检查: http://localhost:8000/health
echo.
echo 💡 提示：
echo    - 按 Ctrl+C 停止服务器
echo    - 访问主页下载客户端和文档
echo    - 查看logs目录获取详细日志
echo.

python server_enhanced.py

pause 