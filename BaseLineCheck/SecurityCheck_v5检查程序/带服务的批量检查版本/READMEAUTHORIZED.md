### ✅ **使用说明：**

---

### 📄 **1. 目标回顾**
- **目标：** 运行 `check5_win10-11_updated.ps1` 时进行以下操作：
   - **首次授权：** 通过输入授权密钥，将当前网段记录到 `ip_set_config.json` 并加密，只有被授权的网段才能执行安全检查。
   - **后续运行：** 自动检测当前网段是否被授权，已授权则继续执行，否则要求重新输入密钥进行授权。

---

### 📚 **2. 文件结构说明**
- `check5_win10-11_updated.ps1` - 主 PowerShell 脚本
- `ip_set_config.json` - 存储已授权网段的加密配置文件，首次运行脚本时会自动创建

---

### ⚡️ **3. 第一次运行（授权网段）**
---

#### ✅ **Step 1：运行脚本**
- 以 **管理员权限** 运行 PowerShell：
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```
- 运行 `check5_win10-11_updated.ps1`：
```powershell
.\check5_win10-11_updated.ps1
```

---

#### ✅ **Step 2：输入授权密钥**
- **首次运行时：** 提示输入授权密钥。
```powershell
请输入授权密钥:
```
- 输入正确的密钥 `Hzdsz@2025#`（或已修改的密钥），密钥会进行验证：
   - 如果密钥正确 ✅ -> 记录当前网段到 `ip_set_config.json` 并加密
   - 如果密钥错误 ❌ -> 终止脚本运行
```powershell
授权成功，添加当前网段到授权列表。
```

---

#### ✅ **Step 3：授权完成**
- `ip_set_config.json` 文件在脚本目录下生成，已加密存储授权的网段信息。

---

### ⚡️ **4. 之后运行（已授权的网段自动识别）**
---

#### ✅ **Step 1：再次运行脚本**
- 重新运行 `check5_win10-11_updated.ps1` 时，自动检测当前网段。
- 如果当前网段已经授权 ✅：
```powershell
当前网段 (192.168.1.0/24) 已授权，开始执行安全检查。
```
- 如果当前网段未授权 ❌，会提示重新输入密钥进行授权：
```powershell
请输入授权密钥:
```
---

### 🔐 **5. 如何手动修改或添加授权的网段**
---

#### ✅ **Step 1：运行脚本**
- 运行 `check5_win10-11_updated.ps1` 并重新输入授权密钥：
```powershell
.\check5_win10-11_updated.ps1
```

#### ✅ **Step 2：重新授权新网段**
- 运行脚本时，在不同网段下重新运行脚本并输入授权密钥，系统会自动记录新的网段。
```powershell
授权成功，添加当前网段到授权列表。
```

#### ✅ **Step 3：检查授权配置**
- 授权的网段信息存储在 `ip_set_config.json` 中，已加密，防止手动修改。

---

### 📄 **6. 如何查看授权的网段**
---

#### ✅ **Step 1：解密查看 `ip_set_config.json`**
- 运行以下命令解密查看授权网段：
```powershell
$ipConfigPath = Join-Path $PSScriptRoot "ip_set_config.json"
$encryptedContent = Get-Content $ipConfigPath -Raw
$decryptedContent = Unprotect-ConfigContent $encryptedContent
$decryptedContent | ConvertFrom-Json
```
---

#### ✅ **Step 2：查看网段内容**
- 查看已授权的网段信息：
```json
{
  "ipList": [
    {
      "subnet": "192.168.1.0/24",
      "expiryDate": "2026-03-27",
      "addedDate": "2025-03-27"
    },
    {
      "subnet": "10.0.0.0/16",
      "expiryDate": "2026-03-27",
      "addedDate": "2025-03-27"
    }
  ]
}
```
---

### 🛑 **7. 解除授权或重新授权**
---

#### ✅ **Step 1：删除 `ip_set_config.json`**
- 如果需要重新授权或删除现有网段，可以手动删除 `ip_set_config.json` 文件：
```powershell
Remove-Item -Path ".\ip_set_config.json" -Force
```

#### ✅ **Step 2：重新运行脚本进行授权**
- 重新运行 `check5_win10-11_updated.ps1` 并输入密钥即可重新授权网段。

---

### ⚙️ **8. 高级配置和自定义**
---

✅ **修改授权密钥：**
- 修改 `$AuthorizedKey` 的内容：
```powershell
$AuthorizedKey = ConvertTo-SecureString "新密钥123" -AsPlainText -Force
```

✅ **修改加密密钥：**
- 修改 `$EncryptionKey` 的内容：
```powershell
$EncryptionKey = ConvertTo-SecureString "新的加密密钥" -AsPlainText -Force
```

✅ **修改签名密钥：**
- 修改 `$SignatureKey` 的内容：
```powershell
$SignatureKey = "新的签名密钥"
```

✅ **设置 IP 授权过期时间：**
- 修改 `Add-AuthorizedIP` 函数中设置的过期时间（默认为 1 年）：
```powershell
$expiryDate = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
```

✅ **更改 `EventLog` 记录设置：**
- 修改 `Write-EventLog` 记录的 `EventId`、`LogName` 和 `Source`。
---

### 🚀 **9. 常见问题排查**
---

#### ❗️ **Q1：出现授权失败？**
- 确认输入的授权密钥正确，并且未更改 `$AuthorizedKey` 的值。
- 检查 `ip_set_config.json` 是否已生成并加密。

#### ❗️ **Q2：无法读取配置文件？**
- 确认 `ip_set_config.json` 是否被系统或其他程序占用。
- 尝试删除 `ip_set_config.json` 并重新授权。

#### ❗️ **Q3：`EventLog` 无法记录？**
- 需要以 **管理员权限** 运行 PowerShell 来记录 `EventLog`。

---

### 🎯 **总结：**
- ✅ 第一次运行时需要输入授权密钥
- ✅ 后续运行自动检测当前网段是否已授权
- ✅ 可以随时删除 `ip_set_config.json` 重新授权
- ✅ 添加了加密、签名验证、时间戳验证、EventLog 记录等防篡改机制

如有问题或需要进一步优化，请随时联系我！🚀