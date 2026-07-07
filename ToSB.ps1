# ToSB.ps1
# 将 Hysteria v1/v2、ClashMeta、SingBox 节点配置转换为统一的 SingBox 格式
# 输出目录由 $Script:OutputDirName 变量控制（默认 "ToSB"）

$ErrorActionPreference = "Stop"
$Script:OutputDirName = "ToSB"          # 输出目录名，改这里即可
$script:PythonExe = $null

# ============================================================
# 0. 环境初始化
# ============================================================
$_envScript = Join-Path $PSScriptRoot "_env.ps1"
if (-not (Test-Path $_envScript)) {
    $_envScript = Join-Path (Split-Path $PSScriptRoot -Parent) "_env.ps1"
}
. $_envScript

$ProjectRoot = $env:CHROMEGO_PATH

# 端口配置
$DefaultListenPort = 1080      # 单个节点配置文件使用的监听端口
$MergedStartPort   = 22001     # 合并文件 config_999.json 的起始监听端口

# ============================================================
# 1. Python 环境检测 & PyYAML 安装
# ============================================================
function Find-Python {
    $managed = "C:\Users\xinji\.workbuddy\binaries\python\versions\3.13.12\python.exe"
    if (Test-Path $managed) { return $managed }
    $sys = Get-Command python -ErrorAction SilentlyContinue
    if ($sys) { return $sys.Source }
    $sys = Get-Command python3 -ErrorAction SilentlyContinue
    if ($sys) { return $sys.Source }
    throw "未找到 Python，请安装 Python 后再运行此脚本。"
}

function Ensure-PyYAML {
    param([string]$PyExe)
    $result = & $PyExe -c "import yaml; print('OK')" 2>&1
    if ($result -eq 'OK') { return }
    Write-Host "正在安装 PyYAML..." -ForegroundColor Yellow
    $null = & $PyExe -m pip install pyyaml -q 2>&1
    Write-Host "PyYAML 安装完成。" -ForegroundColor Green
}

$script:PythonExe = Find-Python
Ensure-PyYAML -PyExe $script:PythonExe

# ============================================================
# 2. 工具函数
# ============================================================

# 拆分 host:port（支持 IPv6 [::1]:8080）
function Split-HostPort {
    param([string]$HostPort)
    if ($HostPort -match '^\[(.+)\]:(\d+)$') {
        return @{ host = $Matches[1]; port = [int]$Matches[2] }
    }
    $idx = $HostPort.LastIndexOf(':')
    if ($idx -le 0) { return $null }
    return @{
        host = $HostPort.Substring(0, $idx)
        port = [int]$HostPort.Substring($idx + 1)
    }
}

# 解析带宽字符串 "11 Mbps" / "11 mbps" → 11
function Parse-Bandwidth {
    param([string]$BW)
    if (-not $BW) { return 0 }
    if ($BW -match '^\s*(\d+(?:\.\d+)?)') { return [int][double]$Matches[1] }
    return 0
}

# 生成节点 tag（用于 SingBox route.final）
function New-NodeTag {
    param([string]$Protocol, [string]$Server, [int]$Port)
    return "$Protocol-$($Server)-$Port"
}

# 净化 tag 中的特殊字符（/ \ : . → -，用于合并文件防冲突）
function Sanitize-Tag {
    param([string]$Tag)
    $clean = $Tag -replace '[\/\\: ]+', '-'
    # 合并连续的 -
    while ($clean -match '--') {
        $clean = $clean -replace '--', '-'
    }
    # 去掉首尾 -
    return $clean.Trim('-')
}

