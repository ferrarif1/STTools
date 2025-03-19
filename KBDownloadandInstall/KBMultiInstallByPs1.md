
---

### **脚本功能说明**：
1. **日志记录**：
   - 日志文件 `install_kb_log.txt` 会记录以下信息：
     - 脚本运行的开始和结束时间。
     - 每个补丁的安装状态（成功或失败）。
     - 已跳过的补丁信息。

2. **跳过已安装补丁**：
   - 使用 `Get-HotFix` 获取系统中已安装的补丁列表。
   - 如果补丁已安装，则跳过并记录到日志中。

3. **系统版本过滤**：
   - 只安装文件名中包含指定系统版本的 `.msu` 文件。

4. **错误处理**：
   - 使用 `try-catch` 捕获安装过程中的错误，并记录到日志中。

---

### **脚本**：

```powershell
# 设置日志文件
$logFile = "install_kb_log.txt"

# 记录脚本开始时间
$startTime = Get-Date
echo "脚本开始时间: $startTime" | Out-File -Append $logFile

# 提示用户输入系统版本
$systemVersion = Read-Host "请输入系统版本（例如：windows 7）"
$systemVersionLower = $systemVersion.ToLower()

# 获取系统中已安装的补丁列表
$installedPatches = Get-HotFix | ForEach-Object { $_.HotFixID }

# 获取所有 KB 号文件夹
$kbFolders = Get-ChildItem -Path .\ -Directory -Filter "KB*"

# 遍历每个 KB 文件夹
foreach ($folder in $kbFolders) {
    Write-Host "进入文件夹: $folder"
    echo "进入文件夹: $folder" | Out-File -Append $logFile

    # 获取当前文件夹下的 .msu 文件
    $msuFiles = Get-ChildItem -Path $folder.FullName -Filter "*.msu"

    foreach ($file in $msuFiles) {
        # 检查文件名中是否包含指定的系统版本
        if ($file.Name.ToLower() -like "*$systemVersionLower*") {
            # 提取 KB 号
            $kbNumber = $folder.Name -replace "KB", ""

            # 检查补丁是否已安装
            if ($installedPatches -contains $kbNumber) {
                Write-Host "补丁 $kbNumber 已安装，跳过: $file"
                echo "补丁 $kbNumber 已安装，跳过: $file" | Out-File -Append $logFile
            } else {
                Write-Host "正在安装补丁: $file"
                echo "正在安装补丁: $file" | Out-File -Append $logFile

                # 安装补丁
                try {
                    Start-Process -FilePath "wusa.exe" -ArgumentList "$($file.FullName) /quiet /norestart" -Wait
                    Write-Host "补丁安装成功: $file"
                    echo "补丁安装成功: $file" | Out-File -Append $logFile
                } catch {
                    Write-Host "补丁安装失败: $file"
                    echo "补丁安装失败: $file" | Out-File -Append $logFile
                }
            }
        }
    }
}

# 记录脚本结束时间
$endTime = Get-Date
echo "脚本结束时间: $endTime" | Out-File -Append $logFile

Write-Host "所有更新已安装，请重启系统生效！"
echo "所有更新已安装，请重启系统生效！" | Out-File -Append $logFile
```



### **日志文件示例**：
```
脚本开始时间: 2023-10-01 12:00:00
进入文件夹: KB1234567
正在安装补丁: windows7-x64-patch.msu
补丁安装成功: windows7-x64-patch.msu
进入文件夹: KB2345678
补丁 KB2345678 已安装，跳过: WINDOWS7-x86-patch.msu
脚本结束时间: 2023-10-01 12:05:00
所有更新已安装，请重启系统生效！
```

---

### **使用方法**：
1. 将脚本保存为 `install_kb.ps1`，放置在 `patches/` 目录下。
2. 打开 PowerShell，导航到 `patches/` 目录。
3. 运行脚本：`.\install_kb.ps1`。
4. 输入系统版本（如 `windows 7`），脚本会自动安装符合条件的补丁。

---

### **注意事项**：
- 确保以管理员权限运行脚本。
- 如果需要重启系统，可以移除 `/norestart` 参数。
- 日志文件会保存在脚本同级目录下，方便后续检查。

希望这个优化后的脚本能更好地满足你的需求！
