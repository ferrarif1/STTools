# ✅ 使用说明

---

## 📄 1. 首次使用

### 1.1 下载检查工具压缩包

访问以下地址下载压缩包：  
```
http://<server_ip>:8000/SecurityCheck_v5
```  
压缩包内容包括：  
- **SecurityCheck_v5.exe**  
- **config.json**  
- **ip_set_config.json**

**Windows 7/8 用户**  
- 依赖补丁：
  - .NET Framework 安装包（dotNetFx35）一般系统已自带，如果没有，需要先安装dotNetFx35
  - 访问 `http://<server_ip>:8000/msu` 下载对应系统的补丁包：
    - Windows 7 补丁（Win7AndW2K8R2-KB3191566-x64.msu）
    - Windows 8 补丁（Win8.1AndW2K12R2-KB3191564-x64.msu）

**Windows 10/11 用户**  
  
  *（无需额外依赖）*

### 1.2 复制必要文件到目标目录

例如，将解压后的文件复制到 **C:\** 根目录中：

```plaintext
1. 将 SecurityCheck_v5.exe 复制到 C:\
2. 将 config.json 复制到 C:\
```


### 1.3 编辑 config.json 内容（主要设置 uploadUrl）

修改配置示例：

```json
{
    "scriptPath": "C:\\SecurityCheck_v5.exe",
    "uploadUrl": "http://Your_server_ip:8000/log",
    "failCache": "C:\\check_fail.json"
}
```

将 `"Your_server_ip"` 替换为实际服务器 IP，并根据实际路径修改 `"scriptPath"`。

- **运行：**  
程序启动后会自动检测当前网段是否被授权；若已授权则继续执行，否则需重新输入授权密钥。  
---

## 📄 2. 授权所在网段

- 启动 **SecurityCheck_v5.exe** 进行安全基线检查。
- **首次使用需授权：**  
  程序将提示您输入授权密钥，并自动检测当前以太网适配器所在的网段。检测到的网段会保存至加密文件 **ip_set_config.json** 中，仅允许授权网段继续安全检查，可同时授权多个网段。  
  示例配置如下：

  ```json
  {
      "ipset": "{
        \"ipList\": [
          {
            \"subnet\": \"172.16.1.0/26\",
            \"addedDate\": \"2025-03-31\",
            \"expiryDate\": \"2026-03-31\"
          }, {
            \"subnet\": \"10.136.72.0/255.255.255.0\",
            \"addedDate\": \"2025-04-03\",
            \"expiryDate\": \"2026-04-03\"
          }
        ]}",
      "Timestamp": "2025-03-31T09:46:01",
      "Content": "wW059cCsXY3KVByipNqssT4xCQ3tpRkj4/tIiOEpzLWGVrTnxOX+AP6/xXFd/ixkl1Rog3+WDBJn8MItqSlaQ0N5hTaULHInv0cn1e7YoM2EBEpvXT+n8Qhs/25Upk2WqtvglEsxfIla3EhrBrC9TUO4RRQHdp3nDzp1XkictygKFBoA5UBOqZXlNhXRm+tVhHADl8YeTOUcpFL9NdGW+4n28l13uMtdBxf42b1P1WBVbCkJ4XP648IAOpfjhEIssb1TeDOmNM188KOqvMSNU+C1dIBwlbSsysrVZ/glmu1O8yUna5Lw5COscpuYz2v6SI9ZpXVlN42phEkTpBz6Kea9m7lp2LLkYiO92sbzpKI="
  }
  ```


---

## 📚 3. 文件结构说明

- **SecurityCheck_v5.exe** – 主程序（根据版本分别为 SecurityCheck_v5.exe 或 SecurityCheck_v5.exe）
- **ip_set_config.json** – 存储已授权网段的加密配置文件（程序自动生成，如需重新授权直接删除此文件）
- **config.json** – 配置文件（包含脚本路径、上传 URL 等配置）

---

## 🔍 4. 检查项目说明

程序运行时将按以下项目进行检查：

1. **FTP 服务与传输功能检查**
2. **网卡信息检查**
3. **高危端口状态检测**  
   - 检查端口：22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899
4. **IPv6 禁用状态检查**
5. **高危漏洞修复检查**  
   - 包含 Windows 更新情况
6. **密码策略检查**
7. **Guest 用户状态检查**
8. **U 盘自动播放功能检查**
9. **Google 浏览器版本检测**
10. **锁屏策略检查**

---

## 📄 5. 检查结果说明

检查结果主要内容包括：

- **Item**：检查项目名称  
- **Issue**：检查发现的问题或状态  
- **Suggestion**：修复建议

