#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
离线依赖安装脚本
用于安装服务器所需的Python包
"""

import os
import sys
import subprocess
import platform

def check_python_version():
    """检查Python版本"""
    version = sys.version_info
    print(f"Python版本: {version.major}.{version.minor}.{version.micro}")
    
    if version.major < 3 or (version.major == 3 and version.minor < 7):
        print("❌ 需要Python 3.7或更高版本")
        return False
    
    print("✅ Python版本符合要求")
    return True

def check_package(package_name):
    """检查包是否已安装"""
    try:
        __import__(package_name)
        print(f"✅ {package_name} 已安装")
        return True
    except ImportError:
        print(f"❌ {package_name} 未安装")
        return False

def install_package_from_wheel(wheel_path):
    """从wheel文件安装包"""
    try:
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', wheel_path])
        print(f"✅ 成功安装: {os.path.basename(wheel_path)}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ 安装失败: {e}")
        return False

def main():
    """主函数"""
    print("Security Check 服务器依赖安装工具")
    print("=" * 50)
    
    # 检查Python版本
    if not check_python_version():
        return
    
    # 检查系统架构
    arch = platform.architecture()[0]
    print(f"系统架构: {arch}")
    
    # 检查已安装的包
    print("\n检查已安装的包:")
    packages = ['requests', 'pandas', 'chardet', 'openpyxl']
    missing_packages = []
    
    for package in packages:
        if not check_package(package):
            missing_packages.append(package)
    
    if not missing_packages:
        print("\n✅ 所有依赖包已安装，无需额外安装")
        return
    
    print(f"\n需要安装的包: {', '.join(missing_packages)}")
    
    # 检查packages目录
    packages_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "packages")
    if not os.path.exists(packages_dir):
        print(f"\n❌ packages目录不存在: {packages_dir}")
        print("请在有网络的环境中运行以下命令下载包:")
        print()
        for package in missing_packages:
            print(f"pip download {package} -d ./packages")
        print()
        print("然后将packages目录复制到服务器目录中")
        return
    
    # 查找wheel文件
    wheel_files = []
    for file in os.listdir(packages_dir):
        if file.endswith('.whl'):
            wheel_files.append(os.path.join(packages_dir, file))
    
    if not wheel_files:
        print(f"\n❌ packages目录中没有找到.whl文件: {packages_dir}")
        return
    
    print(f"\n找到 {len(wheel_files)} 个wheel文件:")
    for wheel_file in wheel_files:
        print(f"  - {os.path.basename(wheel_file)}")
    
    # 安装包
    print("\n开始安装包...")
    success_count = 0
    
    for wheel_file in wheel_files:
        if install_package_from_wheel(wheel_file):
            success_count += 1
    
    print(f"\n安装完成: {success_count}/{len(wheel_files)} 个包安装成功")
    
    # 最终检查
    print("\n最终检查:")
    all_installed = True
    for package in packages:
        if not check_package(package):
            all_installed = False
    
    if all_installed:
        print("\n✅ 所有依赖包安装成功！")
        print("现在可以运行服务器了:")
        print("  python server_enhanced.py")
    else:
        print("\n❌ 部分依赖包安装失败，请检查错误信息")

if __name__ == '__main__':
    main() 