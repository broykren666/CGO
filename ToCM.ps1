# ToCM.ps1
# 将 Hysteria v1/v2、Xray(VLESS)、SingBox、ClashMeta 节点配置
# 转换为统一的 ClashMeta YAML 格式（不支持: ShadowQuic / Mieru / Juicity / NaiveProxy / Psiphon）
# 输出目录由 $Script:OutputDirName 变量控制（默认 "ToCM"）

param([switch]$Yes)

$ErrorActionPreference = "Stop"
$Script:OutputDirName = "ToCM"          # 输出目录名，改这里即可
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
    if (-not $HostPort) { return $null }
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

# 解析带宽字符串 "11 Mbps" / "11 mbps" → "11 Mbps"（ClashMeta 格式）
function Format-Bandwidth {
    param([string]$BW)
    if (-not $BW) { return "0 Mbps" }
    if ($BW -match '^\s*(\d+(?:\.\d+)?)\s*(mbps|Mbps)?\s*$') {
        return "$($Matches[1]) Mbps"
    }
    if ($BW -match '^\s*(\d+(?:\.\d+)?)') {
        return "$($Matches[1]) Mbps"
    }
    return "0 Mbps"
}

# 生成 ClashMeta proxy name（前缀-文件名-国家代码）
function Get-ProxyName {
    param([string]$Prefix, [string]$FileName)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $country = ""
    if ($Script:CountryMap.ContainsKey($FileName)) {
        $country = "-" + $Script:CountryMap[$FileName]
    }
    return "$Prefix-$baseName$country"
}

# ============================================================
# 3. Hysteria v1 JSON → ClashMeta proxy [ordered]
# ============================================================

function Convert-Hysteria1ToCM {
    param([string]$FilePath, [string]$SourceName)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hp = Split-HostPort -HostPort $json.server
    if (-not $hp) { throw "无法解析 Hysteria v1 server 字段: $($json.server)" }

    $name = Get-ProxyName -Prefix "HY1" -FileName $SourceName

    $proxy = [ordered]@{
        name             = $name
        type             = "hysteria"
        server           = $hp.host
        port             = $hp.port
        'auth-str'       = $json.auth_str
        up               = Format-Bandwidth -BW $json.up_mbps
        down             = Format-Bandwidth -BW $json.down_mbps
        sni              = $json.server_name
        'skip-cert-verify' = [bool]$json.insecure
        protocol         = $(if ($json.protocol) { $json.protocol } else { "udp" })
    }

    # ALPN: 字符串 → 数组
    if ($json.alpn) {
        if ($json.alpn -is [array]) {
            $proxy.alpn = @($json.alpn)
        } else {
            $proxy.alpn = @($json.alpn.ToString())
        }
    }

    # 混淆
    if ($json.obfs -and $json.obfs -ne '') {
        $proxy.obfs = $json.obfs
    }

    # QUIC 高级参数
    if ($json.PSObject.Properties['recv_window_conn']) {
        $proxy.'recv-window-conn' = [int]$json.recv_window_conn
    }
    if ($json.PSObject.Properties['recv_window']) {
        $proxy.'recv-window' = [int]$json.recv_window
    }
    if ($json.PSObject.Properties['disable_mtu_discovery']) {
        $proxy.'disable-mtu-discovery' = [bool]$json.disable_mtu_discovery
    }

    return @{ Proxy = $proxy; Name = $name; Protocol = "hysteria" }
}

# ============================================================
# 4. Hysteria v2 JSON → ClashMeta proxy [ordered]
# ============================================================

function Convert-Hysteria2ToCM {
    param([string]$FilePath, [string]$SourceName)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hp = Split-HostPort -HostPort $json.server
    if (-not $hp) { throw "无法解析 Hysteria v2 server 字段: $($json.server)" }

    $name = Get-ProxyName -Prefix "HY2" -FileName $SourceName

    $proxy = [ordered]@{
        name              = $name
        type              = "hysteria2"
        server            = $hp.host
        port              = $hp.port
        password          = $json.auth
        sni               = $json.tls.sni
        'skip-cert-verify' = [bool]$json.tls.insecure
    }

    # 带宽
    if ($json.bandwidth) {
        $proxy.up   = Format-Bandwidth -BW $json.bandwidth.up
        $proxy.down = Format-Bandwidth -BW $json.bandwidth.down
    }

    return @{ Proxy = $proxy; Name = $name; Protocol = "hysteria2" }
}