检查完成后，结果将：
1. 在控制台显示详细信息；
2. 上传到配置的服务器（根据 config.json 中的 uploadUrl）；
3. 若上传失败，则保存到本地缓存文件 **check_fail.json**。

所有数据最终汇总至 `summary.xlsx` 文件中。

---

## 🤖 6. Server 部署与运行说明

### 6.1 部署环境准备

- **操作系统要求**：  
  在同一网段内部署一台 PC 作为服务端，建议使用 Windows 10 或更高版本（其它系统亦可，但请确保已安装相应的 Python 环境）。

- **Python 环境配置**：  
  请确认已安装 Python（建议 Python 3.11）及所需依赖包（如 pandas、chardet 等），具体参见后续"安装依赖"部分。

### 6.2 启动服务端

1. 在服务端 PC 上进入 **server.py** 所在目录；
2. 打开命令行并执行：
   ```bash
   python server.py
   ```
3. 服务端启动后，将监听 8000 端口并自动创建 `Monitor` 目录。  
   当客户端上传日志数据时，会以客户端 IP 为文件名保存日志（例如：`192.168.1.5.txt`），所有数据合并写入 `Monitor\summary.xlsx` 以便统计与分析。

### 6.3 服务端功能说明

服务端提供以下 HTTP 接口：
- `http://<server_ip>:8000/` - 主页面，提供工具下载入口
- `http://<server_ip>:8000/SecurityCheck_v5` - 下载检查工具压缩包
- `http://<server_ip>:8000/msu` - 下载 Windows 7/8 系统补丁包
- `http://<server_ip>:8000/readme` - 管理员使用说明页面
- `http://<server_ip>:8000/log` - 接收客户端上传的检查日志（POST 请求）

---

## 运行说明

- **客户端下载**：  
  被检查用户可通过浏览器访问 `http://<server_ip>:8000/` 下载包含工具和配置文件的 ZIP 压缩包。

- **客户端上传数据**：  
  客户端程序运行后，会将日志数据 POST 至服务器地址 `http://<server_ip>:8000/log`。

- **日志存储**：  
  - 每个客户端请求数据会追加保存至对应的 `[客户端IP].txt` 文件中；
  - 所有数据汇总后以 Excel 格式存储至 `summary.xlsx` 文件中。

---

## 🛠 7. 安装依赖

### 7.1 客户端安装依赖

- **Windows 7/8 用户**  
  如果系统缺少 .NET Framework，请先离线安装 .NET Framework（dotNetFx35）。  
  - Windows 7 用户需离线安装：`Win7AndW2K8R2-KB3191566-x64.msu`  
  - Windows 8 用户需离线安装：`Win8.1AndW2K12R2-KB3191564-x64.msu`

### 7.2 服务端安装依赖

服务端需安装 Python 环境及以下依赖包：
- **openpyxl**（依赖：et_xmlfile、jdcal）
- **pandas**（依赖：numpy、python-dateutil、pytz）
- **chardet**（通常无额外依赖）

---

## 离线安装说明

### 1. 离线安装 Python 3.11

请从 [Python 官网](https://www.python.org/downloads/) 或内网资源下载对应平台的 Python 3.11 离线安装包，并复制至离线机器后进行安装。

### 2. 联网环境下下载所有依赖包

建议在联网环境下创建以下两个文件夹：
- **offline_pip** – 用于存放 pip、setuptools、wheel 以及 openpyxl 及其依赖
- **packages** – 用于存放 pandas、chardet 及其依赖（numpy、python-dateutil、pytz）

执行下列命令下载相关包：

**(1) 下载 pip、setuptools、wheel：**
```bash
pip download pip setuptools wheel -d ./offline_pip --no-binary :all:
```

**(2) 下载 openpyxl et_xmlfile jdcal pandas chardet numpy python-dateutil pytz：**
```bash
pip download openpyxl et_xmlfile jdcal pandas chardet numpy python-dateutil pytz -d ./packages
```

### 3. 离线环境安装步骤

将上述两个文件夹及 Python 3.11 安装包复制至离线机器，按以下步骤依次执行：

1. **安装 setuptools 和 wheel：**
   ```bash
   python -m pip install --no-index --find-links=./offline_pip setuptools wheel
   ```
2. **安装 pip（python里可能已经自带）：**
   ```bash
   python -m pip install --no-index --find-links=./offline_pip pip
   ```
3. **离线安装 openpyxl 等包依赖：**
   ```bash
   pip install --no-index --find-links=./packages openpyxl et_xmlfile jdcal pandas chardet numpy python-dateutil pytz
   ```
