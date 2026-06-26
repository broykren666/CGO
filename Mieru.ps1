. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Mieru 一键翻墙" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "mieru"
$CORE_EXE = "mieru.exe"
$CORE_NAME = "Mieru"
# ======================================================================

try {
    Show-Banner -Title "Mieru 一键翻墙脚本"
    
    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME
    if ($null -eq $selectedConfig) { Press-AnyKey; exit 0 }

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    # 启动内核（mieru 需要先 apply config 再 start，两步操作）
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $configPath = Join-Path $workingDir $selectedConfig

    # 第一步：apply config
    Write-Host "正在应用 Mieru 配置..." -ForegroundColor Cyan
    $applyProcess = Start-Process -FilePath $corePath -ArgumentList "apply config `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru -Wait

    if ($applyProcess.ExitCode -ne 0) {
        Write-Host "警告: apply config 执行失败，错误代码: $($applyProcess.ExitCode)" -ForegroundColor Yellow
    } else {
        Write-Host "配置应用成功。" -ForegroundColor Green
    }

    # 第二步：start
    Write-Host "正在启动 Mieru 请稍候..." -ForegroundColor Cyan
    $process = Start-Process -FilePath $corePath -ArgumentList "start" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
