# 设置补丁目录
$PATCHES_DIR = "patches"

# 获取当前 Windows 版本
function Get-WindowsVersion {
    $version = (Get-CimInstance Win32_OperatingSystem).Version
    $release = (Get-CimInstance Win32_OperatingSystem).Caption
    return "$release $version"
}

# 获取适用于当前 Windows 版本的补丁
function Get-MatchingPatches {
    param (
        [string]$kbFolder
    )

    $matchingPatches = @()
    $currentVersion = Get-WindowsVersion

    # 遍历 KB 目录下的所有文件
    $patchFiles = Get-ChildItem -Path $kbFolder -Filter "*.msu" | Select-Object -ExpandProperty FullName
    foreach ($file in $patchFiles) {
        # 判断文件名是否包含 Windows 版本信息
        if ($file -match "Windows 7|Windows 8|Windows 10|Windows 11|Server 2008|Server 2012|Server 2016|Server 2019") {
            if ($file -match $currentVersion.Split(" ")[0]) {
                $matchingPatches += $file
            }
        }
    }

    return $matchingPatches
}

# 安装补丁
function Install-Patch {
    param (
        [string]$patchPath
    )
    Write-Host "正在安装：$patchPath ..."
    Start-Process -FilePath "wusa.exe" -ArgumentList "`"$patchPath`" /quiet /norestart" -NoNewWindow -Wait
    if ($?) {
        Write-Host "安装成功：$patchPath"
    } else {
        Write-Host "安装失败：$patchPath"
    }
}

# 遍历所有 KB 文件夹并安装补丁
function Install-AllPatches {
    if (-Not (Test-Path $PATCHES_DIR)) {
        Write-Host "错误：目录 $PATCHES_DIR 不存在！"
        return
    }

    $kbFolders = Get-ChildItem -Path $PATCHES_DIR -Directory
    foreach ($kbFolder in $kbFolders) {
        Write-Host "正在检查 KB$($kbFolder.Name) 补丁..."
        $patches = Get-MatchingPatches -kbFolder $kbFolder.FullName

        if ($patches.Count -eq 0) {
            Write-Host "未找到适用于当前系统的 KB$($kbFolder.Name) 补丁，跳过。"
            continue
        }

        foreach ($patch in $patches) {
            Install-Patch -patchPath $patch
        }
    }
}

# 执行主函数
Install-AllPatches
