#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Python包下载脚本
在有网络的环境中下载所需的包，用于离线安装
"""

import os
import sys
import subprocess
import platform

def download_packages():
    """下载所需的Python包"""
    # 创建packages目录
    packages_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "packages")
    if not os.path.exists(packages_dir):
        os.makedirs(packages_dir)
        print(f"创建目录: {packages_dir}")
    
    # 需要下载的包
    packages = [
        'requests',
        'pandas', 
        'chardet',
        'openpyxl'  # pandas写入Excel需要
    ]
    
    print("开始下载Python包...")
    print(f"下载目录: {packages_dir}")
    print()
    
    success_count = 0
    for package in packages:
        try:
            print(f"正在下载 {package}...")
            cmd = [sys.executable, '-m', 'pip', 'download', package, '-d', packages_dir]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                print(f"✅ {package} 下载成功")
                success_count += 1
            else:
                print(f"❌ {package} 下载失败: {result.stderr}")
                
        except Exception as e:
            print(f"❌ {package} 下载异常: {e}")
    
    print(f"\n下载完成: {success_count}/{len(packages)} 个包下载成功")
    
    # 列出下载的文件
    if os.path.exists(packages_dir):
        files = os.listdir(packages_dir)
        if files:
            print(f"\n下载的文件 ({len(files)} 个):")
            for file in files:
                file_path = os.path.join(packages_dir, file)
                file_size = os.path.getsize(file_path)
                print(f"  - {file} ({file_size:,} bytes)")
        else:
            print("\n❌ 没有下载到任何文件")
    
    print(f"\n📁 包文件保存在: {packages_dir}")
    print("请将此目录复制到内网环境的服务器目录中")

def main():
    """主函数"""
    print("Security Check 服务器 - Python包下载工具")
    print("=" * 50)
    print("此脚本用于在有网络的环境中下载所需的Python包")
    print("下载完成后，将packages目录复制到内网环境进行离线安装")
    print("=" * 50)
    
    # 检查Python版本
    version = sys.version_info
    print(f"Python版本: {version.major}.{version.minor}.{version.micro}")
    
    if version.major < 3 or (version.major == 3 and version.minor < 7):
        print("❌ 需要Python 3.7或更高版本")
        return
    
    # 检查系统架构
    arch = platform.architecture()[0]
    print(f"系统架构: {arch}")
    print()
    
    # 下载包
    download_packages()
    
    print("\n" + "=" * 50)
    print("下载完成！")
    print("下一步操作:")
    print("1. 将packages目录复制到内网环境的服务器目录")
    print("2. 在内网环境中运行: python install_dependencies.py")
    print("3. 安装完成后运行: python server_enhanced.py")

if __name__ == '__main__':
    main() 