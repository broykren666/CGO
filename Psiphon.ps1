. "$PSScriptRoot\_common.ps1"
Initialize-Script -Title "Psiphon 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_NAME = "Psiphon3"
$CORE_DIR = "psiphon"
$CORE_EXE = "psiphon3.exe"
# ======================================================================

try {
    Show-Banner -Title "Psiphon 一键启动"

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    # 启动 psiphon3.exe
    $workingDir = Join-Path $PSScriptRoot $CORE_DIR
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

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
