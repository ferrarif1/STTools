import os
import time
import shutil
import openpyxl
from pathlib import Path
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import tkinter as tk
from tkinter import simpledialog, messagebox

WATCH_DIR = Path(__file__).parent.resolve()
BACKUP_DIR = WATCH_DIR / "台账自动备份"
LOG_FILE = WATCH_DIR / "台账修改记录.xlsx"

# 初始化备份和日志文件
BACKUP_DIR.mkdir(exist_ok=True)

if not LOG_FILE.exists():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "修改记录"
    ws.append(["时间", "台账名称", "修改人", "修改说明", "台账文件名", "记录生成时间"])
    wb.save(LOG_FILE)

# 活动缓存
file_mod_time = {}
file_watching = {}

class ExcelHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.src_path.endswith(".xlsx") and not event.is_directory:
            print(f"[新建] {event.src_path}")
            # 新建文件不立即备份，等待首次修改后处理

    def on_modified(self, event):
        if event.is_directory or not event.src_path.endswith(".xlsx"):
            return

        filepath = Path(event.src_path)
        filename = filepath.name
        now = time.time()

        if filename not in file_mod_time or now - file_mod_time[filename] > 10:
            file_mod_time[filename] = now
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_file = BACKUP_DIR / f"{filename[:-5]}_{timestamp}.xlsx"
            shutil.copy2(filepath, backup_file)
            print(f"[备份] {filename} → {backup_file.name}")
            file_watching[filename] = {
                "path": filepath,
                "time": timestamp
            }

    def on_deleted(self, event):
        if event.is_directory or not event.src_path.endswith(".xlsx"):
            return
        print(f"[删除] {event.src_path}")
        # 可扩展：将删除记录写入日志


def ask_user_and_log(filename: str, filepath: Path, timestamp: str):
    root = tk.Tk()
    root.withdraw()

    user = simpledialog.askstring("记录修改人", "请输入你的姓名：", parent=root)
    if not user:
        return
    comment = simpledialog.askstring("修改说明", f"你对 {filename} 修改了什么？", parent=root)
    if not comment:
        comment = "未填写"

    time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    wb = openpyxl.load_workbook(LOG_FILE)
    ws = wb.active
    ws.append([time_str, filename[:-5], user, comment, filename, time_str])
    wb.save(LOG_FILE)

    messagebox.showinfo("记录完成", f"✅ 已记录对 {filename} 的修改。")
    root.destroy()


def monitor():
    observer = Observer()
    handler = ExcelHandler()
    observer.schedule(handler, str(WATCH_DIR), recursive=False)
    observer.start()
    print(f"📡 正在监控目录：{WATCH_DIR}")

    try:
        while True:
            time.sleep(10)
            now = time.time()
            expired = []

            for fname, info in file_watching.items():
                fpath = info["path"]
                last_mod = os.path.getmtime(fpath) if fpath.exists() else 0
                if now - last_mod > 20:
                    print(f"[确认关闭] {fname}")
                    ask_user_and_log(fname, fpath, info["time"])
                    expired.append(fname)

            for fname in expired:
                file_watching.pop(fname)

    except KeyboardInterrupt:
        observer.stop()
        print("⛔ 监控停止")
    observer.join()


if __name__ == "__main__":
    monitor()
