# 已安装的程序列表，再次进行过滤
$installedApps | Where-Object {
    # 检查是否为用户程序（不包含排除列表中的关键字）
    $isUserApp = $true
    foreach ($exclusion in $exclusionList) {
        if ($_.DisplayName -like "*$exclusion*") {
            $isUserApp = $false
            break
        }
    }
    # 保留名称包含 'Office' 的 Microsoft Corporation 程序
    $isUserApp -and ($whitelist -notcontains $_.DisplayName) -and ($_.Publisher -ne "Microsoft Corporation" -or $_.DisplayName -like "*Office*")
} | ForEach-Object {
    "$($_.DisplayName) - Version: $($_.DisplayVersion) - Publisher: $($_.Publisher)"
} | Out-File -FilePath .\NonWhitelistedApps.txt -Append # 使用-Append避免覆盖之前的内容
