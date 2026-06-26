. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Shadowquic 一键翻墙" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "shadowquic"
$CORE_EXE = "shadowquic.exe"
$CORE_NAME = "ShadowQuic"
# ======================================================================

try {
    Show-Banner -Title "Shadowquic 一键翻墙脚本"
    
    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME
    if ($null -eq $selectedConfig) { Press-AnyKey; exit 0 }

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    # 启动内核
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $configPath = Join-Path $workingDir $selectedConfig
    $process = Start-Process -FilePath $corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
