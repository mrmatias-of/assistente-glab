$ErrorActionPreference = "Stop"

# Troque esta URL pela URL raw do Assistente G-LAB hospedado.
$scriptUrl = "https://seu-dominio.com/WinTool.ps1"
$tempRoot = Join-Path $env:TEMP "WinTool"
$scriptPath = Join-Path $tempRoot "WinTool.ps1"

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
Invoke-RestMethod -Uri $scriptUrl -OutFile $scriptPath
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $scriptPath
