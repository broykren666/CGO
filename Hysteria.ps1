. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Hysteria 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "hysteria"
$CORE_EXE = "hysteria-tun-windows-6.0-386.exe"
$CORE_NAME = "Hysteria"
# ======================================================================

# 预计算路径 — 用 [IO.Path]::Combine 替代 Join-Path，彻底避免 Clear-Host 后参数绑定异常
$_workDir = [IO.Path]::Combine($PSScriptRoot, $CORE_DIR)
$_corePath = [IO.Path]::Combine($_workDir, $CORE_EXE)

try {   
    if (-not (Test-Path $_corePath)) {
        Write-Host "错误: 内核文件不存在: $CORE_EXE ($_corePath)" -ForegroundColor Red
        Press-AnyKey; exit 1
    }

    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME -ScriptRoot "$PSScriptRoot"
    if ($null -eq $selectedConfig -or $selectedConfig -eq '') { Press-AnyKey; exit 0 }

    # 启动内核
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $configPath = [IO.Path]::Combine($_workDir, $selectedConfig)

    if (-not (Test-Path $configPath)) { Write-Host "错误: 配置文件不存在 — $configPath" -ForegroundColor Red; Press-AnyKey; exit 1 }

    $process = Start-Process -FilePath $_corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $_workDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
