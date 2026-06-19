. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Juicity 一键翻墙" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "juicity"
$CORE_EXE = "juicity-client.exe"
$IP_UPDATE_DIR = Join-Path $PSScriptRoot (Join-Path $CORE_DIR "ip_Update")
# ======================================================================

try {
    Show-Banner -Title "Juicity 一键翻墙脚本"
    Invoke-IPUpdate -IPUpdateDir $IP_UPDATE_DIR

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    if (-not (Confirm-Launch -CoreName "Juicity ($CORE_EXE)")) {
        Press-AnyKey; exit 0
    }

    # 启动内核（juicity 参数格式：juicity-client.exe run -c config.json）
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $configPath = Join-Path $workingDir "config.json"
    $process = Start-Process -FilePath $corePath -ArgumentList "run -c `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