# ============================================================
# 5. Xray (VLESS+REALITY+xhttp) → ClashMeta proxy [ordered]
# ============================================================

function Convert-XrayToCM {
    param([string]$FilePath, [string]$SourceName)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json

    # 找到 VLESS 出站
    $vnext = $null
    foreach ($ob in $json.outbounds) {
        if ($ob.protocol -eq 'vless') {
            $vnext = $ob
            break
        }
    }
    if (-not $vnext) { throw "Xray 配置中未找到 VLESS 出站" }

    $address  = $vnext.settings.vnext[0].address
    $port     = $vnext.settings.vnext[0].port
    $uuid     = $vnext.settings.vnext[0].users[0].id
    $enc      = $vnext.settings.vnext[0].users[0].encryption
    $flow     = $vnext.settings.vnext[0].users[0].flow

    $ss       = $vnext.streamSettings
    $network  = $ss.network
    $security = $ss.security

    $name = Get-ProxyName -Prefix "XV" -FileName $SourceName

    $proxy = [ordered]@{
        name     = $name
        type     = "vless"
        server   = $address
        port     = [int]$port
        uuid     = $uuid
        network  = $network
    }

    # 加密（VLESS 通常为 none，但也可能是自定义值）
    if ($enc -and $enc -ne 'none') {
        $proxy.encryption = $enc
    }

    # flow（xtls-rprx-vision 等）
    if ($flow) {
        $proxy.flow = $flow
    }

    # REALITY 参数
    if ($security -eq 'reality' -and $ss.realitySettings) {
        $rs = $ss.realitySettings
        $proxy.servername = $rs.serverName

        if ($rs.fingerprint) {
            $proxy.'client-fingerprint' = $rs.fingerprint
        }

        $ropts = [ordered]@{}
        if ($rs.publicKey) {
            $ropts.'public-key' = $rs.publicKey
        }
        if ($rs.shortId) {
            $ropts.'short-id' = $rs.shortId
        }
        if ($ropts.Count -gt 0) {
            $proxy.'reality-opts' = $ropts
        }
    }

    # xhttp 参数
    if ($network -eq 'xhttp' -and $ss.xhttpSettings) {
        $xopts = [ordered]@{}
        if ($ss.xhttpSettings.path) {
            $xopts.path = $ss.xhttpSettings.path
        }
        if ($ss.xhttpSettings.mode) {
            $xopts.mode = $ss.xhttpSettings.mode
        }
        if ($xopts.Count -gt 0) {
            $proxy.'xhttp-opts' = $xopts
        }
    }

    return @{ Proxy = $proxy; Name = $name; Protocol = "vless" }
}

# ============================================================
# 6. SingBox JSON → ClashMeta proxy [ordered]
# ============================================================

