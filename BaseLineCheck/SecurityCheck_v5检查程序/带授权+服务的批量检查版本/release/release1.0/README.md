### ✅ 使用说明

---

## 📄 1. 首次使用

### 1.1 复制文件到 C 盘根目录（或其他目录）

请将以下文件复制到 **C:\** 根目录下：

```plaintext
1. 复制 SecurityCheck_v5.exe 到 C:\
2. 复制 config.json 到 C:\
```

### 1.2 编辑 config.json

主要需设置 **uploadUrl**（示例配置）：

```json
{
    "scriptPath": "C:\\SecurityCheck_v5.exe",
    "uploadUrl": "http://Your_server_ip:8000/log",
    "failCache": "C:\\check_fail.json"
}
```

---

## 📄 2. 授权所在网段

- **运行 SecurityCheck_v5.exe 执行安全基线检查**
- **首次授权**  
  初次启动程序时，系统会提示输入授权密钥，程序自动识别以太网适配器的网段，并记录到 `ip_set_config.json`（该文件经过加密），只有授权网段内的计算机才能进行安全检查。示例配置如下：

  ```json
  {
      "ipset": "{
          \"ipList\": [
              {
                  \"subnet\": \"172.16.1.0/26\",
                  \"addedDate\": \"2025-03-31\",
                  \"expiryDate\": \"2026-03-31\"
              }
          ]}",
      "Timestamp": "2025-03-31T09:46:01",
      "Content": "wW059cCsXY3KVByipNqssT4xCQ3tpRkj4/tIiOEpzLWGVrTnxOX+AP6/xXFd/ixkl1Rog3+WDBJn8MItqSlaQ0N5hTaULHInv0cn1e7YoM2EBEpvXT+n8Qhs/25Upk2WqtvglEsxfIla3EhrBrC9TUO4RRQHdp3nDzp1XkictygKFBoA5UBOqZXlNhXRm+tVhHADl8YeTOUcpFL9NdGW+4n28l13uMtdBxf42b1P1WBVbCkJ4XP648IAOpfjhEIssb1TeDOmNM188KOqvMSNU+C1dIBwlbSsysrVZ/glmu1O8yUna5Lw5COscpuYz2v6SI9ZpXVlN42phEkTpBz6Kea9m7lp2LLkYiO92sbzpKI="
  }
  ```

- **后续运行**  
  程序启动后会自动检测当前网段是否在授权范围内，如果被授权则继续执行，否则需重新输入密钥进行授权。

---

## 📚 3. 文件结构说明

- **SecurityCheck_v5.exe**  
  主程序（打包后的执行文件）

- **ip_set_config.json**  
  存储已授权网段的加密配置文件（程序自动生成）

- **config.json**  
  配置文件（包含脚本路径、上传 URL 等配置信息）

---

## 🔍 4. 检查项目说明

程序执行时将进行以下检查项目：

1. **FTP 服务与传输功能检查**
2. **网卡信息检查**
3. **高危端口状态检测**  
   检查端口：22, 23, 135, 137, 138, 139, 445, 455, 3389, 4899
4. **IPv6 禁用状态检查**
5. **高危漏洞修复检查**  
   检查 Windows 更新情况
6. **密码策略检查**
7. **Guest 用户状态检查**
8. **U盘自动播放功能检查**
9. **Google 浏览器版本检测**
10. **锁屏策略检查**

---

## 📄 5. 检查结果说明

检查完成后，检查结果将以 JSON 格式保存，具体内容包括：

- **Item**：检查项目名称
- **Issue**：检查发现的问题或状态
- **Suggestion**：修复建议

结果呈现方式：

1. 在控制台显示详细检查信息
2. 上传到配置的服务器（通过 `config.json` 中的 `uploadUrl`）
3. 如果上传失败，则保存到本地缓存文件 `check_fail.json`

---

## 🛠 7. 安装依赖

### 7.1 客户端依赖

- **操作系统及 .NET Framework**  
  - **Win7、Win8**：若缺少 .NET Framework，请离线安装 .NET Framework（例如：dotNetFx35）。
  - **Win7**：离线安装 `Win7AndW2K8R2-KB3191566-x64.msu`。
  - **Win8**：离线安装 `Win8.1AndW2K12R2-KB3191564-x64.msu`。

### 7.2 服务端依赖

服务端需要具备 Python 环境及以下 Python 库依赖：

- **Python 安装**  
  离线安装 Python 3.11。请先在 [Python 官网](https://www.python.org/downloads/) 或内网一粒云02账户下载对应平台的 Python 3.11 离线安装包，然后拷贝到离线机器后进行安装。

- **Python 库依赖说明**  
  - **openpyxl** 及其依赖：  
    - 还需要依赖 `et_xmlfile` 和 `jdcal`
  - **pandas** 依赖：  
    - 除了自身外，还依赖 `numpy`、`python-dateutil` 和 `pytz`
  - **chardet**：  
    - 无额外依赖

---

### 离线安装步骤（服务端）

#### 1. 联网环境下下载所有依赖包

在联网环境下，创建以下两个文件夹以保存离线安装包：

- **offline_pip**：存放 `pip`、`setuptools`、`wheel` 以及 `openpyxl` 及其依赖
- **packages**：存放 `pandas`、`chardet` 以及 pandas 的其它依赖（`numpy`、`python-dateutil`、`pytz`）

执行以下命令下载包（或从内网一粒云02账户直接下载）：

**(1) 下载 pip、setuptools、wheel 及 openpyxl 相关包：**

```bash
pip download pip setuptools wheel -d ./offline_pip --no-binary :all:
pip download openpyxl et_xmlfile jdcal -d ./offline_pip
```

**(2) 下载 pandas、chardet 及其所有依赖：**

```bash
pip download pandas chardet numpy python-dateutil pytz -d ./packages
```

#### 2. 离线环境安装步骤

将上述下载的两个文件夹及 Python 3.11 安装包一起拷贝到离线机器上，然后依次执行以下命令：

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
