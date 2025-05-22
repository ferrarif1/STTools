import os
import chardet

# 定义办公软件关键词
OFFICE_SOFTWARE_KEYWORDS = [
    "office", "word", "excel", "powerpoint", "wps", "pdf", "winrar", "chrome", "firefox", "outlook", "acrobat",
    "zip", "adobe", "google", "file", "visio", "note", "edge", "explorer", "mail", "player", "media", "网盘", "文档",
    "表格", "图", "输入法", "百度", "阿里", "腾讯", "云", "会议", "翻译", "客户端"
]

# 定义应剔除的关键词
EXCLUDE_KEYWORDS = ["java", "manifest", "framework", "system", "component", "python"]

def detect_file_encoding(file_path):
    """
    检测文件的编码方式
    :param file_path: 文件路径
    :return: 文件编码
    """
    with open(file_path, 'rb') as file:
        result = chardet.detect(file.read())
    return result['encoding'] or 'utf-8'


def find_office_apps_by_version(directory):
    """
    在指定目录下查找含有办公软件信息的文本文件，并按系统版本分类
    :param directory: 目录路径
    :return: 按系统版本分类的办公软件列表字典
    """
    apps_by_system = {}

    for filename in os.listdir(directory):
        if filename.endswith('.txt'):
            filepath = os.path.join(directory, filename)
            encoding = detect_file_encoding(filepath)

            try:
                with open(filepath, 'r', encoding=encoding, errors='ignore') as file:
                    system_version = None
                    for line in file:
                        if line.lower().startswith("system"):
                            system_version = line.strip()
                            continue
                        if system_version and any(keyword.lower() in line.lower() for keyword in OFFICE_SOFTWARE_KEYWORDS) and \
                                not any(exclude_keyword.lower() in line.lower() for exclude_keyword in EXCLUDE_KEYWORDS):
                            if system_version not in apps_by_system:
                                apps_by_system[system_version] = []
                            apps_by_system[system_version].append(line.strip())
            except Exception as e:
                print(f"Error reading {filepath}: {e}")

    return apps_by_system


def save_results_to_files(system_to_apps, output_dir):
    """
    将按系统版本分类的办公软件列表保存到单独的文件中
    :param system_to_apps: 按系统版本分类的办公软件列表字典
    :param output_dir: 输出文件夹路径
    """
    for system, apps in system_to_apps.items():
        # 去除重复项并排序
        unique_apps = sorted(set(apps), key=str.lower)

        # 获取纯净的系统版本名称
        pure_system = system.split(":", 1)[-1].strip()
        output_filename = f'{output_dir}/result-{pure_system.replace(" ", "_").lower()}.txt'

        try:
            with open(output_filename, 'w', newline='', encoding='utf-8') as output_file:
                for app in unique_apps:
                    print(app)
                    output_file.write(app + '\n')
        except IOError as e:
            print(f"Error writing to {output_filename}: {e}")


# 指定输入和输出文件夹路径
input_directory = './allApps'
output_directory = './checkedAllApps/'

# 执行查找和保存操作
system_to_apps = find_office_apps_by_version(input_directory)
save_results_to_files(system_to_apps, output_directory)