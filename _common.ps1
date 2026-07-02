# ======================================================================
# Common.ps1 — 公共函数库
# 供代理启动脚本引用。启动脚本需先读取 .env 获取 CHROMEGO_PATH，再引用本文件。
# ======================================================================

# ------------------------------------------------------------
# 加载 .env 配置（CHROMEGO_PATH / IPINFO_TOKEN）
# ------------------------------------------------------------
$Script:CHROMEGO_PATH = ""
$Script:IPINFO_TOKEN = ""

$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch '^\s*#') {
            if ($line -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
                $k = $matches[1].Trim()
                $v = $matches[2].Trim().Trim('"').Trim("'")
                if ($k -eq 'CHROMEGO_PATH') { $Script:CHROMEGO_PATH = $v }
                if ($k -eq 'IPINFO_TOKEN')   { $Script:IPINFO_TOKEN   = $v }
            }
        }
    }
}

# 回退：.env 不存在时使用默认值
if (-not $Script:CHROMEGO_PATH) { $Script:CHROMEGO_PATH = "$PSScriptRoot" }
if (-not $Script:IPINFO_TOKEN)   { $Script:IPINFO_TOKEN   = "311cf96f8bbc1b" }

# ------------------------------------------------------------
# Ensure-Admin: 检查管理员权限，非管理员则自动提权重启
# 参数: -ScriptPath (当前脚本的完整路径，用于提权重启)
# ------------------------------------------------------------
function Ensure-Admin {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )

    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "请求管理员权限..." -ForegroundColor Yellow
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -File `"$ScriptPath`"" -Verb RunAs
        exit
    }
}

# ------------------------------------------------------------
# Initialize-Script: 控制台初始化（编码、目录、提权、标题）
# 参数: -Title (窗口标题), -ScriptPath (当前脚本路径，用于提权重启)
# ------------------------------------------------------------
function Initialize-Script {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )

    # 设置控制台编码为 UTF-8
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    chcp 936 > $null

    # 切换到项目根目录（优先 CHROMEGO_PATH，回退 PSScriptRoot）
    if ($Script:CHROMEGO_PATH) {
        Set-Location -Path $Script:CHROMEGO_PATH
    } else {
        Set-Location -Path $PSScriptRoot
    }

    # 检查管理员权限（若非管理员则自动提权重启）
    Ensure-Admin -ScriptPath $ScriptPath

    # 设置控制台标题
    $Host.UI.RawUI.WindowTitle = $Title
}

# ------------------------------------------------------------
# Show-Banner: 显示绿色横幅
# 参数: -Title (横幅标题文字)
# ------------------------------------------------------------
function Show-Banner {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    Write-Host "========================================" -ForegroundColor Green
    Write-Host "    $Title" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
}

# ------------------------------------------------------------
# Test-CoreFile: 检查内核文件是否存在，不存在则报错退出
# 参数: -CoreDir (内核目录), -CoreExe (内核文件名)
# 返回: 内核文件的完整路径
# ------------------------------------------------------------
function Test-CoreFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CoreDir,
        [Parameter(Mandatory=$true)]
        [string]$CoreExe,
        [string]$ScriptRoot
    )

    if (-not $ScriptRoot) { $ScriptRoot = if ($Script:CHROMEGO_PATH) { $Script:CHROMEGO_PATH } else { "$PSScriptRoot" } }
    $corePath = [IO.Path]::Combine($ScriptRoot, $CoreDir, $CoreExe)

    if (-not (Test-Path $corePath)) {
        Write-Host "错误: 内核文件不存在: $CoreExe" -ForegroundColor Red
        Write-Host "请检查 CORE_EXE 配置是否正确" -ForegroundColor Red
        Press-AnyKey
        exit 1
    }

    return $corePath
}

# ------------------------------------------------------------
# Press-AnyKey: 等待用户按任意键
# 参数: -Message (提示信息，默认 "按任意键退出...")
# ------------------------------------------------------------
function Press-AnyKey {
    param(
        [string]$Message = "按任意键退出..."
    )

    Write-Host $Message -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ------------------------------------------------------------
# Get-LocalLANIP: 获取本机局域网 IPv4 地址
# 返回: IP 地址字符串 (如 "192.168.31.93")，失败返回 $null
# ------------------------------------------------------------
function Get-LocalLANIP {
    try {
        $ip = (Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.IPv4Address -ne $null } |
            Select-Object -First 1).IPv4Address.IPAddress
        if ($ip) { return $ip }
    } catch {}
    return $null
}

