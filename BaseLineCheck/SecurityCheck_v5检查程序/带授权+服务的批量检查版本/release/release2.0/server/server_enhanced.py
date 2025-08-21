#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
增强版日志服务器 - 解决服务掉线问题
支持自动重启、错误处理、日志记录、健康检查等功能
"""

import json
import os
import time
import logging
import signal
import sys
import threading
import traceback
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
import pandas as pd
import chardet
import socket
import ssl

# 配置常量
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MONITOR_DIR = os.path.join(BASE_DIR, 'Monitor')
EXCEL_PATH = os.path.join(MONITOR_DIR, 'summary.xlsx')
LOG_DIR = os.path.join(BASE_DIR, 'logs')
PID_FILE = os.path.join(BASE_DIR, 'server.pid')

# 服务器配置
HOST = '0.0.0.0'
PORT = 8000
MAX_RETRIES = 3
RETRY_DELAY = 5

# 创建必要的目录
for directory in [MONITOR_DIR, LOG_DIR]:
    if not os.path.exists(directory):
        os.makedirs(directory)

# 配置日志
def setup_logging():
    """配置日志系统"""
    log_file = os.path.join(LOG_DIR, f'server_{datetime.now().strftime("%Y%m%d")}.log')
    
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

class EnhancedLogHandler(BaseHTTPRequestHandler):
    """增强版日志处理器"""
    
    def log_message(self, format, *args):
        """重写日志方法，使用我们的logger"""
        logger.info(f"{self.client_address[0]} - {format % args}")
    
    def do_GET(self):
        """处理GET请求"""
        try:
            # 健康检查端点
            if self.path == "/health":
                self.send_health_response()
                return
            
            # 状态检查端点
            elif self.path == "/status":
                self.send_status_response()
                return
            
            # 主页面：index.html，供被检查用户使用
            elif self.path == "/" or self.path == "/index.html":
                self.serve_file("index.html", "text/html")
            
            # 返回 Security Check 工具下载文件
            elif self.path == "/SecurityCheck_v5":
                self.serve_file('SecurityCheck_v5.zip', 'application/zip', as_attachment=True)
            
            elif self.path == "/msu":
                self.serve_file('msu.zip', 'application/zip', as_attachment=True)
            
            # 返回管理员使用说明页面 readme.html
            elif self.path == "/readme":
                self.serve_file("README.html", "text/html")
            
            else:
                self.send_error(404, "Not Found")
                
        except Exception as e:
            logger.error(f"GET请求处理错误: {str(e)}")
            logger.error(traceback.format_exc())
            self.send_error(500, "Internal Server Error")
    
    def do_POST(self):
        """处理POST请求"""
        if self.path != '/log':
            self.send_error(404, "Not Found")
            return

        try:
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length == 0:
                self.send_error(400, "Empty request body")
                return
            
            # 读取请求数据
            raw_bytes = self.rfile.read(content_length)
            
            # 检测编码
            detection = chardet.detect(raw_bytes)
            encoding = detection['encoding'] if detection['confidence'] > 0.7 else 'utf-8'
            logger.info(f"检测到编码: {encoding}, 可信度: {detection['confidence']}")
            
            # 解析JSON数据
            raw_data = raw_bytes.decode(encoding)
            plugin_data = json.loads(raw_data)
            client_ip = self.client_address[0]
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

            logger.info(f"收到来自 {client_ip} 的日志数据")

            # 保存到文本文件
            self.save_to_txt(client_ip, timestamp, plugin_data)
            
            # 保存到Excel文件
            self.append_to_excel(client_ip, timestamp, plugin_data)

            # 发送成功响应
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'success'}, ensure_ascii=False).encode('utf-8'))
            
            logger.info(f"成功处理来自 {client_ip} 的请求")

        except json.JSONDecodeError as e:
            logger.error(f"JSON解析错误: {str(e)}")
            self.send_error(400, "Invalid JSON")
        except Exception as e:
            logger.error(f"POST请求处理错误: {str(e)}")
            logger.error(traceback.format_exc())
            self.send_error(500, f"Server Error: {str(e)}")

    def save_to_txt(self, ip, timestamp, data):
        """保存日志到文本文件"""
        try:
            txt_path = os.path.join(MONITOR_DIR, f"{ip}.txt")
            with open(txt_path, 'a', encoding='utf-8') as f:
                f.write(f"[{timestamp}] {json.dumps(data, ensure_ascii=False)}\n")
        except Exception as e:
            logger.error(f"保存文本文件失败: {str(e)}")

    def append_to_excel(self, ip, timestamp, data):
        """追加数据到Excel文件"""
        try:
            record = {'IP': ip, '时间': timestamp}
            if isinstance(data, dict):
                record.update(data)
                df_new = pd.DataFrame([record])
            elif isinstance(data, list):
                df_list = []
                for entry in data:
                    row = {'IP': ip, '时间': timestamp}
                    if isinstance(entry, dict):
                        row.update(entry)
                    else:
                        row['数据'] = str(entry)
                    df_list.append(row)
                df_new = pd.DataFrame(df_list)
            else:
                record['数据'] = str(data)
                df_new = pd.DataFrame([record])

            # 使用临时文件避免并发写入问题
            temp_excel_path = EXCEL_PATH + '.tmp'
            
            if os.path.exists(EXCEL_PATH):
                df_old = pd.read_excel(EXCEL_PATH)
                df_all = pd.concat([df_old, df_new], ignore_index=True)
            else:
                df_all = df_new

            # 先写入临时文件，再重命名
            df_all.to_excel(temp_excel_path, index=False)
            if os.path.exists(EXCEL_PATH):
                os.remove(EXCEL_PATH)
            os.rename(temp_excel_path, EXCEL_PATH)
            
        except Exception as e:
            logger.error(f"保存Excel文件失败: {str(e)}")

    def serve_file(self, filename, content_type, as_attachment=False):
        """提供文件下载服务"""
        try:
            filepath = os.path.join(BASE_DIR, filename)
            if os.path.exists(filepath):
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                if as_attachment:
                    self.send_header("Content-Disposition", f"attachment; filename=\"{os.path.basename(filename)}\"")
                self.end_headers()
                
                # 分块读取大文件，避免内存问题
                with open(filepath, 'rb') as f:
                    while True:
                        chunk = f.read(8192)  # 8KB chunks
                        if not chunk:
                            break
                        self.wfile.write(chunk)
            else:
                logger.warning(f"文件不存在: {filename}")
                self.send_error(404, "File not found")
        except Exception as e:
            logger.error(f"文件服务错误: {str(e)}")
            self.send_error(500, "File service error")

    def send_health_response(self):
        """发送健康检查响应"""
        try:
            health_data = {
                'status': 'healthy',
                'timestamp': datetime.now().isoformat(),
                'uptime': time.time() - self.server.start_time,
                'version': '2.0'
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps(health_data, ensure_ascii=False).encode('utf-8'))
        except Exception as e:
            logger.error(f"健康检查响应错误: {str(e)}")

    def send_status_response(self):
        """发送状态信息响应"""
        try:
            status_data = {
                'server_info': {
                    'host': HOST,
                    'port': PORT,
                    'start_time': datetime.fromtimestamp(self.server.start_time).isoformat(),
                    'uptime': time.time() - self.server.start_time
                },
                'file_info': {
                    'monitor_dir': MONITOR_DIR,
                    'excel_file': EXCEL_PATH,
                    'excel_exists': os.path.exists(EXCEL_PATH)
                }
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps(status_data, ensure_ascii=False, indent=2).encode('utf-8'))
        except Exception as e:
            logger.error(f"状态响应错误: {str(e)}")

class EnhancedHTTPServer(HTTPServer):
    """增强版HTTP服务器"""
    
    def __init__(self, server_address, RequestHandlerClass):
        super().__init__(server_address, RequestHandlerClass)
        self.start_time = time.time()
        self.request_count = 0
        self.error_count = 0

def write_pid_file():
    """写入PID文件"""
    try:
        with open(PID_FILE, 'w') as f:
            f.write(str(os.getpid()))
    except Exception as e:
        logger.error(f"写入PID文件失败: {str(e)}")

def remove_pid_file():
    """删除PID文件"""
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception as e:
        logger.error(f"删除PID文件失败: {str(e)}")

def signal_handler(signum, frame):
    """信号处理器"""
    logger.info(f"收到信号 {signum}，正在关闭服务器...")
    remove_pid_file()
    sys.exit(0)

def check_port_available(host, port):
    """检查端口是否可用"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind((host, port))
            return True
    except OSError:
        return False

