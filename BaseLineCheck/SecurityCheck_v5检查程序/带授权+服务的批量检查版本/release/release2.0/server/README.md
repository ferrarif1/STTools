# 🛡️ Security Check 服务器 - 内网环境完整解决方案

> 专为内网环境设计的Security Check日志收集服务器，支持离线安装、任务计划程序部署和自动重启监控

[![Python](https://img.shields.io/badge/python-3.7+-blue.svg)](https://www.python.org/)
[![Windows](https://img.shields.io/badge/Windows-7%2B-green.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 📋 目录

- [项目概述](#项目概述)
- [功能特性](#功能特性)
- [文件结构](#文件结构)
- [快速开始](#快速开始)
- [离线安装](#离线安装)
- [详细使用](#详细使用)
- [监控和维护](#监控和维护)
- [故障排除](#故障排除)
- [技术架构](#技术架构)

## 🎯 项目概述

Security Check基线检查工具的服务端，采用任务计划程序方案，支持离线安装，无需任何外部依赖，确保在内网环境中稳定运行。

### ✨ 主要特性

- 🖥️ **系统集成** - 使用Windows自带任务计划程序
- 🔄 **自动重启** - 掉线时自动重启，确保高可用性
- 📊 **健康监控** - 实时健康检查和状态监控
- 📝 **详细日志** - 完整的操作日志和错误记录
- 🚀 **开机自启** - 系统启动时自动运行
- 🛡️ **权限管理** - 支持SYSTEM权限运行
- 📦 **离线安装** - 支持完全离线环境部署
- 🔧 **便捷管理** - 提供批处理脚本简化操作

## 📁 文件结构

```
server/
├── README.md                             # 完整技术文档
├── server_enhanced.py                    # 增强版服务器（核心）
├── install_task_scheduler_simple.py      # 任务计划安装脚本
├── auto_restart_monitor.py               # 自动重启监控器
├── download_packages.py                  # 包下载脚本（有网络时使用）
├── install_dependencies.py               # 离线安装脚本
├── start_server.bat                      # 一键启动脚本
├── packages/                             # 离线包目录
│   ├── requests-2.32.5-py3-none-any.whl
│   ├── pandas-2.2.3-cp311-cp311-win_amd64.whl
│   ├── chardet-5.2.0-py3-none-any.whl
│   ├── openpyxl-3.1.5-py2.py3-none-any.whl
│   └── ... (其他依赖包)
├── scripts/                              # 批处理脚本目录
│   ├── quick_start.bat                   # 快速启动脚本
│   ├── start_task.bat                    # 启动任务脚本
│   ├── stop_task.bat                     # 停止任务脚本
│   ├── restart_task.bat                  # 重启任务脚本
│   └── check_task_status.bat             # 检查状态脚本
├── logs/                                 # 日志目录（运行时生成）
│   ├── server_*.log                      # 服务器日志
│   ├── task_scheduler_simple_*.log       # 任务安装日志
│   └── auto_restart_*.log                # 监控器日志
└── Monitor/                              # 监控数据目录（运行时生成）
    ├── summary.xlsx                      # 汇总数据
    └── *.txt                             # 各IP的日志文件
```

## 🚀 快速开始

### 环境要求

- **操作系统**: Windows 7/8/10/11
- **Python**: 3.7+
- **权限**: 管理员权限（用于安装任务计划）

### 安装步骤

#### 1. 离线安装依赖包

```bash
# 运行离线安装脚本
python install_dependencies.py
```

#### 2. 安装任务计划

```bash
# 以管理员身份运行命令提示符
python install_task_scheduler_simple.py install
```

#### 3. 启动服务器

```bash
# 一键启动（推荐）
start_server.bat

# 使用批处理脚本快速启动
scripts\quick_start.bat

# 或者手动启动
python install_task_scheduler_simple.py start
```

#### 4. 启动自动重启监控

```bash
# 启动自动重启监控器
python auto_restart_monitor.py
```

## 📦 离线安装

### 包下载（在有网络的环境中）

如果您需要更新依赖包，可以在有网络的环境中运行：

```bash
# 下载最新的依赖包
python download_packages.py
```

这将下载以下包到 `packages/` 目录：
- **requests** - HTTP请求库
- **pandas** - 数据处理库
- **chardet** - 编码检测库
- **openpyxl** - Excel文件处理库
- **numpy** - 数值计算库（pandas依赖）
- **其他依赖包**

### 离线安装（在内网环境中）

```bash
# 运行离线安装脚本
python install_dependencies.py
```

脚本会自动：
- 检查Python版本
- 检查已安装的包
- 从 `packages/` 目录安装缺失的包
- 验证安装结果

## 🛠️ 详细使用

### 批处理脚本管理

我们提供了便捷的批处理脚本，简化日常操作：

```bash
# 快速启动（推荐）
scripts\quick_start.bat

# 启动任务
scripts\start_task.bat

# 停止任务
scripts\stop_task.bat

# 重启任务
scripts\restart_task.bat

# 检查状态
scripts\check_task_status.bat
```

### Python脚本管理

```bash
# 安装任务计划
python install_task_scheduler_simple.py install

# 启动任务
python install_task_scheduler_simple.py start

# 停止任务
python install_task_scheduler_simple.py stop

# 重启任务
python install_task_scheduler_simple.py restart

# 检查状态
python install_task_scheduler_simple.py status

# 卸载任务
python install_task_scheduler_simple.py uninstall
```

### 服务器功能

#### 主页访问

```bash
# 访问主页
http://localhost:8000
# 或
http://localhost:8000/index.html
```

主页提供以下功能：
- 📥 **客户端下载** - Security Check 客户端、Windows补丁包、服务端依赖包（可选）
- 📚 **文档访问** - 服务端和客户端技术文档
- 🔍 **服务器状态** - 实时健康检查和状态监控

#### 健康检查端点

```bash
# 检查服务器健康状态
curl http://localhost:8000/health

# 查看详细状态信息
curl http://localhost:8000/status
```

#### 日志收集端点

```bash
# 发送日志数据
curl -X POST http://localhost:8000/log \
  -H "Content-Type: application/json" \
  -d '{"message": "test log", "level": "info"}'
```

#### 文件下载端点

```bash
# 下载Security Check工具
curl -O http://localhost:8000/SecurityCheck_v5

# 下载Windows 7/8补丁包
curl -O http://localhost:8000/msu.zip

# 下载服务端依赖包（可选）
curl -O http://localhost:8000/server.zip

# 访问服务端文档
curl http://localhost:8000/README-Server.html

# 访问客户端文档
curl http://localhost:8000/README-Client.html
```

## 🔄 监控和维护

### 自动重启监控

自动重启监控器提供以下功能：

- **定期检查** - 每30秒检查一次服务器状态
- **自动重启** - 掉线时自动重启任务计划
- **重试机制** - 最多重试3次，避免无限重启
- **日志记录** - 详细记录所有操作

#### 配置参数

可以在 `auto_restart_monitor.py` 中修改：

```python
CHECK_INTERVAL = 30      # 检查间隔（秒）
MAX_RESTART_ATTEMPTS = 3 # 最大重启尝试次数
```

### 日志管理

#### 查看日志

```bash
# 查看服务器日志
type logs\server_*.log

# 查看任务安装日志
type logs\task_scheduler_simple_*.log

# 查看监控器日志
type logs\auto_restart_*.log
```

#### 日志轮转

建议定期清理旧日志文件：

```bash
# 清理7天前的日志
forfiles /p logs /s /m *.log /d -7 /c "cmd /c del @path"
```

## 🔍 故障排除

### 常见问题

#### 1. 依赖包安装失败

**问题**: 提示缺少pandas、requests等包
**解决**: 运行离线安装脚本

```bash
python install_dependencies.py
```

#### 2. 任务安装失败

**问题**: 提示需要管理员权限
**解决**: 以管理员身份运行命令提示符

```bash
# 检查管理员权限
net session
```

#### 3. 服务器无法访问

**问题**: 无法访问 http://localhost:8000
**解决**: 检查端口占用和防火墙设置

```bash
# 检查端口占用
netstat -ano | findstr :8000

# 检查防火墙
netsh advfirewall firewall show rule name=all | findstr 8000
```

#### 4. 自动重启不工作

**问题**: 监控器无法重启服务器
**解决**: 检查任务计划状态

```bash
# 检查任务状态
scripts\check_task_status.bat

# 手动重启任务
scripts\restart_task.bat
```

#### 5. Excel写入失败

**问题**: 日志数据没有写入Excel文件
**解决**: 检查依赖包和权限

```bash
# 重新安装依赖包
python install_dependencies.py

# 检查Monitor目录权限
dir Monitor
```

### 性能优化

#### 内存优化

- 服务器内存占用约50-100MB
- 监控器内存占用约20-30MB
- 建议定期重启释放内存

#### 磁盘优化

- 定期清理日志文件
- 监控Excel文件大小
- 建议设置日志轮转

## 🏗️ 技术架构

### 系统架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   客户端应用    │    │   Security      │    │   任务计划      │
│                │───▶│   Check工具     │───▶│   程序          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   增强版服务器  │    │   自动重启      │
                       │   server_enhanced│    │   监控器        │
                       └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   日志存储      │    │   健康检查      │
                       │   Monitor/      │    │   /health       │
                       └─────────────────┘    └─────────────────┘
```

### 核心组件

#### 1. 增强版服务器 (`server_enhanced.py`)

- **HTTP服务器** - 基于Python内置http.server
- **健康检查** - `/health` 和 `/status` 端点
- **日志收集** - `/log` 端点接收客户端数据
- **文件服务** - 提供工具和补丁下载
- **Excel写入** - 支持并发安全的Excel数据写入
- **错误处理** - 完善的异常处理和日志记录

#### 2. 任务计划安装器 (`install_task_scheduler_simple.py`)

- **任务创建** - 使用schtasks创建系统任务
- **权限管理** - 设置SYSTEM权限运行
- **开机自启** - 配置系统启动时运行
- **状态管理** - 启动、停止、重启任务
- **批处理生成** - 自动生成管理脚本

#### 3. 自动重启监控器 (`auto_restart_monitor.py`)

- **健康检查** - 定期检查服务器状态
- **自动重启** - 掉线时自动重启任务
- **重试机制** - 限制重启次数避免无限循环
- **日志记录** - 详细记录监控活动

#### 4. 离线安装工具

- **包下载器** (`download_packages.py`) - 在有网络环境下载依赖包
- **离线安装器** (`install_dependencies.py`) - 在内网环境安装依赖包

#### 5. Web界面

- **主页** (`index.html`) - 美观的Web界面，提供文件下载和文档访问
- **实时状态** - 自动检查服务器健康状态
- **响应式设计** - 支持桌面和移动设备访问

### 数据流

```
客户端 → 服务器 → 日志文件 → Excel汇总
   ↓         ↓         ↓
健康检查 ← 监控器 ← 状态检查
```

## 📊 监控指标

### 服务器指标

- **运行时间** - 服务器启动后的运行时长
- **请求数量** - 接收到的HTTP请求数量
- **错误率** - 错误请求占总请求的比例
- **响应时间** - 平均响应时间

### 系统指标

- **内存使用** - 服务器进程内存占用
- **CPU使用** - 服务器进程CPU使用率
- **磁盘空间** - 日志文件占用空间
- **网络连接** - 活跃连接数量

## 🔒 安全考虑

### 访问控制

- 服务器监听所有网络接口 (0.0.0.0:8000)
- 建议配置防火墙限制访问IP
- 可以添加认证机制增强安全性

### 数据保护

- 日志数据存储在本地
- 建议定期备份重要数据
- 可以加密敏感日志信息

## 📈 扩展功能

### 可能的扩展

1. **Web管理界面** - 提供Web界面管理服务器
2. **数据库存储** - 使用数据库替代文件存储
3. **集群部署** - 支持多服务器集群
4. **API接口** - 提供RESTful API接口
5. **告警通知** - 支持邮件、短信告警

## 📞 技术支持

### 获取帮助

1. **查看日志** - 检查 `logs/` 目录下的日志文件
2. **健康检查** - 访问 `/health` 端点检查状态
3. **重启服务** - 使用重启命令恢复服务
4. **查看文档** - 参考本README文档

### 常见操作

```bash
# 完整重启流程
scripts\stop_task.bat
scripts\start_task.bat
python auto_restart_monitor.py

# 检查所有状态
scripts\check_task_status.bat
curl http://localhost:8000/health
```

### 依赖包信息

当前版本包含的依赖包：
- **requests** 2.32.5 - HTTP请求库
- **pandas** 2.2.3 - 数据处理库
- **chardet** 5.2.0 - 编码检测库
- **openpyxl** 3.1.5 - Excel文件处理库
- **numpy** 2.2.4 - 数值计算库
- **其他依赖包** - 详见packages目录

---

⭐ **Security Check 服务器 - 内网环境的最佳选择！**

> 简单、可靠、支持离线安装，专为内网环境设计的高可用日志收集服务器。 