# 自定义 JSON 序列化（保持 [ordered] 字段顺序）
function ConvertTo-OrderedJson {
    param($Object, [int]$Depth = 10, [int]$Indent = 0)
    $pad = " " * ($Indent * 2)
    $pad1 = " " * (($Indent + 1) * 2)

    if ($null -eq $Object) { return "null" }

    if ($Object -is [bool]) {
        return $Object.ToString().ToLower()
    }

    if ($Object -is [string]) {
        $escaped = $Object.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')
        return '"' + $escaped + '"'
    }

    if ($Object -is [int] -or $Object -is [long] -or $Object -is [double] -or $Object -is [decimal]) {
        return $Object.ToString()
    }

    if ($Object -is [array] -or $Object -is [System.Collections.ArrayList]) {
        $items = @()
        foreach ($item in $Object) {
            $val = ConvertTo-OrderedJson -Object $item -Depth ($Depth - 1) -Indent ($Indent + 1)
            $items += "$pad1$val"
        }
        if ($items.Count -eq 0) { return "[]" }
        return "[`n$($items -join ",`n")`n$pad]"
    }

    # Hashtable / OrderedDictionary / PSCustomObject
    $enumerator = if ($Object -is [System.Collections.IDictionary]) {
        $Object.GetEnumerator()
    } else {
        $Object.PSObject.Properties
    }

    $lines = @()
    foreach ($p in $enumerator) {
        if ($p -is [System.Collections.DictionaryEntry]) {
            $key = $p.Key; $val = $p.Value
        } else {
            $key = $p.Name; $val = $p.Value
        }
        $valJson = ConvertTo-OrderedJson -Object $val -Depth ($Depth - 1) -Indent ($Indent + 1)
        $lines += "$pad1`"$key`": $valJson"
    }

    if ($lines.Count -eq 0) { return "{}" }
    return "{`n$($lines -join ",`n")`n$pad}"
}

# ============================================================
# 3. SingBox 模板生成
# ============================================================

function New-SingBoxConfig {
    param(
        [PSCustomObject]$Outbound,
        [string]$Tag,
        [int]$ListenPort = $DefaultListenPort,
        [string]$InboundTag = "mixed-in"
    )
    $config = [ordered]@{
        inbounds  = @(
            [ordered]@{
                type             = "mixed"
                tag              = $InboundTag
                listen           = "::"
                listen_port      = $ListenPort
                set_system_proxy = $false
            }
        )
        outbounds = @(
            $Outbound,
            [ordered]@{
                type = "direct"
                tag  = "direct"
            }
        )
        route     = [ordered]@{
            rules = @(
                [ordered]@{
                    inbound = $InboundTag
                    action  = "sniff"
                }
            )
            final = $Tag
        }
    }
    return $config
}

# ============================================================
# 4. Hysteria v1 JSON → SingBox Outbound
# ============================================================

function Convert-Hysteria1ToSB {
    param([string]$FilePath)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hp = Split-HostPort -HostPort $json.server
    if (-not $hp) { throw "无法解析 Hysteria v1 server 字段: $($json.server)" }

    $tag = New-NodeTag -Protocol "hysteria1" -Server $hp.host -Port $hp.port

    $outbound = [ordered]@{
        type        = "hysteria"
        tag         = $tag
        server      = $hp.host
        server_port = $hp.port
        up_mbps     = [int]$json.up_mbps
        down_mbps   = [int]$json.down_mbps
        auth_str    = $json.auth_str
        tls         = [ordered]@{
            enabled     = $true
            server_name = $json.server_name
            insecure    = [bool]$json.insecure
        }
    }

    # ALPN: 字符串 → 数组
    if ($json.alpn) {
        if ($json.alpn -is [array]) {
            $outbound.tls.alpn = @($json.alpn)
        } else {
            $outbound.tls.alpn = @($json.alpn.ToString())
        }
    }

    # 混淆
    if ($json.obfs -and $json.obfs -ne '') {
        $outbound.obfs = $json.obfs
    }

    # QUIC 参数
    if ($json.PSObject.Properties['recv_window_conn']) {
        $outbound.recv_window_conn = [int]$json.recv_window_conn
    }
    if ($json.PSObject.Properties['recv_window']) {
        $outbound.recv_window = [int]$json.recv_window
    }
    if ($json.PSObject.Properties['disable_mtu_discovery']) {
        $outbound.disable_mtu_discovery = [bool]$json.disable_mtu_discovery
    }

    return @{ Outbound = $outbound; Tag = $tag }
}

# ============================================================
# 5. Hysteria v2 JSON → SingBox Outbound
# ============================================================

function Convert-Hysteria2ToSB {
    param([string]$FilePath)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hp = Split-HostPort -HostPort $json.server
    if (-not $hp) { throw "无法解析 Hysteria v2 server 字段: $($json.server)" }

    $tag = New-NodeTag -Protocol "hysteria2" -Server $hp.host -Port $hp.port

    $outbound = [ordered]@{
        type        = "hysteria2"
        tag         = $tag
        server      = $hp.host
        server_port = $hp.port
        password    = $json.auth
        tls         = [ordered]@{
            enabled     = $true
            server_name = $json.tls.sni
            insecure    = [bool]$json.tls.insecure
        }
    }

    # 带宽
    if ($json.bandwidth) {
        $outbound.up_mbps   = Parse-Bandwidth -BW $json.bandwidth.up
        $outbound.down_mbps = Parse-Bandwidth -BW $json.bandwidth.down
    }

    return @{ Outbound = $outbound; Tag = $tag }
}

# ============================================================
# 6. ClashMeta YAML → SingBox Outbound（通过 Python 解析）
# ============================================================

function Convert-ClashMetaToSB {
    param([string]$FilePath)

    # 用 Python 解析 YAML 并提取 proxies 数组为 JSON
    $pyScript = @"
import sys, json
try:
    import yaml
except ImportError:
    print(json.dumps({"error": "PyYAML not installed"}))
    sys.exit(1)

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    content = f.read()

# ClashMeta 配置文件可能有重复的 YAML 文档（多次 append）
# 只解析第一个文档
docs = list(yaml.safe_load_all(content))
if not docs:
    print(json.dumps({"error": "empty YAML"}))
    sys.exit(1)

data = docs[0]
proxies = data.get('proxies', [])

# 只保留 SingBox 支持的协议类型
supported = {'hysteria', 'hysteria2', 'tuic', 'anytls'}
filtered = [p for p in proxies if p.get('type', '') in supported]
print(json.dumps(filtered, ensure_ascii=False))
"@

    $pyOutput = & $script:PythonExe -c $pyScript $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Python YAML 解析失败: $pyOutput"
    }

    $proxies = $pyOutput | ConvertFrom-Json
    if (-not $proxies -or $proxies.Count -eq 0) {
        throw "ClashMeta 文件中没有可转换的代理节点"
    }

    # ClashMeta 每个 YAML 文件只有一个 proxy
    $proxy = if ($proxies -is [array]) { $proxies[0] } else { $proxies }
    $proxyType = $proxy.type

    # 从 ClashMeta 转换为 SingBox outbound
    $outbound = $null; $tag = $null;

    switch ($proxyType) {
        'hysteria2' {
            $tag = New-NodeTag -Protocol "hysteria2-cm" -Server $proxy.server -Port $proxy.port
            $outbound = [ordered]@{
                type        = "hysteria2"
                tag         = $tag
                server      = $proxy.server
                server_port = [int]$proxy.port
                password    = $proxy.password
                up_mbps     = Parse-Bandwidth -BW $proxy.up
                down_mbps   = Parse-Bandwidth -BW $proxy.down
                tls         = [ordered]@{
                    enabled     = $true
                    server_name = $proxy.sni
                    insecure    = [bool]$proxy.'skip-cert-verify'
                }
            }
        }
        'hysteria' {
            $tag = New-NodeTag -Protocol "hysteria-cm" -Server $proxy.server -Port $proxy.port
            $outbound = [ordered]@{
                type        = "hysteria"
                tag         = $tag
                server      = $proxy.server
                server_port = [int]$proxy.port
                auth_str    = $proxy.'auth-str'
                up_mbps     = Parse-Bandwidth -BW $proxy.up
                down_mbps   = Parse-Bandwidth -BW $proxy.down
                tls         = [ordered]@{
                    enabled     = $true
                    server_name = $proxy.sni
                    insecure    = [bool]$proxy.'skip-cert-verify'
                }
            }
            # ALPN
            if ($proxy.alpn) {
                if ($proxy.alpn -is [array]) {
                    $outbound.tls.alpn = @($proxy.alpn)
                } else {
                    $outbound.tls.alpn = @($proxy.alpn.ToString())
                }
            }
        }
        'tuic' {
            $tag = New-NodeTag -Protocol "tuic-cm" -Server $proxy.server -Port $proxy.port
            $outbound = [ordered]@{
                type               = "tuic"
                tag                = $tag
                server             = $proxy.server
                server_port        = [int]$proxy.port
                uuid               = $proxy.uuid
                password           = $proxy.password
                congestion_control = if ($proxy.'congestion-controller') { $proxy.'congestion-controller' } else { "bbr" }
                tls                = [ordered]@{
                    enabled     = $true
                    server_name = $proxy.sni
                    insecure    = [bool]$proxy.'skip-cert-verify'
                }
            }
            # ALPN
            if ($proxy.alpn) {
                if ($proxy.alpn -is [array]) {
                    $outbound.tls.alpn = @($proxy.alpn)
                } else {
                    $outbound.tls.alpn = @($proxy.alpn.ToString())
                }
            }
        }
        'anytls' {
            $tag = New-NodeTag -Protocol "anytls-cm" -Server $proxy.server -Port $proxy.port
            $outbound = [ordered]@{
                type        = "anytls"
                tag         = $tag
                server      = $proxy.server
                server_port = [int]$proxy.port
                password    = $proxy.password
                tls         = [ordered]@{
                    enabled     = $true
                    server_name = $proxy.sni
                    insecure    = [bool]$proxy.'skip-cert-verify'
                }
            }
            if ($proxy.alpn) {
                if ($proxy.alpn -is [array]) {
                    $outbound.tls.alpn = @($proxy.alpn)
                } else {
                    $outbound.tls.alpn = @($proxy.alpn.ToString())
                }
            }
        }
        default {
            throw "不支持的 ClashMeta 代理类型: $proxyType"
        }
    }

    return @{ Outbound = $outbound; Tag = $tag }
}

# ============================================================
# 7. SingBox JSON → 直接复制
# ============================================================

function Convert-SingBoxToSB {
    param([string]$FilePath)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $outbounds = $json.outbounds
    $proxy = $null

    # 找到第一个非 direct/block/dns 的 outbound
    foreach ($ob in $outbounds) {
        if ($ob.type -notin @('direct', 'block', 'dns')) {
            $proxy = $ob
            break
        }
    }
    if (-not $proxy) { throw "SingBox 配置中未找到代理出站" }

    $tag = $proxy.tag
    $outbound = [ordered]@{}
    $proxy.PSObject.Properties | ForEach-Object { $outbound[$_.Name] = $_.Value }

    return @{ Outbound = $outbound; Tag = $tag }
}

# ============================================================
# 8. 扫描源目录
# ============================================================

$sources = [ordered]@{
    "SingBox"     = @{
        Dir     = [IO.Path]::Combine($ProjectRoot, "singbox")
        Pattern = "config_*.json"
        Type    = "singbox"
    }
    "ClashMeta"   = @{
        Dir     = [IO.Path]::Combine($ProjectRoot, "clash.meta")
        Pattern = "config_*.yaml"
        Type    = "clashmeta"
    }
    "Hysteria v1" = @{
        Dir     = [IO.Path]::Combine($ProjectRoot, "hysteria")
        Pattern = "config_*.json"
        Type    = "hysteria1"
    }
    "Hysteria v2" = @{
        Dir     = [IO.Path]::Combine($ProjectRoot, "hysteria2")
        Pattern = "config_*.json"
        Type    = "hysteria2"
    }
}

$allFiles = [System.Collections.ArrayList]@()
foreach ($srcName in $sources.Keys) {
    $info = $sources[$srcName]
    $dirPath = $info.Dir
    if (-not (Test-Path $dirPath)) {
        Write-Host "[警告] 目录不存在，跳过: $dirPath" -ForegroundColor DarkYellow
        continue
    }
    $files = Get-ChildItem -Path $dirPath -Filter $info.Pattern -File | Sort-Object Name
    foreach ($f in $files) {
        # 排除合并输出文件（防止被意外当作源文件）
        if ($f.Name -eq "config_999.json") { continue }
        $null = $allFiles.Add(@{
            Source     = $srcName
            SourcePath = $f.FullName
            FileName   = $f.Name
            Type       = $info.Type
        })
    }
}

if ($allFiles.Count -eq 0) {
    Write-Host "未找到任何配置文件，退出。" -ForegroundColor Red
    exit 0
}

# 读取每个来源目录的 .node_cache（格式: config_X.json|国家|IP）
$nodeCache = @{}
foreach ($srcName in $sources.Keys) {
    $cacheFile = [IO.Path]::Combine($sources[$srcName].Dir, ".node_cache")
    if (-not (Test-Path $cacheFile)) { continue }
    $lines = Get-Content $cacheFile -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '') { continue }
        $parts = $trimmed -split '\|', 3
        if ($parts.Length -lt 3) { continue }
        $nodeCache[$parts[0]] = @{ Country = $parts[1]; IP = $parts[2] }
    }
}

# ============================================================
# 9. 列出待转换文件
# ============================================================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "               ToSB - 节点配置转换工具                   " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$globalCount = 0
foreach ($srcName in $sources.Keys) {
    $srcFiles = $allFiles | Where-Object { $_.Source -eq $srcName }
    if ($srcFiles.Count -eq 0) { continue }
    Write-Host " [$srcName]  ($($srcFiles.Count) 个文件)" -ForegroundColor Yellow
    Write-Host " ├─ $($sources[$srcName].Dir)" -ForegroundColor DarkGray
    foreach ($f in $srcFiles) {
        $globalCount++
        $cacheInfo = ""
        if ($nodeCache.ContainsKey($f.FileName)) {
            $ci = $nodeCache[$f.FileName]
            $cacheInfo = "  [$($ci.Country)] $($ci.IP)"
        }
        Write-Host " │  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($f.FileName)" -ForegroundColor White -NoNewline
        Write-Host $cacheInfo -ForegroundColor DarkGray
    }
    Write-Host " └─" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host " 输出目录: $([IO.Path]::Combine($ProjectRoot, $Script:OutputDirName))" -ForegroundColor Green
Write-Host " 文件总计: $globalCount 个文件待转换" -ForegroundColor Green
Write-Host ""

# ============================================================
# 10. 用户确认
# ============================================================

$confirm = Read-Host "确认开始转换? (Y/n)"
if ($confirm -ne '' -and $confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "已取消。" -ForegroundColor Red
    exit 0
}

# ============================================================
# 11. 执行转换
# ============================================================

$outDir = [IO.Path]::Combine($ProjectRoot, $Script:OutputDirName)

# 清空或创建输出目录
if (Test-Path $outDir) {
    Write-Host "`n清理旧输出目录..." -ForegroundColor DarkGray
    Remove-Item -Path "$outDir\*" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    $null = New-Item -ItemType Directory -Path $outDir -Force
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  开始转换..." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$idx = 1
$okCount = 0
$failCount = 0
$sourceToOutput = @{}  # 源文件路径 -> 输出 config_N.json
$allResults = [System.Collections.ArrayList]@()  # 用于生成 config_999.json

foreach ($f in $allFiles) {
    $outName = "config_$idx.json"
    $outPath = [IO.Path]::Combine($outDir, $outName)
    $sourceLabel = "$($f.Source)/$($f.FileName)"

    try {
        $result = $null
        switch ($f.Type) {
            "hysteria1" { $result = Convert-Hysteria1ToSB -FilePath $f.SourcePath }
            "hysteria2" { $result = Convert-Hysteria2ToSB -FilePath $f.SourcePath }
            "clashmeta" { $result = Convert-ClashMetaToSB -FilePath $f.SourcePath }
            "singbox"   { $result = Convert-SingBoxToSB -FilePath $f.SourcePath }
            default     { throw "未知来源类型: $($f.Type)" }
        }

        $config = New-SingBoxConfig -Outbound $result.Outbound -Tag $result.Tag

        # 自定义 JSON 序列化：保持字段顺序，2 空格缩进
        $jsonStr = ConvertTo-OrderedJson -Object $config
        [System.IO.File]::WriteAllText($outPath, $jsonStr, [System.Text.UTF8Encoding]::new($false))

        $sourceToOutput[$f.SourcePath] = $outName
        $null = $allResults.Add($result)

        $protocol = $result.Outbound.type
        Write-Host "  [$idx] OK  $sourceLabel  ->  $outName  ($protocol)" -ForegroundColor Green
        $okCount++
    }
    catch {
        Write-Host "  [$idx] FAIL  $sourceLabel  ->  $outName" -ForegroundColor Red
        Write-Host "         错误: $($_.Exception.Message)" -ForegroundColor DarkRed
        $failCount++
    }
    $idx++
}

# ============================================================
# 12. 合并 .node_cache
# ============================================================

$mergedCache = [System.Text.StringBuilder]::new()

foreach ($srcName in $sources.Keys) {
    $cacheFile = [IO.Path]::Combine($sources[$srcName].Dir, ".node_cache")
    if (-not (Test-Path $cacheFile)) { continue }

    $lines = Get-Content $cacheFile -Encoding UTF8
    $dirPath = $sources[$srcName].Dir

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '') { continue }

        # 格式: 原始文件名|国家|IP
        $parts = $trimmed -split '\|', 3
        if ($parts.Length -lt 3) { continue }

        $origName   = $parts[0]
        $country    = $parts[1]
        $ip         = $parts[2]
        $origPath   = [IO.Path]::Combine($dirPath, $origName)

        if ($sourceToOutput.ContainsKey($origPath)) {
            $newName = $sourceToOutput[$origPath]
            $null = $mergedCache.AppendLine("$newName|$country|$ip")
        }
        else {
            Write-Host "  [警告] .node_cache 中找不到对应输出: $srcName / $origName" -ForegroundColor DarkYellow
        }
    }
}

