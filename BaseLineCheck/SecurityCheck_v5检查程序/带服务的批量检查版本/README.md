# 🛡️ Windows安全基线检查工具 🔍

[check5_Autherized.ps1授权版使用说明](https://github.com/ferrarif1/STTools/blob/main/BaseLineCheck/SecurityCheck_v5%E6%A3%80%E6%9F%A5%E7%A8%8B%E5%BA%8F/%E5%B8%A6%E6%9C%8D%E5%8A%A1%E7%9A%84%E6%89%B9%E9%87%8F%E6%A3%80%E6%9F%A5%E7%89%88%E6%9C%AC/READMEAUTHORIZED.md)

## 🌟 项目概述

Windows安全基线检查工具是一个综合性安全检查解决方案，用于检测同网段Windows系统的安全配置情况。该工具采用客户端-服务器架构：

- **🖥️ 服务器端**：收集、存储和汇总多台Windows客户端的安全检查结果
- **💻 客户端**：在Windows设备上执行安全基线检查，并将结果实时上报到中央服务器

## ✅ 系统要求

### 服务器端要求
- ⚙️ Python 3.6或更高版本
- 📊 pandas库（数据处理）
- 🔤 chardet库（编码检测）
- 🪟 Windows操作系统

### 客户端要求
- 🪟 Windows 7/8/10/11操作系统
- 📜 PowerShell 3.0或更高版本

## 🚀 快速开始

### 📡 服务器端设置

1. **安装Python环境**
   ```
   https://www.python.org/downloads/
   ```

2. **安装依赖库**
   ```
   pip install pandas chardet
   ```

3. **启动服务器**
   ```
   python server.py
   ```
   成功启动后将显示：`🟢 日志服务器已启动：http://localhost:8000/log`

### 💿 客户端编译与分发

1. **编译为EXE文件**
   ```powershell
   cd ./带服务的批量检查版本
   powershell -ExecutionPolicy ByPass -File ".\build.ps1"
   ```

2. **分发给用户**
   将编译好的EXE文件和config.json配置文件一起分发

3. **用户使用**
   用户只需双击EXE文件即可运行安全检查，无需其他设置

## ⚙️ 配置详解

### 服务器配置

服务器默认监听8000端口。需要修改时，编辑`server.py`文件：

```python
if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8000), LogHandler)  # 修改端口号
    print("日志服务器已启动：http://localhost:8000/log")
    server.serve_forever()
```

### 客户端配置

通过`config.json`文件进行配置：

```json
{
  "scriptPath": "C:\\SecurityCheck_v5.exe",
  "uploadUrl": "http://172.16.1.20:8000/log",
  "failCache": "C:\\check_fail.json"
}
```

| 参数 | 说明 |
|------|------|
| scriptPath | 客户端程序在本地的安装路径 |
| uploadUrl | 服务器URL (http://服务器IP:端口/log) |
| failCache | 上传失败时的本地缓存文件路径 |

## 🔍 检测功能

系统会全面检查以下安全配置项：

1. 🌐 **FTP服务与传输功能** - 检测是否存在不安全的FTP服务
2. 📡 **网卡信息与无线状态** - 识别潜在的网络安全问题
3. 🔌 **高危端口状态** - 检查常见高危端口是否被适当封锁
4. 🌍 **IPv6禁用状态** - 验证IPv6协议是否已禁用
5. 🔄 **系统更新情况** - 检查系统补丁是否及时更新
6. 🔑 **密码策略合规性** - 审查密码有效期等安全策略
7. 👤 **Guest用户状态** - 确认访客账户是否被禁用
8. 💾 **U盘自动播放功能** - 检测可移动媒体安全设置
9. 🌐 **Google Chrome版本** - 验证浏览器是否为最新版本
10. 🔒 **锁屏策略合规性** - 检查屏幕锁定时间设置

## 📊 数据存储

服务器自动汇总并存储所有检查结果：

- 📝 **详细日志**：`Monitor/客户端IP.txt`
- 📊 **数据汇总**：`Monitor/summary.xlsx`

## ❓ 常见问题解答

### 🔴 无法连接到服务器？
- ✅ 确认服务器IP和端口配置正确
- ✅ 检查防火墙是否允许端口8000的入站连接
- ✅ 验证客户端与服务器的网络连通性

### 🔤 中文显示乱码？
- ✅ 确保服务器已安装chardet库: `pip install chardet`
- ✅ 检查PowerShell脚本使用UTF-8编码保存

### 📊 如何查看报告？
检查结果会在三个位置显示:
1. 💻 客户端的命令行窗口（实时显示）
2. 📝 服务器上按IP组织的文本日志
3. 📊 服务器上的Excel汇总报表

### 🔄 上传失败后处理？
检查结果会自动缓存在本地。下次运行时，系统会尝试重新上传之前失败的数据。

## 🛠️ 开发与定制

要修改检查内容或扩展功能，您可以编辑以下文件：

- ✏️ `check5_win10-11.ps1`: 添加或修改检查功能
- 🔄 `check5.ps1`: 用于编译的主脚本
  ```powershell
  cd .\带服务的批量检查版本
  powershell -ExecutionPolicy ByPass -File ".\build.ps1"
  ```
- 🖥️ `server.py`: 服务器端数据处理逻辑

## 📋 更新日志

### v1.0.0 (2025-03-27)
- ✨ 首次发布
- 🔍 支持10项安全基线检查
- 🔄 实现客户端-服务器架构
- 📊 添加Excel报表汇总功能

---
📜 本工具用于企业内部安全基线检查，请在合法授权的情况下使用