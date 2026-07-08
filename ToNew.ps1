# ToNew.ps1
# 批量更新不同内核的节点配置文件
# 用法:
#   .\ToNew.ps1                    交互式选择内核，逐一更新
#   .\ToNew.ps1 -Yes               跳过确认，更新全部内核
#   .\ToNew.ps1 -Kernel "hysteria2,singbox"  只更新指定内核
#   .\ToNew.ps1 -Yes -Kernel "hysteria2"     静默更新指定内核
param(
    [switch]$Yes,
    [string]$Kernel = ""
)

$ErrorActionPreference = "Stop"

# ============================================================
# 0. 环境初始化
# ============================================================
$_envScript = Join-Path $PSScriptRoot "_env.ps1"
if (-not (Test-Path $_envScript)) {
    $_envScript = Join-Path (Split-Path $PSScriptRoot -Parent) "_env.ps1"
}
. $_envScript

$ProjectRoot = $env:CHROMEGO_PATH

# 加载 _common.ps1 以复用 IP 提取、国家查询、缓存写入等函数
$_commonScript = Join-Path $ProjectRoot "_common.ps1"
if (Test-Path $_commonScript) {
    . $_commonScript
} else {
    Write-Host "错误: 找不到 _common.ps1，请确认项目路径正确: $ProjectRoot" -ForegroundColor Red
    exit 1
}

# ============================================================
# 1. 内核发现
# ============================================================
function Discover-Kernels {
    $kernels = @()
    $items = Get-ChildItem -Path $ProjectRoot -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $items) {
        # 跳过非内核目录
        $skipDirs = @("Browser", "chrome-user-data", "z0-doc", "z1-cmd", "z2-ps", "ToSB", "ToV2", ".workbuddy")
        if ($dir.Name -in $skipDirs) { continue }
        
        $ipUpdateDir = Join-Path $dir.FullName "ip_Update"
        if (-not (Test-Path $ipUpdateDir)) { continue }
        
        # 统计 ip_Update 下的脚本数量
        $scriptCount = @(Get-ChildItem -Path $ipUpdateDir -Filter "*.bat" -ErrorAction SilentlyContinue).Count
        $scriptCount += @(Get-ChildItem -Path $ipUpdateDir -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
        if ($scriptCount -eq 0) { continue }
        
        $kernels += [PSCustomObject]@{
            Name        = $dir.Name
            Path        = $dir.FullName
            IPUpdateDir = $ipUpdateDir
            NodeCount   = $scriptCount
        }
    }
    return $kernels | Sort-Object Name
}