# ------------------------------------------------------------
# Get-ConfigLocalPort: 从配置文件中提取本地监听端口及协议类型
# 参数: -ConfigPath (配置文件路径)
# 返回: @(@{Port=1080; Type="mixed"}, ...) 数组，Type 为 "mixed"/"socks"/"http"
#       失败返回空数组
# ------------------------------------------------------------
function Get-ConfigLocalPort {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )

    $results = @()

    if (-not (Test-Path $ConfigPath)) { return $results }

    $ext = [System.IO.Path]::GetExtension($ConfigPath).ToLower()

    if ($ext -eq '.json') {
        try {
            $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { return $results }

        # 1) SingBox: inbounds[].listen_port + inbounds[].type
        if ($json.inbounds) {
            foreach ($inbound in $json.inbounds) {
                if ($inbound.listen_port) {
                    $portType = $inbound.type
                    if ($portType -eq 'mixed') {
                        $results += [PSCustomObject]@{ Port = [int]$inbound.listen_port; Type = 'mixed' }
                    } elseif ($portType -eq 'socks') {
                        $results += [PSCustomObject]@{ Port = [int]$inbound.listen_port; Type = 'socks' }
                    } elseif ($portType -eq 'http') {
                        $results += [PSCustomObject]@{ Port = [int]$inbound.listen_port; Type = 'http' }
                    }
                }
            }
        }

        # 2) Hysteria / Hysteria2: socks5.listen → "127.0.0.1:1080"
        if ($json.socks5 -and $json.socks5.listen) {
            $port = _Extract-PortFromAddr $json.socks5.listen
            if ($port) { $results += [PSCustomObject]@{ Port = $port; Type = 'socks' } }
        }

        # 3) Xray: inbounds[].port + inbounds[].protocol
        #    （与 SingBox 的 inbounds 结构不同，Xray 用 protocol 字段和 port 字段）
        if ($json.inbounds -and $results.Count -eq 0) {
            foreach ($inbound in $json.inbounds) {
                if ($inbound.port -and $inbound.protocol) {
                    $proto = $inbound.protocol.ToLower()
                    if ($proto -eq 'socks') {
                        $results += [PSCustomObject]@{ Port = [int]$inbound.port; Type = 'socks' }
                    } elseif ($proto -eq 'http') {
                        $results += [PSCustomObject]@{ Port = [int]$inbound.port; Type = 'http' }
                    }
                }
            }
        }

        # 4) Mieru: socks5Port
        if ($json.socks5Port) {
            $results += [PSCustomObject]@{ Port = [int]$json.socks5Port; Type = 'socks' }
        }

        # 5) NaiveProxy: listen → "socks://127.0.0.1:1080"
        if ($json.listen -and $results.Count -eq 0) {
            $listenVal = $json.listen.ToString()
            if ($listenVal -match 'socks://') {
                $port = _Extract-PortFromAddr $listenVal
                if ($port) { $results += [PSCustomObject]@{ Port = $port; Type = 'socks' } }
            } elseif ($listenVal -match 'http://') {
                $port = _Extract-PortFromAddr $listenVal
                if ($port) { $results += [PSCustomObject]@{ Port = $port; Type = 'http' } }
            }
        }

        # 6) Juicity: listen → "127.0.0.1:1080" (无 socks5 子对象)
        if ($json.listen -and $results.Count -eq 0 -and -not ($json.socks5)) {
            $port = _Extract-PortFromAddr $json.listen
            if ($port) { $results += [PSCustomObject]@{ Port = $port; Type = 'socks' } }
        }

    } elseif ($ext -eq '.yaml' -or $ext -eq '.yml') {
        try {
            $content = Get-Content $ConfigPath -Raw -Encoding UTF8
        } catch { return $results }

        $lines = $content -split "`n"

        # ClashMeta: mixed-port / port / socks-port (仅匹配顶层字段，无缩进)
        foreach ($line in $lines) {
            if ($line -match '^mixed-port\s*:\s*(\d+)') {
                $results += [PSCustomObject]@{ Port = [int]$Matches[1]; Type = 'mixed' }
            } elseif ($line -match '^socks-port\s*:\s*(\d+)') {
                $results += [PSCustomObject]@{ Port = [int]$Matches[1]; Type = 'socks' }
            } elseif ($line -match '^port\s*:\s*(\d+)') {
                $results += [PSCustomObject]@{ Port = [int]$Matches[1]; Type = 'http' }
            }
        }

        # ShadowQuic: inbound.bind-addr → "127.0.0.1:4080"
        if ($results.Count -eq 0) {
            $inOutbound = $false
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^inbound\s*:') { $inOutbound = $true; continue }
                if ($inOutbound -and $trimmed -match '^bind-addr\s*:\s*"?([^"]+)"?') {
                    $port = _Extract-PortFromAddr $Matches[1]
                    if ($port) { $results += [PSCustomObject]@{ Port = $port; Type = 'socks' } }
                    break
                }
                if ($inOutbound -and $line -match '^\S') { $inOutbound = $false }
            }
        }
    }

    return $results
}

