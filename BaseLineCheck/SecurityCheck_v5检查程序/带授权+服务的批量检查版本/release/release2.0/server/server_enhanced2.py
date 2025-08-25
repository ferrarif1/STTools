#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
增强版日志服务器（TXT-only + 并发上限 + 日志轮转）
"""

import json, os, time, logging, signal, sys, threading, traceback, socket
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from queue import Queue
import chardet
from logging.handlers import RotatingFileHandler

# ===== 基本路径 =====
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MONITOR_DIR = os.path.join(BASE_DIR, 'Monitor')
LOG_DIR = os.path.join(BASE_DIR, 'logs')
PID_FILE = os.path.join(BASE_DIR, 'server.pid')

# ===== 配置 =====
HOST, PORT = '0.0.0.0', 8000
MAX_RETRIES, RETRY_DELAY = 3, 5
MAX_BODY_BYTES, SOCKET_TIMEOUT = 2*1024*1024, 10
MAX_CONNS = 200   # 最大并发连接数

for d in [MONITOR_DIR, LOG_DIR]:
    os.makedirs(d, exist_ok=True)

# ===== 日志配置（带轮转）=====
def setup_logging():
    log_file = os.path.join(LOG_DIR, 'server.log')
    handler = RotatingFileHandler(log_file, maxBytes=10*1024*1024, backupCount=5, encoding='utf-8')
    logging.basicConfig(level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[handler, logging.StreamHandler(sys.stdout)])
    return logging.getLogger(__name__)
logger = setup_logging()

# ===== 写入队列 =====
write_q = Queue(maxsize=10000)

def rotate_if_large(path, max_bytes=10*1024*1024):
    if os.path.exists(path) and os.path.getsize(path) >= max_bytes:
        bak = path + ".1"
        if os.path.exists(bak): os.remove(bak)
        os.rename(path, bak)

def _append_txt(ip, ts, data):
    txt_path = os.path.join(MONITOR_DIR, f"{ip}.txt")
    rotate_if_large(txt_path)
    with open(txt_path, 'a', encoding='utf-8') as f:
        f.write(f"[{ts}] {json.dumps(data, ensure_ascii=False)}\n")

def writer_worker():
    while True:
        ip, ts, data = write_q.get()
        try:
            _append_txt(ip, ts, data)
        except Exception as e:
            logger.error(f"后台写入失败: {e}")
        finally:
            write_q.task_done()
threading.Thread(target=writer_worker, daemon=True).start()

# ===== 并发限制 =====
conn_sem = threading.Semaphore(MAX_CONNS)

class ThreadingEnhancedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

# ===== 请求处理 =====
class EnhancedLogHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        logger.info(f"{self.client_address[0]} - {format % args}")

    def handle(self):
        with conn_sem:
            super().handle()

    def _set_timeout(self): 
        try: self.connection.settimeout(SOCKET_TIMEOUT)
        except: pass

    def do_GET(self):
        self._set_timeout()
        try:
            if self.path == "/health": return self.send_health()
            elif self.path == "/status": return self.send_status()
            elif self.path == "/" or self.path == "/index.html":
                return self.serve_file("index.html","text/html")
            elif self.path == "/SecurityCheck_v5":
                return self.serve_file('../SecurityCheck.zip','application/zip',True)
            elif self.path == "/msu.zip":
                return self.serve_file('./msu.zip','application/zip',True)
            elif self.path == "/server.zip":
                return self.serve_file('./server.zip','application/zip',True)
            else: self.send_error(404,"Not Found")
        except Exception as e:
            logger.error(f"GET错误: {e}\n{traceback.format_exc()}")

    def do_POST(self):
        self._set_timeout()
        if self.path!="/log": self.send_error(404); return
        try:
            length = int(self.headers.get('Content-Length') or 0)
            if length<=0 or length>MAX_BODY_BYTES: self.send_error(413); return
            raw = self.rfile.read(length)
            try: raw_text = raw.decode('utf-8')
            except UnicodeDecodeError:
                enc = (chardet.detect(raw) or {}).get('encoding') or 'utf-8'
                raw_text = raw.decode(enc, errors='ignore')
            data = json.loads(raw_text)
            ip, ts = self.client_address[0], time.strftime("%Y-%m-%d %H:%M:%S")
            try: write_q.put_nowait((ip, ts, data))
            except: self.send_error(503,"Busy"); return
            self.send_response(200); self.send_header('Content-type','application/json'); self.end_headers()
            self.wfile.write(b'{"status":"success"}')
        except Exception as e:
            logger.error(f"POST错误: {e}\n{traceback.format_exc()}")
            try: self.send_error(500)
            except: pass

    def serve_file(self, filename, ctype, as_attach=False):
        path = os.path.join(BASE_DIR, filename)
        if not os.path.exists(path): self.send_error(404); return
        self.send_response(200); self.send_header("Content-Type",ctype)
        if as_attach: self.send_header("Content-Disposition",f"attachment; filename={os.path.basename(filename)}")
        self.end_headers()
        try:
            with open(path,'rb') as f:
                while chunk:=f.read(8192):
                    try: self.wfile.write(chunk)
                    except (BrokenPipeError,ConnectionResetError): break
        except Exception as e: logger.error(f"下载错误: {e}")

    def send_health(self):
        self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers()
        self.wfile.write(json.dumps({"status":"healthy","uptime":time.time()-self.server.start_time},ensure_ascii=False).encode())

    def send_status(self):
        self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers()
        self.wfile.write(json.dumps({"uptime":time.time()-self.server.start_time,"monitor_dir":MONITOR_DIR},ensure_ascii=False,indent=2).encode())

# ===== 启动函数 =====
def write_pid(): open(PID_FILE,'w').write(str(os.getpid()))
def rm_pid(): 
    try: os.remove(PID_FILE)
    except: pass

def signal_handler(sig,frame): rm_pid(); sys.exit(0)

def start_server():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    try:
        srv = ThreadingEnhancedHTTPServer((HOST,PORT),EnhancedLogHandler)
        srv.start_time=time.time(); write_pid()
        logger.info(f"日志服务器已启动 http://{HOST}:{PORT}/")
        srv.serve_forever()
    finally: rm_pid()

def main():
    for i in range(MAX_RETRIES):
        try:
            start_server(); break
        except Exception as e:
            logger.error(f"启动失败: {e}")
            if i<MAX_RETRIES-1: time.sleep(RETRY_DELAY)

if __name__=="__main__": main()
