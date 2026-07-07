# ToV2.ps1
# 将支持的节点配置转换为 v2rayN 客户端导入分享链接格式
# 输出目录由 $Script:OutputDirName 变量控制（默认 "ToV2"）
param([switch]$Yes)

$ErrorActionPreference = "Stop"
$Script:OutputDirName = "ToV2"          # 输出目录名，改这里即可
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
# 1. Python 环境检测 & PyYAML 安装（仅 ClashMeta 需要）
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

# URL 编码（RFC 3986）
function ConvertTo-UrlEncoded {
    param([string]$Str)
    if (-not $Str) { return "" }
    return [Uri]::EscapeDataString($Str)
}

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

# 安全读取 JSON 配置
function Read-JsonConfig {
    param([string]$Path)
    $raw = Get-Content $Path -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

# ============================================================
# 3. 各协议 → v2rayN 分享链接 URL
# ============================================================

# --- Hysteria v2 → hysteria2:// ---
function New-Hysteria2Url {
    param(
        [string]$Server,         # host:port 合并字符串
        [string]$Auth,           # 认证密码
        [string]$Sni,            # SNI
        [bool]$Insecure,         # 跳过证书验证
        [string]$NodeName        # 备注
    )

    $hp = Split-HostPort -HostPort $Server
    if (-not $hp) { throw "无法解析 server 字段: $Server" }

    $hostStr = if ($hp.host -match ':') { "[$($hp.host)]" } else { $hp.host }

    $url = "hysteria2://"
    $url += ConvertTo-UrlEncoded $Auth
    $url += "@" + $hostStr + ":" + $hp.port
    $url += "/?sni=" + (ConvertTo-UrlEncoded $Sni)
    $url += "&insecure=" + $(if ($Insecure) { "1" } else { "0" })

    if ($NodeName) {
        $url += "#" + (ConvertTo-UrlEncoded $NodeName)
    }

    return $url
}

# --- VLESS + Reality + xhttp → vless:// ---
function New-VlessUrl {
    param([PSCustomObject]$Config, [string]$NodeName)

    $vnext = $Config.outbounds |
        Where-Object { $_.protocol -eq 'vless' } |
        Select-Object -First 1

    if (-not $vnext) { throw "未找到 VLESS 出站" }

    $address = $vnext.settings.vnext[0].address
    $port    = $vnext.settings.vnext[0].port
    $uuid    = $vnext.settings.vnext[0].users[0].id
    $enc     = $vnext.settings.vnext[0].users[0].encryption
    $flow    = $vnext.settings.vnext[0].users[0].flow

    $ss = $vnext.streamSettings
    $network  = $ss.network
    $security = $ss.security
    $rs       = $ss.realitySettings
    $sni      = $rs.serverName
    $fp       = $rs.fingerprint
    $pbk      = $rs.publicKey
    $sid      = $rs.shortId

    # 构建 URL
    # IPv6 地址用方括号
    $hostStr = if ($address -match ':') { "[$address]" } else { $address }

    $url = "vless://"
    $url += ConvertTo-UrlEncoded $uuid
    $url += "@" + $hostStr + ":" + $port
    $url += "?type=" + $network
    $url += "&security=" + $security
    $url += "&sni=" + (ConvertTo-UrlEncoded $sni)
    $url += "&fp=" + $fp
    $url += "&pbk=" + (ConvertTo-UrlEncoded $pbk)
    $url += "&sid=" + $sid

    # 加密：只有非 none 才添加
    if ($enc -and $enc -ne 'none') {
        $encEncoded = ConvertTo-UrlEncoded $enc
        $url += "&encryption=" + $encEncoded
    }

    # flow（可选）
    if ($flow) {
        $url += "&flow=" + $flow
    }

    # xhttp 特有参数
    if ($network -eq 'xhttp') {
        $xhttp = $ss.xhttpSettings
        if ($xhttp.path) {
            $url += "&path=" + (ConvertTo-UrlEncoded $xhttp.path)
        }
        if ($xhttp.mode) {
            $url += "&mode=" + $xhttp.mode
        }
    }

    if ($NodeName) {
        $url += "#" + (ConvertTo-UrlEncoded $NodeName)
    }

    return $url
}

# --- Juicity → juicity:// ---
function New-JuicityUrl {
    param(
        [string]$Server,         # host:port 合并字符串
        [string]$Uuid,
        [string]$Password,
        [string]$Sni,
        [bool]$AllowInsecure,
        [string]$CongestionControl,
        [string]$NodeName
    )

    $hp = Split-HostPort -HostPort $Server
    if (-not $hp) { throw "无法解析 server 字段: $Server" }

    $userInfo = (ConvertTo-UrlEncoded $Uuid) + ":" + (ConvertTo-UrlEncoded $Password)

    $hostStr = if ($hp.host -match ':') { "[$($hp.host)]" } else { $hp.host }

    $url = "juicity://"
    $url += $userInfo
    $url += "@" + $hostStr + ":" + $hp.port
    $url += "/?sni=" + (ConvertTo-UrlEncoded $Sni)
    $url += "&allowInsecure=" + $(if ($AllowInsecure) { "1" } else { "0" })
    $url += "&congestion_control=" + $CongestionControl

    if ($NodeName) {
        $url += "#" + (ConvertTo-UrlEncoded $NodeName)
    }

    return $url
}

# --- NaiveProxy → naive+https:// ---
function New-NaiveProxyUrl {
    param(
        [string]$ProxyUrl,       # 原始 proxy URL: https://user:pass@host:port
        [string]$NodeName
    )

    # 直接替换协议前缀
    $url = $ProxyUrl -replace '^https://', 'naive+https://'

    if ($NodeName) {
        $url += "#" + (ConvertTo-UrlEncoded $NodeName)
    }

    return $url
}

# --- TUIC → tuic:// ---
function New-TuicUrl {
    param(
        [string]$Server,
        [int]$Port,
        [string]$Uuid,
        [string]$Password,
        [string]$Sni,
        [bool]$Insecure,
        [string]$CongestionControl,
        [string[]]$Alpn,
        [string]$UdpRelayMode,
        [string]$NodeName
    )

    $userInfo = (ConvertTo-UrlEncoded $Uuid) + ":" + (ConvertTo-UrlEncoded $Password)

    $hostStr = if ($Server -match ':') { "[$Server]" } else { $Server }

    $url = "tuic://"
    $url += $userInfo
    $url += "@" + $hostStr + ":" + $Port
    $url += "/?congestion_control=" + $CongestionControl
    $url += "&alpn=" + $(if ($Alpn -and $Alpn.Count -gt 0) { ($Alpn -join ',') } else { 'h3' })
    $url += "&sni=" + (ConvertTo-UrlEncoded $Sni)
    $url += "&allowInsecure=" + $(if ($Insecure) { "1" } else { "0" })
    $url += "&udp_relay_mode=" + $(if ($UdpRelayMode) { $UdpRelayMode } else { 'native' })

    if ($NodeName) {
        $url += "#" + (ConvertTo-UrlEncoded $NodeName)
    }

    return $url
}

# ============================================================
# 4. 各源 → URL 转换入口函数（返回 @{Url, Protocol, NodeName}）
# ============================================================

function Convert-Hysteria2Config {
    param([string]$FilePath, [string]$SourceName)

    $json = Read-JsonConfig -Path $FilePath

    # 提取 sni（hysteria2 嵌套在 tls 对象中）
    $sni       = $json.tls.sni
    $insecure  = [bool]$json.tls.insecure
    $auth      = $json.auth
    $server    = $json.server
    $nodeName  = "HY2-$([IO.Path]::GetFileNameWithoutExtension($SourceName))"

    $url = New-Hysteria2Url -Server $server -Auth $auth -Sni $sni -Insecure $insecure -NodeName $nodeName

    return @{ Url = $url; Protocol = "hysteria2" }
}

function Convert-XrayConfig {
    param([string]$FilePath, [string]$SourceName)

    $json = Read-JsonConfig -Path $FilePath

    $nodeName = "VLESS-$([IO.Path]::GetFileNameWithoutExtension($SourceName))"

    $url = New-VlessUrl -Config $json -NodeName $nodeName

    return @{ Url = $url; Protocol = "vless+reality" }
}

function Convert-JuicityConfig {
    param([string]$FilePath, [string]$SourceName)

    $json = Read-JsonConfig -Path $FilePath

    $hp = Split-HostPort -HostPort $json.server
    $nodeName = "Juicity-$([IO.Path]::GetFileNameWithoutExtension($SourceName))"

    $url = New-JuicityUrl `
        -Server $json.server `
        -Uuid $json.uuid `
        -Password $json.password `
        -Sni $json.sni `
        -AllowInsecure ([bool]$json.allow_insecure) `
        -CongestionControl $json.congestion_control `
        -NodeName $nodeName

    return @{ Url = $url; Protocol = "juicity" }
}

function Convert-NaiveProxyConfig {
    param([string]$FilePath, [string]$SourceName)

    $json = Read-JsonConfig -Path $FilePath

    # proxy URL 格式: https://user:pass@fan.193919.xyz:44000
    $proxyUrl = $json.proxy

    $nodeName = "Naive-$([IO.Path]::GetFileNameWithoutExtension($SourceName))"

    $url = New-NaiveProxyUrl -ProxyUrl $proxyUrl -NodeName $nodeName

    return @{ Url = $url; Protocol = "naiveproxy" }
}

function Convert-SingBoxConfig {
    param([string]$FilePath, [string]$SourceName)

    $json = Read-JsonConfig -Path $FilePath

    # 找到第一个非 direct/block/dns 的 outbound
    $proxy = $null
    foreach ($ob in $json.outbounds) {
        if ($ob.type -notin @('direct', 'block', 'dns')) {
            $proxy = $ob
            break
        }
    }
    if (-not $proxy) { throw "SingBox 配置中未找到代理出站" }

    if ($proxy.type -ne 'tuic') {
        throw "不支持的 SingBox 代理类型: $($proxy.type)"
    }

    $nodeName = "SB-$([IO.Path]::GetFileNameWithoutExtension($SourceName))"

    # ALPN 处理：可能是数组或字符串
    $alpn = @()
    if ($proxy.tls.alpn) {
        if ($proxy.tls.alpn -is [array]) {
            $alpn = @($proxy.tls.alpn)
        } else {
            $alpn = @($proxy.tls.alpn.ToString())
        }
    }

    $url = New-TuicUrl `
        -Server $proxy.server `
        -Port $proxy.server_port `
        -Uuid $proxy.uuid `
        -Password $proxy.password `
        -Sni $proxy.tls.server_name `
        -Insecure ([bool]$proxy.tls.insecure) `
        -CongestionControl $(if ($proxy.congestion_control) { $proxy.congestion_control } else { "bbr" }) `
        -Alpn $alpn `
        -UdpRelayMode "" `
        -NodeName $nodeName

    return @{ Url = $url; Protocol = "tuic" }
}

function Convert-ClashMetaConfig {
    param([string]$FilePath, [string]$SourceName)

    # 用 Python 解析 YAML，提取 proxies 中支持的节点
    $pyScript = @"
import sys, json
try:
    import yaml
except ImportError:
    print(json.dumps({"error": "PyYAML not installed"}))
    sys.exit(1)

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    content = f.read()

# 只解析第一个 YAML 文档
docs = list(yaml.safe_load_all(content))
if not docs:
    print(json.dumps({"error": "empty YAML"}))
    sys.exit(1)

data = docs[0]
proxies = data.get('proxies', [])

# 只保留 v2rayN URL 格式支持的协议
supported = {'hysteria2', 'tuic'}
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

    # 每个文件只有一个 proxy（取第一个）
    $proxy = if ($proxies -is [array]) { $proxies[0] } else { $proxies }
    $proxyType = $proxy.type
    $nodeName  = "CM-$([IO.Path]::GetFileNameWithoutExtension($SourceName))"

    switch ($proxyType) {
        'hysteria2' {
            $url = New-Hysteria2Url `
                -Server "$($proxy.server):$($proxy.port)" `
                -Auth $proxy.password `
                -Sni $proxy.sni `
                -Insecure ([bool]$proxy.'skip-cert-verify') `
                -NodeName $nodeName

            return @{ Url = $url; Protocol = "hysteria2" }
        }
        'tuic' {
            # ALPN 处理
            $alpn = @()
            if ($proxy.alpn) {
                if ($proxy.alpn -is [array]) {
                    $alpn = @($proxy.alpn)
                } else {
                    $alpn = @($proxy.alpn.ToString())
                }
            }

            $url = New-TuicUrl `
                -Server $proxy.server `
                -Port ([int]$proxy.port) `
                -Uuid $proxy.uuid `
                -Password $proxy.password `
                -Sni $proxy.sni `
                -Insecure ([bool]$proxy.'skip-cert-verify') `
                -CongestionControl $(if ($proxy.'congestion-controller') { $proxy.'congestion-controller' } else { "bbr" }) `
                -Alpn $alpn `
                -UdpRelayMode $(if ($proxy.'udp-relay-mode') { $proxy.'udp-relay-mode' } else { "" }) `
                -NodeName $nodeName

            return @{ Url = $url; Protocol = "tuic" }
        }
        default {
            throw "不支持的 ClashMeta 代理类型: $proxyType"
        }
    }
}