# ------------------------------------------------------------
# _Extract-PortFromAddr: 从地址字符串中提取端口号
# 支持: "127.0.0.1:1080" / "socks://127.0.0.1:1080" / "[::1]:1080"
# 返回: 端口号(int)，失败返回 $null
# ------------------------------------------------------------
function _Extract-PortFromAddr {
    param([string]$Addr)

    if (-not $Addr) { return $null }

    # 去掉协议前缀
    $clean = $Addr -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''

    # IPv6 [::]:port
    if ($clean -match '\]:(\d+)$') { return [int]$Matches[1] }

    # IPv4 host:port
    if ($clean -match ':(\d+)$') { return [int]$Matches[1] }

    return $null
}

# ------------------------------------------------------------
# Wait-CoreStart: 等待内核启动并检查进程状态
# 参数: -Process (Start-Process 返回的进程对象)
#       -ConfigPath (可选，配置文件路径，用于提取端口信息)
# ------------------------------------------------------------
function Wait-CoreStart {
    param(
        [Parameter(Mandatory=$true)]
        $Process,
        [string]$ConfigPath
    )

    # 等待一下确保启动
    Start-Sleep -Seconds 2

    if ($Process.HasExited) {
        Write-Host "警告: 内核可能启动失败，进程已退出。" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # 提取端口信息
    $portStr = ""
    $localAddrs = @()
    $lanAddrs = @()
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $ports = Get-ConfigLocalPort -ConfigPath $ConfigPath
        if ($ports -and $ports.Count -gt 0) {
            # 去重（同一 Port+Type 可能因配置文件内容重复而出现多次）
            $ports = @($ports | Group-Object { "$($_.Port)-$($_.Type)" } | ForEach-Object { $_.Group[0] })

            # 端口号字符串
            $portStr = ($ports | ForEach-Object { $_.Port } | Select-Object -Unique) -join ', '

            # 构建代理地址列表（本地优先，局域网其次）
            $lanIP = Get-LocalLANIP
            foreach ($p in $ports) {
                if ($p.Type -eq 'mixed') {
                    $localAddrs += "http://127.0.0.1:$($p.Port)"
                    $localAddrs += "socks://127.0.0.1:$($p.Port)"
                    if ($lanIP) {
                        $lanAddrs += "http://${lanIP}:$($p.Port)"
                        $lanAddrs += "socks://${lanIP}:$($p.Port)"
                    }
                } elseif ($p.Type -eq 'socks') {
                    $localAddrs += "socks://127.0.0.1:$($p.Port)"
                    if ($lanIP) { $lanAddrs += "socks://${lanIP}:$($p.Port)" }
                } elseif ($p.Type -eq 'http') {
                    $localAddrs += "http://127.0.0.1:$($p.Port)"
                    if ($lanIP) { $lanAddrs += "http://${lanIP}:$($p.Port)" }
                }
            }
        }
    }

    # 显示启动信息
    if ($portStr) {
        Write-Host "内核已启动 (PID: $($Process.Id) PORT: $portStr)" -ForegroundColor Green
    } else {
        Write-Host "内核已启动 (PID: $($Process.Id))" -ForegroundColor Green
    }

    if ($localAddrs.Count -gt 0) {
        Write-Host "本地代理：" -ForegroundColor Cyan
        foreach ($addr in $localAddrs) {
            Write-Host "  $addr" -ForegroundColor Gray
        }
    }

    if ($lanAddrs.Count -gt 0) {
        Write-Host "局域网代理：" -ForegroundColor Cyan
        foreach ($addr in $lanAddrs) {
            Write-Host "  $addr" -ForegroundColor Gray
        }
    }

    Write-Host ""
}

# ------------------------------------------------------------
# Get-IPCountry: 查询单个 IP 的归属国家
# 参数: -IP (IP地址字符串)
# 返回: 国家代码 (如 "US")，失败返回 $null
# ------------------------------------------------------------
function Get-IPCountry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP
    )
    
    try {
        $apiUrl = "https://api.ipinfo.io/lite/$IP`?token=$Script:IPINFO_TOKEN"
        $response = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 5 -ErrorAction Stop
        if ($response.country_code) {
            return $response.country_code
        }
        return "N/A"
    } catch {
        return $null
    }
}