function Convert-SingBoxToCM {
    param([string]$FilePath, [string]$SourceName)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json

    # 找到第一个非 direct/block/dns 的 outbound
    $proxy = $null
    foreach ($ob in $json.outbounds) {
        if ($ob.type -notin @('direct', 'block', 'dns')) {
            $proxy = $ob
            break
        }
    }
    if (-not $proxy) { throw "SingBox 配置中未找到代理出站" }

    $sbType   = $proxy.type
    $name     = Get-ProxyName -Prefix "SB" -FileName $SourceName

    switch ($sbType) {
        'tuic' {
            $cm = [ordered]@{
                name                  = $name
                type                  = "tuic"
                server                = $proxy.server
                port                  = [int]$proxy.server_port
                uuid                  = $proxy.uuid
                password              = $proxy.password
                'congestion-controller' = $(if ($proxy.congestion_control) { $proxy.congestion_control } else { "bbr" })
                sni                   = $proxy.tls.server_name
                'skip-cert-verify'    = [bool]$proxy.tls.insecure
            }
            # ALPN
            if ($proxy.tls.alpn) {
                if ($proxy.tls.alpn -is [array]) {
                    $cm.alpn = @($proxy.tls.alpn)
                } else {
                    $cm.alpn = @($proxy.tls.alpn.ToString())
                }
            }
            # udp-relay-mode
            if ($proxy.PSObject.Properties['udp_relay_mode']) {
                $cm.'udp-relay-mode' = $proxy.udp_relay_mode
            }
            return @{ Proxy = $cm; Name = $name; Protocol = "tuic" }
        }
        'anytls' {
            $cm = [ordered]@{
                name               = $name
                type               = "anytls"
                server             = $proxy.server
                port               = [int]$proxy.server_port
                password           = $proxy.password
                sni                = $proxy.tls.server_name
                'skip-cert-verify'  = [bool]$proxy.tls.insecure
            }
            if ($proxy.tls.alpn) {
                if ($proxy.tls.alpn -is [array]) {
                    $cm.alpn = @($proxy.tls.alpn)
                } else {
                    $cm.alpn = @($proxy.tls.alpn.ToString())
                }
            }
            return @{ Proxy = $cm; Name = $name; Protocol = "anytls" }
        }
        'hysteria2' {
            $cm = [ordered]@{
                name               = $name
                type               = "hysteria2"
                server             = $proxy.server
                port               = [int]$proxy.server_port
                password           = $proxy.password
                sni                = $proxy.tls.server_name
                'skip-cert-verify'  = [bool]$proxy.tls.insecure
            }
            if ($proxy.PSObject.Properties['up_mbps']) {
                $cm.up = Format-Bandwidth -BW ([string]$proxy.up_mbps)
            }
            if ($proxy.PSObject.Properties['down_mbps']) {
                $cm.down = Format-Bandwidth -BW ([string]$proxy.down_mbps)
            }
            return @{ Proxy = $cm; Name = $name; Protocol = "hysteria2" }
        }
        default {
            throw "不支持的 SingBox 代理类型: $sbType"
        }
    }
}

# ============================================================
# 7. Juicity JSON → ClashMeta proxy [ordered]
# ============================================================

function Convert-JuicityToCM {
    param([string]$FilePath, [string]$SourceName)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hp = Split-HostPort -HostPort $json.server
    if (-not $hp) { throw "无法解析 Juicity server 字段: $($json.server)" }

    $name = Get-ProxyName -Prefix "JC" -FileName $SourceName

    $proxy = [ordered]@{
        name                   = $name
        type                   = "juicity"
        server                 = $hp.host
        port                   = $hp.port
        uuid                   = $json.uuid
        password               = $json.password
        sni                    = $json.sni
        'skip-cert-verify'      = [bool]$json.allow_insecure
        'congestion-controller' = $(if ($json.congestion_control) { $json.congestion_control } else { "bbr" })
    }

    return @{ Proxy = $proxy; Name = $name; Protocol = "juicity" }
}

# ============================================================
# 8. NaiveProxy JSON → ClashMeta proxy [ordered]
# ============================================================

function Convert-NaiveProxyToCM {
    param([string]$FilePath, [string]$SourceName)

    $json = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json

    # proxy URL 格式: https://user:pass@host:port
    $proxyUrl = $json.proxy
    if (-not $proxyUrl) { throw "NaiveProxy 配置中未找到 proxy URL" }

    # 解析 URL
    $uri = [uri]$proxyUrl
    if (-not $uri.Host) { throw "无法解析 NaiveProxy proxy URL: $proxyUrl" }

    $username = ""
    $password = ""
    if ($uri.UserInfo) {
        $parts = $uri.UserInfo -split ':', 2
        $username = [Uri]::UnescapeDataString($parts[0])
        if ($parts.Length -gt 1) {
            $password = [Uri]::UnescapeDataString($parts[1])
        }
    }

    $name = Get-ProxyName -Prefix "NP" -FileName $SourceName

    $proxy = [ordered]@{
        name     = $name
        type     = "naive"
        server   = $uri.Host
        port     = [int]$uri.Port
        username = $username
        password = $password
        protocol = $uri.Scheme
    }

    return @{ Proxy = $proxy; Name = $name; Protocol = "naive" }
}

# ============================================================
# 9. ClashMeta YAML → 直接提取 proxies[0]
# ============================================================

