# ======================================================================
# Common.ps1 — 公共函数库
# 供所有代理启动脚本引用：. "$PSScriptRoot\Common.ps1"
# ======================================================================

# IP 信息查询 API 配置
$Script:IPINFO_TOKEN = "311cf96f8bbc1b"

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

    # 切换到脚本所在目录
    Set-Location -Path $PSScriptRoot

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
        [string]$CoreExe
    )

    $corePath = Join-Path $PSScriptRoot (Join-Path $CoreDir $CoreExe)

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

    Write-Host $Message
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ------------------------------------------------------------
# Wait-CoreStart: 等待内核启动并检查进程状态
# 参数: -Process (Start-Process 返回的进程对象)
# ------------------------------------------------------------
function Wait-CoreStart {
    param(
        [Parameter(Mandatory=$true)]
        $Process
    )

    # 等待一下确保启动
    Start-Sleep -Seconds 2

    if ($Process.HasExited) {
        Write-Host "警告: 内核可能启动失败，进程已退出。" -ForegroundColor Yellow
    } else {
        Write-Host "内核已启动 (PID: $($Process.Id))" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "内核已启动，按任意键关闭此窗口..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ------------------------------------------------------------
# Show-Menu: 显示编号菜单并获取用户选择
# 参数: -Options (数组), -TimeoutSeconds (超时秒数), -DefaultOption (超时默认值)
# ------------------------------------------------------------
function Show-Menu {
    param(
        [string[]]$Options,
        [int]$TimeoutSeconds = 17,
        [string]$DefaultOption = "0"
    )
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "$($i+1)、$($Options[$i])" -ForegroundColor Cyan
    }
    Write-Host ""
    
    $prompt = "请选择要更新的IP（默认 $DefaultOption 跳过更新）："
    Write-Host $prompt -NoNewline
    
    $startTime = Get-Date
    $keyPressed = $null
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $keyPressed = $key.KeyChar.ToString()
            if ($keyPressed -match '^\d+$') {
                Write-Host $keyPressed
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }
    
    if ($null -eq $keyPressed) {
        Write-Host $DefaultOption -ForegroundColor Yellow
        return $DefaultOption
    }
    
    return $keyPressed
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
# Get-IPsFromOutput: 从脚本输出中提取公网 IP 地址
# 参数: -Text (脚本输出文本)
# 返回: 去重后的公网 IP 数组
# ------------------------------------------------------------
function Get-IPsFromOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text
    )
    
    $ipPattern = '\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b'
    $matches = [regex]::Matches($Text, $ipPattern)
    $seen = @{}
    
    foreach ($m in $matches) {
        $ip = $m.Groups[1].Value
        # 过滤私有IP、保留IP、广播地址
        if ($ip -match '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.0\.0\.0|255\.255\.255\.255|224\.|240\.)') {
            continue
        }
        if (-not $seen.ContainsKey($ip)) {
            $seen[$ip] = $true
        }
    }
    
    return $seen.Keys
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
# Get-IPsFromConfig: 从内核配置文件中提取节点 IP/域名，并解析为 IP
# 参数: -ConfigDir (内核目录路径，如 "Xray/")
# 返回: @{IP="1.2.3.4"; Country="US"; Domain="example.com"} 数组
# 
# 策略：针对不同内核类型，从已知的节点地址字段路径精确提取，
# 而不是通配正则扫描整个文件（避免捞出 DNS/SNI/本地地址等杂项）。
# ------------------------------------------------------------
function Get-IPsFromConfig {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigDir
    )
    
    # 扫描配置文件
    $configNames = @("config.json", "config.yaml", "client.yaml")
    $configPath = $null
    foreach ($name in $configNames) {
        $path = Join-Path $ConfigDir $name
        if (Test-Path $path) {
            $configPath = $path
            break
        }
    }
    
    if (-not $configPath) { return @() }
    
    $rawText = [System.IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
    if (-not $rawText) { return @() }
    
    $ext = [System.IO.Path]::GetExtension($configPath).ToLower()
    $rawAddresses = @()
    
    # === JSON 配置文件：结构化提取 ===
    if ($ext -eq '.json') {
        try {
            $json = $rawText | ConvertFrom-Json
            $rawAddresses = Find-NodeAddressesInJson -Object $json
        } catch {
            # JSON 解析失败，回退到 YAML 式行匹配
            $rawAddresses = Find-NodeAddressesInYaml -Text $rawText
        }
    } 
    # === YAML 配置文件：键值行匹配 ===
    else {
        $rawAddresses = Find-NodeAddressesInYaml -Text $rawText
    }
    
    # 解析所有地址为 IP，去重
    $results = @()
    $seenIPs = @{}
    $seenDomains = @{}
    
    foreach ($addr in $rawAddresses) {
        $ips = @(Resolve-AddressToIP -Address $addr)
        foreach ($ip in $ips) {
            if (-not $seenIPs.ContainsKey($ip)) {
                $seenIPs[$ip] = $true
                # 判断原始地址是域名还是 IP；URL 格式（NaiveProxy）提取 host
                $domain = $null
                if ($addr -match '^https?://') {
                    # URL 格式 → 提取 hostname
                    try { $domain = ([System.Uri]$addr).Host } catch {
                        if ($addr -match '://([^/:@]+)') { $domain = $Matches[1] }
                    }
                } elseif ($addr -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -and 
                          $addr -notmatch '^[0-9a-fA-F:]+:[0-9a-fA-F:]+$' -and
                          $addr -notmatch '^\[[0-9a-fA-F:]+\](:\d+)?$') {
                    # 裸域名（非 IPv4 非 IPv6）
                    $domain = $addr
                }
                $results += [PSCustomObject]@{ IP = $ip; Domain = $domain }
            }
        }
    }
    
    return $results
}

# ------------------------------------------------------------
# Find-NodeAddressesInJson: 递归遍历 JSON 对象，提取已知节点地址字段的值
# 已知节点地址字段名（这些是真正代理服务器地址）:
#   server, address, addr, ipAddress, domainName, proxy
# 排除的字段（SNI伪装/DNS/本地监听/标签/URL中的域名）:
#   sni, server_name, server-name, serverName, resolver, dns, listen, bind-addr, tag
# ------------------------------------------------------------
function Find-NodeAddressesInJson {
    param(
        $Object,
        [string]$ParentKey = ""
    )
    
    $addresses = @()
    
    if ($Object -is [PSCustomObject] -or $Object -is [Hashtable]) {
        $props = if ($Object -is [Hashtable]) { $Object.Keys } else { $Object.PSObject.Properties.Name }
        
        foreach ($propName in $props) {
            $value = if ($Object -is [Hashtable]) { $Object[$propName] } else { $Object.$propName }
            $key = $propName.ToLower()
            
            # 检查是否是已知节点地址字段
            $isAddressKey = ($key -eq 'server' -or $key -eq 'address' -or 
                           $key -eq 'addr' -or $key -eq 'ipaddress' -or 
                           $key -eq 'domainname' -or $key -eq 'proxy')
            
            # 排除非节点字段（SNI/DNS/本地监听等）
            $isNoiseKey = ($key -eq 'sni' -or $key -eq 'server_name' -or 
                         $key -eq 'server-name' -or $key -eq 'servername' -or
                         $key -eq 'resolver' -or $key -eq 'dns' -or
                         $key -eq 'listen' -or $key -eq 'bind-addr' -or
                         $key -eq 'tag' -or $key -eq 'name')
            
            if ($isAddressKey -and -not $isNoiseKey) {
                # 是节点地址字段 → 提取值
                if ($value -is [string] -and $value.Length -gt 0) {
                    # 跳过 URL 格式的 DNS 等非节点地址（如 dns.servers[].address）
                    # 仅 proxy 键（NaiveProxy）允许 URL 格式
                    $isUrlValue = ($value -match '^https?://')
                    if ($isUrlValue -and $key -ne 'proxy') {
                        # 跳过：DNS 服务器 URL、resolver URL 等
                    } else {
                        $addresses += $value
                    }
                }
                # 如果值是对象或数组，不深入（地址字段应是标量）
            }
            
            # 递归遍历嵌套结构（数组遍历元素，对象递归）
            # 跳过噪声键的子树：dns/resolver 等子树内不提取地址
            $isNoiseParent = ($key -eq 'sni' -or $key -eq 'server_name' -or 
                            $key -eq 'server-name' -or $key -eq 'servername' -or
                            $key -eq 'resolver' -or $key -eq 'dns' -or
                            $key -eq 'listen' -or $key -eq 'bind-addr')
            
            if (-not $isNoiseParent) {
                if ($value -is [Array]) {
                    foreach ($item in $value) {
                        if ($item -is [PSCustomObject] -or $item -is [Hashtable]) {
                            $addresses += Find-NodeAddressesInJson -Object $item -ParentKey $key
                        }
                    }
                } elseif ($value -is [PSCustomObject] -or $value -is [Hashtable]) {
                    $addresses += Find-NodeAddressesInJson -Object $value -ParentKey $key
                }
            }
        }
    }
    
    return $addresses
}

# ------------------------------------------------------------
# Find-NodeAddressesInYaml: YAML 键值行匹配提取节点地址
# 用于 .yaml 和 JSON 解析失败时的回退
# ------------------------------------------------------------
function Find-NodeAddressesInYaml {
    param([string]$Text)
    
    $addresses = @()
    
    # 已知的节点地址键名（YAML 键）
    $addressKeys = @('server', 'address', 'addr', 'ipAddress', 'domainName', 'proxy')
    
    # 排除的非节点键名
    $noiseKeys = @('sni', 'server_name', 'server-name', 'serverName', 
                   'resolver', 'dns', 'listen', 'bind-addr', 'tag', 'name')
    
    # 逐行匹配：缩进无关，匹配 "key: value" 或 "key: "value"" 模式
    $lines = $Text -split "`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*(.+?)\s*:\s*(.+)$') {
            $key = $Matches[1].Trim().Trim('"').Trim("'")
            $val = $Matches[2].Trim().Trim('"').Trim("'")
            
            $keyLower = $key.ToLower()
            
            # 跳过注释和仅包含数字/布尔值的值
            if ($val -match '^\d{1,5}$' -or $val -eq 'true' -or $val -eq 'false' -or $val -eq 'null' -or $val -eq '""' -or $val -eq "''") {
                continue
            }
            
            # 跳过排除的键
            $isNoise = $false
            foreach ($nk in $noiseKeys) {
                if ($keyLower -eq $nk) { $isNoise = $true; break }
            }
            if ($isNoise) { continue }
            
            # 匹配节点地址键
            foreach ($ak in $addressKeys) {
                if ($keyLower -eq $ak) {
                    # 验证值看起来像地址（包含 IP 或域名）
                    if ($val -match '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -or
                        $val -match '[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}' -or
                        $val -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
                        $addresses += $val
                    }
                    break
                }
            }
        }
    }
    
    return $addresses
}