# ============================================================
# 5. 扫描源目录（只扫描 v2rayN URL 格式支持的源）
# ============================================================

$sources = [ordered]@{
    "Hysteria v2" = @{
        Dir        = [IO.Path]::Combine($ProjectRoot, "hysteria2")
        Pattern    = "config_*.json"
        Type       = "hysteria2"
        Convert    = ${function:Convert-Hysteria2Config}
        CacheFile  = [IO.Path]::Combine($ProjectRoot, "hysteria2", ".node_cache")
    }
    "Xray"        = @{
        Dir        = [IO.Path]::Combine($ProjectRoot, "Xray")
        Pattern    = "config_*.json"
        Type       = "xray"
        Convert    = ${function:Convert-XrayConfig}
        CacheFile  = [IO.Path]::Combine($ProjectRoot, "Xray", ".node_cache")
    }
    "Juicity"     = @{
        Dir        = [IO.Path]::Combine($ProjectRoot, "juicity")
        Pattern    = "config_*.json"
        Type       = "juicity"
        Convert    = ${function:Convert-JuicityConfig}
        CacheFile  = [IO.Path]::Combine($ProjectRoot, "juicity", ".node_cache")
    }
    "NaiveProxy"  = @{
        Dir        = [IO.Path]::Combine($ProjectRoot, "naiveproxy")
        Pattern    = "config_*.json"
        Type       = "naiveproxy"
        Convert    = ${function:Convert-NaiveProxyConfig}
        CacheFile  = [IO.Path]::Combine($ProjectRoot, "naiveproxy", ".node_cache")
    }
    "SingBox"     = @{
        Dir        = [IO.Path]::Combine($ProjectRoot, "singbox")
        Pattern    = "config_*.json"
        Type       = "singbox"
        Convert    = ${function:Convert-SingBoxConfig}
        CacheFile  = [IO.Path]::Combine($ProjectRoot, "singbox", ".node_cache")
    }
    "ClashMeta"   = @{
        Dir        = [IO.Path]::Combine($ProjectRoot, "clash.meta")
        Pattern    = "config_*.yaml"
        Type       = "clashmeta"
        Convert    = ${function:Convert-ClashMetaConfig}
        CacheFile  = [IO.Path]::Combine($ProjectRoot, "clash.meta", ".node_cache")
    }
}

