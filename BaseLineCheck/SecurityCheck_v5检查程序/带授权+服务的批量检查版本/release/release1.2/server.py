from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import time
import pandas as pd
import chardet

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MONITOR_DIR = os.path.join(BASE_DIR, 'Monitor')
EXCEL_PATH = os.path.join(MONITOR_DIR, 'summary.xlsx')

if not os.path.exists(MONITOR_DIR):
    os.makedirs(MONITOR_DIR)

class LogHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # 主页面：index.html，供被检查用户使用
        if self.path == "/" or self.path == "/index.html":
            self.serve_file("index.html", "text/html")
        # 返回 Security Check 工具下载文件
        elif self.path == "/SecurityCheck_v5":
            # 默认返回 SecurityCheck_v5.exe、config.json、ip_set_config.json, 依赖dotnet与msu补丁
            self.serve_file('SecurityCheck_v5.zip', 'application/zip', as_attachment=True)
        elif self.path == "/msu":
            # 默认返回 SecurityCheck_v5.exe、config.json、ip_set_config.json, 依赖dotnet与msu补丁
            self.serve_file('msu.zip', 'application/zip', as_attachment=True)
        # 返回管理员使用说明页面 readme.html
        elif self.path == "/readme":
            self.serve_file("README.html", "text/html")
        else:
            self.send_error(404)
    
    def do_POST(self):
        if self.path != '/log':
            self.send_error(404, "Not Found")
            return

        content_length = int(self.headers.get('Content-Length', 0))
        try:
            raw_bytes = self.rfile.read(content_length)
            
            detection = chardet.detect(raw_bytes)
            encoding = detection['encoding'] if detection['confidence'] > 0.7 else 'utf-8'
            print(f"检测到编码: {encoding}, 可信度: {detection['confidence']}")
            
            raw_data = raw_bytes.decode(encoding)
            plugin_data = json.loads(raw_data)
            client_ip = self.client_address[0]
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

            txt_path = os.path.join(MONITOR_DIR, f"{client_ip}.txt")
            with open(txt_path, 'a', encoding='utf-8') as f:
                f.write(f"[{timestamp}] {json.dumps(plugin_data, ensure_ascii=False)}\n")

            self.append_to_excel(client_ip, timestamp, plugin_data)

            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'success'}, ensure_ascii=False).encode('utf-8'))

        except json.JSONDecodeError as e:
            print(f"JSON解析错误: {str(e)}")
            self.send_error(400, "Invalid JSON")
        except Exception as e:
            print(f"服务器错误: {str(e)}")
            self.send_error(500, f"Server Error: {str(e)}")

    def append_to_excel(self, ip, timestamp, data):
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

        if os.path.exists(EXCEL_PATH):
            df_old = pd.read_excel(EXCEL_PATH)
            df_all = pd.concat([df_old, df_new], ignore_index=True)
        else:
            df_all = df_new

        df_all.to_excel(EXCEL_PATH, index=False)

    def serve_file(self, filename, content_type, as_attachment=False):
        filepath = os.path.join(BASE_DIR, filename)
        if os.path.exists(filepath):
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            if as_attachment:
                self.send_header("Content-Disposition", f"attachment; filename=\"{os.path.basename(filename)}\"")
            self.end_headers()
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_error(404, "File not found")

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8000), LogHandler)
    print("日志服务器已启动：http://localhost:8000/")
    server.serve_forever()