# ============================================================
# 2. 执行单个内核的批量更新
# 返回: @{ Success = N; Failed = N } 的统计对象
# ============================================================
function Invoke-KernelBatchUpdate {
    param(
        [Parameter(Mandatory=$true)]
        $Kernel
    )
    
    $coreName = $Kernel.Name
    $coreDir = $Kernel.Path
    $ipUpdateDir = $Kernel.IPUpdateDir
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  [$coreName] 开始批量更新节点" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # 扫描 ip_Update 下的脚本
    $batScripts = @(Get-ChildItem -Path $ipUpdateDir -Filter "*.bat" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $ps1Scripts = @(Get-ChildItem -Path $ipUpdateDir -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $scripts = $batScripts + $ps1Scripts
    
    $successCount = 0
    $failCount = 0
    
    for ($i = 0; $i -lt $scripts.Count; $i++) {
        $scriptName = $scripts[$i]
        $scriptPath = Join-Path $ipUpdateDir $scriptName
        
        Write-Host ""
        Write-Host "  [$($i+1)/$($scripts.Count)] $scriptName" -ForegroundColor Yellow -NoNewline
        
        $extension = [System.IO.Path]::GetExtension($scriptName).ToLower()
        
        try {
            # 执行脚本
            $scriptDir = Split-Path $scriptPath -Parent
            $exitCode = 0
            
            if ($extension -eq ".bat") {
                $tmpOut = [System.IO.Path]::GetTempFileName()
                $tmpErr = [System.IO.Path]::GetTempFileName()
                
                $proc = Start-Process -FilePath "cmd.exe" `
                    -ArgumentList "/c `"echo.|`"$scriptPath`"`"" `
                    -WorkingDirectory $scriptDir `
                    -NoNewWindow `
                    -PassThru `
                    -RedirectStandardOutput $tmpOut `
                    -RedirectStandardError $tmpErr
                
                $proc.WaitForExit()
                $exitCode = $proc.ExitCode
                
                Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
            } elseif ($extension -eq ".ps1") {
                $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$scriptPath`"" 2>&1
                $result | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) {
                        Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
                    }
                }
                $exitCode = $LASTEXITCODE
            }
            
            if ($exitCode -ne 0) {
                Write-Host "  失败 (exit=$exitCode)" -ForegroundColor Red
                $failCount = $failCount + 1
                continue
            }
            
            # 提取脚本编号
            $index = ""
            if ($scriptName -match 'ip[_\-](\d+)') {
                $index = $Matches[1]
            }
            if (-not $index) {
                Write-Host "  跳过 (无法提取编号)" -ForegroundColor Yellow
                $failCount = $failCount + 1
                continue
            }
            
            # 检测生成的配置文件
            $generatedFile = $null
            $ext = $null
            if (Test-Path (Join-Path $coreDir "config.json")) {
                $generatedFile = Join-Path $coreDir "config.json"
                $ext = "json"
            } elseif (Test-Path (Join-Path $coreDir "config.yaml")) {
                $generatedFile = Join-Path $coreDir "config.yaml"
                $ext = "yaml"
            } elseif (Test-Path (Join-Path $coreDir "client.yaml")) {
                $generatedFile = Join-Path $coreDir "client.yaml"
                $ext = "yaml"
            }
            
            if (-not $generatedFile) {
                Write-Host "  失败 (未生成配置文件)" -ForegroundColor Red
                $failCount = $failCount + 1
                continue
            }
            
            # 重命名为 config_X.*
            $configNewName = "config_$index.$ext"
            $configNewPath = Join-Path $coreDir $configNewName
            Move-Item -Path $generatedFile -Destination $configNewPath -Force
            
            # 提取 server IP 并查询国家
            $serverIP = Get-ConfigServerIP -ConfigPath $configNewPath
            if ($serverIP) {
                $country = Get-IPCountry -IP $serverIP
                if (-not $country) { $country = "N/A" }
                Write-NodeCache -CoreDir $coreDir -ConfigFile $configNewName -Country $country -IP $serverIP
                Write-Host "  OK → $configNewName | $country | $serverIP" -ForegroundColor Green
            } else {
                Write-NodeCache -CoreDir $coreDir -ConfigFile $configNewName -Country "N/A" -IP "?.?.?.?"
                Write-Host "  OK → $configNewName (无法获取IP)" -ForegroundColor Yellow
            }
            
            $successCount = $successCount + 1
            
        } catch {
            Write-Host "  异常: $_" -ForegroundColor Red
            $failCount = $failCount + 1
        }
    }
    
    Write-Host ""
    Write-Host "  [$coreName] 完成: 成功 $successCount / 失败 $failCount" -ForegroundColor $(if ($successCount -gt 0) { "Green" } else { "Yellow" })
    
    return @{ Name = $coreName; Success = $successCount; Failed = $failCount }
}

