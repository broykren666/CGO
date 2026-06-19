#requires -RunAsAdministrator

# 设置控制台编码为 UTF-8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 936 > $null

# 切换到脚本所在目录
Set-Location -Path $PSScriptRoot

# 检查管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "请求管理员权限..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 设置控制台标题
$Host.UI.RawUI.WindowTitle = "Mieru 一键翻墙"

# 引入公共函数库
. "$PSScriptRoot\Common.ps1"

# ==================== 配置常量（请根据实际情况修改） ====================
# 内核目录（相对于脚本所在目录）
$CORE_DIR = "mieru"
# 内核程序文件名
$CORE_EXE = "mieru.exe"
# IP更新脚本目录（绝对路径）
$IP_UPDATE_DIR = Join-Path $PSScriptRoot (Join-Path $CORE_DIR "ip_Update")
# ======================================================================

# 主程序
try {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "    Mieru 一键翻墙脚本" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    # 调用 IP 更新流程
    Invoke-IPUpdate -IPUpdateDir $IP_UPDATE_DIR
    
    # 检查内核文件是否存在
    $corePath = Join-Path $PSScriptRoot (Join-Path $CORE_DIR $CORE_EXE)
    
    if (-not (Test-Path $corePath)) {
        Write-Host "错误: 内核文件不存在: $CORE_EXE" -ForegroundColor Red
        Write-Host "请检查 CORE_EXE 配置是否正确" -ForegroundColor Red
        Write-Host "按任意键退出..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    # 二次确认启动
    if (-not (Confirm-Launch -CoreName "Mieru ($CORE_EXE)")) {
        Write-Host "按任意键退出..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 0
    }

    # 启动内核（mieru 需要先 apply config 再 start，两步操作）
    Write-Host "正在应用 Mieru 配置..." -ForegroundColor Cyan
    
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $configPath = Join-Path $workingDir "config.json"
    
    # 第一步：apply config
    $applyProcess = Start-Process -FilePath $corePath -ArgumentList "apply config `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru -Wait
    
    if ($applyProcess.ExitCode -ne 0) {
        Write-Host "警告: apply config 执行失败，错误代码: $($applyProcess.ExitCode)" -ForegroundColor Yellow
    } else {
        Write-Host "配置应用成功。" -ForegroundColor Green
    }
    
    # 第二步：start
    Write-Host "正在启动 Mieru 请稍候..." -ForegroundColor Cyan
    $process = Start-Process -FilePath $corePath -ArgumentList "start" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru
    
    # 等待一下确保启动
    Start-Sleep -Seconds 2
    
    if ($process.HasExited) {
        Write-Host "警告: 内核可能启动失败，进程已退出。" -ForegroundColor Yellow
    } else {
        Write-Host "内核已启动 (PID: $($process.Id))" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "内核已启动，按任意键关闭此窗口..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Write-Host "按任意键退出..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
