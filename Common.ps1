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
        $ips = Resolve-AddressToIP -Address $addr
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

    if ($nodeInfos.Count -gt 0) {
        Write-Host ""
        Write-Host "========== 节点 IP 信息 ==========" -ForegroundColor Cyan
        foreach ($ni in $nodeInfos) {
            $country = Get-IPCountry -IP $ni.IP
            $label = if ($ni.Domain) { "$($ni.Domain) → $($ni.IP)" } else { $ni.IP }
            if ($country) {
                Write-Host " 📍 节点：$label`n 🌏 国家：$country" -ForegroundColor Green
            } else {
                Write-Host " 📍 节点：$label`n 🌏 国家：查询失败" -ForegroundColor Yellow
            }
        }
        Write-Host "==================================" -ForegroundColor Cyan
    } else {
        Write-Host " 失败：未在配置文件中找到节点地址" -ForegroundColor DarkGray
        Write-Host "==================================" -ForegroundColor Cyan
    }
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
