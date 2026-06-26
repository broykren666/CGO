. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Juicity 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "juicity"
$CORE_EXE = "juicity-client.exe"
$CORE_NAME = "Juicity"
# ======================================================================

try {   
    # 提前保存路径变量快照，防止 Invoke-NodeMenu 调用后自动变量或脚本变量被意外清空
    $_psRoot = "$PSScriptRoot"
    $_coreDir = "$CORE_DIR"

    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME
    if ($null -eq $selectedConfig) { Press-AnyKey; exit 0 }

    $corePath = Test-CoreFile -CoreDir $_coreDir -CoreExe $CORE_EXE

    # 启动内核（juicity 参数格式：juicity-client.exe run -c config.json）
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $_psRoot $_coreDir
    $configPath = Join-Path $workingDir $selectedConfig
    $process = Start-Process -FilePath $corePath -ArgumentList "run -c `"$configPath`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
