# _env.ps1 — 加载 .env 中的 IPINFO_TOKEN，设置项目根路径
# CHROMEGO_PATH 始终为脚本所在目录，不从 .env 读取
$_envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $_envFile) {
    Get-Content $_envFile -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^\s*IPINFO_TOKEN\s*=\s*"?(.+?)"?\s*$') {
            $env:IPINFO_TOKEN = $matches[1].Trim()
        }
    }
}
$env:CHROMEGO_PATH = $PSScriptRoot
