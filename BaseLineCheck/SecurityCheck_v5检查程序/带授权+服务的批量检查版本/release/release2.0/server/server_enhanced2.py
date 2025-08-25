#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
增强版日志服务器（TXT-only）
- 去除 Excel 读写，仅保留逐行 TXT 记录（每个来源 IP 一个 txt）
- 多线程 HTTP 服务器 + 后台写队列，避免阻塞 / 并发文件冲突
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
from socketserver import ThreadingMixIn
from queue import Queue, Empty
import chardet
import socket

# ===== 基本路径 =====
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MONITOR_DIR = os.path.join(BASE_DIR, 'Monitor')
LOG_DIR = os.path.join(BASE_DIR, 'logs')
PID_FILE = os.path.join(BASE_DIR, 'server.pid')

# ===== 服务器配置 =====
HOST = '0.0.0.0'
PORT = 8000
MAX_RETRIES = 3
RETRY_DELAY = 5
MAX_BODY_BYTES = 2 * 1024 * 1024   # 2MB 上报体限制
SOCKET_TIMEOUT = 10                # 单连接超时（秒）

# ===== 目录准备 =====
for directory in [MONITOR_DIR, LOG_DIR]:
    os.makedirs(directory, exist_ok=True)

# ===== 日志 =====
def setup_logging():
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

# ===== 后台写入队列（串行落盘）=====
write_q: "Queue[tuple[str,str,object]]" = Queue(maxsize=10000)

def _append_txt(ip: str, timestamp: str, data):
    """将记录追加到 IP 对应的文本文件"""
    txt_path = os.path.join(MONITOR_DIR, f"{ip}.txt")
    line = f"[{timestamp}] {json.dumps(data, ensure_ascii=False)}\n"
    # 原子式 append
    with open(txt_path, 'a', encoding='utf-8') as f:
        f.write(line)

def writer_worker():
    while True:
        try:
            ip, ts, data = write_q.get()
        except Exception:
            continue
        try:
            _append_txt(ip, ts, data)
        except Exception as e:
            logger.error(f"后台写入失败: {e}")
        finally:
            write_q.task_done()

threading.Thread(target=writer_worker, daemon=True).start()

# ===== 线程化 HTTPServer =====
class ThreadingEnhancedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

