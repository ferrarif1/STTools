import os
import sys
import socket
import subprocess
import datetime
import json
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import time

import requests
import nmap

try:
    import whois
except ImportError:
    import pythonwhois as whois

REPORT_DIR = "scan_reports"
os.makedirs(REPORT_DIR, exist_ok=True)


def get_ip(domain):
    try:
        return socket.gethostbyname(domain)
    except Exception as e:
        return f"[!] 无法解析域名 {domain}: {e}"


def ipinfo_lookup(ip):
    print("[*] 正在查询 IP 归属信息...")
    try:
        resp = requests.get(f"https://ipinfo.io/{ip}/json", timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            result = "## IP 信息\n"
            for k in ['ip', 'hostname', 'org', 'city', 'region', 'country', 'loc', 'asn']:
                if k in data:
                    result += f"{k}: {data[k]}\n"
            return result
    except Exception as e:
        return f"## IP 信息\n[!] 查询失败：{e}\n"
    return "## IP 信息\n[!] 未获取到有效数据。\n"


def passive_whois(domain):
    print("[*] 正在查询 Whois 信息...")
    try:
        info = whois.whois(domain)
        result = "## Whois\n"
        if isinstance(info, dict):
            for k, v in info.items():
                result += f"{k}: {v}\n"
        else:
            result += str(info)
        return result
    except Exception as e:
        return f"## Whois\n[!] Whois 查询失败：{e}\n"


def subdomain_enum(domain):
    print("[*] 正在执行子域名枚举（OneForAll）...")
    try:
        subprocess.run([
            "python3", "OneForAll/oneforall.py", "run", "--target", domain,
            "--brute", "False", "--format", "json", "--path", REPORT_DIR
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        output_path = os.path.join(REPORT_DIR, f"{domain}.json")
        if os.path.exists(output_path):
            result = "## 子域名\n"
            with open(output_path, 'r') as f:
                data = json.load(f)
                for item in data[:10]:
                    result += f"- {item.get('subdomain')}\n"
            return result
        return f"## 子域名\n[!] 未生成输出文件\n"
    except Exception as e:
        return f"## 子域名\n[!] 子域名枚举失败：{e}\n"


def nmap_scan(ip):
    print("[*] 正在执行端口扫描（nmap）...")
    try:
        scanner = nmap.PortScanner()
        scanner.scan(ip, arguments='-Pn -T4 -p 1-1000')
        output = "## 端口扫描\n"
        for host in scanner.all_hosts():
            output += f"[+] 主机: {host}\n"
            for proto in scanner[host].all_protocols():
                for port in scanner[host][proto]:
                    service = scanner[host][proto][port]['name']
                    output += f"    - {proto.upper()} 端口 {port}: {service}\n"
        return output
    except Exception as e:
        return f"## 端口扫描\n[!] nmap 扫描失败：{e}\n"



def https_port_scan(ip):
    print("[*] 正在检测常见 HTTPS 端口...")
    ports = [443, 8443, 9443]
    open_ports = []
    for port in ports:
        try:
            s = socket.create_connection((ip, port), timeout=3)
            s.close()
            open_ports.append(port)
        except:
            continue
    return f"## HTTPS端口探测\n[+] 支持 HTTPS 的端口：{open_ports}\n"


def nuclei_scan(target):
    choice = input("[?] 是否使用 nuclei 进行漏洞扫描？(y/n): ").strip().lower()
    if choice != 'y':
        return ""
    print("[*] 正在执行漏洞探测（nuclei）...")
    try:
        if not target.startswith("http"):
            target = f"http://{target}"
        cmd = f"nuclei -u {target} -severity low,medium,high,critical -tags cve,default,exposure,misconfig -timeout 10 -rate-limit 50"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        output = result.stdout.strip()
        return f"## 漏洞探测（Nuclei）\n{output if output else '[!] 未发现漏洞。'}\n"
    except Exception as e:
        return f"## 漏洞探测（Nuclei）\n[!] nuclei 扫描失败：{e}\n"


def xray_scan(target):
    choice = input("[?] 是否使用 Xray 执行漏洞扫描？(y/n): ").strip().lower()
    choice = ''
    if choice != 'y':
        return ""
    print("[*] 正在运行 xray 扫描...")
    try:
        cmd = f"xray webscan --url http://{target} --html-output {REPORT_DIR}/{target}_xray.html"
        subprocess.run(cmd, shell=True)
        return f"## Xray\n[+] Xray 扫描报告已生成: {target}_xray.html\n"
    except Exception as e:
        return f"## Xray\n[!] 扫描失败：{e}\n"


def httpx_fingerprint(target):
    print("[*] 正在识别网站指纹信息（httpx）...")
    try:
        cmd = f"httpx -u {target} -status-code -title -tech-detect -cdn"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return f"## 指纹识别\n{result.stdout.strip()}\n"
    except Exception as e:
        return f"## 指纹识别\n[!] 指纹识别失败：{e}\n"


def scan_target(target):
    print(f"\n====== 🎯 开始扫描 {target} ======")
    ip = get_ip(target if not target.startswith("http") else urlparse(target).hostname)
    if isinstance(ip, str) and ip.startswith("[!]"):
        return f"# 扫描报告 - {target}\n{ip}\n"

    content = f"# 扫描报告 - {target}\n生成时间：{datetime.datetime.now()}\n\n"
    results = {}

    with ThreadPoolExecutor(max_workers=6) as executor:
        future_map = {
            executor.submit(ipinfo_lookup, ip): "ipinfo",
            executor.submit(passive_whois, target): "whois",
            executor.submit(subdomain_enum, target): "subdomain",
            executor.submit(nmap_scan, ip): "nmap",
            executor.submit(https_port_scan, ip): "https",
            executor.submit(httpx_fingerprint, target): "fingerprint",
        }
        for future in as_completed(future_map):
            key = future_map[future]
            print(f"[+] {key} 扫描完成")
            try:
                results[key] = future.result()
            except Exception as e:
                results[key] = f"## {key}\n[!] 异常：{e}\n"

    results["nuclei"] = nuclei_scan(target)
    results["xray"] = xray_scan(target)

    for section in ["ipinfo", "whois", "subdomain", "nmap", "https", "nuclei", "xray", "fingerprint"]:
        content += "\n" + results.get(section, f"## {section}\n[!] 无结果\n")

    report_path = os.path.join(REPORT_DIR, f"{target}_report.md")
    with open(report_path, "w") as f:
        f.write(content)
    print(f"[✔] 报告已保存至: {report_path}")
    return content


def run_batch(targets):
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(scan_target, t.strip()) for t in targets if t.strip()]
        time.sleep(1)
        for future in as_completed(futures):
            _ = future.result()


if __name__ == '__main__':
    if len(sys.argv) == 2 and os.path.exists(sys.argv[1]):
        with open(sys.argv[1]) as f:
            targets = f.readlines()
        run_batch(targets)
    else:
        target = input("请输入 IP 或域名: ").strip()
        scan_target(target)