if ($mergedCache.Length -gt 0) {
    $cacheOut = [IO.Path]::Combine($outDir, ".node_cache")
    [System.IO.File]::WriteAllText($cacheOut, $mergedCache.ToString(), [System.Text.UTF8Encoding]::new($false))
    $cacheLines = ($mergedCache.ToString() -split "`n" | Where-Object { $_ -ne '' }).Count
    Write-Host "  .node_cache: $cacheLines 条已合并输出" -ForegroundColor Green
}
else {
    Write-Host "  .node_cache: 无内容可合并" -ForegroundColor DarkYellow
}

# ============================================================
# 13. 生成 map.log 映射记录
# ============================================================

$mapLog = [System.Text.StringBuilder]::new()
$null = $mapLog.AppendLine("ToSB 转换映射记录")
$null = $mapLog.AppendLine("生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $mapLog.AppendLine("")

foreach ($srcName in $sources.Keys) {
    $null = $mapLog.AppendLine("──────────────────────────────────────────")
    $null = $mapLog.AppendLine("  $srcName")
    $null = $mapLog.AppendLine("──────────────────────────────────────────")

    $srcFiles = $allFiles | Where-Object { $_.Source -eq $srcName }
    foreach ($f in $srcFiles) {
        if ($sourceToOutput.ContainsKey($f.SourcePath)) {
            $newName = $sourceToOutput[$f.SourcePath]
            $null = $mapLog.AppendLine("  $($f.FileName)  ->  $newName")
        }
        else {
            $null = $mapLog.AppendLine("  $($f.FileName)  ->  (转换失败)")
        }
    }
    $null = $mapLog.AppendLine("")
}

$mapOut = [IO.Path]::Combine($outDir, "map.log")
[System.IO.File]::WriteAllText($mapOut, $mapLog.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "  map.log: 映射记录已生成" -ForegroundColor Green

# ============================================================
# 14. 生成合并节点文件 config_999.json
# ============================================================

if ($allResults.Count -gt 0) {
    $mergedInbounds  = [System.Collections.ArrayList]@()
    $mergedOutbounds = [System.Collections.ArrayList]@()
    $mergedRules     = [System.Collections.ArrayList]@()
    $seenTags        = @{}  # 去重：tag → 出现次数

    for ($i = 0; $i -lt $allResults.Count; $i++) {
        $port       = $MergedStartPort + $i
        $inTag      = "in-$($i + 1)"
        $outTag     = Sanitize-Tag -Tag $allResults[$i].Tag
        $outbound   = $allResults[$i].Outbound

        # 去重：如果 tag 已存在，追加序号
        if ($seenTags.ContainsKey($outTag)) {
            $seenTags[$outTag] = $seenTags[$outTag] + 1
            $outTag = "$outTag-$($seenTags[$outTag])"
        }
        else {
            $seenTags[$outTag] = 1
        }

        # 克隆 outbound 并替换 tag（避免修改原始对象影响单个文件）
        $cloned = [ordered]@{}
        if ($outbound -is [System.Collections.IDictionary]) {
            foreach ($k in $outbound.Keys) { $cloned[$k] = $outbound[$k] }
        }
        else {
            $outbound.PSObject.Properties | ForEach-Object { $cloned[$_.Name] = $_.Value }
        }
        $cloned['tag'] = $outTag

        # 每个节点一个独立 inbound
        $null = $mergedInbounds.Add([ordered]@{
            type             = "mixed"
            tag              = $inTag
            listen           = "::"
            listen_port      = $port
            set_system_proxy = $false
        })

        # 出站（tag 已去重）
        $null = $mergedOutbounds.Add($cloned)

        # 路由规则：该 inbound → 对应 outbound
        $null = $mergedRules.Add([ordered]@{
            inbound  = $inTag
            outbound = $outTag
        })
    }

    # 加 direct 兜底
    $null = $mergedOutbounds.Add([ordered]@{
        type = "direct"
        tag  = "direct"
    })

    $mergedConfig = [ordered]@{
        inbounds  = $mergedInbounds
        outbounds = $mergedOutbounds
        route     = [ordered]@{
            rules = $mergedRules
            final = "direct"
        }
    }

    $mergedPath = [IO.Path]::Combine($outDir, "config_999.json")
    $mergedJson = ConvertTo-OrderedJson -Object $mergedConfig
    [System.IO.File]::WriteAllText($mergedPath, $mergedJson, [System.Text.UTF8Encoding]::new($false))

    $startPort = $MergedStartPort
    $endPort   = $MergedStartPort + $allResults.Count - 1
    Write-Host "  config_999.json: $($allResults.Count) 个节点合并, 端口 $startPort~$endPort" -ForegroundColor Green
}

# ============================================================
# 15. 输出汇总
# ============================================================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  转换完成!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  成功: $okCount  失败: $failCount  总计: $($okCount + $failCount)" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "  输出目录: $outDir" -ForegroundColor Green
Write-Host ""
$null = Read-Host "按回车键退出..."
