$ErrorActionPreference = "Stop"

$repoZipUrl = "https://github.com/mrmatias-of/assistente-glab/archive/refs/heads/main.zip"
$tempRoot = Join-Path $env:TEMP "Assistente-GLAB"
$zipPath = Join-Path $tempRoot "assistente-glab-main.zip"
$extractRoot = Join-Path $tempRoot "repo"
$appRoot = Join-Path $extractRoot "assistente-glab-main"
$scriptPath = Join-Path $appRoot "WinTool.ps1"

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}

Invoke-RestMethod -Uri $repoZipUrl -OutFile $zipPath
Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "WinTool.ps1 nao encontrado apos baixar o Assistente G-LAB."
}

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $scriptPath