# ------------------------------------------------------------
# Resolve-AddressToIP: 将地址字符串（IP / IP:port / 域名 / URL）解析为公网 IPv4
# 参数: -Address (地址字符串)
# 返回: @("1.2.3.4") 数组（可能多个）
# ------------------------------------------------------------
function Resolve-AddressToIP {
    param([string]$Address)
    
    if (-not $Address) { return @() }
    
    # 去掉引号和前后空白
    $clean = $Address.Trim().Trim('"').Trim("'")
    if ($clean.Length -eq 0) { return @() }
    
    # 处理 URL 格式 (NaiveProxy: https://user:pass@domain:port)
    if ($clean -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        try {
            $uri = [System.Uri]$clean
            $clean = $uri.Host
        } catch {
            # URL 解析失败，尝试正则提取 host
            if ($clean -match '://([^/:@]+)') {
                $clean = $Matches[1]
            }
        }
    }
    
    # 去掉端口 (ip:port 或 [ipv6]:port)
    if ($clean -match '^\[.+\]:\d+$') {
        $clean = $clean -replace '^\[(.+)\]:\d+$', '$1'
    } elseif ($clean -match '^(.+):\d+$') {
        $clean = $Matches[1]
    }
    
    # 过滤私有/回环地址
    if ($clean -match '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.0\.0\.0|::1|localhost$)') {
        return @()
    }
    
    # 已经是公网 IPv4
    if ($clean -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        # 验证每段 0-255
        $parts = $clean -split '\.'
        $valid = $true
        foreach ($p in $parts) {
            if ([int]$p -gt 255) { $valid = $false; break }
        }
        if ($valid) { return @($clean) }
    }
    
    # 已经是公网 IPv6
    if ($clean -match '^[0-9a-fA-F:]+:[0-9a-fA-F:]+$') {
        return @($clean)
    }
    
    # 域名 → DNS 解析
    if ($clean -match '\.') {
        try {
            $entry = [System.Net.Dns]::GetHostEntry($clean)
            $ips = @()
            foreach ($addr in $entry.AddressList) {
                if ($addr.AddressFamily -eq 'InterNetwork') {
                    $ip = $addr.ToString()
                    if ($ip -notmatch '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)') {
                        $ips += $ip
                    }
                }
            }
            return $ips
        } catch {
            return @()
        }
    }
    
    return @()
}

# ------------------------------------------------------------
# Read-NodeCache: 读取内核目录下的 .node_cache 文件
# 参数: -CoreDir (内核目录路径)
# 返回: @{ConfigFile; Country; IP} 数组
# ------------------------------------------------------------
function Read-NodeCache {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CoreDir
    )
    
    $cachePath = Join-Path $CoreDir ".node_cache"
    $results = @()
    
    if (Test-Path $cachePath) {
        $lines = Get-Content $cachePath -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            $parts = $line -split '\|'
            if ($parts.Count -ge 3) {
                $results += [PSCustomObject]@{
                    ConfigFile = $parts[0].Trim()
                    Country    = $parts[1].Trim()
                    IP         = $parts[2].Trim()
                }
            }
        }
    }
    
    return $results
}

# ------------------------------------------------------------
# Write-NodeCache: 写入 .node_cache（覆盖指定 config 行或追加）
# 参数: -CoreDir, -ConfigFile, -Country, -IP
# ------------------------------------------------------------
function Write-NodeCache {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CoreDir,
        [Parameter(Mandatory=$true)]
        [string]$ConfigFile,
        [Parameter(Mandatory=$true)]
        [string]$Country,
        [Parameter(Mandatory=$true)]
        [string]$IP
    )
    
    $cachePath = Join-Path $CoreDir ".node_cache"
    $newLine = "$ConfigFile|$Country|$IP"
    $lines = @()
    $found = $false
    
    if (Test-Path $cachePath) {
        $existing = Get-Content $cachePath -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $existing) {
            if ($line -match "^$([regex]::Escape($ConfigFile))\|") {
                $lines += $newLine
                $found = $true
            } elseif ($line.Trim().Length -gt 0) {
                $lines += $line
            }
        }
    }
    
    if (-not $found) {
        $lines += $newLine
    }
    
    $lines | Set-Content $cachePath -Encoding UTF8
}

# ------------------------------------------------------------
# Resolve-ServerToIP: 公共助手 — 将 server 字符串解析为 IP 地址
# 自动处理端口剥离、IPv4、IPv6、域名 DNS 解析
# 参数: -Server (原始 server 值，可含端口，如 "www.abc.xyz:13377")
# 返回: IP 地址字符串 或 $null
# ------------------------------------------------------------
function Resolve-ServerToIP {
    param([string]$Server)
    if (-not $Server) { return $null }
    $ips = @(Resolve-AddressToIP -Address $Server)
    if ($ips.Count -gt 0) { return $ips[0] }
    return $null
}

