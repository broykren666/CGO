# Update-Cores.ps1 - 代理内核批量更新工具
#requires -Version 5.1

<#
.SYNOPSIS
    代理内核批量更新工具 - 列出版本、比对最新、交互式更新

.DESCRIPTION
    扫描所有代理内核的当前版本号，查询 GitHub 最新 Release 版本，
    显示版本对比表，支持交互式选择更新。更新时自动备份旧内核(.bak 后缀)。

.NOTES
    将此脚本放在与内核目录同级的目录下运行（如 ChromeGo/），
    若放在子目录（如 z2-ps/），脚本会自动向上查找。
    版本: 1.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

# ==================== 内核注册表 ====================

$KernelDefs = @(
    @{
        Name         = "Xray"
        Dir          = "Xray"
        Exe          = "xray.exe"
        VerArgs      = "-version"
        VerRegex     = "Xray\s+(\S+)"
        Repo         = "XTLS/Xray-core"
        IsArchive    = $true
        # 各架构在 GitHub Release 资产中的命名
        ArchNames    = @{ "amd64" = "64"; "386" = "32" }
        ExeInZip     = "xray.exe"
        AssetExcludes = @()
        Skip         = $false
    },
    @{
        Name         = "SingBox"
        Dir          = "singbox"
        Exe          = "sing-box.exe"
        VerArgs      = "version"
        VerRegex     = "version\s+([\d.]+)"
        Repo         = "SagerNet/sing-box"
        IsArchive    = $true
        ArchNames    = @{ "amd64" = "amd64"; "386" = "386" }
        ExeInZip     = "sing-box.exe"
        AssetExcludes = @()
        Skip         = $false
    },
    @{
        Name         = "Hysteria2"
        Dir          = "hysteria2"
        Exe          = "hysteria2.exe"
        VerArgs      = "version"
        VerRegex     = "Version:\s+v?([\d.]+)"
        Repo         = "apernet/hysteria"
        IsArchive    = $false
        ArchNames    = @{ "amd64" = "amd64"; "386" = "386" }
        ExeInZip     = ""
        AssetExcludes = @("-avx")  # 排除 AVX 优化变体
        Skip         = $false
    }
    @{
        Name         = "Hysteria"
        Dir          = "hysteria"
        Exe          = "hysteria-tun-windows-6.0-386.exe"
        VerArgs      = "--version"
        VerRegex     = "version\s+v?([\d.]+)"
        Repo         = ""
        IsArchive    = $false
        ArchNames    = @{}
        ExeInZip     = ""
        AssetExcludes = @()
        Skip         = $true
        SkipReason   = "已停更 (v1 EOL)"
    },
    @{
        Name         = "ClashMeta"
        Dir          = "clash.meta"
        Exe          = "clash.meta-windows-386.exe"
        VerArgs      = "-v"
        VerRegex     = "Meta\s+v?([\d.]+)"
        Repo         = "MetaCubeX/mihomo"
        IsArchive    = $true
        ArchNames    = @{ "amd64" = "amd64"; "386" = "386" }
        ExeInZip     = ""           # 动态搜索 zip 内的 exe
        AssetExcludes = @("compatible", "-v\d+-", "-go\d+")  # 排除变体版本
        Skip         = $false
    },
    @{
        Name         = "Mieru"
        Dir          = "mieru"
        Exe          = "mieru.exe"
        VerArgs      = "version"
        VerRegex     = "^([\d.]+)$"
        Repo         = "enfein/mieru"
        IsArchive    = $true
        ArchNames    = @{ "amd64" = "amd64"; "386" = "x86" }
        ExeInZip     = "mieru.exe"
        AssetExcludes = @()
        Skip         = $false
    },
    @{
        Name         = "Juicity"
        Dir          = "juicity"
        Exe          = "juicity-client.exe"
        VerArgs      = "-v"
        VerRegex     = "version\s+v?([\d.]+)"
        Repo         = "juicity/juicity"
        IsArchive    = $true
        ArchNames    = @{ "amd64" = "x86_64" }  # 注意: 无 386 构建
        ExeInZip     = ""           # 动态搜索 zip 内的 exe
        AssetExcludes = @()
        Skip         = $false
    },
    @{
        Name         = "NaiveProxy"
        Dir          = "naiveproxy"
        Exe          = "naive.exe"
        VerArgs      = "--version"
        VerRegex     = "naive\s+(\S+)"
        Repo         = "klzgrad/naiveproxy"
        IsArchive    = $true
        ArchNames    = @{ "amd64" = "x64"; "386" = "x86" }
        ExeInZip     = "naive.exe"
        AssetExcludes = @()
        Skip         = $false
    },
    @{
        Name         = "ShadowQuic"
        Dir          = "shadowquic"
        Exe          = "shadowquic.exe"
        VerArgs      = "--version"
        VerRegex     = "shadowquic\s+([\d.]+)"
        Repo         = "spongebob888/shadowquic"
        IsArchive    = $false
        ArchNames    = @{ "amd64" = "x86_64" }  # 注意: 无 386 构建
        ExeInZip     = ""
        AssetExcludes = @()
        Skip         = $false
    },
    @{
        Name         = "Psiphon"
        Dir          = "psiphon"
        Exe          = "psiphon3.exe"
        VerArgs      = ""
        VerRegex     = ""
        Repo         = ""
        IsArchive    = $false
        ArchNames    = @{}
        ExeInZip     = ""
        AssetExcludes = @()
        Skip         = $true
        SkipReason   = "闭源软件, 无 GitHub Release"
    }
)