# 读取各源的 .node_cache（config文件名 → 国家|IP）
$nodeCache = @{}
foreach ($srcName in $sources.Keys) {
    $cachePath = $sources[$srcName].CacheFile
    if (Test-Path $cachePath) {
        $lines = Get-Content $cachePath -Encoding UTF8
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -eq '') { continue }
            $parts = $trimmed -split '\|', 3
            if ($parts.Length -ge 3) {
                $nodeCache[$parts[0]] = @{ Country = $parts[1]; IP = $parts[2] }
            }
        }
    }
}

# 扫描文件
$allFiles = [System.Collections.ArrayList]@()
$unsupportedSources = [ordered]@{
    "Hysteria v1" = [IO.Path]::Combine($ProjectRoot, "hysteria")
    "ShadowQUIC"  = [IO.Path]::Combine($ProjectRoot, "shadowquic")
    "Mieru"       = [IO.Path]::Combine($ProjectRoot, "mieru")
    "Psiphon"     = [IO.Path]::Combine($ProjectRoot, "psiphon")
}

foreach ($srcName in $sources.Keys) {
    $info = $sources[$srcName]
    $dirPath = $info.Dir
    if (-not (Test-Path $dirPath)) {
        Write-Host "[警告] 目录不存在，跳过: $dirPath" -ForegroundColor DarkYellow
        continue
    }
    $files = Get-ChildItem -Path $dirPath -Filter $info.Pattern -File | Sort-Object Name
    foreach ($f in $files) {
        # 排除合并文件
        if ($f.Name -eq "config_999.json") { continue }
        $null = $allFiles.Add(@{
            Source     = $srcName
            SourcePath = $f.FullName
            FileName   = $f.Name
            Type       = $info.Type
            Convert    = $info.Convert
        })
    }
}