# ------------------------------------------------------------
# Get-ServerIP-Hysteria2: Hysteria / Hysteria2 / NaiveProxy / Juicity
# 扁平 JSON 结构，server 在根级
# ------------------------------------------------------------
function Get-ServerIP-Hysteria2 {
    param([string]$ConfigPath)
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.server) { return $null }
        return Resolve-ServerToIP -Server $json.server
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ServerIP-SingBox: SingBox 内核
# JSON 结构，server 在 outbounds[].server
# ------------------------------------------------------------
function Get-ServerIP-SingBox {
    param([string]$ConfigPath)
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.outbounds) { return $null }
        foreach ($outbound in $json.outbounds) {
            if ($outbound.server) {
                $ip = Resolve-ServerToIP -Server $outbound.server
                if ($ip) { return $ip }
            }
        }
        return $null
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ServerIP-Xray: Xray 内核
# JSON 结构，server 在 outbounds[].settings.vnext[0].address
# ------------------------------------------------------------
function Get-ServerIP-Xray {
    param([string]$ConfigPath)
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.outbounds) { return $null }
        foreach ($outbound in $json.outbounds) {
            if (-not ($outbound.settings -and $outbound.settings.vnext)) { continue }
            $vnext = $outbound.settings.vnext
            $vnextItem = if ($vnext -is [array]) { $vnext[0] } else { $vnext }
            if ($vnextItem.address) {
                $ip = Resolve-ServerToIP -Server $vnextItem.address
                if ($ip) { return $ip }
            }
        }
        return $null
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ServerIP-ClashMeta: Clash.Meta 内核
# YAML 结构，server 在 proxies: 块下
# ------------------------------------------------------------
function Get-ServerIP-ClashMeta {
    param([string]$ConfigPath)
    try {
        $content = Get-Content $ConfigPath -Raw -Encoding UTF8
        $lines = $content -split "`n"
        $inProxy = $false
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^proxies\s*:') {
                $inProxy = $true
                continue
            }
            if ($inProxy -and $trimmed -match '^\s*server\s*:\s*(.+)$') {
                $server = $Matches[1].Trim().Trim('"').Trim("'")
                $ip = Resolve-ServerToIP -Server $server
                if ($ip) { return $ip }
                return $null
            }
            if ($inProxy -and $line -match '^\S') {
                $inProxy = $false
            }
        }
        return $null
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ServerIP-Mieru: Mieru 内核
# JSON 结构，server 在 profiles[].servers[].ipAddress
# 兼容 domainName 兜底
# ------------------------------------------------------------
function Get-ServerIP-Mieru {
    param([string]$ConfigPath)
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.profiles) { return $null }
        foreach ($profile in $json.profiles) {
            if (-not $profile.servers) { continue }
            foreach ($server in $profile.servers) {
                if ($server.ipAddress) {
                    $ip = Resolve-ServerToIP -Server $server.ipAddress
                    if ($ip) { return $ip }
                }
                elseif ($server.domainName) {
                    $ip = Resolve-ServerToIP -Server $server.domainName
                    if ($ip) { return $ip }
                }
            }
        }
        return $null
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ServerIP-NaiveProxy: NaiveProxy 内核
# JSON 结构，proxy URL 中包含服务器地址
# 格式: "https://user:pass@host:port"
# ------------------------------------------------------------
function Get-ServerIP-NaiveProxy {
    param([string]$ConfigPath)
    try {
        $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.proxy) { return $null }
        if ($json.proxy -match '@([^:]+)') {
            return Resolve-ServerToIP -Server $Matches[1]
        }
        return $null
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ServerIP-ShadowQuic: ShadowQuic 内核
# YAML 结构，server 在 outbound.addr (host:port)
# ------------------------------------------------------------
function Get-ServerIP-ShadowQuic {
    param([string]$ConfigPath)
    try {
        $content = Get-Content $ConfigPath -Raw -Encoding UTF8
        $lines = $content -split "`n"
        $inOutbound = $false
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^outbound\s*:') {
                $inOutbound = $true
                continue
            }
            if ($inOutbound -and $trimmed -match '^addr\s*:\s*"([^"]+)"') {
                $server = ($Matches[1] -replace ':\d+$', '')
                return Resolve-ServerToIP -Server $server
            }
            if ($inOutbound -and $line -match '^\S') { break }
        }
        return $null
    } catch { return $null }
}