function Convert-ClashMetaToCM {
    param([string]$FilePath, [string]$SourceName)

    # 用 Python 提取 proxies 数组中第一个条目
    $pyScript = @"
import sys, json
try:
    import yaml
except ImportError:
    print(json.dumps({"error": "PyYAML not installed"}))
    sys.exit(1)

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    content = f.read()

# 只解析第一个 YAML 文档（支持多文档文件）
docs = list(yaml.safe_load_all(content))
if not docs:
    print(json.dumps({"error": "empty YAML"}))
    sys.exit(1)

data = docs[0]
proxies = data.get('proxies', [])
if not proxies:
    print(json.dumps({"error": "no proxies found"}))
    sys.exit(1)

# 只取第一个 proxy
proxy = proxies[0]
# 确保 name 存在
if 'name' not in proxy:
    proxy['name'] = 'unnamed'

# 检查协议是否被 ClashMeta 支持
supported = {'hysteria', 'hysteria2', 'tuic', 'vless', 'vmess', 'trojan',
             'shadowsocks', 'ss', 'juicity', 'naive', 'anytls',
             'http', 'socks5', 'wireguard', 'ssh', 'snell'}
if proxy.get('type', '') not in supported:
    print(json.dumps({"error": f"unsupported proxy type: {proxy.get('type', 'unknown')}"}))
    sys.exit(1)

print(json.dumps(proxy, ensure_ascii=False, default=str))
"@

    $pyOutput = & $script:PythonExe -c $pyScript $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Python YAML 解析失败: $pyOutput"
    }

    $proxyJson = $pyOutput | ConvertFrom-Json

    # 检查是否有 error
    if ($proxyJson.error) {
        throw $proxyJson.error
    }

    # 覆盖 name 为统一命名格式，但保留原始 name 作为备注
    $name = Get-ProxyName -Prefix "CM" -FileName $SourceName

    # 构建 [ordered] 代理对象
    $cmProxy = [ordered]@{
        name = $name
    }
    foreach ($prop in $proxyJson.PSObject.Properties) {
        if ($prop.Name -eq 'name') { continue }  # 跳过原始 name
        $cmProxy[$prop.Name] = $prop.Value
    }

    # 确保 type 在第二位
    if ($cmProxy.Keys -contains 'type') {
        $typeVal = $cmProxy['type']
        # 移动 type 到 name 之后：重建 ordered dict
        $newProxy = [ordered]@{ name = $name; type = $typeVal }
        foreach ($k in $cmProxy.Keys) {
            if ($k -ne 'type') {
                $newProxy[$k] = $cmProxy[$k]
            }
        }
        $cmProxy = $newProxy
    }

    return @{ Proxy = $cmProxy; Name = $name; Protocol = $cmProxy.type }
}

# ============================================================
# 10. 扫描源目录
# ============================================================

$sources = [ordered]@{
    "Hysteria v1" = @{
        Dir       = [IO.Path]::Combine($ProjectRoot, "hysteria")
        Pattern   = "config_*.json"
        Type      = "hysteria1"
        Converter = ${function:Convert-Hysteria1ToCM}
    }
    "Hysteria v2" = @{
        Dir       = [IO.Path]::Combine($ProjectRoot, "hysteria2")
        Pattern   = "config_*.json"
        Type      = "hysteria2"
        Converter = ${function:Convert-Hysteria2ToCM}
    }
    "Xray"        = @{
        Dir       = [IO.Path]::Combine($ProjectRoot, "Xray")
        Pattern   = "config_*.json"
        Type      = "xray"
        Converter = ${function:Convert-XrayToCM}
    }
    "SingBox"     = @{
        Dir       = [IO.Path]::Combine($ProjectRoot, "singbox")
        Pattern   = "config_*.json"
        Type      = "singbox"
        Converter = ${function:Convert-SingBoxToCM}
    }
    "ClashMeta"   = @{
        Dir       = [IO.Path]::Combine($ProjectRoot, "clash.meta")
        Pattern   = "config_*.yaml"
        Type      = "clashmeta"
        Converter = ${function:Convert-ClashMetaToCM}
    }
}

# 不支持的来源（列出但跳过）
$unsupportedSources = [ordered]@{
    "ShadowQuic" = "shadowquic 协议不被 ClashMeta 支持"
    "Mieru"      = "mieru 协议不被 ClashMeta 支持"
    "Juicity"    = "juicity 协议不被 Clash Verge Rev 内置内核支持"
    "NaiveProxy" = "naive 协议不被 Clash Verge Rev 内置内核支持"
    "Psiphon"    = "无标准配置格式"
}