# ============================================================
# 6. 列出待转换文件 & 不支持的内核
# ============================================================

if (-not $Yes) { Clear-Host }

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "         ToV2 - v2rayN 分享链接生成工具              " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 列出支持的节点
$globalCount = 0
Write-Host " [支持转换的内核]" -ForegroundColor Green
Write-Host ""

foreach ($srcName in $sources.Keys) {
    $srcFiles = $allFiles | Where-Object { $_.Source -eq $srcName }
    if ($srcFiles.Count -eq 0) { continue }
    Write-Host " [$srcName]  ($($srcFiles.Count) 个文件)" -ForegroundColor Yellow
    Write-Host " ├─ $($sources[$srcName].Dir)" -ForegroundColor DarkGray
    foreach ($f in $srcFiles) {
        $globalCount++
        # 读取 .node_cache 获取国家/IP
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

# 列出不支持的内核
$hasUnsupported = $false
foreach ($name in $unsupportedSources.Keys) {
    $dir = $unsupportedSources[$name]
    if (Test-Path $dir) {
        $count = (Get-ChildItem -Path $dir -Filter "config_*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "config_999.json" }).Count
        if ($count -gt 0) {
            if (-not $hasUnsupported) {
                Write-Host ""
                Write-Host " [不支持的内核]（已跳过）" -ForegroundColor DarkYellow
                $hasUnsupported = $true
            }
            Write-Host "   ✗ $name  ($count 个文件) — 无标准分享链接格式或不被 v2rayN 支持" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host " 输出文件: $([IO.Path]::Combine($ProjectRoot, $Script:OutputDirName, 'v2-url.txt'))" -ForegroundColor Green
Write-Host " 映射日志: $([IO.Path]::Combine($ProjectRoot, $Script:OutputDirName, 'map.log'))" -ForegroundColor Green
Write-Host " 文件总计: $globalCount 个文件待转换" -ForegroundColor Green

if ($globalCount -eq 0) {
    Write-Host ""
    Write-Host "没有可转换的文件，退出。" -ForegroundColor Red
    exit 0
}

Write-Host ""

# ============================================================
# 7. 用户确认
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
# 8. 执行转换
# ============================================================

$outDir = [IO.Path]::Combine($ProjectRoot, $Script:OutputDirName)

# 创建输出目录
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

# 收集所有 URL 和映射信息
$allUrls = [System.Collections.ArrayList]@()
$mapEntries = [System.Collections.ArrayList]@()
$idx = 1
$okCount = 0
$failCount = 0

foreach ($f in $allFiles) {
    $sourceLabel = "$($f.Source)/$($f.FileName)"

    try {
        $convertFunc = $f.Convert
        $result = & $convertFunc -FilePath $f.SourcePath -SourceName $f.FileName

        $url       = $result.Url
        $protocol  = $result.Protocol

        $null = $allUrls.Add($url)

        # map.log 条目
        $null = $mapEntries.Add(@{
            Source   = $sourceLabel
            Protocol = $protocol
            Url      = $url
        })

        Write-Host "  [$idx] OK  $sourceLabel  ->  $protocol" -ForegroundColor Green
        $okCount++
    }
    catch {
        Write-Host "  [$idx] FAIL  $sourceLabel" -ForegroundColor Red
        Write-Host "         错误: $($_.Exception.Message)" -ForegroundColor DarkRed

        $null = $mapEntries.Add(@{
            Source   = $sourceLabel
            Protocol = "FAIL"
            Url      = $_.Exception.Message
        })

        $failCount++
    }
    $idx++
}

# ============================================================
# 9. 写入 v2-url.txt
# ============================================================

$urlFilePath = [IO.Path]::Combine($outDir, "v2-url.txt")
$urlContent = ($allUrls -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($urlFilePath, $urlContent, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "  v2-url.txt: $($allUrls.Count) 条链接已生成" -ForegroundColor Green

# ============================================================
# 10. 写入 v2-Base64.txt（订阅格式，一行一条 URL 然后整体 Base64）
# ============================================================

$base64Content = ($allUrls -join "`r`n")
$base64Bytes = [System.Text.Encoding]::UTF8.GetBytes($base64Content)
$base64String = [System.Convert]::ToBase64String($base64Bytes)
$base64FilePath = [IO.Path]::Combine($outDir, "v2-Base64.txt")
$null = [System.IO.File]::WriteAllText($base64FilePath, $base64String, [System.Text.UTF8Encoding]::new($false))

Write-Host "  v2-Base64.txt: 订阅格式已生成 ($($base64String.Length) 字符)" -ForegroundColor Green

# ============================================================
# 11. 生成 map.log
# ============================================================

$mapLog = [System.Text.StringBuilder]::new()
$null = $mapLog.AppendLine("ToV2 转换映射记录")
$null = $mapLog.AppendLine("生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $mapLog.AppendLine("")

foreach ($srcName in $sources.Keys) {
    $srcEntries = $mapEntries | Where-Object { $_.Source -like "$srcName/*" }
    if ($srcEntries.Count -eq 0) { continue }

    $null = $mapLog.AppendLine("──────────────────────────────────────────")
    $null = $mapLog.AppendLine("  $srcName")
    $null = $mapLog.AppendLine("──────────────────────────────────────────")

    foreach ($entry in $srcEntries) {
        $fileName = $entry.Source -replace '^.*/', ''
        $protocol  = $entry.Protocol
        $url       = $entry.Url

        if ($protocol -eq 'FAIL') {
            $null = $mapLog.AppendLine("  $fileName  ->  转换失败: $url")
        }
        else {
            $shortUrl = if ($url.Length -gt 120) { $url.Substring(0, 117) + "..." } else { $url }
            $null = $mapLog.AppendLine("  $fileName  ->  $protocol  ->  $shortUrl")
        }
    }
    $null = $mapLog.AppendLine("")
}

$mapOut = [IO.Path]::Combine($outDir, "map.log")
[System.IO.File]::WriteAllText($mapOut, $mapLog.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "  map.log: 映射记录已生成" -ForegroundColor Green

# ============================================================
# 11. 输出汇总
# ============================================================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  转换完成!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  成功: $okCount  失败: $failCount  总计: $($okCount + $failCount)" `
    -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "  输出目录: $outDir" -ForegroundColor Green
Write-Host "  链接文件: $urlFilePath" -ForegroundColor Green
Write-Host "  映射日志: $mapOut" -ForegroundColor Green
Write-Host ""
if (-not $Yes) { $null = Read-Host "按回车键退出..." }