# ------------------------------------------------------------
# Get-ConfigServerIP: 协议分发器
# 按文件扩展名和 JSON 结构自动分发到对应协议提取函数
# 参数: -ConfigPath (配置文件路径)
# 返回: IP 地址字符串，失败返回 $null
# ------------------------------------------------------------
function Get-ConfigServerIP {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    if (-not (Test-Path $ConfigPath)) { return $null }
    
    $ext = [System.IO.Path]::GetExtension($ConfigPath).ToLower()
    
    # YAML → Clash.Meta / ShadowQuic
    if ($ext -eq '.yaml' -or $ext -eq '.yml') {
        $ip = Get-ServerIP-ClashMeta -ConfigPath $ConfigPath
        if ($ip) { return $ip }
        $ip = Get-ServerIP-ShadowQuic -ConfigPath $ConfigPath
        if ($ip) { return $ip }
    }
    
    # JSON → 按特征按序尝试（优先匹配特征最明确的协议）
    if ($ext -eq '.json') {
        # 1) 扁平 JSON (Hysteria2 等): 根级 server 字段
        $ip = Get-ServerIP-Hysteria2 -ConfigPath $ConfigPath
        if ($ip) { return $ip }
        
        # 2) Xray: outbounds[].settings.vnext 结构
        $ip = Get-ServerIP-Xray -ConfigPath $ConfigPath
        if ($ip) { return $ip }
        
        # 3) SingBox: outbounds[].server 通用结构
        $ip = Get-ServerIP-SingBox -ConfigPath $ConfigPath
        if ($ip) { return $ip }
        
        # 4) Mieru: profiles[].servers[].ipAddress 结构
        $ip = Get-ServerIP-Mieru -ConfigPath $ConfigPath
        if ($ip) { return $ip }
        
        # 5) NaiveProxy: proxy URL 中提取 @host:port
        $ip = Get-ServerIP-NaiveProxy -ConfigPath $ConfigPath
        if ($ip) { return $ip }
    }
    
    return $null
}

# ------------------------------------------------------------
# Show-NodeMenu: 渲染多节点选择菜单
# 参数: -ConfigFiles (config_*.json 文件名数组)
#       -NodeCache (Read-NodeCache 返回的缓存数组)
#       -CoreName (内核名称，用于标题显示)
# ------------------------------------------------------------
function Show-NodeMenu {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ConfigFiles,
        [AllowNull()]
        $NodeCache,
        [Parameter(Mandatory=$true)]
        [string]$CoreName
    )
    
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  $CoreName 节点选择" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++) {
        $file = $ConfigFiles[$i]
        $info = if ($NodeCache) { $NodeCache | Where-Object { $_.ConfigFile -eq $file } | Select-Object -First 1 } else { $null }
        $countryStr = ""
        $ipStr = ""
        if ($info) {
            $countryStr = $info.Country
            $ipStr = $info.IP
        }
        Write-Host "  [$($i+1)] $file  " -ForegroundColor Cyan -NoNewline
        if ($countryStr) { Write-Host "$countryStr  " -ForegroundColor Magenta -NoNewline }
        if ($ipStr) { Write-Host "$ipStr" -ForegroundColor DarkGray }
        else { Write-Host "" }
    }
    
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [U] 更新节点" -ForegroundColor Yellow
    Write-Host "  [Q] 退出脚本" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
}

