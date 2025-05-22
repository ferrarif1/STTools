### **README - Microsoft Update Catalog 补丁下载工具**  

[使用PowerShell批量安装补丁看此说明](https://github.com/ferrarif1/STTools/blob/main/KBDownloadandInstall/KBMultiInstallByPs1.md)  
[使用Installer.exe批量安装补丁看此说明](https://github.com/ferrarif1/STTools/blob/main/KBDownloadandInstall/KBMultiInstallByExe.md)
#### **📌 功能概述**  
本工具基于 **Selenium** 和 **Requests**，自动化从 **Microsoft Update Catalog** （Microsoft Update Catalog (catalog.update.microsoft.com) 上主要提供的是安全更新补丁，特别是：安全更新 (Security Updates)，关键补丁 (Critical Updates)，高危漏洞修复 (Security Vulnerability Fixes)）批量下载指定的 **KB 补丁**，并支持以下功能：  

- **📥 批量下载 KB 补丁**：支持从 Excel 读取多个 KB 号，自动搜索并下载对应补丁。  
- **📂 处理多个补丁版本**：当同一个 KB 号有多个补丁时，会下载所有可用文件，并按序号命名，避免覆盖。  
- **❌ 失败标记**：如果 KB 号没有可下载的文件，则创建 `failed_KBxxxx/` 目录进行标记，避免中断任务。  
- **📊 结果记录**：下载完成后，生成 **更新后的 Excel 文件**，记录每个 KB 号的下载状态（成功/失败）。  
- **🖥️ 兼容无 GUI 运行**：支持 **无头模式（Headless）** 运行，无需手动操作浏览器。  

---

## **🚀 使用方法**  

### **1️⃣ 依赖环境**  
请确保 Python 环境已安装以下依赖（如未安装，可使用 `pip` 安装）：  

```sh
pip3 install selenium pandas openpyxl requests
```

此外，需要 **Google Chrome 浏览器** 及对应的 **ChromeDriver**，可通过以下命令检查版本：  

```sh
google-chrome --version
chromedriver --version
```

若 `chromedriver` 未安装，可手动下载并放置到 `/usr/local/bin/chromedriver` 或相应路径。

---

### **2️⃣ 准备 Excel 文件**  
创建 Excel 文件（如 `kb_list.xlsx`），其中 **第一列** 填写 **KB 号**，可带 `KB` 前缀或直接写数字，例如：  

```
KB5017858
KB5034122
5034765
```

---

### **3️⃣ 运行脚本**  
将 `script.py` 运行，即可自动下载 KB 补丁：  

```sh
python script.py
```

---

## **📁 目录结构**  

```
patches/                     # 下载的 KB 补丁存放目录
│── KB5034765/               # 每个 KB 号单独存放
│   ├── KB5034765_1.msu      # 该 KB 号的第 1 个补丁
│   ├── KB5034765_2.msu      # 该 KB 号的第 2 个补丁（若有多个）
│── failed_KB5017858/        # 失败标记目录（如果未找到可下载文件）
│── failed_KB5034000/
updated_kb_list.xlsx         # 结果 Excel 文件，记录下载状态
```

---

## **📌 下载逻辑**  
1. 读取 Excel 里的 KB 号，并去掉 `KB` 前缀（如有）。  
2. 访问 Microsoft Update Catalog 进行搜索。  
3. 查找所有 **Download** 按钮，逐个点击下载。  
4. **如果有多个补丁**，依次下载，并按 `KBxxxx_1.msu`、`KBxxxx_2.msu` 命名。  
5. **如果找不到下载文件**，则创建 `failed_KBxxxx/` 目录标记失败。  
6. 所有 KB 处理完成后，生成 `updated_kb_list.xlsx` 记录每个 KB 号的下载状态。  

---

## **📊 结果示例（updated_kb_list.xlsx）**
| KB 编号  | 结果 |
|----------|------|
| 5034765  | 成功 |
| 5017858  | 失败 |
| 5034122  | 成功 |

**✅ "成功"：补丁下载完成，存放在 `patches/KBxxxx/` 目录中。**  
**❌ "失败"：该 KB 号无可下载补丁，已标记 `failed_KBxxxx/`。**  

---

## **🛠️ 可能遇到的问题**
### **1️⃣ chromedriver 版本不匹配**
- **错误信息**：
  ```
  selenium.common.exceptions.SessionNotCreatedException: Message: session not created: This version of ChromeDriver only supports Chrome version XX
  ```
- **解决方案**：  
  1. 检查 Chrome 版本：`google-chrome --version`  
  2. 下载 **对应版本** 的 `chromedriver` 并替换旧版本。
  3. chromedriver下载地址：https://googlechromelabs.github.io/chrome-for-testing/#stable

### **2️⃣ 无法下载 KB 补丁**
- **可能原因**：
  - Microsoft 更新目录没有该 KB 号的下载链接。
  - 网络连接问题导致请求失败。
- **解决方案**：
  - 确保 **网络正常**，可访问 `https://www.catalog.update.microsoft.com/`。
  - 检查 `failed_KBxxxx/` 目录确认失败 KB 号。

### **3️⃣ 下载文件过慢**
- **可能原因**：Microsoft 服务器响应慢，导致 `requests.get()` 超时。  
- **解决方案**：
  - 可在 `requests.get(download_link, stream=True)` 添加超时设置，如：
    ```python
    response = requests.get(download_link, stream=True, timeout=60)
    ```

---


![](https://github.com/ferrarif1/MyWorkNote/blob/main/Tools/KBDownload%26Install/%E8%BF%90%E8%A1%8C%E5%9B%BE.jpg)
