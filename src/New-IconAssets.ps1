$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$catalogPath = Join-Path $root "config\apps.json"
$iconRoot = Join-Path $root "assets\icons"

New-Item -ItemType Directory -Path $iconRoot -Force | Out-Null
$apps = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json

function Get-SafeIconName {
    param([string]$Id)
    return ($Id -replace '[^a-zA-Z0-9.-]', '_') + ".png"
}

function New-FallbackIcon {
    param([object]$App, [string]$Path)

    $bitmap = [System.Drawing.Bitmap]::new(64, 64)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $color = [System.Drawing.ColorTranslator]::FromHtml($App.accent)
    $brush = [System.Drawing.SolidBrush]::new($color)
    $graphics.FillRectangle($brush, 0, 0, 64, 64)

    $fontSize = if ($App.icon.Length -gt 2) { 16 } else { 21 }
    $font = [System.Drawing.Font]::new("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = [System.Drawing.StringFormat]::new()
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $graphics.DrawString($App.icon, $font, $white, [System.Drawing.RectangleF]::new(0, 0, 64, 64), $format)

    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

$downloaded = 0
$fallback = 0

foreach ($app in $apps) {
    $path = Join-Path $iconRoot (Get-SafeIconName -Id $app.id)
    $ok = $false

    if ($app.domain) {
        $domain = [Uri]::EscapeDataString($app.domain)
        $url = "https://www.google.com/s2/favicons?domain=$domain&sz=64"
        try {
            Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -TimeoutSec 20
            if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt 100)) {
                $ok = $true
                $downloaded++
            }
        } catch {
            $ok = $false
        }
    }

    if (-not $ok) {
        New-FallbackIcon -App $app -Path $path
        $fallback++
    }
}

"Icones reais baixados: $downloaded"
"Fallbacks gerados: $fallback"
