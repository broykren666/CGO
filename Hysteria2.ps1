. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Hysteria2 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "hysteria2"
$CORE_EXE = "hysteria2.exe"
$CORE_NAME = "Hysteria2"
# ======================================================================

try {   
    $_psRoot = "$PSScriptRoot"
    $_coreDir = "$CORE_DIR"
    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME
    if ($null -eq $selectedConfig) { Press-AnyKey; exit 0 }

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    # 启动内核
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $_psRoot $_coreDir
    $configPath = Join-Path $workingDir $selectedConfig
    $process = Start-Process -FilePath $corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