# ------------------------------------------------------------
# Show-NodeInfo: 从配置目录读取节点地址并显示地理位置信息
# 参数: -ConfigDir (内核目录路径)
# ------------------------------------------------------------
function Show-NodeInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigDir
    )

    $nodeInfos = Get-IPsFromConfig -ConfigDir $ConfigDir
    
    Write-Host ""
    Write-Host "========== 节点 IP 信息 ==========" -ForegroundColor Cyan

    if ($nodeInfos.Count -gt 0) {        
        foreach ($ni in $nodeInfos) {
            $country = Get-IPCountry -IP $ni.IP
            $label = if ($ni.Domain) { "$($ni.Domain) → $($ni.IP)" } else { $ni.IP }
            if ($country) {
                Write-Host " 📍 节点：$label`n 🌏 国家：$country" -ForegroundColor Green
            } else {
                Write-Host " 📍 节点：$label`n 🌏 国家：查询失败" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host " 失败：未在配置文件中找到节点地址" -ForegroundColor DarkGray        
    }
    Write-Host "==================================" -ForegroundColor Cyan
}

# ------------------------------------------------------------
# Invoke-IPUpdate: 执行 IP 更新流程（扫描目录 + 菜单选择 + 执行脚本 + 读取配置查询IP归属地）
# 参数: -IPUpdateDir (IP更新目录的绝对路径)
# ------------------------------------------------------------
function Invoke-IPUpdate {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IPUpdateDir
    )
    
    if (-not (Test-Path $IPUpdateDir)) {
        Write-Host "警告: IP更新目录不存在: $IPUpdateDir" -ForegroundColor Yellow
        Write-Host "按任意键跳过IP更新..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    # 扫描 IP 更新目录下的所有 bat 和 ps1 文件
    $ipScripts = @()
    $ipScripts += Get-ChildItem -Path $IPUpdateDir -Filter "*.bat" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
    $ipScripts += Get-ChildItem -Path $IPUpdateDir -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
    
    if ($ipScripts.Count -eq 0) {
        Write-Host "警告: 目录下未找到任何 .bat 或 .ps1 文件！" -ForegroundColor Yellow
        Write-Host "路径: $IPUpdateDir" -ForegroundColor Yellow
        Write-Host "按任意键跳过IP更新..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Write-Host "是否执行IP更新？(⚠️ 首次使用务必先更新IP)" -ForegroundColor Yellow
    Write-Host ""
    
    # 显示菜单并获取选择
    $selectedIndex = Show-Menu -Options $ipScripts -TimeoutSeconds 17 -DefaultOption "0"
    $selectedNum = [int]$selectedIndex
    
    # 如果选择 0 则跳过，但仍显示节点信息
    if ($selectedNum -eq 0) {
        Write-Host "跳过IP更新。" -ForegroundColor Gray
        
        # 即使跳过更新，也读取配置文件显示节点 IP 归属地
        $configDir = Split-Path $IPUpdateDir -Parent
        Show-NodeInfo -ConfigDir $configDir
        
        return
    }
    
    # 执行对应的脚本
    if ($selectedNum -ge 1 -and $selectedNum -le $ipScripts.Count) {
        $selectedScript = $ipScripts[$selectedNum - 1]
        $scriptPath = Join-Path $IPUpdateDir $selectedScript
        
        Write-Host "正在执行: $selectedScript" -ForegroundColor Cyan
        
        $extension = [System.IO.Path]::GetExtension($selectedScript).ToLower()
        
        try {
            # 执行脚本：bat 静默运行隐藏杂项输出，ps1 流式显示；均收集输出用于 IP 提取
            $scriptDir = Split-Path $scriptPath -Parent
            $outputLines = [System.Collections.ArrayList]::new()
            
            if ($extension -eq ".bat") {
                # bat 文件：静默执行，隐藏 wget/copy 等杂项输出
                # echo.| 用于自动应答 bat 中的 pause 命令；-Encoding OEM 解决中文 GBK 乱码
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
                
                # 静默收集输出（不打印 wget 细节，仅用于 IP 提取）
                [void]$outputLines.AddRange(@(Get-Content $tmpOut -Encoding OEM -ErrorAction SilentlyContinue))
                [void]$outputLines.AddRange(@(Get-Content $tmpErr -Encoding OEM -ErrorAction SilentlyContinue))
                
                Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
                Write-Host " 完成" -ForegroundColor Green
            } elseif ($extension -eq ".ps1") {
                # ps1 文件：通过管道流式输出
                $exitCode = 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`"$scriptPath`"" 2>&1 | ForEach-Object {
                    $line = $_.ToString()
                    Write-Host $line
                    [void]$outputLines.Add($line)
                }
                $exitCode = $LASTEXITCODE
            }
            
            if ($exitCode -ne 0) {
                Write-Host "警告: IP更新脚本执行失败，错误代码: $exitCode" -ForegroundColor Yellow
            } else {
                Write-Host "IP更新脚本执行完成。" -ForegroundColor Green
                
                # 从内核配置文件中提取节点 IP/域名 并查询地理位置
                $configDir = Split-Path $IPUpdateDir -Parent
                Show-NodeInfo -ConfigDir $configDir
            }
        } catch {
            Write-Host "执行脚本时出错: $_" -ForegroundColor Red
        }
        
        Write-Host ""
    } else {
        Write-Host "无效的选择！" -ForegroundColor Red
    }
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
# Get-ConfigServerIP: 从配置文件中提取第一个 outbound 的 server 地址
# 支持 .json 和 .yaml 两种格式
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
    
    try {
        if ($ext -eq '.json') {
            $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.outbounds) {
                foreach ($outbound in $json.outbounds) {
                    # 通用: outbound.server (singbox 等)
                    if ($outbound.server -and $outbound.server -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                        return $outbound.server
                    }
                    # IPv6 (含 : 不含 .)
                    if ($outbound.server -and $outbound.server -match ':' -and $outbound.server -notmatch '\.') {
                        return $outbound.server
                    }
                    if ($outbound.server -and $outbound.server -match '\.') {
                        $ips = @(Resolve-AddressToIP -Address $outbound.server)
                        if ($ips.Count -gt 0) { return $ips[0] }
                    }
                    # Xray: settings.vnext[0].address (VLESS/VMess)
                    if ($outbound.settings -and $outbound.settings.vnext) {
                        $vnext = $outbound.settings.vnext
                        $vnextItem = if ($vnext -is [array]) { $vnext[0] } else { $vnext }
                        if ($vnextItem.address) {
                            $addr = $vnextItem.address
                            # IPv4
                            if ($addr -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $addr }
                            # IPv6 (含 : 不含 .)
                            if ($addr -match ':' -and $addr -notmatch '\.') { return $addr }
                            # 域名 → DNS 解析
                            if ($addr -match '\.') {
                                $ips = @(Resolve-AddressToIP -Address $addr)
                                if ($ips.Count -gt 0) { return $ips[0] }
                            }
                        }
                    }
                }
            }
        } elseif ($ext -eq '.yaml' -or $ext -eq '.yml') {
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
                    # IPv4
                    if ($server -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                        return $server
                    }
                    # IPv6 (含 : 不含 .)
                    if ($server -match ':' -and $server -notmatch '\.') {
                        return $server
                    }
                    # 域名 → DNS 解析
                    if ($server -match '\.') {
                        $ips = @(Resolve-AddressToIP -Address $server)
                        if ($ips.Count -gt 0) { return $ips[0] }
                    }
                    break
                }
                # 仅当行首无缩进（顶层 YAML key）时才退出 proxies 区域
                if ($inProxy -and $line -match '^\S') {
                    $inProxy = $false
                }
            }
        }
    } catch {
        return $null
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
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  $CoreName 内核管理" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++) {
        $file = $ConfigFiles[$i]
        $info = if ($NodeCache) { $NodeCache | Where-Object { $_.ConfigFile -eq $file } | Select-Object -First 1 } else { $null }
        $countryStr = ""
        $ipStr = ""
        if ($info) {
            $countryStr = "[$($info.Country)]"
            $ipStr = $info.IP
        }
        Write-Host "  $($i+1)) $file  $countryStr  $ipStr" -ForegroundColor Cyan
    }
    
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  U) 更新节点配置" -ForegroundColor Yellow
    Write-Host "  Q) 退出脚本" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
}

