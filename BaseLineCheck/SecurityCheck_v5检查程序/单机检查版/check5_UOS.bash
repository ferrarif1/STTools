#!/bin/bash

# 设置输出颜色
function success() { echo -e "\e[32m✔ $1\e[0m"; }
function error() { echo -e "\e[31m✖ $1\e[0m"; }
function instruction() { echo -e "\e[33m修复建议：$1\e[0m"; }
function separator() { echo "--------"; }

echo "========== UOS 安全检查报告 =========="

# 1. FTP服务检查
echo -e "\n【1】FTP服务与传输功能检查："
ftp_status=$(systemctl is-active vsftpd 2>/dev/null)
if [[ "$ftp_status" == "active" ]]; then
    error "FTP 服务 (vsftpd) 正在运行。"
    instruction "建议执行 'sudo systemctl disable --now vsftpd' 禁用FTP服务。"
else
    success "FTP服务未运行或未安装。"
fi

if lsof -i:21 >/dev/null 2>&1; then
    error "检测到端口21 (FTP) 被监听。"
    instruction "建议关闭FTP相关服务或应用。"
else
    success "端口21未被监听。"
fi
separator

# 2. 网卡信息检查
echo -e "\n【2】网卡信息检查："
interfaces=$(ip -o link show | awk -F': ' '{print $2}')
if [[ -n "$interfaces" ]]; then
    echo "检测到以下启用的网卡："
    ip addr show | grep "state UP" | awk '{print $2}'
else
    error "未检测到启用的网卡。"
fi

if nmcli device | grep -i wifi | grep -i connected >/dev/null 2>&1; then
    error "检测到启用的无线网卡。"
    instruction "建议关闭无线网卡（使用 'nmcli radio wifi off'）。"
else
    success "无线网卡已禁用或不存在。"
fi
separator

# 3. 高危端口检测
echo -e "\n【3】高危端口检测："
ports=(22 23 135 137 138 139 445 455 3389 4899)
for port in "${ports[@]}"; do
    if ss -tuln | grep ":$port " >/dev/null 2>&1; then
        error "端口 $port 正在监听。"
        instruction "建议使用防火墙封禁或关闭相关服务。"
    else
        success "端口 $port 未监听。"
    fi
done
separator

# 4. IPv6 禁用状态
echo -e "\n【4】IPv6 禁用状态："
if sysctl net.ipv6.conf.all.disable_ipv6 | grep -q '1'; then
    success "IPv6 已禁用。"
else
    error "IPv6 未完全禁用。"
    instruction "建议在 /etc/sysctl.conf 添加 'net.ipv6.conf.all.disable_ipv6 = 1' 并 sysctl -p 应用。"
fi
separator

# 5. 最近系统更新
echo -e "\n【5】系统更新检查："
last_update=$(ls -lt --time-style=long-iso /var/lib/apt/extended_states 2>/dev/null | head -n 1 | awk '{print $6, $7}')
if [[ -n "$last_update" ]]; then
    success "最近一次系统更新时间：$last_update"
else
    error "无法确定最近更新记录。"
fi
separator

# 6. Guest 用户状态
echo -e "\n【6】Guest 用户状态："
if grep -E '^guest:' /etc/passwd >/dev/null 2>&1; then
    error "存在Guest用户。"
    instruction "建议删除或禁用Guest账户。"
else
    success "系统无Guest账户。"
fi
separator

# 7. USB 自动播放设置（Linux通常不启用）
echo -e "\n【7】U盘自动播放设置："
# Linux一般不会默认自动播放，但某些桌面环境可设置
if gsettings get org.gnome.desktop.media-handling automount | grep -q true; then
    error "检测到U盘自动挂载功能开启。"
    instruction "建议执行 'gsettings set org.gnome.desktop.media-handling automount false' 禁用。"
else
    success "U盘自动播放功能已禁用。"
fi
separator

# 8. 锁屏策略检查
echo -e "\n【8】锁屏策略检查："
lock_timeout=$(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null)
lock_enabled=$(gsettings get org.gnome.desktop.screensaver lock-enabled 2>/dev/null)
if [[ "$lock_timeout" -le 600 && "$lock_enabled" == "true" ]]; then
    success "锁屏策略符合要求（$lock_timeout 秒，需输入密码）"
else
    error "锁屏策略不符合要求（超时: $lock_timeout 秒，密码保护: $lock_enabled）"
    instruction "建议设置锁屏超时≤600秒，并启用锁屏密码。"
fi
separator

# 9. 密码策略检查
echo -e "\n【9】密码策略检查："
min_days=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
if [[ "$max_days" -le 90 ]]; then
    success "密码最大使用周期符合要求（$max_days 天）。"
else
    error "密码最大使用周期过长（$max_days 天）。"
    instruction "建议设置 'PASS_MAX_DAYS 90' 以强制90天修改密码。"
fi
separator

echo -e "\n========== 检查结束 =========="
echo "按任意键退出..."
read -n 1