def start_server():
    """启动服务器"""
    # 注册信号处理器
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # 检查端口是否被占用
    if not check_port_available(HOST, PORT):
        logger.error(f"端口 {PORT} 已被占用，请检查是否有其他服务在运行")
        return False
    
    try:
        # 创建服务器
        server = EnhancedHTTPServer((HOST, PORT), EnhancedLogHandler)
        
        # 写入PID文件
        write_pid_file()
        
        logger.info(f"增强版日志服务器已启动：http://{HOST}:{PORT}/")
        logger.info(f"健康检查: http://{HOST}:{PORT}/health")
        logger.info(f"状态信息: http://{HOST}:{PORT}/status")
        logger.info(f"PID文件: {PID_FILE}")
        
        # 启动服务器
        server.serve_forever()
        
    except KeyboardInterrupt:
        logger.info("收到中断信号，正在关闭服务器...")
    except Exception as e:
        logger.error(f"服务器启动失败: {str(e)}")
        logger.error(traceback.format_exc())
        return False
    finally:
        remove_pid_file()
    
    return True

def main():
    """主函数"""
    logger.info("正在启动增强版日志服务器...")
    
    retry_count = 0
    while retry_count < MAX_RETRIES:
        try:
            if start_server():
                break
            else:
                retry_count += 1
                if retry_count < MAX_RETRIES:
                    logger.warning(f"服务器启动失败，{RETRY_DELAY}秒后重试 ({retry_count}/{MAX_RETRIES})")
                    time.sleep(RETRY_DELAY)
                else:
                    logger.error(f"服务器启动失败，已达到最大重试次数 ({MAX_RETRIES})")
        except Exception as e:
            logger.error(f"服务器运行异常: {str(e)}")
            retry_count += 1
            if retry_count < MAX_RETRIES:
                time.sleep(RETRY_DELAY)

if __name__ == '__main__':
    main() 