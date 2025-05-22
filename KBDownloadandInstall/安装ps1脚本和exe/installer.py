import os
import platform
import subprocess

# 定义补丁目录
PATCHES_DIR = "patches"

# 获取当前 Windows 版本信息
def get_windows_version():
    """ 获取当前 Windows 版本信息 """
    version = platform.version()
    release = platform.release()
    system_name = platform.system()

    if "Windows" not in system_name:
        print("该脚本仅适用于 Windows 系统！")
        return None

    return f"{release} {version}"

# 解析 Windows 版本并匹配补丁
def get_matching_patches(kb_folder):
    """ 获取适用于当前 Windows 版本的补丁文件 """
    matching_patches = []
    current_version = get_windows_version()

    if not current_version:
        return []

    # 遍历 KB 目录下的所有文件
    for file in os.listdir(kb_folder):
        file_path = os.path.join(kb_folder, file)
        if file.endswith(".msu"):
            # 简单匹配 Windows 版本（这里假设文件名包含 Windows 版本关键字）
            if any(ver in file for ver in ["Windows 7", "Windows 8", "Windows 10", "Windows 11", "Server 2008", "Server 2012", "Server 2016", "Server 2019"]):
                if str(current_version.split()[0]) in file:
                    matching_patches.append(file_path)

    return matching_patches

# 安装补丁
def install_patch(patch_path):
    """ 使用 wusa.exe 安装 Windows 补丁 """
    print(f"正在安装：{patch_path} ...")
    try:
        subprocess.run(["wusa", patch_path, "/quiet", "/norestart"], check=True)
        print(f"安装成功：{patch_path}")
    except subprocess.CalledProcessError:
        print(f"安装失败：{patch_path}")

# 遍历所有 KB 文件夹并安装匹配的补丁
def install_all_patches():
    """ 遍历 patches 目录，查找并安装适用于当前 Windows 版本的补丁 """
    if not os.path.exists(PATCHES_DIR):
        print(f"错误：目录 {PATCHES_DIR} 不存在！")
        return

    for kb_folder in os.listdir(PATCHES_DIR):
        full_kb_path = os.path.join(PATCHES_DIR, kb_folder)
        if os.path.isdir(full_kb_path):
            print(f"正在检查 KB{kb_folder} 补丁...")
            patches = get_matching_patches(full_kb_path)

            if not patches:
                print(f"未找到适用于当前系统的 KB{kb_folder} 补丁，跳过。")
                continue

            for patch in patches:
                install_patch(patch)

if __name__ == "__main__":
    install_all_patches()