# ===== 处理器 =====
class EnhancedLogHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        logger.info(f"{self.client_address[0]} - {format % args}")

    def _set_timeout(self):
        try:
            self.connection.settimeout(SOCKET_TIMEOUT)
        except Exception:
            pass

    # ---------- GET ----------
    def do_GET(self):
        self._set_timeout()
        try:
            if self.path == "/health":
                self.send_health_response(); return
            elif self.path == "/status":
                self.send_status_response(); return
            elif self.path == "/" or self.path == "/index.html":
                self.serve_file("index.html", "text/html"); return
            elif self.path == "/SecurityCheck_v5":
                # 先检查再发
                path = os.path.join(BASE_DIR, '../SecurityCheck.zip')
                if not os.path.exists(path):
                    self.send_error(404, "SecurityCheck.zip not found"); return
                self.serve_file('../SecurityCheck.zip', 'application/zip', as_attachment=True); return
            elif self.path == "/msu.zip":
                path = os.path.join(BASE_DIR, 'msu.zip')
                if not os.path.exists(path):
                    self.send_error(404, "msu.zip not found"); return
                self.serve_file('./msu.zip', 'application/zip', as_attachment=True); return
            elif self.path == "/server.zip":
                path = os.path.join(BASE_DIR, 'server.zip')
                if not os.path.exists(path):
                    self.send_error(404, "server.zip not found"); return
                self.serve_file('./server.zip', 'application/zip', as_attachment=True); return
            elif self.path == "/README-Server.html":
                self.serve_file('../README-Server.html', 'text/html'); return
            elif self.path == "/README-Client.html":
                self.serve_file('../README-Client.html', 'text/html'); return
            else:
                self.send_error(404, "Not Found")
        except Exception as e:
            logger.error(f"GET处理错误: {e}")
            logger.error(traceback.format_exc())
            # 这里尽量不再 send_error，避免 headers 已发送后的异常

    # ---------- POST ----------
    def do_POST(self):
        self._set_timeout()
        if self.path != '/log':
            self.send_error(404, "Not Found")
            return

        try:
            length = int(self.headers.get('Content-Length') or 0)
            if length <= 0 or length > MAX_BODY_BYTES:
                self.send_error(413, "Payload Too Large")
                return

            raw = self.rfile.read(length)

            # UTF-8 优先，失败再 detect 兜底
            try:
                raw_text = raw.decode('utf-8')
            except UnicodeDecodeError:
                detection = chardet.detect(raw) or {}
                enc = detection.get('encoding') or 'utf-8'
                raw_text = raw.decode(enc, errors='ignore')

            data = json.loads(raw_text)
            client_ip = self.client_address[0]
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

            # 入队（后台写）
            try:
                write_q.put_nowait((client_ip, timestamp, data))
            except Exception:
                self.send_error(503, "Server busy")
                return

            # 立即回应
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'success'}, ensure_ascii=False).encode('utf-8'))

        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
        except Exception as e:
            logger.error(f"POST处理错误: {e}")
            logger.error(traceback.format_exc())
            # 若还未发头，可 500；若已发头，静默记录
            try:
                self.send_error(500, "Server Error")
            except Exception:
                pass

    # ---------- 文件服务 ----------
    def serve_file(self, filename, content_type, as_attachment=False):
        try:
            filepath = os.path.join(BASE_DIR, filename)
            if not os.path.exists(filepath):
                self.send_error(404, "File not found")
                return

            self.send_response(200)
            self.send_header("Content-Type", content_type)
            if as_attachment:
                self.send_header("Content-Disposition", f"attachment; filename=\"{os.path.basename(filename)}\"")
            self.end_headers()

            with open(filepath, 'rb') as f:
                while True:
                    chunk = f.read(8192)
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                    except (BrokenPipeError, ConnectionResetError):
                        logger.warning("客户端中途断开连接")
                        break
        except Exception as e:
            logger.error(f"文件服务错误: {e}")
            # 这里不再 send_error，避免 headers 已发后的异常

    # ---------- 健康/状态 ----------
    def send_health_response(self):
        try:
            health_data = {
                'status': 'healthy',
                'timestamp': datetime.now().isoformat(),
                'uptime': time.time() - self.server.start_time,
                'version': '2.0-txt'
            }
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps(health_data, ensure_ascii=False).encode('utf-8'))
        except Exception as e:
            logger.error(f"健康检查响应错误: {e}")

    def send_status_response(self):
        try:
            status_data = {
                'server_info': {
                    'host': HOST,
                    'port': PORT,
                    'start_time': datetime.fromtimestamp(self.server.start_time).isoformat(),
                    'uptime': time.time() - self.server.start_time
                },
                'file_info': {
                    'monitor_dir': MONITOR_DIR
                }
            }
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps(status_data, ensure_ascii=False, indent=2).encode('utf-8'))
        except Exception as e:
            logger.error(f"状态响应错误: {e}")

# ===== 启动辅助 =====
def write_pid_file():
    try:
        with open(PID_FILE, 'w') as f:
            f.write(str(os.getpid()))
    except Exception as e:
        logger.error(f"写入PID失败: {e}")

def remove_pid_file():
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception as e:
        logger.error(f"删除PID失败: {e}")

def signal_handler(signum, frame):
    logger.info(f"收到信号 {signum}，准备退出")
    remove_pid_file()
    sys.exit(0)

def check_port_available(host, port):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind((host, port))
            return True
    except OSError:
        return False

def start_server():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    if not check_port_available(HOST, PORT):
        logger.error(f"端口 {PORT} 已占用")
        return False

    try:
        server = ThreadingEnhancedHTTPServer((HOST, PORT), EnhancedLogHandler)
        server.start_time = time.time()
        write_pid_file()

        logger.info(f"TXT-only 日志服务器已启动: http://{HOST}:{PORT}/")
        logger.info(f"健康检查: http://{HOST}:{PORT}/health")
        logger.info(f"状态信息: http://{HOST}:{PORT}/status")
        logger.info(f"PID文件: {PID_FILE}")

        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("收到中断信号，正在关闭...")
    except Exception as e:
        logger.error(f"服务器启动失败: {e}")
        logger.error(traceback.format_exc())
        return False
    finally:
        remove_pid_file()
    return True

def main():
    logger.info("正在启动 TXT-only 日志服务器...")
    retry = 0
    while retry < MAX_RETRIES:
        ok = start_server()
        if ok:
            break
        retry += 1
        if retry < MAX_RETRIES:
            logger.warning(f"{RETRY_DELAY}s 后重试 ({retry}/{MAX_RETRIES})")
            time.sleep(RETRY_DELAY)
        else:
            logger.error(f"已达最大重试次数: {MAX_RETRIES}")

if __name__ == '__main__':
    main()