# 扫描文件
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
        if ($f.Name -eq "config_999.json") { continue }
        $null = $allFiles.Add(@{
            Source     = $srcName
            SourcePath = $f.FullName
            FileName   = $f.Name
            Type       = $info.Type
            Converter  = $info.Converter
        })
    }
}

# 读取每个来源目录的 .node_cache（格式: config_X.xxx|国家|IP）
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

# 构建 源文件名 → 国家代码 映射表（用于代理命名后缀）
$Script:CountryMap = @{}
foreach ($key in $nodeCache.Keys) {
    $Script:CountryMap[$key] = $nodeCache[$key].Country
}

# ============================================================
# 11. 列出待转换文件
# ============================================================

if (-not $Yes) { Clear-Host }

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "            ToCM - 节点配置转 ClashMeta YAML             " -ForegroundColor Cyan
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

# 列出不支持的内核（含文件统计）
$hasUnsupported = $false
foreach ($name in $unsupportedSources.Keys) {
    $reason = $unsupportedSources[$name]
    # 匹配目录名
    $dirMap = @{
        "ShadowQuic" = "shadowquic"
        "Mieru"      = "mieru"
        "Juicity"    = "juicity"
        "NaiveProxy" = "naiveproxy"
        "Psiphon"    = "psiphon"
    }
    $dir = [IO.Path]::Combine($ProjectRoot, $dirMap[$name])
    if (Test-Path $dir) {
        $count = @(Get-ChildItem -Path $dir -Filter "config_*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "config_999.json" }).Count
        if ($count -gt 0) {
            if (-not $hasUnsupported) {
                Write-Host ""
                Write-Host " [不支持的内核]（已跳过）" -ForegroundColor DarkYellow
                $hasUnsupported = $true
            }
            Write-Host "   ✗ $name  ($count 个文件) — $reason" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host " 输出目录: $([IO.Path]::Combine($ProjectRoot, $Script:OutputDirName))" -ForegroundColor Green
Write-Host " 文件总计: $globalCount 个文件待转换" -ForegroundColor Green
Write-Host ""

if ($globalCount -eq 0) {
    Write-Host "没有可转换的文件，退出。" -ForegroundColor Red
    exit 0
}

# ============================================================
# 12. 用户确认
# ============================================================

if (-not $Yes) {
    $confirm = Read-Host "确认开始转换? (Y/n)"
} else {
    $confirm = "Y"
}
if ($confirm -ne '' -and $confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "已取消。" -ForegroundColor Red
    exit 0
}

# ============================================================
# 13. 执行转换
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
$sourceToOutput = @{}  # 源文件路径 -> 输出 config_N.yaml
$allResults = [System.Collections.ArrayList]@()  # 用于生成合并 YAML

foreach ($f in $allFiles) {
    $outName = "config_$idx.yaml"
    $outPath = [IO.Path]::Combine($outDir, $outName)
    $sourceLabel = "$($f.Source)/$($f.FileName)"

    try {
        $converter = $f.Converter
        $result = & $converter -FilePath $f.SourcePath -SourceName $f.FileName

        # 存储结果（稍后统一用 Python 生成 YAML）
        $sourceToOutput[$f.SourcePath] = $outName
        $null = $allResults.Add(@{
            Result   = $result
            Source   = $f.Source
            FileName = $f.FileName
        })

        $protocol = $result.Protocol
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
# 14. 用 Python 生成 YAML 文件（individual + merged）
# ============================================================

if ($allResults.Count -gt 0) {
    Write-Host ""
    Write-Host "生成 YAML 文件..." -ForegroundColor Cyan

    # 构建 JSON 数据传给 Python
    $proxiesJson = [System.Collections.ArrayList]@()
    foreach ($r in $allResults) {
        $proxyObj = $r.Result.Proxy
        $jsonStr = $proxyObj | ConvertTo-Json -Depth 10 -Compress
        $null = $proxiesJson.Add($jsonStr)
    }

    # Python 脚本：生成 individual + merged YAML
    $pythonOutDir = $outDir -replace '\\', '/'
    $allProxiesArray = "[" + ($proxiesJson -join ",") + "]"

    $pyGenScript = @"
import sys, json, os
import yaml

proxies = json.loads(r'''${allProxiesArray}''')
output_dir = r'${pythonOutDir}'

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

# 生成单个文件
for i, proxy in enumerate(proxies):
    pname = proxy.get('name', f'node-{i+1}')
    config = {
        'mixed-port': 7890,
        'allow-lan': False,
        'log-level': 'info',
        'proxies': [proxy],
        'proxy-groups': [
            {
                'name': '\U0001f680 \u8282\u70b9\u9009\u62e9',
                'type': 'select',
                'proxies': [pname, 'DIRECT']
            }
        ],
        'rules': ['MATCH,\U0001f680 \u8282\u70b9\u9009\u62e9']
    }
    filepath = os.path.join(output_dir, f'config_{i+1}.yaml')
    with open(filepath, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False,
                  sort_keys=False, indent=2, width=200)

# 生成合并文件
proxy_names = [p.get('name', f'node-{i+1}') for i, p in enumerate(proxies)]

merged_config = {
    'mixed-port': 7890,
    'allow-lan': False,
    'log-level': 'info',
    'dns': {
        'enabled': True,
        'nameserver': ['119.29.29.29', '223.5.5.5'],
        'fallback-filter': {
            'geoip': False,
            'ipcidr': ['240.0.0.0/4', '0.0.0.0/32']
        }
    },
    'proxies': proxies,
    'proxy-groups': [
        {
            'name': '\U0001f680 \u8282\u70b9\u9009\u62e9',
            'type': 'select',
            'proxies': ['\u267b\ufe0f \u81ea\u52a8\u9009\u62e9', 'DIRECT'] + proxy_names
        },
        {
            'name': '\u267b\ufe0f \u81ea\u52a8\u9009\u62e9',
            'type': 'fallback',
            'url': 'https://www.gstatic.com/generate_204',
            'interval': 5,
            'proxies': proxy_names[:]
        },
        {
            'name': '\U0001f41f \u6f0f\u7f51\u4e4b\u9c7c',
            'type': 'select',
            'proxies': ['\U0001f680 \u8282\u70b9\u9009\u62e9', 'DIRECT', '\u267b\ufe0f \u81ea\u52a8\u9009\u62e9']
        }
    ],
    'rules': ['MATCH,\U0001f680 \u8282\u70b9\u9009\u62e9']
}

merged_path = os.path.join(output_dir, 'config_999.yaml')
with open(merged_path, 'w', encoding='utf-8') as f:
    yaml.dump(merged_config, f, allow_unicode=True, default_flow_style=False,
              sort_keys=False, indent=2, width=200)

print(f'OK: {len(proxies)} individual + 1 merged YAML generated')
"@

    $pyGenOutput = & $script:PythonExe -c $pyGenScript 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  YAML 生成失败: $pyGenOutput" -ForegroundColor Red
    } else {
        Write-Host "  $pyGenOutput" -ForegroundColor Green
    }
}

# ============================================================
# 15. 合并 .node_cache
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

        $parts = $trimmed -split '\|', 3
        if ($parts.Length -lt 3) { continue }

        $origName = $parts[0]
        $country  = $parts[1]
        $ip       = $parts[2]
        $origPath = [IO.Path]::Combine($dirPath, $origName)

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
# 16. 生成 map.log 映射记录
# ============================================================

$mapLog = [System.Text.StringBuilder]::new()
$null = $mapLog.AppendLine("ToCM 转换映射记录")
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
            # 找对应的 result 获取协议
            $matching = $allResults | Where-Object { $_.FileName -eq $f.FileName -and $_.Source -eq $f.Source }
            $protocol = if ($matching) { $matching.Result.Protocol } else { "?" }
            $null = $mapLog.AppendLine("  $($f.FileName)  ->  $newName  ($protocol)")
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
# 17. 输出汇总
# ============================================================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  转换完成!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  成功: $okCount  失败: $failCount  总计: $($okCount + $failCount)" `
    -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "  输出目录: $outDir" -ForegroundColor Green
Write-Host "  合并文件: $([IO.Path]::Combine($outDir, 'config.yaml'))" -ForegroundColor Green
Write-Host ""
if (-not $Yes) { $null = Read-Host "按回车键退出..." }
