$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $root "WinTool.ps1"

if (-not (Test-Path -LiteralPath $app)) {
    throw "WinTool.ps1 nao encontrado em $root"
}

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $app
