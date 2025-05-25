# ✅ 增强版小程序扫描 CLI v3.2（支持调试日志与目录跳过提示）

import os
import subprocess
import json
import matplotlib.pyplot as plt
from collections import defaultdict
from io import StringIO
import csv
import argparse
import sys

# 设置中文支持
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['Arial Unicode MS']
matplotlib.rcParams['axes.unicode_minus'] = False

NODEJSSCAN_PATH = "nodejsscan.app"

scan_results = []
failed_paths = []

# 调用 semgrep
def scan_with_semgrep(app_path):
    result = []
    try:
        cmd = ["semgrep", "--config", "p/owasp-top-ten", "--json", "-q", app_path]
        print(f"  [→] semgrep 执行中...")
        process = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if process.returncode != 0:
            failed_paths.append(app_path)
            print(f"[!] semgrep 扫描失败: {app_path}")
            print("[命令] ", " ".join(cmd))
            print("[stdout]", process.stdout.strip())
            print("[stderr]", process.stderr.strip())
            return []
        result_json = json.loads(process.stdout)
        for item in result_json.get("results", []):
            result.append({
                "type": item.get("check_id", "未知规则"),
                "file": item.get("path", app_path),
                "info": item.get("extra", {}).get("message", ""),
                "engine": "semgrep"
            })
            # 立即写入每个漏洞到文件
            with open("scan_results.txt", "a", encoding='utf-8') as f:
                f.write(f"文件: {item['path']}, 类型: {item['check_id']}, 描述: {item['extra'].get('message', '')}\n")
    except Exception as e:
        failed_paths.append(app_path)
        print(f"semgrep 异常: {e}")
    return result

# 递归扫描 wx 目录
def scan_directory(wx_path):
    global scan_results
    scan_results.clear()
    for app_name in os.listdir(wx_path):
        app_path = os.path.join(wx_path, app_name)
        if not os.path.isdir(app_path): continue
        for sub_ver in os.listdir(app_path):
            app_dir = os.path.join(app_path, sub_ver, "__APP__")
            if os.path.isdir(app_dir):
                print(f"[*] 扫描中: {app_dir}")
                
                result = scan_with_semgrep(app_dir)
                scan_results.extend(result)

# Markdown 报告
def generate_markdown():
    md = StringIO()
    md.write("# 小程序漏洞扫描报告\n\n")
    for item in scan_results:
        md.write(f"## 文件: {item['file']}\n")
        md.write(f"**类型**: {item['type']}\n\n")
        md.write(f"**描述**: {item['info']}\n\n")
        md.write(f"**引擎**: {item['engine']}\n\n---\n")
    return md.getvalue()

def export_md(path="scan_report.md"):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(generate_markdown())
    print(f"[+] Markdown 报告导出完成：{path}")

def export_csv(path="scan_report.csv"):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["类型", "文件", "描述", "引擎"])
        for item in scan_results:
            writer.writerow([item['type'], item['file'], item['info'], item['engine']])
    print(f"[+] CSV 报告导出完成：{path}")

def export_error_log(path="scan_errors.txt"):
    if failed_paths:
        with open(path, 'w', encoding='utf-8') as f:
            for p in failed_paths:
                f.write(p + "\n")
        print(f"[!] 失败路径记录至: {path}")

def draw_chart():
    count = defaultdict(int)
    for item in scan_results:
        count[item['type']] += 1
    if not count:
        return
    labels, sizes = zip(*count.items())
    plt.figure(figsize=(6, 6))
    plt.pie(sizes, labels=labels, autopct="%1.1f%%")
    plt.title("漏洞类型分布")
    plt.tight_layout()
    plt.savefig("chart.png")
    print("[+] 漏洞类型分布图保存为 chart.png")

# ====== 主流程 ======
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="小程序源码漏洞扫描工具")
    parser.add_argument('--path', type=str, default="./wx", help='小程序 wx 根目录路径')
    parser.add_argument('--nochart', action='store_true', help='不生成饼图')
    args = parser.parse_args()

    try:
        print(f"[+] 开始扫描目录: {args.path}")
        scan_directory(args.path)
        export_md()
        export_csv()
        export_error_log()
        if not args.nochart:
            draw_chart()
        print("[✓] 扫描完成，总计发现漏洞项：", len(scan_results))
    except KeyboardInterrupt:
        print("\n[!] 扫描中断，已退出。")
        sys.exit(1)
