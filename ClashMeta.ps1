. "$PSScriptRoot\Common.ps1"
Initialize-Script -Title "Clash.Meta 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量（请根据实际情况修改） ====================
$CORE_DIR = "clash.meta"
$CORE_EXE = "clash.meta-windows-386.exe"
$CORE_NAME = "Clash.Meta"
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

    # 启动内核（clash.meta 使用 -d 指定工作目录，自动读取 config.yaml）
    # 将选中的 config_X.yaml 复制为 config.yaml
    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $configSrc = [IO.Path]::Combine($_workDir, $selectedConfig)
    $configDst = [IO.Path]::Combine($_workDir, "config.yaml")

    if (-not (Test-Path $configSrc)) { Write-Host "错误: 配置文件不存在 — $configSrc" -ForegroundColor Red; Press-AnyKey; exit 1 }

    Copy-Item -Path $configSrc -Destination $configDst -Force
    $process = Start-Process -FilePath $_corePath -ArgumentList "-d `"$_workDir`"" -WorkingDirectory $_workDir -WindowStyle Normal -PassThru

    Wait-CoreStart -Process $process

} catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
    exit 1
}
