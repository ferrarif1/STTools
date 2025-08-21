#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简化版任务计划程序安装脚本
专门适用于内网环境，无需任何外部依赖
"""

import os
import sys
import subprocess
import logging
from datetime import datetime

# 配置
TASK_NAME = "SecurityCheckServer"
SCRIPT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "server_enhanced.py")
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

def setup_logging():
    """设置日志"""
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
    
    log_file = os.path.join(LOG_DIR, f'task_scheduler_simple_{datetime.now().strftime("%Y%m%d")}.log')
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stdout)
        ]
    )
    return logging.getLogger(__name__)

logger = setup_logging()

def check_admin():
    """检查是否具有管理员权限"""
    try:
        return subprocess.check_output(['net', 'session'], stderr=subprocess.DEVNULL, shell=True)
    except subprocess.CalledProcessError:
        return False

def install_task():
    """安装任务计划"""
    if not check_admin():
        logger.error("需要管理员权限来安装任务")
        print("❌ 请以管理员身份运行此脚本")
        return False
    
    try:
        # 检查任务是否已存在
        result = subprocess.run(['schtasks', '/query', '/tn', TASK_NAME], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.warning(f"任务 {TASK_NAME} 已存在")
            print(f"⚠️  任务 {TASK_NAME} 已存在")
            return True
        
        # 创建任务
        logger.info("正在创建任务计划...")
        print("🔧 正在创建任务计划...")
        
        # 构建schtasks命令
        cmd = [
            'schtasks', '/create', '/tn', TASK_NAME,
            '/tr', f'"{sys.executable}" "{SCRIPT_PATH}"',
            '/sc', 'onstart',  # 系统启动时运行
            '/ru', 'SYSTEM',   # 以SYSTEM权限运行
            '/f'               # 强制创建
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info("任务计划创建成功")
            print("✅ 任务计划创建成功")
            return True
        else:
            logger.error(f"任务计划创建失败: {result.stderr}")
            print(f"❌ 任务计划创建失败: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"创建任务计划时发生错误: {e}")
        print(f"❌ 创建任务计划时发生错误: {e}")
        return False

def uninstall_task():
    """卸载任务计划"""
    if not check_admin():
        logger.error("需要管理员权限来卸载任务")
        print("❌ 请以管理员身份运行此脚本")
        return False
    
    try:
        result = subprocess.run(['schtasks', '/delete', '/tn', TASK_NAME, '/f'], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info("任务计划卸载成功")
            print("✅ 任务计划卸载成功")
            return True
        else:
            logger.error(f"任务计划卸载失败: {result.stderr}")
            print(f"❌ 任务计划卸载失败: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"卸载任务计划时发生错误: {e}")
        print(f"❌ 卸载任务计划时发生错误: {e}")
        return False

def start_task():
    """启动任务"""
    try:
        result = subprocess.run(['schtasks', '/run', '/tn', TASK_NAME], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info("任务启动成功")
            print("✅ 任务启动成功")
            return True
        else:
            logger.error(f"任务启动失败: {result.stderr}")
            print(f"❌ 任务启动失败: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"启动任务时发生错误: {e}")
        print(f"❌ 启动任务时发生错误: {e}")
        return False

def stop_task():
    """停止任务"""
    try:
        # 查找并终止相关进程
        cmd = f'taskkill /f /im python.exe /fi "WINDOWTITLE eq {TASK_NAME}*"'
        subprocess.run(cmd, shell=True, capture_output=True)
        
        logger.info("任务停止成功")
        print("✅ 任务停止成功")
        return True
        
    except Exception as e:
        logger.error(f"停止任务时发生错误: {e}")
        print(f"❌ 停止任务时发生错误: {e}")
        return False

def check_task_status():
    """检查任务状态"""
    try:
        result = subprocess.run(['schtasks', '/query', '/tn', TASK_NAME], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            if "Ready" in result.stdout:
                logger.info("任务已就绪")
                print("🟢 任务已就绪")
                return "READY"
            elif "Running" in result.stdout:
                logger.info("任务正在运行")
                print("🟢 任务正在运行")
                return "RUNNING"
            else:
                logger.info("任务状态未知")
                print("🟡 任务状态未知")
                return "UNKNOWN"
        else:
            logger.error("无法查询任务状态")
            print("❌ 无法查询任务状态")
            return "ERROR"
            
    except Exception as e:
        logger.error(f"检查任务状态时发生错误: {e}")
        print(f"❌ 检查任务状态时发生错误: {e}")
        return "ERROR"

def create_batch_scripts():
    """创建批处理脚本"""
    scripts_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts")
    if not os.path.exists(scripts_dir):
        os.makedirs(scripts_dir)
    
    # 启动任务脚本
    start_script = f'''@echo off
echo 正在启动 Security Check 服务器...
schtasks /run /tn {TASK_NAME}
if %errorlevel% equ 0 (
    echo 任务启动成功
    echo 访问地址: http://localhost:8000/
    echo 健康检查: http://localhost:8000/health
    timeout /t 5 /nobreak > nul
    echo 检查服务器状态...
    powershell -Command "try {{ Invoke-WebRequest -Uri 'http://localhost:8000/health' -UseBasicParsing | Out-Null; Write-Host '服务器运行正常' }} catch {{ Write-Host '服务器可能未完全启动，请稍后检查' }}"
    pause
) else (
    echo 任务启动失败
    pause
)
'''
    
    # 停止任务脚本
    stop_script = f'''@echo off
echo 正在停止 Security Check 服务器...
taskkill /f /im python.exe /fi "WINDOWTITLE eq {TASK_NAME}*" > nul 2>&1
echo 任务停止成功
pause
'''
    
    # 重启任务脚本
    restart_script = f'''@echo off
echo 正在重启 Security Check 服务器...
taskkill /f /im python.exe /fi "WINDOWTITLE eq {TASK_NAME}*" > nul 2>&1
timeout /t 3 /nobreak > nul
schtasks /run /tn {TASK_NAME}
if %errorlevel% equ 0 (
    echo 任务重启成功
    echo 访问地址: http://localhost:8000/
) else (
    echo 任务重启失败
)
pause
'''
    
    # 状态检查脚本
    status_script = f'''@echo off
echo 检查 Security Check 服务器状态...
schtasks /query /tn {TASK_NAME}
echo.
echo 检查服务器进程...
tasklist /fi "imagename eq python.exe" /fi "WINDOWTITLE eq {TASK_NAME}*"
echo.
echo 访问地址: http://localhost:8000/health
pause
'''
    
    # 快速启动脚本（直接运行服务器）
    quick_start_script = f'''@echo off
echo 快速启动 Security Check 服务器...
echo 注意：这是直接启动，不是作为任务计划运行
echo.
cd /d "{os.path.dirname(os.path.abspath(__file__))}"
python server_enhanced.py
pause
'''
    
    scripts = {
        "start_task.bat": start_script,
        "stop_task.bat": stop_script,
        "restart_task.bat": restart_script,
        "check_task_status.bat": status_script,
        "quick_start.bat": quick_start_script
    }
    
    for filename, content in scripts.items():
        filepath = os.path.join(scripts_dir, filename)
        with open(filepath, 'w', encoding='gbk') as f:
            f.write(content)
        logger.info(f"创建脚本: {filename}")
    
    return scripts_dir

def main():
    """主函数"""
    print("Security Check 服务器任务计划管理工具 (简化版)")
    print("=" * 60)
    print("适用于内网环境，无需任何外部依赖")
    print("=" * 60)
    
    if len(sys.argv) > 1:
        action = sys.argv[1].lower()
        
        if action == "install":
            if install_task():
                create_batch_scripts()
                print("📁 管理脚本已创建在 scripts/ 目录")
            else:
                print("❌ 任务计划安装失败")
        
        elif action == "uninstall":
            if uninstall_task():
                print("✅ 任务计划卸载成功")
            else:
                print("❌ 任务计划卸载失败")
        
        elif action == "start":
            if start_task():
                print("✅ 任务启动成功")
            else:
                print("❌ 任务启动失败")
        
        elif action == "stop":
            if stop_task():
                print("✅ 任务停止成功")
            else:
                print("❌ 任务停止失败")
        
        elif action == "status":
            check_task_status()
        
        elif action == "restart":
            if stop_task():
                import time
                time.sleep(3)
                if start_task():
                    print("✅ 任务重启成功")
                else:
                    print("❌ 任务重启失败")
            else:
                print("❌ 任务重启失败")
        
        else:
            print("❌ 未知操作")
    
    else:
        print("使用方法:")
        print("  python install_task_scheduler_simple.py install    # 安装任务")
        print("  python install_task_scheduler_simple.py uninstall  # 卸载任务")
        print("  python install_task_scheduler_simple.py start      # 启动任务")
        print("  python install_task_scheduler_simple.py stop       # 停止任务")
        print("  python install_task_scheduler_simple.py restart    # 重启任务")
        print("  python install_task_scheduler_simple.py status     # 检查状态")
        print()
        print("或者使用批处理脚本:")
        print("  scripts/start_task.bat")
        print("  scripts/stop_task.bat")
        print("  scripts/restart_task.bat")
        print("  scripts/check_task_status.bat")
        print("  scripts/quick_start.bat (直接启动)")
        print()
        print("优势:")
        print("  ✅ 适用于内网环境")
        print("  ✅ 无需任何外部依赖")
        print("  ✅ 使用系统自带功能")
        print("  ✅ 开机自动启动")
        print("  ✅ 系统级权限运行")
        print()
        print("注意:")
        print("  📝 任务计划程序不是真正的Windows服务")
        print("  📝 启动时间可能比服务稍慢")
        print("  📝 建议使用 quick_start.bat 进行测试")

if __name__ == '__main__':
    main() 