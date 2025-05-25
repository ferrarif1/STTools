# 🛡️ Scan Tool 使用说明

本工具是一个集成化的信息收集与漏洞探测脚本，支持对 IP 或域名进行全面的安全扫描，输出结构化的 Markdown 报告。

## 📦 功能模块

| 模块名         | 说明                                                                 |
|----------------|----------------------------------------------------------------------|
| `IP归属信息`    | 查询目标 IP 的归属地、组织等基础信息（通过 [ipinfo.io](https://ipinfo.io)） |
| `Whois`        | 查询域名的注册人、组织、邮箱等注册信息                                |
| `子域名枚举`    | 使用 OneForAll 工具对目标进行被动子域名枚举                             |
| `端口扫描`      | 通过 nmap 检测目标常见端口开放情况                                     |
| `HTTPS端口探测`| 检测 443/8443/9443 等常见 HTTPS 端口是否开放                          |
| `目录扫描（可选）`      | 通过 dirsearch 枚举目录和路径                                   |
| `漏洞扫描-nuclei`| 使用 nuclei 对站点进行漏洞扫描，支持 CVE、弱配置等                   |
| `指纹识别-httpx`| 网站指纹识别，提取标题、技术栈、CDN 信息等                            |
| `Xray 扫描（可选）` | 通过 Xray 进行漏洞探测并生成 HTML 报告（需提前下载好）             |
| `Naabu 扫描（可选）`| 快速 TCP 端口扫描工具，适合高并发/范围探测                        |

---

## 🧰 安装依赖

请确保安装以下依赖：

- Python 包：`pip install requests nmap whois`
- 工具包：
  - [`nmap`](https://nmap.org/)
  - [`httpx`](https://github.com/projectdiscovery/httpx)
  - [`nuclei`](https://github.com/projectdiscovery/nuclei)
  - [`OneForAll`](https://github.com/shmilylty/OneForAll)
  - [`dirsearch`](https://github.com/maurosoria/dirsearch)
  - （可选）[`xray`](https://github.com/chaitin/xray)
  - （可选）[`naabu`](https://github.com/projectdiscovery/naabu)

建议将这些工具放入系统 PATH 中。

---

## 🚀 使用方法

### 扫描单个目标

```bash
python3 scan_tool.py
# 然后按提示输入 IP 或域名，例如：
# 请输入 IP 或域名: example.com
```

### 批量扫描多个目标

准备一个文本文件，例如 `targets.txt`：

```
example.com
1.1.1.1
test.site
```

执行：

```bash
python3 scan_tool.py targets.txt
```

---

## 📄 报告输出

所有报告以 Markdown 形式保存在 `scan_reports/` 目录中，命名规则如下：

```
scan_reports/
├── example.com_report.md
├── 1.1.1.1_report.md
└── ...
```

其中如使用了 Xray，还会有：

```
example.com_xray.html
```

---

## ⚙️ 常见问题

- 若出现 `nmap not found` 等错误，需安装并配置环境变量
- 推荐使用最新版的 `httpx`, `nuclei`, `xray` 以获得最佳支持
- OneForAll 枚举子域失败，请检查是否初始化（需首次执行 OneForAll/setup/setup.py）

---

## 📎 特别说明

- 本脚本支持并发扫描多个目标、并发模块检测
- 目录扫描（dirsearch）、Xray、Naabu 为交互确认式，避免误触发重任务
- 脚本在 Mac 上测试通过，建议配合 Homebrew 安装工具组件