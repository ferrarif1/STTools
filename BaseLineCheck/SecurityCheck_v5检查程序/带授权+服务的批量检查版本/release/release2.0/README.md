# 🛡️ SecurityCheck - 授权验证与基线检查工具

> 一款集成了授权验证与基线检查的自动化安全工具，支持RSA数字签名验证和结果自动上传

## 📋 目录

- [简介](#简介)
- [功能特性](#功能特性)
- [文件说明](#文件说明)
- [使用方法](#使用方法)
- [授权逻辑](#授权逻辑)
- [打包说明](#打包说明)
- [注意事项](#注意事项)

## 🎯 简介

SecurityCheck 是一款集成了**授权验证**与**基线检查**的自动化安全工具。

### ✨ 主要特性

- 🖥️ **多系统支持** - 支持 Win7 / Win8 / Win10 / Win11（基于 WMI 获取网卡信息，兼容老系统）
- 🔐 **安全授权** - 采用 RSA 数字签名验证授权文件，防止伪造篡改
- 🔄 **自动化执行** - 授权通过后，自动执行基线检查，并将结果上传至指定服务端
- 📊 **结果管理** - 支持失败重试和结果缓存机制

## 📂 文件说明

### 普通用户文件

| 文件名 | 说明 | 分发对象 |
|--------|------|----------|
| `SecurityCheck.ps1` / `SecurityCheck.exe` | 主程序脚本或打包后的可执行文件 | 所有用户 |
| `license.json` | 授权文件（由本工具生成），包含授权网段、到期日及签名 | 所有用户 |
| `config.json` | 客户端配置文件 | 所有用户 |

### 管理员文件

| 文件名 | 说明 | 分发对象 |
|--------|------|----------|
| `private_key.xml` | 管理员专用的私钥文件，用于生成合法授权 | **仅管理员** ⚠️ |

### 配置文件示例

**config.json**:
```json
{
  "uploadUrl": "http://10.136.72.59:8000/log",
  "failCache": "check_fail.json",
  "scriptPath": "check5.ps1"
}
```

## 🚀 使用方法

### 1. 首次运行 / 授权过期

当检测不到有效授权时，程序会自动进入**授权模式**：

1. **自动加载私钥** - 自动加载同目录下的 `private_key.xml`
2. **输入授权网段** - 支持以下格式：
   - `192.168.1.0/24` - 标准CIDR格式
   - `192.168.1.100` - 自动补 `/24`
   - `0.0.0.0` - 自动转换为 `0.0.0.0/0`（全网段授权）
3. **设置到期日期** - 格式：`YYYY-MM-DD`
4. **生成授权文件** - 程序使用私钥签发授权，生成新的 `license.json`

完成后，程序会立即校验该授权并进入基线检查流程。

### 2. 正常运行

**PowerShell 脚本方式**:
```powershell
powershell -ExecutionPolicy Bypass -File .\SecurityCheck.ps1
```

**EXE 可执行文件方式**:
```cmd
.\SecurityCheck.exe
```

### 3. 运行流程

1. **授权验证** - 程序读取并校验 `license.json`：
   - ✅ 验证签名是否有效
   - ✅ 检查到期日是否未过期
   - ✅ 检查本机任一网卡 IP 是否在授权网段内

2. **基线检查** - 校验通过后执行基线检查

3. **结果上传** - 将检查结果发送到 `config.json` 中的 `uploadUrl`（或默认值）

4. **失败重试** - 如果上传失败，会缓存到 `failCache` 文件，下次运行时自动补传

## 🔑 授权逻辑

### 授权文件结构

**license.json** 示例：
```json
{
  "Data": {
    "Expire": "2025-12-31",
    "AllowedSubnets": ["192.168.0.0/16"],
    "IssuedAt": "2025-08-21T12:00:00Z"
  },
  "Signature": "Base64签名字符串"
}
```

### 校验规则

授权验证需要满足以下**所有条件**：

- ✅ **时间验证** - 当前日期 ≤ Expire
- ✅ **网络验证** - 当前任一网卡 IP 属于 AllowedSubnets
- ✅ **签名验证** - 签名验证通过（RSA 公钥校验）

满足以上条件即视为授权有效。

## ⚙️ 打包说明

### 打包为 EXE

推荐使用 **PS2EXE** 工具进行打包：

```powershell
# 安装 PS2EXE
Install-Module -Name PS2EXE -Force

# 打包脚本
ps2exe .\SecurityCheck.ps1 .\SecurityCheck.exe
```

### 打包选项

```powershell
# 带图标打包
ps2exe .\SecurityCheck.ps1 .\SecurityCheck.exe -IconFile .\icon.ico

# 无控制台窗口打包
ps2exe .\SecurityCheck.ps1 .\SecurityCheck.exe -NoConsole

# 管理员权限打包
ps2exe .\SecurityCheck.ps1 .\SecurityCheck.exe -RequireAdmin
```

## ⚠️ 注意事项

### 文件分发

**普通用户分发包**：
- ✅ `SecurityCheck.exe`（或 `.ps1` 脚本）
- ✅ `license.json`（已签发）
- ✅ `config.json`（可选）

**管理员专用**：
- 🔒 `private_key.xml` - **严禁分发给普通用户**

### 系统要求

- **PowerShell** ≥ v3.0（Win7 需安装补丁）
- **Windows 系统** - Win7 / Win8 / Win10 / Win11
- **网络连接** - 用于结果上传

### 安全建议

1. **私钥保护** - `private_key.xml` 文件必须严格保密
2. **定期更新** - 建议定期更新授权文件
3. **网络隔离** - 在安全网络环境中使用
4. **权限控制** - 确保只有授权用户能够运行程序

## 📞 技术支持

如有问题或建议，请联系：

- **技术支持**: [联系邮箱]
- **问题反馈**: [GitHub Issues]
- **文档更新**: [项目地址]

---

⭐ 如果这个工具对您有帮助，请给我们一个星标！
