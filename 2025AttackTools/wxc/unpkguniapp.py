import os
import subprocess

WX_DIR = "wx"  # 修改为你的小程序目录路径
BINGO_SCRIPT = "bingo.sh"  # bingo.sh 路径

def find_wxapkg_files(root_dir):
    targets = []
    for app_name in os.listdir(root_dir):
        app_path = os.path.join(root_dir, app_name)
        if not os.path.isdir(app_path):
            continue
        for sub in os.listdir(app_path):
            sub_path = os.path.join(app_path, sub)
            if os.path.isdir(sub_path):
                app_file = os.path.join(sub_path, "__APP__.wxapkg")
                if os.path.exists(app_file):
                    targets.append((app_name, app_file))
    return targets

def unpack_all():
    targets = find_wxapkg_files(WX_DIR)
    print(f"共发现 {len(targets)} 个小程序包，开始解包...\n")

    for app_name, pkg_path in targets:
        print(f"📦 解包 {app_name}...")
        try:
            subprocess.run([BINGO_SCRIPT, pkg_path], check=True)
        except subprocess.CalledProcessError as e:
            print(f"[!] 解包失败: {pkg_path}，错误信息：{e}")
        print("")

    print("✅ 所有小程序处理完成。")

if __name__ == "__main__":
    unpack_all()
