# 安装PS2EXE（如果还没安装）
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module -Name ps2exe -Force -Scope CurrentUser
}

# 获取脚本所在目录
$scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# 打包命令
$params = @{
    InputFile = Join-Path $scriptPath "check5.ps1"
    OutputFile = Join-Path $scriptPath "SecurityCheck_v5.exe"
    NoConsole = $false                # 显示控制台窗口
    RequireAdmin = $true             # 要求管理员权限
    Version = "1.0.0.0"              # 版本号
    Description = "Security Baseline Check Tool V5"
}

# 执行打包
Invoke-ps2exe @params

Write-Output "打包完成：SecurityCheck_v5.exe" 