# ==================== 自动检测基础目录 ====================
# 脚本应放在与内核目录同级的目录下运行
# 若放在子目录（如 z2-ps/），自动向上查找父目录

$BaseDir = $PSScriptRoot
$foundAnyDir = $false
foreach ($def in $KernelDefs) {
    if (-not $def.Skip -and (Test-Path (Join-Path $BaseDir $def.Dir))) {
        $foundAnyDir = $true
        break
    }
}
if (-not $foundAnyDir) {
    $parentDir = Split-Path $BaseDir -Parent
    foreach ($def in $KernelDefs) {
        if (-not $def.Skip -and (Test-Path (Join-Path $parentDir $def.Dir))) {
            $foundAnyDir = $true
            break
        }
    }
    if ($foundAnyDir) { $BaseDir = $parentDir }
}

# ==================== 函数区 ====================

# ------------------------------------------------------------
# Get-SystemArch: 检测操作系统架构
# ------------------------------------------------------------
function Get-SystemArch {
    if ([System.Environment]::Is64BitOperatingSystem) { return "amd64" }
    return "386"
}

# ------------------------------------------------------------
# Get-ExeArch: 从版本输出或文件名推断 exe 架构
# ------------------------------------------------------------
function Get-ExeArch {
    param([string]$VerOutput, [string]$ExeFilename)

    # 优先从版本输出中解析
    $archFromOutput = @(
        @{ R = "windows/amd64";  A = "amd64" },
        @{ R = "windows/386";    A = "386"   },
        @{ R = "windows\s+amd64"; A = "amd64" },
        @{ R = "windows\s+386";   A = "386"   },
        @{ R = "Architecture.*amd64"; A = "amd64" },
        @{ R = "Architecture.*386";   A = "386"   }
    )
    foreach ($p in $archFromOutput) {
        if ($VerOutput -match $p.R) { return $p.A }
    }

    # 从文件名推断
    if ($ExeFilename -match "-amd64")                   { return "amd64" }
    if ($ExeFilename -match "-386|-x86|-32[^a]")        { return "386"   }
    if ($ExeFilename -match "-64[^a]" -and $ExeFilename -notmatch "arm64") { return "amd64" }

    # 兜底: 使用系统架构
    return Get-SystemArch
}

# ------------------------------------------------------------
# Resolve-DownloadArch: 确定下载时使用的架构
# 优先匹配当前 exe 架构, 若该架构无对应资产则回退
# ------------------------------------------------------------
function Resolve-DownloadArch {
    param([string]$ExeArch, [hashtable]$ArchNames)

    if ($ArchNames.ContainsKey($ExeArch)) { return $ExeArch }

    $sysArch = Get-SystemArch
    if ($ArchNames.ContainsKey($sysArch)) { return $sysArch }

    # 取首个可用的架构
    if ($ArchNames.Count -gt 0) { return $ArchNames.Keys[0] }
    return ""
}

