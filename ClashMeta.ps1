. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Clash.Meta 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "clash.meta"
$CORE_EXE = "clash.meta-windows-386.exe"
$CORE_NAME = "Clash.Meta"
# ======================================================================

try {
    Show-Banner -Title "Clash.Meta 一键启动脚本"
    
    $_psRoot = "$PSScriptRoot"
    $_coreDir = "$CORE_DIR"
    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME
    if ($null -eq $selectedConfig) { Press-AnyKey; exit 0 }

    $corePath = Test-CoreFile -CoreDir $CORE_DIR -CoreExe $CORE_EXE

    # 启动内核（clash.meta 使用 -d 指定工作目录，自动读取 config.yaml）
    # 将选中的 config_X.yaml 复制为 config.yaml
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $workingDir = Join-Path $_psRoot $_coreDir
    $configSrc = Join-Path $workingDir $selectedConfig
    $configDst = Join-Path $workingDir "config.yaml"
    Copy-Item -Path $configSrc -Destination $configDst -Force
    $process = Start-Process -FilePath $corePath -ArgumentList "-d `"$workingDir`"" -WorkingDirectory $workingDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
