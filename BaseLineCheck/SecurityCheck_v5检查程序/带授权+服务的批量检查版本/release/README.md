### ✅ **使用说明：**

---

### 📄 **1. 首次使用**

1. **复制必要文件到 C 盘根目录**
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
- **安全检查：** 执行全面的安全基线检查，包括 FTP、网卡、端口、IPv6 等多个方面。

---

### 📚 **3. 文件结构说明**
- `SecurityCheck_v5.exe` - 主程序（打包后的执行文件）
- `ip_set_config.json` - 存储已授权网段的加密配置文件（程序自动生成）
- `config.json` - 配置文件（包含脚本路径、上传 URL 等配置）

---

### 🔍 **4. 检查项目说明**
1. **FTP服务与传输功能检查**
   - FTP服务状态
   - FTP客户端功能
   - FTP端口（21）监听状态
   - FTP防火墙规则

2. **网卡信息检查**
   - 网卡状态与配置
   - IP配置信息
   - 无线网卡状态

3. **高危端口状态检测**
   - 检查端口：22,23,135,137,138,139,445,455,3389,4899
   - 防火墙规则检查

4. **IPv6 禁用状态检查**
   - 注册表配置检查

5. **高危漏洞修复检查**
   - Windows 更新情况
   - 补丁安装状态

6. **密码策略检查**
   - 密码有效期
   - 密码复杂度要求

7. **Guest 用户状态检查**
   - 账户启用状态

8. **U盘自动播放功能检查**
   - 注册表配置检查

9. **Google 浏览器版本检测**
   - Chrome 版本检查
   - 更新建议

10. **锁屏策略检查**
    - 超时时间设置
    - 密码保护状态

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

---

### 🕒 **6. 定时任务功能**

为了定期自动执行安全检查，程序会创建一个定时任务。以下是相关说明：

- **任务名称:** `SecurityCheck_v5_Task`
- **触发器:** 每月 1 日和 15 日的 9:00 AM，带有 2 小时的随机延迟，以避免任务堆积。
- **操作:** 运行 `C:\SecurityCheck_v5.exe`
- **用户:** 系统账户 (`NT AUTHORITY\SYSTEM`)


#### **任务创建步骤**
1. 程序首次运行时会自动创建定时任务。
2. 如果任务已存在，则不会重复创建，不覆盖创建，需要手动删除。
3. 可以通过任务计划程序查看和管理该任务。

---

### 🛠 **7. 常见问题**

1. **任务创建失败**
   - 确保以管理员权限运行 `SecurityCheck_v5.exe`。
   - 检查任务计划程序是否有足够的权限创建任务。

2. **任务未按预期运行**
   - 确认任务计划程序中的任务是否启用。
   - 检查任务的触发器设置是否正确。

3. **任务日志**
   - 可以在任务计划程序中查看任务的历史记录和日志，以了解任务的执行情况。
