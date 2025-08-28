import os
import re
import concurrent.futures

# 规则定义
rules = {
    "明文接口地址": r"https?://[^\s\"']+",
    "token/secret字段": r"(token|access_token|appId|appKey|secret|clientSecret)\s*[:=]\s*[\"'][^\"']{8,}[\"']",
    "eval等危险函数": r"\b(eval|Function|new Function)\b",
    "wx.request未使用https": r"wx\.request\s*\(\s*\{[^}]*url\s*:\s*[\"']http://",
    "调试模式开启": r'"debug"\s*:\s*true',
}

# 扫描单个文件
def scan_file(filepath):
    findings = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            for issue, pattern in rules.items():
                matches = re.findall(pattern, content)
                if matches:
                    findings.append((issue, matches, filepath))
    except Exception:
        pass
    return findings

# 扫描一个小程序的源码目录（__APP__）
def scan_app(app_src_path):
    app_findings = []
    for root, _, files in os.walk(app_src_path):
        for file in files:
            if file.endswith(('.js', '.json', '.wxml', '.wxss', '.ts')):
                full_path = os.path.join(root, file)
                app_findings.extend(scan_file(full_path))
    return app_findings

# 主函数：递归遍历 wx/ 下的小程序目录
def main(base_dir='wx'):
    all_findings = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        futures = []

        for app_name in os.listdir(base_dir):
            app_path = os.path.join(base_dir, app_name)
            if not os.path.isdir(app_path):
                continue

            for sub_version in os.listdir(app_path):
                sub_path = os.path.join(app_path, sub_version)
                if not os.path.isdir(sub_path):
                    continue

                app_dir = os.path.join(sub_path, "__APP__")
                if os.path.isdir(app_dir):
                    futures.append(executor.submit(scan_app, app_dir))

        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                all_findings.extend(result)

    # 打印报告
    for issue, matches, filepath in all_findings:
        print(f"\n[!] {issue} - 文件：{filepath}")
        for match in matches:
            print(f"    - {match}")

if __name__ == "__main__":
    main()
