#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
自动重启监控脚本
监控服务器状态，掉线时自动重启
"""

import requests
import time
import subprocess
import logging
import os
import sys
import signal
from datetime import datetime
from threading import Thread, Event

# 配置
SERVER_URL = "http://localhost:8000"
HEALTH_URL = f"{SERVER_URL}/health"
CHECK_INTERVAL = 30  # 检查间隔（秒）
RESTART_DELAY = 5    # 重启延迟（秒）
MAX_RESTART_ATTEMPTS = 50  # 最大重启尝试次数

# 日志配置
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR)

def setup_logging():
    """设置日志"""
    log_file = os.path.join(LOG_DIR, f'auto_restart_{datetime.now().strftime("%Y%m%d")}.log')
    
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

class AutoRestartMonitor:
    """自动重启监控器"""
    
    def __init__(self):
        self.stop_event = Event()
        self.restart_count = 0
        self.last_check_time = None
        
    def check_server_health(self):
        """检查服务器健康状态"""
        try:
            response = requests.get(HEALTH_URL, timeout=10)
            if response.status_code == 200:
                data = response.json()
                logger.info(f"服务器健康检查通过: {data}")
                return True
            else:
                logger.warning(f"服务器响应异常: {response.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            logger.error("无法连接到服务器")
            return False
        except requests.exceptions.Timeout:
            logger.error("服务器响应超时")
            return False
        except Exception as e:
            logger.error(f"健康检查失败: {e}")
            return False
    
    def restart_task(self):
        """重启任务计划"""
        logger.info("正在重启任务计划...")
        
        try:
            # 停止任务
            result = subprocess.run(['schtasks', '/run', '/tn', 'SecurityCheckServer'], 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("任务重启成功")
                return True
            else:
                logger.error(f"任务重启失败: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"重启任务时发生错误: {e}")
            return False
    
    def monitor_loop(self):
        """监控循环"""
        logger.info("开始监控服务器...")
        
        while not self.stop_event.is_set():
            try:
                self.last_check_time = datetime.now()
                
                # 检查服务器状态
                if not self.check_server_health():
                    logger.warning("服务器健康检查失败")
                    
                    # 尝试重启服务器
                    if self.restart_count < MAX_RESTART_ATTEMPTS:
                        if self.restart_task():
                            logger.info("服务器已重启")
                            self.restart_count = 0
                        else:
                            self.restart_count += 1
                            logger.error(f"重启失败，尝试次数: {self.restart_count}/{MAX_RESTART_ATTEMPTS}")
                    else:
                        logger.error(f"已达到最大重启次数 ({MAX_RESTART_ATTEMPTS})，停止自动重启")
                        break
                else:
                    # 服务器正常，重置重启计数
                    if self.restart_count > 0:
                        logger.info("服务器恢复正常，重置重启计数")
                        self.restart_count = 0
                
                # 等待下次检查
                self.stop_event.wait(CHECK_INTERVAL)
                
            except Exception as e:
                logger.error(f"监控循环中发生错误: {e}")
                time.sleep(CHECK_INTERVAL)
    
    def start_monitoring(self):
        """开始监控"""
        logger.info("启动自动重启监控器...")
        
        # 检查服务器是否已运行
        if not self.check_server_health():
            logger.info("服务器未运行，尝试启动...")
            if not self.restart_task():
                logger.error("无法启动服务器")
                return False
        
        # 启动监控线程
        monitor_thread = Thread(target=self.monitor_loop, daemon=True)
        monitor_thread.start()
        
        logger.info("监控器已启动，按 Ctrl+C 停止")
        
        try:
            # 主循环
            while not self.stop_event.is_set():
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("收到停止信号")
        finally:
            self.stop_event.set()
            logger.info("监控器已停止")

def signal_handler(signum, frame):
    """信号处理器"""
    logger.info(f"收到信号 {signum}，正在停止监控器...")
    sys.exit(0)

def main():
    """主函数"""
    # 注册信号处理器
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    print("Security Check 服务器自动重启监控器")
    print("=" * 50)
    print(f"监控地址: {SERVER_URL}")
    print(f"检查间隔: {CHECK_INTERVAL} 秒")
    print(f"最大重启次数: {MAX_RESTART_ATTEMPTS}")
    print()
    
    # 创建监控器
    monitor = AutoRestartMonitor()
    
    # 开始监控
    monitor.start_monitoring()

if __name__ == '__main__':
    main() 
