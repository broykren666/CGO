. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Hysteria 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "hysteria"
$CORE_EXE = "hysteria-tun-windows-6.0-386.exe"
$IP_UPDATE_DIR = Join-Path $PSScriptRoot (Join-Path $CORE_DIR "ip_Update")
# ======================================================================

try {
    Show-Banner -Title "Hysteria 一键启动脚本"
    Invoke-IPUpdate -IPUpdateDir $IP_UPDATE_DIR

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    if (-not (Confirm-Launch -CoreName "Hysteria ($CORE_EXE)")) {
        Press-AnyKey; exit 0
    }

    # 启动内核
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $configPath = Join-Path $workingDir "config.json"
    $process = Start-Process -FilePath $corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
