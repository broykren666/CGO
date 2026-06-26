# _env.ps1 — 加载 .env 并设置 $env:CHROMEGO_PATH
# 供内核脚本在 dot-source Common.ps1 之前引用
$_envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $_envFile) {
    Get-Content $_envFile -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^\s*CHROMEGO_PATH\s*=\s*"?(.+?)"?\s*$') {
            $env:CHROMEGO_PATH = $matches[1].Trim()
        }
    }
}
if (-not $env:CHROMEGO_PATH) { $env:CHROMEGO_PATH = $PSScriptRoot }