# ------------------------------------------------------------
# Show-NodeUpdateMenu: 显示 ip_X.bat 选择菜单（无配置时的简化版）
# 参数: -CoreName (内核名称)
# ------------------------------------------------------------
function Show-NodeUpdateOnlyMenu {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CoreName
    )
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  $CoreName 内核管理" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  (暂无节点配置文件)" -ForegroundColor DarkGray
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  U) 更新节点配置 (唯一选项)" -ForegroundColor Yellow
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
#       -NoConfigMode (无配置模式：底部显示 Q 退出而非 0 跳过)
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
    
    $ipScripts = @()
    $ipScripts += Get-ChildItem -Path $IPUpdateDir -Filter "*.bat" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object
    $ipScripts += Get-ChildItem -Path $IPUpdateDir -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object
    
    if ($ipScripts.Count -eq 0) {
        Write-Host "警告: 目录下未找到任何 .bat 或 .ps1 文件！" -ForegroundColor Yellow
        Press-AnyKey -Message "按任意键返回..."
        return $false
    }
    
    Write-Host ""
    Write-Host "选择要更新的节点：" -ForegroundColor Yellow
    Write-Host ""
    
    for ($i = 0; $i -lt $ipScripts.Count; $i++) {
        Write-Host "$($i+1)、$($ipScripts[$i])" -ForegroundColor Cyan
    }
    Write-Host "A、更新全部" -ForegroundColor Magenta
    if ($NoConfigMode) {
        Write-Host "Q、退出脚本" -ForegroundColor Red
    } else {
        Write-Host "0、跳过更新" -ForegroundColor Cyan
    }
    Write-Host ""
    
    $promptSuffix = if ($NoConfigMode) { "A=全部, Q=退出" } else { "A=全部, 0=跳过" }
    $choice = Read-Host "请选择 [1-$($ipScripts.Count), $promptSuffix]"
    
    # A → 更新全部
    if ($choice -eq 'a' -or $choice -eq 'A') {
        $successCount = 0
        for ($j = 0; $j -lt $ipScripts.Count; $j++) {
            $ok = Execute-SingleNodeUpdate -ScriptName $ipScripts[$j] -IPUpdateDir $IPUpdateDir -CoreDir $CoreDir
            if ($ok) { $successCount++ }
        }
        Write-Host ""
        Write-Host "全部更新完成: $successCount / $($ipScripts.Count) 个节点成功" -ForegroundColor $(if ($successCount -gt 0) { "Green" } else { "Yellow" })
        Write-Host ""
        Press-AnyKey -Message "按任意键返回菜单..."
        return ($successCount -gt 0)
    }
    
    # Q → 退出（仅 NoConfigMode）
    if ($NoConfigMode -and ($choice -eq 'q' -or $choice -eq 'Q')) {
        return $false
    }
    
    $selectedNum = 0
    if (-not [int]::TryParse($choice, [ref]$selectedNum)) {
        if ($NoConfigMode) {
            Write-Host "未选择更新，退出。" -ForegroundColor Red
            return $false
        }
        Write-Host "跳过更新。" -ForegroundColor Gray
        return $false
    }
    
    if ($selectedNum -eq 0) {
        if ($NoConfigMode) {
            Write-Host "未选择更新，退出。" -ForegroundColor Red
            return $false
        }
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
# Invoke-NodeMenu: 节点管理主菜单 — 替代原 Invoke-IPUpdate 的新入口
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
        [string]$CoreName
    )
    
    $coreDirAbs = Join-Path $PSScriptRoot $CoreDir
    $ipUpdateDir = Join-Path $coreDirAbs "ip_Update"
    
    while ($true) {
        # 扫描内核目录下的 config_*.json 和 config_*.yaml
        $configFiles = @()
        $configFiles += Get-ChildItem -Path $coreDirAbs -Filter "config_*.json" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
        $configFiles += Get-ChildItem -Path $coreDirAbs -Filter "config_*.yaml" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
        $configFiles = @($configFiles | Sort-Object)
        
        $nodeCache = Read-NodeCache -CoreDir $coreDirAbs
        
        if ($configFiles.Count -eq 0) {
            # 无配置文件 → 直接展示节点更新菜单（跳过中间页）
            $updated = Invoke-NodeUpdate -IPUpdateDir $ipUpdateDir -CoreDir $coreDirAbs -NoConfigMode
            if (-not $updated) {
                return $null
            }
            continue
        } else {
            # 有配置文件 → 显示完整菜单
            Show-NodeMenu -ConfigFiles $configFiles -NodeCache $nodeCache -CoreName $CoreName
            
            $choice = Read-Host "请选择操作"
            
            # 数字选择 → 返回对应配置文件名
            if ($choice -match '^\d+$') {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $configFiles.Count) {
                    return $configFiles[$num - 1]
                }
            }
            
            # U 更新
            if ($choice -eq 'u' -or $choice -eq 'U') {
                Invoke-NodeUpdate -IPUpdateDir $ipUpdateDir -CoreDir $coreDirAbs
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

# ------------------------------------------------------------
# Confirm-Launch: 启动内核前二次确认
# 参数: -CoreName (内核名称，用于显示)
#       -TimeoutSeconds (超时秒数，超时后默认确认启动，默认10秒)
# 返回: $true 表示确认启动，$false 表示取消
# ------------------------------------------------------------
function Confirm-Launch {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CoreName,
        [int]$TimeoutSeconds = 15
    )

    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host " 🚀 启动内核: " -NoNewline
    Write-Host $CoreName -ForegroundColor Yellow -NoNewline
    Write-Host ""
    Write-Host " ⚠️ 按 " -NoNewline
    Write-Host "N" -ForegroundColor Red -NoNewline
    Write-Host " 取消，" -NoNewline
    Write-Host "${TimeoutSeconds}s" -ForegroundColor Cyan -NoNewline
    Write-Host " 后自动启动！"
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "是否启动？[Y/n] " -NoNewline -ForegroundColor White

    $startTime = Get-Date
    $keyPressed = $null

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $keyPressed = $key.KeyChar.ToString()
            break
        }
        # 每秒刷新倒计时显示
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        $remaining = $TimeoutSeconds - $elapsed
        Write-Host "`r确认启动？[Y/n]  （$remaining 秒后自动启动）  " -NoNewline -ForegroundColor White
        Start-Sleep -Milliseconds 200
    }

    Write-Host ""  # 换行

    if ($null -eq $keyPressed) {
        # 超时，默认确认
        Write-Host "  超时自动确认，正在启动..." -ForegroundColor Green
        return $true
    }

    if ($keyPressed -eq 'n' -or $keyPressed -eq 'N') {
        Write-Host "  已取消启动。" -ForegroundColor Yellow
        return $false
    }

    Write-Host "  已确认，正在启动..." -ForegroundColor Green
    return $true
}
