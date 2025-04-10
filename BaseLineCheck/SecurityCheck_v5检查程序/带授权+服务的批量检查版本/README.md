### ✅ **使用说明：**

---

### 📄 **1. 首次使用**

1. **复制必要文件到目录（以C 盘根目录举例）**
   ```plaintext
   1. 复制 SecurityCheck_v5.exe 到 C:\
   2. 复制 config.json 到 C:\
   ```

2. **确认文件位置**
   - `C:\SecurityCheck_v5.exe`
   - `C:\config.json`

3. **编辑 config.json 内容 主要设置 uploadUrl**
   ```json
   {
       "scriptPath": "C:\\SecurityCheck_v5.exe",
       "uploadUrl": "http://Your_server_ip:8000/log",
       "failCache": "C:\\check_fail.json"
   }
   ```

### 📄 **2. 授权所在网段**
-  运行 `SecurityCheck_v5.exe` 进行安全基线检查：
- **首次授权：** 通过输入授权密钥，自动识别以太网适配器的网段，将该网段记录到 `ip_set_config.json` 并加密，只有被授权的网段才能执行安全检查。
  如下：
  ```json
  {
      "ipset":  "{
        \"ipList\":  [  
        {                   
        \"subnet\":  \"172.16.1.0/26\",                    
        \"addedDate\":  \"2025-03-31\",   
        \"expiryDate\": \"2026-03-31\"                    
        }       
       ]}",
      "Timestamp":  "2025-03-31T09:46:01",
      "Content":  "wW059cCsXY3KVByipNqssT4xCQ3tpRkj4/tIiOEpzLWGVrTnxOX+AP6/xXFd/ixkl1Rog3+WDBJn8MItqSlaQ0N5hTaULHInv0cn1e7YoM2EBEpvXT+n8Qhs/25Upk2WqtvglEsxfIla3EhrBrC9TUO4RRQHdp3nDzp1XkictygKFBoA5UBOqZXlNhXRm+tVhHADl8YeTOUcpFL9NdGW+4n28l13uMtdBxf42b1P1WBVbCkJ4XP648IAOpfjhEIssb1TeDOmNM188KOqvMSNU+C1dIBwlbSsysrVZ/glmu1O8yUna5Lw5COscpuYz2v6SI9ZpXVlN42phEkTpBz6Kea9m7lp2LLkYiO92sbzpKI="
  }
  ```

- **后续运行：** 自动检测当前网段是否被授权，已授权则继续执行，否则要求重新输入密钥进行授权。


---

### 📚 **3. 文件结构说明**
- `SecurityCheck_v5.exe` - 主程序（打包后的执行文件）
- `ip_set_config.json` - 存储已授权网段的加密配置文件（程序自动生成）
- `config.json` - 配置文件（包含脚本路径、上传 URL 等配置）

---

### 🔍 **4. 检查项目说明**
1. **FTP服务与传输功能检查**  
2. **网卡信息检查**  
3. **高危端口状态检测**  
   - 检查端口：22,23,135,137,138,139,445,455,3389,4899
4. **IPv6 禁用状态检查**  
5. **高危漏洞修复检查**  
   - Windows 更新情况  
6. **密码策略检查**  
7. **Guest 用户状态检查**  
8. **U盘自动播放功能检查**  
9. **Google 浏览器版本检测**  
10. **锁屏策略检查**  
---

### 📄 **5. 检查结果说明**

检查结果会以 JSON 格式保存，包含以下信息：
- Item：检查项目名称
- Issue：检查发现的问题或状态
- Suggestion：修复建议

检查完成后，结果会：
1. 在控制台显示详细信息
2. 上传到配置的服务器（通过 `config.json` 中的 `uploadUrl`）
3. 如果上传失败，保存到本地缓存文件（`check_fail.json`）

最终汇总至summary.xlsx
---

### 🤖 **6. Server 部署与运行说明**

