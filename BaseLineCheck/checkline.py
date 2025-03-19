import os
import subprocess
import re
import socket
import winreg
import ctypes

# 检查操作系统激活状态
def check_activation():
    output = subprocess.getoutput("slmgr /xpr")
    if "永久激活" in output or "已激活" in output:
        print("[+] 系统已激活")
    else:
        print("[-] 系统未激活，请手动激活")

# 检查防病毒软件安装情况（手动提示）
def check_antivirus():
    print("[*] 请手动检查：打开 Windows 安全中心或防病毒软件，确认病毒库定期更新，检查查杀日志")

# 检查弱口令（手动提示）
def check_weak_password():
    print("[*] 请手动检查：确认无弱口令、空口令、默认口令")

# 检查禁用Wi-Fi网卡
def check_wifi_adapter():
    output = subprocess.getoutput('netsh interface show interface')
    if "Wi-Fi" in output and "已禁用" in output:
        print("[+] Wi-Fi 网卡已禁用")
    else:
        print("[-] Wi-Fi 网卡未禁用，请检查")

# 检查高危端口状态
def check_ports():
    high_risk_ports = [22,23,135,137,138,139,445,455,3389,4899]
    open_ports = []
    for port in high_risk_ports:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            if s.connect_ex(('127.0.0.1', port)) == 0:
                open_ports.append(port)
    if open_ports:
        print(f"[-] 以下高危端口未关闭：{open_ports}")
    else:
        print("[+] 所有高危端口已关闭")

# 检查IPv6是否禁用
def check_ipv6():
    output = subprocess.getoutput('reg query HKLM\\SYSTEM\\CurrentControlSet\\Services\\TCPIP6\\Parameters /v DisabledComponents')
    if "0xff" in output:
        print("[+] IPv6 已禁用")
    else:
        print("[-] IPv6 未禁用")

# 提示口令修改策略
def check_password_policy():
    print("[*] 请手动检查：确认口令三个月定期修改策略")

# 检查Guest用户状态
def check_guest():
    output = subprocess.getoutput('net user guest')
    if "账户启用               否" in output:
        print("[+] Guest 用户已禁用")
    else:
        print("[-] Guest 用户未禁用，请禁用")

# 检查U盘自动播放是否关闭
def check_autorun():
    key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                         r"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer", 0, winreg.KEY_READ)
    try:
        value, _ = winreg.QueryValueEx(key, "NoDriveTypeAutoRun")
        if value == 255:
            print("[+] U盘自动播放已关闭")
        else:
            print("[-] U盘自动播放未关闭，请关闭")
    except FileNotFoundError:
        print("[-] 未找到U盘自动播放相关配置，请手动确认")

# 提示Google浏览器升级检查
def check_chrome_version():
    print("[*] 请手动检查：打开Chrome浏览器，点击帮助-关于，确认已更新至最新版本")

# 提示打印机SNMP功能检查
def check_printer_snmp():
    print("[*] 请手动检查：打开打印机属性，确认SNMP功能已禁用")

# 提示开机密码保护
def check_boot_password():
    print("[*] 请手动检查：确认计算机已设置开机密码保护")

# 屏幕锁定策略提示
def check_screen_lock():
    print("[*] 请手动检查：确认屏幕锁定时间设置为10分钟且唤醒需要密码")

# 提示口令明示情况
def check_password_notice():
    print("[*] 请手动检查：确认电脑附近无口令明示或张贴")

# 检查防火墙是否启用
def check_firewall():
    output = subprocess.getoutput('netsh advfirewall show allprofiles state')
    if "ON" in output:
        print("[+] 防火墙已启用")
    else:
        print("[-] 防火墙未启用，请开启并合理配置")

# 主函数
def main():
    check_activation()
    check_antivirus()
    check_weak_password()
    check_wifi_adapter()
    check_ports()
    check_ipv6()
    check_password_policy()
    check_guest()
    check_autorun()
    check_chrome_version()
    check_printer_snmp()
    check_boot_password()
    check_screen_lock()
    check_password_notice()
    check_firewall()

    input("\n检查完成，按回车键退出")

if __name__ == "__main__":
    if not ctypes.windll.shell32.IsUserAnAdmin():
        print("[-] 请以管理员权限运行该脚本")
    else:
        main()
