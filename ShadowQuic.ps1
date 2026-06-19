. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Shadowquic 一键翻墙" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "shadowquic"
$CORE_EXE = "shadowquic.exe"
$IP_UPDATE_DIR = Join-Path $PSScriptRoot (Join-Path $CORE_DIR "ip_Update")
# ======================================================================

try {
    Show-Banner -Title "Shadowquic 一键翻墙脚本"
    Invoke-IPUpdate -IPUpdateDir $IP_UPDATE_DIR

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    if (-not (Confirm-Launch -CoreName "ShadowQuic ($CORE_EXE)")) {
        Press-AnyKey; exit 0
    }

    # 启动内核（shadowquic 使用 client.yaml 配置文件）
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $configPath = Join-Path $workingDir "client.yaml"
    $process = Start-Process -FilePath $corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