### 部署环境准备

- **确认操作系统**：在同一网段内部署一台 PC 作为服务端，确保部署机器使用 Windows 10 或更高版本（其他操作系统也适用，但需安装相应 Python 环境）。
- **配置 Python 环境**：确保已安装 Python（建议 Python 3.11）以及所需依赖包（如 `pandas` 和 `chardet`），参考“7. 安装依赖”。

### 启动服务端

在部署服务端的 PC 上，进入 `server.py` 所在目录，打开命令行后执行以下命令：

```bash
python server.py
```

- 运行后，服务端将在 8000 端口启动，并自动创建 `Monitor` 目录。
- 接收到客户端发送的日志数据后，会根据客户端 IP 生成对应的文本文件（如 `192.168.1.5.txt`），同时将所有数据合并写入 `Monitor\summary.xlsx` 中以便汇总查看。


## 运行说明

- **客户端下载**：浏览器访问http://<server_ip>:8000/下载zip文件，包括SecuritySheck_v5.exe，config.json
- **客户端上传数据**：所有位于同一网段中的客户端程序（需自行编写或配置）运行时，将日志数据 POST 到服务端地址 `http://<server_ip>:8000/log`。
- **日志存储**：
  - 每个客户端的请求数据会追加写入对应的 `[客户端IP].txt` 中；
  - 汇总结果以 Excel 格式保存在 `summary.xlsx` 中，便于后续统计和分析。


### 🛠 **7. 安装依赖**

1. **客户端安装依赖**
   - win7、win8若缺少.net framework，离线安装.net framework：dotNetFx35  
   - win7 - 离线安装Win7AndW2K8R2-KB3191566-x64.msu   
   - win8 - 离线安装Win8.1AndW2K12R2-KB3191564-x64.msu  

1. **服务端安装依赖**
- **需要python环境及以下依赖：**  
- **openpyxl** 还需要依赖【et_xmlfile】和【jdcal】；  
- **pandas** 除了自身外，还依赖【numpy】、【python-dateutil】和【pytz】；  
- **chardet** 通常无额外依赖。  

### 1. 离线安装 Python 3.11

请先在 [Python 官网](https://www.python.org/downloads/) 或内网一粒云02账户下载对应平台的 Python 3.11 离线安装包，并拷贝到离线机器后进行安装。

---

### 2. 联网环境下下载所有依赖包

在联网环境下，先在目标目录下建立两个文件夹：  
- `offline_pip`（用于存放 pip、setuptools、wheel 以及 openpyxl 及其依赖）  
- `packages`（用于存放 pandas、chardet 以及 pandas 的其它依赖）

**(1) 下载 pip、setuptools、wheel 及 openpyxl 相关包，或从内网一粒云02账户直接下载：**

```bash
pip download pip setuptools wheel -d ./offline_pip --no-binary :all:
pip download openpyxl et_xmlfile jdcal -d ./offline_pip
```

**(2) 下载 pandas、chardet 及其所有依赖（numpy、python-dateutil、pytz）：**

```bash
pip download pandas chardet numpy python-dateutil pytz -d ./packages
```

---

### 3. 离线环境安装步骤

将上一步下载好的两个文件夹（`offline_pip` 和 `packages`）连同 Python 3.11 安装包，一同拷贝到离线机器。然后依次执行以下命令：

**(1) 安装 setuptools 和 wheel：**

```bash
python -m pip install --no-index --find-links=./offline_pip setuptools wheel
```

**(2) 安装 pip：**

```bash
python -m pip install --no-index --find-links=./offline_pip pip
```

**(3) 离线安装 openpyxl 及其依赖：**

```bash
python -m pip install --no-index --find-links=./offline_pip openpyxl et_xmlfile jdcal
```

**(4) 离线安装 pandas、chardet 及其依赖：**

```bash
pip install --no-index --find-links=./packages pandas chardet numpy python-dateutil pytz
```

