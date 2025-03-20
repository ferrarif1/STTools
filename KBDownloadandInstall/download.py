# CHROMEDRIVER_PATH = "/usr/local/bin/chromedriver"

import time
import os
import pandas as pd
import requests
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options

from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# Microsoft Update Catalog URL
# Microsoft Update Catalog (catalog.update.microsoft.com) 上主要提供的是安全更新补丁，特别是：
# 安全更新 (Security Updates)
# 关键补丁 (Critical Updates)
# 高危漏洞修复 (Security Vulnerability Fixes)
UPDATE_CATALOG_URL = "https://www.catalog.update.microsoft.com/Search.aspx?q="

# 配置 ChromeDriver
chrome_options = Options()
chrome_options.add_argument("--headless")  # 无界面运行
chrome_options.add_argument("--disable-gpu")
chrome_options.add_argument("--no-sandbox")

# Fix: Use raw string prefix (r) for Windows paths to avoid escape sequence issues
webdriver_path = r"C:\Users\revan\Desktop\STTools\KBDownloadandInstall\chromedriver-win64\chromedriver-win64\chromedriver.exe"
service = Service(webdriver_path)
driver = webdriver.Chrome(service=service, options=chrome_options)



def download_kb_patch(kb_number, download_dir):
    """ 下载指定 KB 号的所有补丁 """
    base_folder_name = f"KB{kb_number}"
    kb_folder = os.path.join(download_dir, base_folder_name)
    os.makedirs(kb_folder, exist_ok=True)

    search_url = f"{UPDATE_CATALOG_URL}KB{kb_number}"
    driver.get(search_url)
    time.sleep(3)  # 等待加载

    try:
        # 查找所有的行
        rows = driver.find_elements(By.XPATH, "//tr[contains(@id, '_R') and contains(@style, 'border-width')]")

        if not rows:
            print(f"未找到 KB{kb_number} 的任何更新项")
            return "失败"

        file_count = 0
        
        for row in rows:
            # 获取 KB 号的链接
            update_name_element = row.find_element(By.XPATH, ".//a[contains(@onclick, 'goToDetails')]")
            update_name = update_name_element.text.strip()
            
            # 获取操作系统类型
            os_type_element = row.find_element(By.XPATH, ".//td[contains(@class, 'resultsbottomBorder resultspadding')]")
            os_type = os_type_element.text.strip()

            # 获取下载按钮
            download_button = row.find_element(By.XPATH, ".//input[@type='button' and @value='Download']")

            # 点击下载按钮
            download_button.click()
            time.sleep(2)

            # 切换到新窗口
            driver.switch_to.window(driver.window_handles[-1])
            time.sleep(2)

            # 使用显式等待，等待下载链接加载
            
            try:
                download_link_element = WebDriverWait(driver, 10).until(
                    EC.presence_of_element_located((By.XPATH, "//a[contains(@href, '.msu')]"))
                )
                download_link = download_link_element.get_attribute("href")

                if not download_link:
                    print(f"未能找到下载链接：{update_name}")
                    continue
                # 构造文件名
                file_count += 1
                file_name = f"{file_count}_{update_name[0:-11]}.msu"  # 简化文件名，截取前10个字符
                file_path = os.path.join(kb_folder, file_name)

                # 下载文件
                print(f"开始下载 {update_name} ...")
                response = requests.get(download_link, stream=True)
                if response.status_code == 200:
                    with open(file_path, "wb") as file:
                        for chunk in response.iter_content(chunk_size=8192):
                            file.write(chunk)
                    print(f"成功下载 {update_name} 到 {file_path}")
                else:
                    print(f"下载失败: {response.status_code}")

            except Exception as e:
                print(f"获取下载链接失败: {e}")

            finally:
                # 关闭下载窗口，回到主页面
                driver.close()
                driver.switch_to.window(driver.window_handles[0])

        return "成功" if file_count > 0 else "失败"

    except Exception as e:
        print(f"处理 KB{kb_number} 失败: {e}")
        return "失败"

    """ 下载指定 KB 号的所有补丁 """
    base_folder_name = f"KB{kb_number}"
    kb_folder = os.path.join(download_dir, base_folder_name)
    os.makedirs(kb_folder, exist_ok=True)

    search_url = f"{UPDATE_CATALOG_URL}KB{kb_number}"
    driver.get(search_url)
    time.sleep(3)  # 等待加载

    try:
        # 获取所有 Download 按钮
        download_buttons = driver.find_elements(By.XPATH, '//input[@type="button" and @value="Download"]')
        if not download_buttons:
            print(f"未找到 KB{kb_number} 的下载按钮，标记为失败")
            failed_folder = os.path.join(download_dir, f"failed_KB{kb_number}")
            os.makedirs(failed_folder, exist_ok=True)
            return "失败"

        file_count = 0
        for button in download_buttons:
            button.click()
            time.sleep(2)

            # 切换到新窗口
            driver.switch_to.window(driver.window_handles[-1])
            time.sleep(2)
           
            # 获取下载链接
            try:
                download_link_element = driver.find_element(By.XPATH, '//a[contains(@href, ".msu")]')
                download_link = download_link_element.get_attribute("href")

                # 获取补丁标题
                title_element = driver.find_element(By.XPATH, '//td[contains(@class, "resultsbottomBorder resultspadding") and contains(text(),"安全更新程序")]')
                title = title_element.text.strip()

                # 获取产品信息
                product_element = driver.find_element(By.XPATH, '//td[contains(@class, "resultsbottomBorder resultspadding") and contains(text(),"Windows")]')
                product = product_element.text.strip()

                if not download_link:
                    print(f"未能找到 KB{kb_number} 的下载链接")
                    continue

                # 按规则命名文件：title前10个字符 + "win" + product的第8-16个字符
                title_part = title[10:15]  # 前10个字符
                product_part = product[7:15]  # 从第8到16个字符
                file_name = f"y{file_count}_{title_part}_{product_part}.msu"

                file_path = os.path.join(kb_folder, file_name)

                # 下载文件
                file_count += 1
                print(f"开始下载 KB{kb_number} 文件 {file_count} ...")
                response = requests.get(download_link, stream=True)
                if response.status_code == 200:
                    with open(file_path, "wb") as file:
                        for chunk in response.iter_content(chunk_size=8192):
                            file.write(chunk)
                    print(f"成功下载 KB{kb_number} 文件 {file_count} 到 {file_path}")
                else:
                    print(f"下载 KB{kb_number} 文件 {file_count} 失败: {response.status_code}")

            except Exception as e:
                print(f"获取 KB{kb_number} 下载链接失败: {e}")

            finally:
                # 关闭下载窗口，回到主页面
                driver.close()
                driver.switch_to.window(driver.window_handles[0])

        return "成功" if file_count > 0 else "失败"

    except Exception as e:
        print(f"处理 KB{kb_number} 失败: {e}")
        failed_folder = os.path.join(download_dir, f"failed_KB{kb_number}")
        os.makedirs(failed_folder, exist_ok=True)
        return "失败"

    """ 下载指定 KB 号的所有补丁 """
    base_folder_name = f"KB{kb_number}"
    kb_folder = os.path.join(download_dir, base_folder_name)
    os.makedirs(kb_folder, exist_ok=True)

    search_url = f"{UPDATE_CATALOG_URL}KB{kb_number}"
    driver.get(search_url)
    time.sleep(3)  # 等待加载

    try:
        # 获取所有 Download 按钮
        download_buttons = driver.find_elements(By.XPATH, '//input[@type="button" and @value="Download"]')
        if not download_buttons:
            print(f"未找到 KB{kb_number} 的下载按钮，标记为失败")
            failed_folder = os.path.join(download_dir, f"failed_KB{kb_number}")
            os.makedirs(failed_folder, exist_ok=True)
            return "失败"

        file_count = 0
        for button in download_buttons:
            button.click()
            time.sleep(2)

            # 切换到新窗口
            driver.switch_to.window(driver.window_handles[-1])
            time.sleep(2)

            # 获取下载链接和补丁标题、产品信息
            try:
                download_link_element = driver.find_element(By.XPATH, '//a[contains(@href, ".msu")]')
                download_link = download_link_element.get_attribute("href")

                title_element = driver.find_element(By.XPATH, '//td[contains(@class, "resultsbottomBorder resultspadding") and contains(text(),"安全更新程序")]')
                title = title_element.text.strip()

                product_element = driver.find_element(By.XPATH, '//td[contains(@class, "resultsbottomBorder resultspadding") and contains(text(),"Windows")]')
                product = product_element.text.strip()

                if not download_link:
                    print(f"未能找到 KB{kb_number} 的下载链接")
                    continue

                # 截取标题和产品信息进行文件命名
                title_part = title[:20]  # 前10个字符
                product_part = product[7:19]  # 从第8到16个字符
                file_name = f"z{product_part}+{title_part}.msu"

                file_path = os.path.join(kb_folder, file_name)

                # 下载文件
                file_count += 1
                print(f"开始下载 KB{kb_number} 文件 {file_count} ...")
                response = requests.get(download_link, stream=True)
                if response.status_code == 200:
                    with open(file_path, "wb") as file:
                        for chunk in response.iter_content(chunk_size=8192):
                            file.write(chunk)
                    print(f"成功下载 KB{kb_number} 文件 {file_count} 到 {file_path}")
                else:
                    print(f"下载 KB{kb_number} 文件 {file_count} 失败: {response.status_code}")

            except Exception as e:
                print(f"获取 KB{kb_number} 下载链接失败: {e}")

            finally:
                # 关闭下载窗口，回到主页面
                driver.close()
                driver.switch_to.window(driver.window_handles[0])

        return "成功" if file_count > 0 else "失败"

    except Exception as e:
        print(f"处理 KB{kb_number} 失败: {e}")
        failed_folder = os.path.join(download_dir, f"failed_KB{kb_number}")
        os.makedirs(failed_folder, exist_ok=True)
        return "失败"

    """ 下载指定 KB 号的所有补丁 """
    base_folder_name = f"KB{kb_number}"
    kb_folder = os.path.join(download_dir, base_folder_name)
    os.makedirs(kb_folder, exist_ok=True)

    search_url = f"{UPDATE_CATALOG_URL}KB{kb_number}"
    driver.get(search_url)
    time.sleep(3)  # 等待加载

    try:
        # 获取所有 Download 按钮
        download_buttons = driver.find_elements(By.XPATH, '//input[@type="button" and @value="Download"]')
        if not download_buttons:
            print(f"未找到 KB{kb_number} 的下载按钮，标记为失败")
            failed_folder = os.path.join(download_dir, f"failed_KB{kb_number}")
            os.makedirs(failed_folder, exist_ok=True)
            return "失败"

        file_count = 0
        for button in download_buttons:
            button.click()
            time.sleep(2)

            # 切换到新窗口
            driver.switch_to.window(driver.window_handles[-1])
            time.sleep(2)

            # 获取下载链接
            try:
                download_link_element = driver.find_element(By.XPATH, '//a[contains(@href, ".msu")]')
                download_link = download_link_element.get_attribute("href")

                if not download_link:
                    print(f"未能找到 KB{kb_number} 的下载链接")
                    continue

                # 下载文件
                file_count += 1
                file_name = f"KB{kb_number}_{file_count}.msu"
                file_path = os.path.join(kb_folder, file_name)

                print(f"开始下载 KB{kb_number} 文件 {file_count} ...")
                response = requests.get(download_link, stream=True)
                if response.status_code == 200:
                    with open(file_path, "wb") as file:
                        for chunk in response.iter_content(chunk_size=8192):
                            file.write(chunk)
                    print(f"成功下载 KB{kb_number} 文件 {file_count} 到 {file_path}")
                else:
                    print(f"下载 KB{kb_number} 文件 {file_count} 失败: {response.status_code}")

            except Exception as e:
                print(f"获取 KB{kb_number} 下载链接失败: {e}")

            finally:
                # 关闭下载窗口，回到主页面
                driver.close()
                driver.switch_to.window(driver.window_handles[0])

        return "成功" if file_count > 0 else "失败"

    except Exception as e:
        print(f"处理 KB{kb_number} 失败: {e}")
        failed_folder = os.path.join(download_dir, f"failed_KB{kb_number}")
        os.makedirs(failed_folder, exist_ok=True)
        return "失败"

def process_kb_list(excel_file, download_base_dir="patches"):
    """ 读取 KB 列表并下载所有补丁 """
    df = pd.read_excel(excel_file, header=None)
    
    # 处理 KB 列表，去掉空值和 KB 前缀
    kb_numbers = df.iloc[:, 0].dropna().astype(str).str.replace("KB", "").str.strip().tolist()

    if not kb_numbers:
        print("Excel 文件为空或无有效 KB 编号")
        return
    
    os.makedirs(download_base_dir, exist_ok=True)

    result_df = pd.DataFrame({'KB 编号': kb_numbers, '结果': [None] * len(kb_numbers)})

    for index, kb in enumerate(kb_numbers):
        print(f"处理 KB{kb}...")
        result = download_kb_patch(kb, download_base_dir)
        result_df.loc[index, '结果'] = result

    output_file = f"updated_{excel_file}"
    result_df.to_excel(output_file, index=False)
    print(f"更新后的 Excel 文件已保存为 {output_file}")

if __name__ == "__main__":
    excel_file = "kb_list.xlsx"
    process_kb_list(excel_file)

    driver.quit()  # 关闭浏览器
