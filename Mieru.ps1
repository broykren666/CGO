. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Mieru 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "mieru"
$CORE_EXE = "mieru.exe"
$CORE_NAME = "Mieru"
# ======================================================================

# 预计算路径 — 用 [IO.Path]::Combine 替代 Join-Path，彻底避免 Clear-Host 后参数绑定异常
$_workDir = [IO.Path]::Combine($PSScriptRoot, $CORE_DIR)
$_corePath = [IO.Path]::Combine($_workDir, $CORE_EXE)

try {    
    if (-not (Test-Path $_corePath)) {
        Write-Host "错误: 内核文件不存在: $CORE_EXE ($_corePath)" -ForegroundColor Red
        Press-AnyKey; exit 1
    }

    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME -ScriptRoot "$PSScriptRoot"
    if ($null -eq $selectedConfig -or $selectedConfig -eq '') { Press-AnyKey; exit 0 }

    # 启动内核（mieru 需要先 apply config 再 start，两步操作）
    $configPath = [IO.Path]::Combine($_workDir, $selectedConfig)

    if (-not (Test-Path $configPath)) { Write-Host "错误: 配置文件不存在 — $configPath" -ForegroundColor Red; Press-AnyKey; exit 1 }

    # 第一步：apply config
    Write-Host "正在应用 Mieru 配置..." -ForegroundColor Cyan
    $applyProcess = Start-Process -FilePath $_corePath -ArgumentList "apply config `"$configPath`"" -WorkingDirectory $_workDir -WindowStyle Normal -PassThru -Wait

    if ($applyProcess.ExitCode -ne 0) {
        Write-Host "警告: apply config 执行失败，错误代码: $($applyProcess.ExitCode)" -ForegroundColor Yellow
    } else {
        Write-Host "配置应用成功。" -ForegroundColor Green
    }

    # 第二步：start
    Write-Host "正在启动 Mieru 请稍候..." -ForegroundColor Cyan
    $process = Start-Process -FilePath $_corePath -ArgumentList "start" -WorkingDirectory $_workDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
