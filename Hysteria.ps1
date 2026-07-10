# 定位 _env.ps1 → 加载 $env:CHROMEGO_PATH（先查脚本所在目录，再查父目录）
$_envScript = Join-Path $PSScriptRoot "_env.ps1"
if (-not (Test-Path $_envScript)) { $_envScript = Join-Path (Split-Path $PSScriptRoot -Parent) "_env.ps1" }
. $_envScript

. (Join-Path $env:CHROMEGO_PATH "_common.ps1")
Initialize-Script -Title "Hysteria 一键启动" -ScriptPath $PSCommandPath

# ==================== 配置常量 ====================
$CORE_NAME = "Hysteria"
$CORE_DIR = "hysteria"
$CORE_EXE = "hysteria-tun-windows-6.0-386.exe"
# =================================================

$_workDir = [IO.Path]::Combine($env:CHROMEGO_PATH, $CORE_DIR)
$_corePath = [IO.Path]::Combine($_workDir, $CORE_EXE)

try {
    if (-not (Test-Path $_corePath)) {
        Write-Host "错误: 内核文件不存在: $CORE_EXE ($_corePath)" -ForegroundColor Red
        Press-AnyKey; exit 1
    }

    while ($true) {
        $selectedConfig = Invoke-NodeMenu -CoreDir $CORE_DIR -CoreName $CORE_NAME -ScriptRoot $env:CHROMEGO_PATH
        if ($null -eq $selectedConfig -or $selectedConfig -eq '') { exit 0 }

        $configPath = [IO.Path]::Combine($_workDir, $selectedConfig)
        if (-not (Test-Path $configPath)) {
            Write-Host "错误: 配置文件不存在 — $configPath" -ForegroundColor Red
            Press-AnyKey -Message "按任意键返回..."
            Clear-Host
            continue
        }

        # 启动循环（支持重启）
        while ($true) {
            Write-Host "当前配置 $configPath" -ForegroundColor Yellow
            Write-Host "正在启动 $CORE_EXE 请稍候..." -ForegroundColor Yellow
            $process = Start-Process -FilePath $_corePath -ArgumentList "-c `"$configPath`"" -WorkingDirectory $_workDir -WindowStyle Normal -PassThru
            $success = Wait-CoreStart -Process $process -ConfigPath $configPath

            $action = Show-PostLaunchMenu -Success $success -CoreName $CORE_NAME -ProcessId $process.Id -CoreExeName $CORE_EXE -ConfigPath $configPath -SupportSwitch

            if ($action -eq "switch") {
                if ($success) { Stop-CoreProcess -ProcessId $process.Id -CoreExeName $CORE_EXE }
                Clear-Host
                break
            }
            if ($action -eq "restart") {
                if ($success) { Stop-CoreProcess -ProcessId $process.Id -CoreExeName $CORE_EXE }
                Clear-Host
                continue
            }
            if ($action -eq "quit") {
                exit 0
            }
        }
    }
}
catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
    Press-AnyKey
}
