. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Clash.Meta 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "clash.meta"
$CORE_EXE = "clash.meta-windows-386.exe"
$IP_UPDATE_DIR = Join-Path $PSScriptRoot (Join-Path $CORE_DIR "ip_Update")
# ======================================================================

try {
    Show-Banner -Title "Clash.Meta 一键启动脚本"
    Invoke-IPUpdate -IPUpdateDir $IP_UPDATE_DIR

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    if (-not (Confirm-Launch -CoreName "Clash.Meta ($CORE_EXE)")) {
        Press-AnyKey; exit 0
    }

    # 启动内核（clash.meta 使用 -d 指定工作目录）
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
    $process = Start-Process -FilePath $corePath -ArgumentList "-d `"$workingDir`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