# ------------------------------------------------------------
# Get-CurrentVersion: 执行内核版本命令, 解析版本号
# ------------------------------------------------------------
function Get-CurrentVersion {
    param([hashtable]$KernelDef)

    $exePath = Join-Path $BaseDir (Join-Path $KernelDef.Dir $KernelDef.Exe)

    if (-not (Test-Path $exePath)) {
        return @{ Version = ""; Output = ""; Found = $false; Arch = "" }
    }

    if ($KernelDef.VerArgs -eq "") {
        return @{ Version = "N/A"; Output = ""; Found = $true; Arch = "" }
    }

    try {
        $output = & $exePath $KernelDef.VerArgs 2>&1 | Out-String
        if ($output -match $KernelDef.VerRegex) {
            $ver   = $Matches[1]
            $arch  = Get-ExeArch -VerOutput $output -ExeFilename $KernelDef.Exe
            return @{ Version = $ver; Output = $output; Found = $true; Arch = $arch }
        }
        return @{ Version = "解析失败"; Output = $output; Found = $true; Arch = "" }
    } catch {
        return @{ Version = "执行失败"; Output = ""; Found = $true; Arch = "" }
    }
}

# ------------------------------------------------------------
# Get-LatestRelease: 查询 GitHub API 获取最新 Release
# ------------------------------------------------------------
function Get-LatestRelease {
    param([string]$Repo)

    if ([string]::IsNullOrWhiteSpace($Repo)) {
        return @{ Tag = ""; Version = ""; Assets = @(); Error = "无仓库" }
    }

    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"

    try {
        $resp = Invoke-RestMethod -Uri $apiUrl -Method Get `
            -Headers @{ "User-Agent" = "Update-Cores/1.0" } -TimeoutSec 30

        # 从 tag_name 提取纯版本号
        $tag = $resp.tag_name
        $ver = $tag -replace "^app/", "" -replace "^v", ""
        # NaiveProxy 等特殊格式: v149.0.7827.114-1 → 149.0.7827.114
        $ver = $ver -replace "-\d+$", ""

        $assets = @($resp.assets | ForEach-Object {
            @{ Name = $_.name; Url = $_.browser_download_url; Size = $_.size }
        })

        return @{ Tag = $tag; Version = $ver; Assets = $assets; Error = "" }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "403") { $msg = "API 限流 (每小时60次)" }
        return @{ Tag = ""; Version = ""; Assets = @(); Error = "查询失败: $msg" }
    }
}

# ------------------------------------------------------------
# Find-AssetUrl: 从 Release 资产列表中匹配正确的下载 URL
# ------------------------------------------------------------
function Find-AssetUrl {
    param([hashtable]$KernelDef, [string]$Arch, [array]$Assets)

    if ($Assets.Count -eq 0) {
        return @{ Url = ""; Name = ""; Error = "无可用资产" }
    }

    $archName = ""
    if ($KernelDef.ArchNames.ContainsKey($Arch)) {
        $archName = $KernelDef.ArchNames[$Arch]
    }
    if ([string]::IsNullOrWhiteSpace($archName)) {
        return @{ Url = ""; Name = ""; Error = "架构 [$Arch] 无可用构建" }
    }

    # 筛选含 win/windows + 架构标识的资产
    # NaiveProxy 等使用 "win" 而非 "windows"，需兼容两种命名
    $candidates = @($Assets | Where-Object {
        $_.Name -match "win" -and $_.Name -match $archName
    })

    # 应用排除规则
    foreach ($exclude in $KernelDef.AssetExcludes) {
        if (-not [string]::IsNullOrWhiteSpace($exclude)) {
            $candidates = @($candidates | Where-Object { $_.Name -notmatch $exclude })
        }
    }

    if ($candidates.Count -eq 0) {
        return @{ Url = ""; Name = ""; Error = "未找到 Windows $Arch 资产" }
    }

    $asset = $candidates[0]
    return @{ Url = $asset.Url; Name = $asset.Name; Error = "" }
}

# ------------------------------------------------------------
# Compare-Versions: 比较两个版本号 (返回 -1/0/1)
# ------------------------------------------------------------
function Compare-Versions {
    param([string]$V1, [string]$V2)

    $v1 = $V1 -replace "^v", ""
    $v2 = $V2 -replace "^v", ""

    if ([string]::IsNullOrWhiteSpace($v1) -or [string]::IsNullOrWhiteSpace($v2)) { return 0 }
    if ($v1 -notmatch "^[\d.]+" -or $v2 -notmatch "^[\d.]+") { return 0 }

    $p1 = $v1 -split "\."
    $p2 = $v2 -split "\."
    $max = [Math]::Max($p1.Length, $p2.Length)

    for ($i = 0; $i -lt $max; $i++) {
        $n1 = if ($i -lt $p1.Length) { [int]$p1[$i] } else { 0 }
        $n2 = if ($i -lt $p2.Length) { [int]$p2[$i] } else { 0 }
        if ($n1 -lt $n2) { return -1 }
        if ($n1 -gt $n2) { return  1 }
    }
    return 0
}

# ------------------------------------------------------------
# Test-CoreRunning: 检查内核进程是否正在运行
# ------------------------------------------------------------
function Test-CoreRunning {
    param([string]$ExeName)

    $procName = $ExeName -replace "\.exe$", ""
    $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
    return ($null -ne $proc -and $proc.Count -gt 0)
}

# ------------------------------------------------------------
# Backup-And-Update: 备份旧内核 + 下载 + 解压/安装 + 验证
# ------------------------------------------------------------
function Backup-And-Update {
    param(
        [hashtable]$KernelDef,
        [string]$AssetUrl,
        [string]$AssetName,
        [string]$DownloadArch
    )

    $exePath   = Join-Path $BaseDir (Join-Path $KernelDef.Dir $KernelDef.Exe)
    $kernelDir = Join-Path $BaseDir $KernelDef.Dir
    $bakPath   = $exePath + ".bak"
    $tempDir   = Join-Path $env:TEMP "UpdateCores_$(Get-Random)"

    # 检查进程是否运行
    if (Test-CoreRunning -ExeName $KernelDef.Exe) {
        Write-Host "  ✗ 内核正在运行, 请先关闭后再更新" -ForegroundColor Red
        return $false
    }

    # 创建临时目录
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # ── 步骤 1: 备份旧内核 ──
        if (Test-Path $exePath) {
            if (Test-Path $bakPath) { Remove-Item $bakPath -Force }
            Rename-Item -Path $exePath -NewName ($KernelDef.Exe + ".bak")
            Write-Host "  [备份] $($KernelDef.Exe) → $($KernelDef.Exe).bak" -ForegroundColor DarkYellow
        }

        # ── 步骤 2: 下载 ──
        $dlPath = Join-Path $tempDir $AssetName
        Write-Host "  [下载] $AssetName ..." -ForegroundColor Cyan -NoNewline

        Invoke-WebRequest -Uri $AssetUrl -OutFile $dlPath `
            -UseBasicParsing -TimeoutSec 180

        $sizeMB = [Math]::Round((Get-Item $dlPath).Length / 1MB, 2)
        Write-Host " 完成 ($sizeMB MB)" -ForegroundColor Green

        # ── 步骤 3: 解压 / 安装 ──
        if ($KernelDef.IsArchive) {
            $extractDir = Join-Path $tempDir "extracted"
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

            # 根据压缩格式选择解压方式
            if ($AssetName -match "\.zip$") {
                Expand-Archive -Path $dlPath -DestinationPath $extractDir -Force
            } elseif ($AssetName -match "\.tar\.gz$|\.tgz$") {
                tar -xzf $dlPath -C $extractDir 2>$null
            } elseif ($AssetName -match "\.tar\.xz$") {
                tar -xJf $dlPath -C $extractDir 2>$null
            }

            # 在解压目录中查找 exe 文件
            $exeFiles = @(Get-ChildItem -Path $extractDir -Filter "*.exe" -Recurse)
            if ($exeFiles.Count -eq 0) {
                throw "解压后未找到 .exe 文件"
            }

            # 选择正确的 exe
            $newExe = $null

            # 优先使用 ExeInZip 指定名称
            if ($KernelDef.ExeInZip -ne "") {
                $newExe = $exeFiles | Where-Object { $_.Name -eq $KernelDef.ExeInZip } | Select-Object -First 1
            }

            # 其次按内核名匹配
            if ($null -eq $newExe) {
                $pattern = $KernelDef.Name -replace "\.", ""
                $newExe = $exeFiles | Where-Object {
                    $_.Name -match $pattern -or $_.Name -match "client"
                } | Select-Object -First 1
            }

            # 兜底取第一个
            if ($null -eq $newExe) { $newExe = $exeFiles[0] }

            # 复制到内核目录, 保持原始 exe 文件名
            Copy-Item -Path $newExe.FullName -Destination $exePath -Force
            Write-Host "  [安装] $($newExe.Name) → $($KernelDef.Exe)" -ForegroundColor Green

        } else {
            # 直接 exe 下载, 重命名安装
            Copy-Item -Path $dlPath -Destination $exePath -Force
            Write-Host "  [安装] $AssetName → $($KernelDef.Exe)" -ForegroundColor Green
        }

        # ── 步骤 4: 验证新版本 ──
        $newVer = Get-CurrentVersion -KernelDef $KernelDef
        if ($newVer.Found -and $newVer.Version -notmatch "失败|解析") {
            Write-Host "  [验证] 当前版本: $($newVer.Version)" -ForegroundColor Green
        } else {
            Write-Host "  [验证] 无法确认新版本号 (文件已替换)" -ForegroundColor Yellow
        }

        return $true

    } catch {
        Write-Host "  ✗ 更新失败: $_" -ForegroundColor Red

        # 尝试恢复备份
        if (Test-Path $bakPath) {
            if (Test-Path $exePath) { Remove-Item $exePath -Force -ErrorAction SilentlyContinue }
            Rename-Item -Path $bakPath -NewName $KernelDef.Exe
            Write-Host "  ↩ 已恢复备份" -ForegroundColor Yellow
        }
        return $false

    } finally {
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ==================== UI 函数 ====================

# ------------------------------------------------------------
# Show-Banner: 显示工具横幅和系统信息
# ------------------------------------------------------------
function Show-Banner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║       代理内核批量更新工具  v1.0             ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $sysArch = Get-SystemArch
    $archLabel = if ($sysArch -eq "amd64") { "64位 (AMD64)" } else { "32位 (x86)" }
    Write-Host "  系统架构: " -NoNewline -ForegroundColor Gray
    Write-Host $archLabel -ForegroundColor Green
    Write-Host "  内核目录: " -NoNewline -ForegroundColor Gray
    Write-Host $BaseDir -ForegroundColor Green
    Write-Host ""
}

# ------------------------------------------------------------
# Show-StatusTable: 显示内核版本对比表
# ------------------------------------------------------------
function Show-StatusTable {
    param([array]$Results)

    # 列宽定义
    $W = @{ Name = 12; Cur = 15; Lat = 15; Status = 14 }

    $hLine = "  $("─" * $W.Name)$("─" * $W.Cur)$("─" * $W.Lat)$("─" * $W.Status)"

    Write-Host "  $("─" * ($W.Name + $W.Cur + $W.Lat + $W.Status + 6))" -ForegroundColor DarkGray

    # 表头
    Write-Host "  " -NoNewline
    Write-Host "$("内核".PadRight($W.Name)) " -NoNewline -ForegroundColor White
    Write-Host "$("当前版本".PadRight($W.Cur)) " -NoNewline -ForegroundColor White
    Write-Host "$("最新版本".PadRight($W.Lat)) " -NoNewline -ForegroundColor White
    Write-Host "$("状态".PadRight($W.Status))" -ForegroundColor White

    Write-Host $hLine -ForegroundColor DarkGray

    # 数据行
    foreach ($r in $Results) {
        $cur = if ($r.CurrentVersion -ne "") { $r.CurrentVersion } else { "-" }
        $lat = if ($r.LatestVersion -ne "")  { $r.LatestVersion  } else { "-" }

        # 状态
        $status     = ""
        $statusClr  = [ConsoleColor]::White

        if ($r.Skip) {
            $status    = $r.SkipReason
            $statusClr = [ConsoleColor]::DarkGray
        } elseif ([string]::IsNullOrWhiteSpace($r.CurrentVersion)) {
            $status    = "未安装"
            $statusClr = [ConsoleColor]::DarkGray
        } elseif ($r.CurrentVersion -match "失败|解析|N/A") {
            # 当前版本无法确定时, 若有最新版本则标记为可尝试更新
            if (-not [string]::IsNullOrWhiteSpace($r.LatestVersion)) {
                $status    = "版本未知 ↑"
                $statusClr = [ConsoleColor]::Yellow
            } else {
                $status    = "版本未知"
                $statusClr = [ConsoleColor]::DarkGray
            }
        } elseif ([string]::IsNullOrWhiteSpace($r.LatestVersion)) {
            $status    = "查询失败"
            $statusClr = [ConsoleColor]::Red
        } elseif ($r.VersionCompare -eq 0) {
            $status    = "已最新 ✓"
            $statusClr = [ConsoleColor]::Green
        } elseif ($r.VersionCompare -lt 0) {
            $status    = "可更新 ↑"
            $statusClr = [ConsoleColor]::Yellow
        } else {
            $status    = "已最新 ✓"
            $statusClr = [ConsoleColor]::Green
        }

        Write-Host "  " -NoNewline
        Write-Host "$($r.Name.PadRight($W.Name)) " -NoNewline -ForegroundColor White
        Write-Host "$($cur.PadRight($W.Cur)) "    -NoNewline -ForegroundColor Cyan
        Write-Host "$($lat.PadRight($W.Lat)) "     -NoNewline -ForegroundColor Green
        Write-Host "$($status.PadRight($W.Status))" -ForegroundColor $statusClr
    }

    Write-Host "  $("─" * ($W.Name + $W.Cur + $W.Lat + $W.Status + 6))" -ForegroundColor DarkGray
    Write-Host ""
}

# ==================== 主流程 ====================

Show-Banner

# ── 扫描所有内核 ──
Write-Host "  正在扫描内核版本..." -ForegroundColor Cyan
$scanResults = @()

foreach ($def in $KernelDefs) {
    $curInfo = Get-CurrentVersion -KernelDef $def
    $latestInfo = Get-LatestRelease -Repo $def.Repo

    # 确定下载架构
    $exeArch = if ($curInfo.Arch -ne "") { $curInfo.Arch } else { Get-SystemArch }
    $dlArch  = Resolve-DownloadArch -ExeArch $exeArch -ArchNames $def.ArchNames

    # 查找下载资产
    $assetInfo = if (-not [string]::IsNullOrWhiteSpace($def.Repo) -and $latestInfo.Assets.Count -gt 0) {
        Find-AssetUrl -KernelDef $def -Arch $dlArch -Assets $latestInfo.Assets
    } else {
        @{ Url = ""; Name = ""; Error = "" }
    }

    # 版本比较
    $cmp = Compare-Versions -V1 $curInfo.Version -V2 $latestInfo.Version

    $skipReason = ""
    if ($def.Skip) { $skipReason = $def.SkipReason }

    $scanResults += @{
        Name           = $def.Name
        KernelDef      = $def
        CurrentVersion = $curInfo.Version
        CurrentArch    = $curInfo.Arch
        DownloadArch   = $dlArch
        LatestVersion  = $latestInfo.Version
        LatestTag      = $latestInfo.Tag
        VersionCompare = $cmp
        AssetUrl       = $assetInfo.Url
        AssetName      = $assetInfo.Name
        AssetError     = $assetInfo.Error
        Skip           = $def.Skip
        SkipReason     = $skipReason
        ApiError       = $latestInfo.Error
    }
}

Show-StatusTable -Results $scanResults

# ── 过滤可更新的内核 ──
# 条件: 非跳过 + 有最新版本 + 有下载URL + (当前版本落后 或 当前版本未知)
$updatable = @($scanResults | Where-Object {
    -not $_.Skip -and
    -not [string]::IsNullOrWhiteSpace($_.LatestVersion) -and
    -not [string]::IsNullOrWhiteSpace($_.AssetUrl) -and
    (
        $_.VersionCompare -lt 0 -or
        $_.CurrentVersion -match "失败|解析|N/A|未知"
    )
})

if ($updatable.Count -eq 0) {
    Write-Host "  没有需要更新的内核。所有内核已是最新版本或不可更新。" -ForegroundColor Green
    Write-Host ""
    Read-Host "按 Enter 键退出"
    exit 0
}

# ── 显示更新菜单 ──
Write-Host "  可更新的内核:" -ForegroundColor Yellow
Write-Host ""

$menuIdx = 1
foreach ($item in $updatable) {
    $archTag = if ($item.DownloadArch -ne "") { " [$($item.DownloadArch)]" } else { "" }
    Write-Host "  [" -NoNewline -ForegroundColor Cyan
    Write-Host "$menuIdx" -NoNewline -ForegroundColor Cyan
    Write-Host "] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($item.Name)$archTag" -NoNewline -ForegroundColor White
    Write-Host "  $($item.CurrentVersion)" -NoNewline -ForegroundColor Cyan
    Write-Host " → " -NoNewline -ForegroundColor Yellow
    Write-Host "$($item.LatestVersion)" -ForegroundColor Green
    $menuIdx++
}

Write-Host ""
Write-Host "  [A] 全部更新" -ForegroundColor Cyan
Write-Host "  [Q] 退出"     -ForegroundColor DarkGray
Write-Host ""

$choice = Read-Host "请选择 (编号 / A / Q)"

if ($choice -match "^q$") { exit 0 }

# ── 确定要更新的列表 ──
$toUpdate = @()

if ($choice -match "^a$") {
    $toUpdate = $updatable
} else {
    $indices = @($choice -split "[,;\s]+" | Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ })
    foreach ($idx in $indices) {
        if ($idx -ge 1 -and $idx -le $updatable.Count) {
            $toUpdate += $updatable[$idx - 1]
        }
    }
}

