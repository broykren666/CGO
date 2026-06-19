# 设置控制台编码为 UTF-8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 936 > $null

# 切换到脚本所在目录
Set-Location -Path $PSScriptRoot

# 引入公共函数库
. "$PSScriptRoot\Common.ps1"

# 检查管理员权限（若非管理员则自动提权重启）
Ensure-Admin -ScriptPath $PSCommandPath

# 设置控制台标题
$Host.UI.RawUI.WindowTitle = "Psiphon 一键翻墙"

# ==================== 配置常量（请根据实际情况修改） ====================
# 内核目录（相对于脚本所在目录）
$CORE_DIR = "psiphon"
# 内核程序文件名
$CORE_EXE = "psiphon3.exe"
# ======================================================================

# 主程序
try {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "    Psiphon 一键翻墙脚本" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    # 检查内核文件是否存在
    $corePath = Join-Path $PSScriptRoot (Join-Path $CORE_DIR $CORE_EXE)
    
    if (-not (Test-Path $corePath)) {
        Write-Host "错误: 内核文件不存在: $CORE_EXE" -ForegroundColor Red
        Write-Host "请检查 CORE_EXE 配置是否正确" -ForegroundColor Red
        Write-Host "按任意键退出..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    
    # 二次确认启动
    if (-not (Confirm-Launch -CoreName "Psiphon ($CORE_EXE)")) {
        Write-Host "按任意键退出..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 0
    }

    # 启动 psiphon3.exe
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $process = Start-Process -FilePath $corePath -WorkingDirectory $workingDir -WindowStyle Normal -PassThru
    
    Write-Host "start..." -ForegroundColor Gray
    
    # 执行 setting.vbs（等待完成）
    $vbsPath = Join-Path $workingDir "setting.vbs"
    if (Test-Path $vbsPath) {
        Write-Host "正在执行 setting.vbs..." -ForegroundColor Cyan
        Start-Process -FilePath "wscript.exe" -ArgumentList "`"$vbsPath`"" -WorkingDirectory $workingDir -Wait
    } else {
        Write-Host "警告: setting.vbs 不存在: $vbsPath" -ForegroundColor Yellow
    }
    
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