# ------------------------------------------------------------
# Execute-SingleNodeUpdate: 执行单个 ip_X 脚本并处理生成后的重命名和缓存
# 参数: -ScriptName (如 "ip_1.bat"), -IPUpdateDir, -CoreDir
# 返回: $true 成功, $false 失败
# ------------------------------------------------------------
function Execute-SingleNodeUpdate {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptName,
        [Parameter(Mandatory=$true)]
        [string]$IPUpdateDir,
        [Parameter(Mandatory=$true)]
        [string]$CoreDir
    )
    
    $scriptPath = Join-Path $IPUpdateDir $ScriptName
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "  正在执行: $ScriptName" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    
    $extension = [System.IO.Path]::GetExtension($ScriptName).ToLower()
    
    try {
        $scriptDir = Split-Path $scriptPath -Parent
        $exitCode = 0
        
        if ($extension -eq ".bat") {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            $tmpErr = [System.IO.Path]::GetTempFileName()
            
            Write-Host "正在下载配置..." -NoNewline
            
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
            Write-Host " 完成" -ForegroundColor Green
        } elseif ($extension -eq ".ps1") {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$scriptPath`"" 2>&1 | ForEach-Object {
                Write-Host $_.ToString()
            }
            $exitCode = $LASTEXITCODE
        }
        
        if ($exitCode -ne 0) {
            Write-Host "警告: 脚本执行失败，错误代码: $exitCode" -ForegroundColor Yellow
            return $false
        }
        
        # === 方案 B: PS 接管，将生成的配置文件重命名为 config_X.* ===
        $index = ""
        if ($ScriptName -match 'ip[_\-](\d+)') {
            $index = $Matches[1]
        }
        
        if (-not $index) {
            Write-Host "警告: 无法从脚本名提取编号，跳过重命名" -ForegroundColor Yellow
            return $false
        }
        
        # 检测 bat 生成的文件名（config.json / config.yaml / client.yaml）
        $generatedFile = $null
        $ext = $null
        if (Test-Path (Join-Path $CoreDir "config.json")) {
            $generatedFile = Join-Path $CoreDir "config.json"
            $ext = "json"
        } elseif (Test-Path (Join-Path $CoreDir "config.yaml")) {
            $generatedFile = Join-Path $CoreDir "config.yaml"
            $ext = "yaml"
        } elseif (Test-Path (Join-Path $CoreDir "client.yaml")) {
            $generatedFile = Join-Path $CoreDir "client.yaml"
            $ext = "yaml"
        }
        
        if ($generatedFile) {
            $configNewName = "config_$index.$ext"
            $configNewPath = Join-Path $CoreDir $configNewName
            
            Move-Item -Path $generatedFile -Destination $configNewPath -Force
            Write-Host "节点配置已保存为: $configNewName" -ForegroundColor Green
            
            # 提取 server IP 并查询国家
            $serverIP = Get-ConfigServerIP -ConfigPath $configNewPath
            if ($serverIP) {
                Write-Host "节点服务器: $serverIP" -ForegroundColor Gray
                $country = Get-IPCountry -IP $serverIP
                if ($country) {
                    Write-Host "节点归属地: $country" -ForegroundColor Green
                    Write-NodeCache -CoreDir $CoreDir -ConfigFile $configNewName -Country $country -IP $serverIP
                } else {
                    Write-Host "归属地查询失败" -ForegroundColor Yellow
                    Write-NodeCache -CoreDir $CoreDir -ConfigFile $configNewName -Country "N/A" -IP $serverIP
                }
            } else {
                Write-Host "未能从配置中提取节点服务器地址" -ForegroundColor Yellow
            }
        } else {
            Write-Host "警告: 未找到生成的配置文件 (config.json / config.yaml / client.yaml)" -ForegroundColor Yellow
            return $false
        }
        
        return $true
    } catch {
        Write-Host "执行脚本时出错: $_" -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------
# Invoke-NodeUpdate: 执行 ip_X.bat 并将生成的 config 重命名为 config_X.*、更新缓存
# 参数: -IPUpdateDir (ip_Update 目录), -CoreDir (内核目录)
#       -NoConfigMode (保留兼容，当前已统一为 R 返回)
# 返回: $true 至少更新了一个节点, $false 用户跳过/退出
# ------------------------------------------------------------
function Invoke-NodeUpdate {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IPUpdateDir,
        [Parameter(Mandatory=$true)]
        [string]$CoreDir,
        [switch]$NoConfigMode
    )
    
    if (-not (Test-Path $IPUpdateDir)) {
        Write-Host "警告: IP更新目录不存在: $IPUpdateDir" -ForegroundColor Yellow
        Press-AnyKey -Message "按任意键返回..."
        return $false
    }
    
    # 用 + 运算符替代 += 避免输出流泄漏
    $batScripts = @(Get-ChildItem -Path $IPUpdateDir -Filter "*.bat" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object)
    $ps1Scripts = @(Get-ChildItem -Path $IPUpdateDir -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object)
    $ipScripts = $batScripts + $ps1Scripts
    
    if ($ipScripts.Count -eq 0) {
        Write-Host "警告: 目录下未找到任何 .bat 或 .ps1 文件！" -ForegroundColor Yellow
        Press-AnyKey -Message "按任意键返回..."
        return $false
    }
    
    # === 标题 ===
    $coreName = Split-Path $CoreDir -Leaf
    $title = if ($coreName -match '^.+$') { $coreName } else { "节点" }
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  $title 节点更新" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    for ($i = 0; $i -lt $ipScripts.Count; $i++) {
        Write-Host "  [$($i+1)]  $($ipScripts[$i])" -ForegroundColor Cyan
    }
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [A] 更新全部" -ForegroundColor Yellow
    Write-Host "  [R] 返回菜单" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    $choice = Read-Host "请选择 [1-$($ipScripts.Count), A=全部, R=返回]"
    
    # A → 更新全部
    if ($choice -eq 'a' -or $choice -eq 'A') {
        $successCount = 0
        for ($j = 0; $j -lt $ipScripts.Count; $j++) {
            $ok = Execute-SingleNodeUpdate -ScriptName $ipScripts[$j] -IPUpdateDir $IPUpdateDir -CoreDir $CoreDir
            if ($ok) { $successCount = $successCount + 1 }
        }
        Write-Host ""
        Write-Host "全部更新完成: $successCount / $($ipScripts.Count) 个节点成功" -ForegroundColor $(if ($successCount -gt 0) { "Green" } else { "Yellow" })
        Write-Host ""
        Press-AnyKey -Message "按任意键返回菜单..."
        return ($successCount -gt 0)
    }
    
    # R → 返回
    if ($choice -eq 'r' -or $choice -eq 'R') {
        return $false
    }
    
    $selectedNum = 0
    if (-not [int]::TryParse($choice, [ref]$selectedNum)) {
        Write-Host "跳过更新。" -ForegroundColor Gray
        return $false
    }
    
    if ($selectedNum -eq 0) {
        Write-Host "跳过更新。" -ForegroundColor Gray
        return $false
    }
    
    if ($selectedNum -lt 1 -or $selectedNum -gt $ipScripts.Count) {
        Write-Host "无效选择，跳过更新。" -ForegroundColor Yellow
        return $false
    }
    
    $selectedScript = $ipScripts[$selectedNum - 1]
    $ok = Execute-SingleNodeUpdate -ScriptName $selectedScript -IPUpdateDir $IPUpdateDir -CoreDir $CoreDir
    if ($ok) {
        Write-Host ""
        Press-AnyKey -Message "按任意键返回菜单..."
    }
    return $ok
}

# ------------------------------------------------------------
# Invoke-NodeMenu: 节点管理主菜单
# 扫描内核目录下的 config_*.json / config_*.yaml，提供节点选择、更新、退出
# 参数: -CoreDir (内核目录名，如 "singbox")
#       -CoreName (内核显示名称，如 "SingBox")
# 返回: 用户选择的配置文件名 (如 "config_1.json")，退出则返回 $null
# ------------------------------------------------------------
function Invoke-NodeMenu {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CoreDir,
        [Parameter(Mandatory=$true)]
        [string]$CoreName,
        [string]$ScriptRoot
    )
    
    if (-not $ScriptRoot) { $ScriptRoot = if ($Script:CHROMEGO_PATH) { $Script:CHROMEGO_PATH } else { "$PSScriptRoot" } }
    $coreDirAbs = [IO.Path]::Combine($ScriptRoot, $CoreDir)
    $ipUpdateDir = [IO.Path]::Combine($coreDirAbs, "ip_Update")
    
    while ($true) {
        # 扫描内核目录下的 config_*.json 和 config_*.yaml
        $configFiles = @()
        $configFiles += Get-ChildItem -Path $coreDirAbs -Filter "config_*.json" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
        $configFiles += Get-ChildItem -Path $coreDirAbs -Filter "config_*.yaml" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
        $configFiles = @($configFiles | Sort-Object)
        
        $nodeCache = Read-NodeCache -CoreDir $coreDirAbs
        
        if ($configFiles.Count -eq 0) {
            # 无配置文件 → 直接展示节点更新菜单（跳过中间页）
            Clear-Host
            $updated = Invoke-NodeUpdate -IPUpdateDir $ipUpdateDir -CoreDir $coreDirAbs -NoConfigMode
            Clear-Host
            if (-not $updated) {
                return $null
            }
            continue
        } else {
            # 有配置文件 → 显示完整菜单
            Show-NodeMenu -ConfigFiles $configFiles -NodeCache $nodeCache -CoreName $CoreName
            
            $choice = Read-Host "请选择操作 [1-$($configFiles.Count), U=更新, Q=退出]"
            
            # 数字选择 → 返回对应配置文件名
            if ($choice -match '^\d+$') {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $configFiles.Count) {
                    return $configFiles[$num - 1]
                }
            }
            
            # U 更新
            if ($choice -eq 'u' -or $choice -eq 'U') {
                Clear-Host
                $null = Invoke-NodeUpdate -IPUpdateDir $ipUpdateDir -CoreDir $coreDirAbs
                Clear-Host
                continue
            }
            
            # Q 退出
            if ($choice -eq 'q' -or $choice -eq 'Q') {
                return $null
            }
            
            Write-Host "无效选择！" -ForegroundColor Red
        }
    }
}