if ($toUpdate.Count -eq 0) {
    Write-Host "  未选择任何内核, 退出。" -ForegroundColor Yellow
    exit 0
}

# ── 确认 ──
Write-Host ""
Write-Host "  确认更新以下内核?" -ForegroundColor Yellow
foreach ($item in $toUpdate) {
    Write-Host "    * $($item.Name): $($item.CurrentVersion) → $($item.LatestVersion)" -ForegroundColor White
}
Write-Host ""

$confirm = Read-Host "确认更新? (Y/N)"
if ($confirm -notmatch "^y$") {
    Write-Host "  已取消。" -ForegroundColor Yellow
    exit 0
}

# ── 执行更新 ──
Write-Host ""
Write-Host "  ════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  开始更新..." -ForegroundColor Cyan
Write-Host ""

$success = 0
$fail    = 0

foreach ($item in $toUpdate) {
    Write-Host "  ── $($item.Name) ──" -ForegroundColor Cyan

    $ok = Backup-And-Update -KernelDef $item.KernelDef `
        -AssetUrl $item.AssetUrl -AssetName $item.AssetName `
        -DownloadArch $item.DownloadArch

    if ($ok) { $success++ } else { $fail++ }
    Write-Host ""
}

# ── 总结 ──
Write-Host "  ════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  更新完成: 成功 " -NoNewline -ForegroundColor Green
Write-Host "$success" -NoNewline -ForegroundColor Green
Write-Host " 个, 失败 " -NoNewline -ForegroundColor Red
Write-Host "$fail" -NoNewline -ForegroundColor Red
Write-Host " 个" -ForegroundColor White
Write-Host ""

Read-Host "按 Enter 键退出"