# ============================================================
# 3. 主流程
# ============================================================
function Main {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ToNew — 批量节点更新工具" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    # 发现内核
    Write-Host "正在扫描内核目录..." -ForegroundColor Gray
    $allKernels = Discover-Kernels
    
    if ($allKernels.Count -eq 0) {
        Write-Host "未找到任何包含 ip_Update/ 目录的内核！" -ForegroundColor Red
        return
    }
    
    # 确定要更新的内核列表
    $selectedKernels = @()
    
    if ($Kernel) {
        # 用户通过 -Kernel 参数指定了内核
        $names = $Kernel -split ',' | ForEach-Object { $_.Trim().ToLower() }
        foreach ($k in $allKernels) {
            if ($k.Name.ToLower() -in $names) {
                $selectedKernels += $k
            }
        }
        if ($selectedKernels.Count -eq 0) {
            Write-Host "错误: 指定的内核未找到或没有 ip_Update/ 目录: $Kernel" -ForegroundColor Red
            Write-Host "可用内核: $($allKernels.Name -join ', ')" -ForegroundColor Gray
            return
        }
    } elseif ($Yes) {
        # -Yes 模式：全部更新
        $selectedKernels = $allKernels
    } else {
        # 交互模式：让用户选择
        Write-Host "发现以下内核（含 ip_Update 节点脚本）:" -ForegroundColor Gray
        Write-Host ""
        for ($i = 0; $i -lt $allKernels.Count; $i++) {
            Write-Host "  [$($i+1)] $($allKernels[$i].Name)  ($($allKernels[$i].NodeCount) 个节点)" -ForegroundColor Cyan
        }
        Write-Host "  [A] 全部更新 ($($allKernels.Count) 个内核)" -ForegroundColor Yellow
        Write-Host "  [Q] 退出" -ForegroundColor Red
        Write-Host ""
        
        $choice = Read-Host "请选择内核 [1-$($allKernels.Count), A=全部, Q=退出]"
        
        if ($choice -eq 'q' -or $choice -eq 'Q') {
            Write-Host "已取消。" -ForegroundColor Gray
            return
        }
        
        if ($choice -eq 'a' -or $choice -eq 'A') {
            $selectedKernels = $allKernels
        } elseif ($choice -match '^\d+$') {
            $num = [int]$choice
            if ($num -ge 1 -and $num -le $allKernels.Count) {
                $selectedKernels = @($allKernels[$num - 1])
            } else {
                Write-Host "无效选择！" -ForegroundColor Red
                return
            }
        } else {
            Write-Host "无效选择！" -ForegroundColor Red
            return
        }
    }
    
    # 显示更新计划
    Write-Host ""
    Write-Host "即将更新以下内核的节点配置:" -ForegroundColor White
    $totalNodes = 0
    foreach ($k in $selectedKernels) {
        Write-Host "  - $($k.Name) ($($k.NodeCount) 个节点)" -ForegroundColor Cyan
        $totalNodes = $totalNodes + $k.NodeCount
    }
    Write-Host "  总计: $($selectedKernels.Count) 个内核, $totalNodes 个节点" -ForegroundColor Gray
    Write-Host ""
    
    if (-not $Yes) {
        $confirm = Read-Host "确认开始更新? [Y/N]"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "已取消。" -ForegroundColor Gray
            return
        }
    }
    
    # 执行批量更新
    $results = @()
    foreach ($k in $selectedKernels) {
        $result = Invoke-KernelBatchUpdate -Kernel $k
        $results += $result
    }
    
    # 汇总报告
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  更新汇总" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    $totalSuccess = 0
    $totalFailed = 0
    foreach ($r in $results) {
        $status = if ($r.Failed -eq 0) { "OK" } else { "$($r.Failed) 失败" }
        Write-Host "  $($r.Name): 成功 $($r.Success), 失败 $($r.Failed)" -ForegroundColor $(if ($r.Failed -eq 0) { "Green" } else { "Yellow" })
        $totalSuccess = $totalSuccess + $r.Success
        $totalFailed = $totalFailed + $r.Failed
    }
    
    Write-Host "  ────────────────────" -ForegroundColor DarkGray
    Write-Host "  总计: 成功 $totalSuccess, 失败 $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Yellow" })
    Write-Host ""
    
    if (-not $Yes) {
        Press-AnyKey -Message "按任意键退出..."
    }
}

Main
