# 定位 _env.ps1 → 加载 $env:CHROMEGO_PATH（先查脚本所在目录，再查父目录）
$_envScript = Join-Path $PSScriptRoot "_env.ps1"
if (-not (Test-Path $_envScript)) { $_envScript = Join-Path (Split-Path $PSScriptRoot -Parent) "_env.ps1" }
. $_envScript

. (Join-Path $env:CHROMEGO_PATH "Common.ps1")
Initialize-Script -Title "ShadowQuic 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量 ====================
$CORE_DIR = "shadowquic"
$CORE_EXE = "shadowquic.exe"
$CORE_NAME = "ShadowQuic"
# ======================================================================

$_workDir = [IO.Path]::Combine($env:CHROMEGO_PATH, $CORE_DIR)
$_corePath = [IO.Path]::Combine($_workDir, $CORE_EXE)

try {    
    if (-not (Test-Path $_corePath)) {
        Write-Host "错误: 内核文件不存在: $CORE_EXE ($_corePath)" -ForegroundColor Red
        Press-AnyKey; exit 1
    }

    $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME -ScriptRoot $env:CHROMEGO_PATH
    if ($null -eq $selectedConfig -or $selectedConfig -eq '') { Press-AnyKey; exit 0 }

    Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Cyan
    $configPath = [IO.Path]::Combine($_workDir, $selectedConfig)
    if (-not (Test-Path $configPath)) {
        Write-Host "错误: 配置文件不存在 — $configPath" -ForegroundColor Red
        Press-AnyKey; exit 1
    }
    $process = Start-Process -FilePath $_corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $_workDir -WindowStyle Normal -PassThru
    Wait-CoreStart -Process $process
    Write-Host "内核已启动，按任意键关闭此窗口..." -ForegroundColor Green
    [Console]::ReadKey($true) | Out-Null
}
catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
}
