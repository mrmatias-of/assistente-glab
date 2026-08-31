param(
    [switch]$NoProfile,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:Root "config\apps.json"
$script:TweaksPath = Join-Path $script:Root "config\tweaks.json"
$script:PresetsPath = Join-Path $script:Root "config\presets.json"
$script:IconRoot = Join-Path $script:Root "assets\icons"
$script:ActiveView = "Install"
$script:SelectedAppIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:SelectedTweakNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:SelectedAppxNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:DnsPresets = @(
    [pscustomobject]@{ Name = "Padrao do provedor"; Primary = ""; Secondary = ""; Description = "Volta para DNS automatico por DHCP." },
    [pscustomobject]@{ Name = "Cloudflare"; Primary = "1.1.1.1"; Secondary = "1.0.0.1"; Description = "DNS rapido com foco em privacidade." },
    [pscustomobject]@{ Name = "Google"; Primary = "8.8.8.8"; Secondary = "8.8.4.4"; Description = "DNS publico do Google." },
    [pscustomobject]@{ Name = "Quad9"; Primary = "9.9.9.9"; Secondary = "149.112.112.112"; Description = "DNS com bloqueio de dominios maliciosos." },
    [pscustomobject]@{ Name = "AdGuard"; Primary = "94.140.14.14"; Secondary = "94.140.15.15"; Description = "DNS com bloqueio de anuncios e rastreadores." }
)
$script:AppxCatalog = @(
    [pscustomobject]@{ Name = "Clipchamp"; Package = "Clipchamp.Clipchamp"; Safe = $true },
    [pscustomobject]@{ Name = "Microsoft News"; Package = "Microsoft.BingNews"; Safe = $true },
    [pscustomobject]@{ Name = "Microsoft Weather"; Package = "Microsoft.BingWeather"; Safe = $true },
    [pscustomobject]@{ Name = "Xbox App"; Package = "Microsoft.GamingApp"; Safe = $true },
    [pscustomobject]@{ Name = "Xbox Game Bar"; Package = "Microsoft.XboxGamingOverlay"; Safe = $true },
    [pscustomobject]@{ Name = "Solitaire Collection"; Package = "Microsoft.MicrosoftSolitaireCollection"; Safe = $true },
    [pscustomobject]@{ Name = "Teams pessoal"; Package = "MicrosoftTeams"; Safe = $true },
    [pscustomobject]@{ Name = "OneNote"; Package = "Microsoft.Office.OneNote"; Safe = $false },
    [pscustomobject]@{ Name = "Fotos"; Package = "Microsoft.Windows.Photos"; Safe = $false },
    [pscustomobject]@{ Name = "Calculadora"; Package = "Microsoft.WindowsCalculator"; Safe = $false }
)

if (-not $ValidateOnly -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Load-JsonFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Name nao encontrado: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Load-AppCatalog {
    return Load-JsonFile -Path $script:ConfigPath -Name "Catalogo de apps"
}

function Load-TweakCatalog {
    return Load-JsonFile -Path $script:TweaksPath -Name "Catalogo de tweaks"
}

function Load-PresetCatalog {
    return Load-JsonFile -Path $script:PresetsPath -Name "Catalogo de presets"
}

function Write-Log {
    param([string]$Message)
    if (-not $script:LogBox) { return }
    $stamp = Get-Date -Format "HH:mm:ss"
    $script:LogBox.Dispatcher.Invoke([Action]{
        $script:LogBox.AppendText("[$stamp] $Message`r`n")
        $script:LogBox.ScrollToEnd()
    })
}

function Invoke-LoggedProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    Write-Log "> $FilePath $($Arguments -join ' ')"
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $escapedArguments = foreach ($argument in $Arguments) {
        if ($null -eq $argument) { continue }
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        } else {
            $argument
        }
    }
    $psi.Arguments = $escapedArguments -join " "
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stdout -and $stdout.Trim()) { Write-Log $stdout.Trim() }
    if ($stderr -and $stderr.Trim()) { Write-Log $stderr.Trim() }
    Write-Log "Exit code: $($process.ExitCode)"
    return $process.ExitCode
}

function Get-WingetPackageArguments {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("install", "uninstall", "upgrade")]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    if ([string]::IsNullOrWhiteSpace($PackageId) -or $PackageId -eq "na") {
        return @()
    }

    $source = "winget"
    $id = $PackageId
    if ($id.StartsWith("msstore:", [System.StringComparison]::OrdinalIgnoreCase)) {
        $source = "msstore"
        $id = $id.Substring("msstore:".Length)
    }

    switch ($Action) {
        "install" {
            return @("install", "--id", $id, "--exact", "--source", $source, "--accept-package-agreements", "--accept-source-agreements", "--silent")
        }
        "upgrade" {
            return @("upgrade", "--id", $id, "--exact", "--source", $source, "--accept-package-agreements", "--accept-source-agreements", "--silent")
        }
        "uninstall" {
            return @("uninstall", "--id", $id, "--exact", "--source", $source, "--silent")
        }
    }
}

function Get-WingetUpgradeAllArguments {
    return @("upgrade", "--all", "--include-unknown", "--accept-package-agreements", "--accept-source-agreements", "--silent")
}

function Test-AssistenteConfig {
    $ids = @{}
    foreach ($app in $script:Catalog) {
        if ([string]::IsNullOrWhiteSpace($app.name)) {
            throw "Existe app sem nome no catalogo."
        }
        if ([string]::IsNullOrWhiteSpace($app.id)) {
            throw "App sem id no catalogo: $($app.name)"
        }
        if ($ids.ContainsKey($app.id)) {
            throw "ID duplicado no catalogo: $($app.id)"
        }
        $ids[$app.id] = $true

        foreach ($actionName in @("install", "upgrade", "uninstall")) {
            $arguments = Get-WingetPackageArguments -Action $actionName -PackageId $app.id
            if ($arguments.Count -eq 0) {
                throw "Argumentos winget vazios para $($app.name) em $actionName."
            }
            if ($actionName -eq "uninstall" -and $arguments -contains "--accept-package-agreements") {
                throw "Argumento invalido no uninstall para $($app.name): --accept-package-agreements"
            }
            if (($app.id -like "msstore:*") -and -not ($arguments -contains "msstore")) {
                throw "App Microsoft Store sem source msstore: $($app.name)"
            }
        }
    }

    foreach ($preset in $script:Presets.PSObject.Properties) {
        foreach ($appId in @($preset.Value.apps)) {
            if (-not $ids.ContainsKey($appId)) {
                throw "Preset $($preset.Name) referencia app inexistente: $appId"
            }
        }
    }

    foreach ($tweak in (Get-AllTweaks)) {
        if ([string]::IsNullOrWhiteSpace($tweak.name)) {
            throw "Existe tweak sem nome no catalogo."
        }
        if ([string]::IsNullOrWhiteSpace($tweak.type)) {
            throw "Tweak sem tipo: $($tweak.name)"
        }
        if ($tweak.safe -and $tweak.type -eq "registry") {
            if ([string]::IsNullOrWhiteSpace($tweak.path) -or [string]::IsNullOrWhiteSpace($tweak.property)) {
                throw "Tweak de registro incompleto: $($tweak.name)"
            }
        }
    }
}

function Invoke-SafeUiAction {
    param(
        [Parameter(Mandatory=$true)][Alias("Action")][scriptblock]$ActionBlock,
        [string]$Name = "acao"
    )

    try {
        & $ActionBlock
    } catch {
        Write-Log "Erro ao executar ${Name}: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace
        }
    }
}

function New-IconBadge {
    param(
        [string]$Text,
        [string]$Accent = "#2563EB",
        [int]$Size = 38
    )

    $badge = [System.Windows.Controls.Border]::new()
    $badge.Width = $Size
    $badge.Height = $Size
    $badge.CornerRadius = "10"
    $badge.Background = $Accent
    $badge.Margin = "0,0,10,0"

    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = $Text
    $label.Foreground = "#FFFFFF"
    $label.FontWeight = "Bold"
    $label.FontSize = 12
    $label.HorizontalAlignment = "Center"
    $label.VerticalAlignment = "Center"
    $label.TextAlignment = "Center"
    $badge.Child = $label
    return $badge
}

function Get-AppIconPath {
    param([object]$App)
    $safeName = ($App.id -replace '[^a-zA-Z0-9.-]', '_') + ".png"
    return Join-Path $script:IconRoot $safeName
}

function New-AppIcon {
    param([object]$App)

    $path = Get-AppIconPath -App $App
    if (Test-Path -LiteralPath $path) {
        $border = [System.Windows.Controls.Border]::new()
        $border.Width = 40
        $border.Height = 40
        $border.CornerRadius = "7"
        $border.Margin = "0,0,10,0"
        $border.Background = "#E2E8F0"

        $image = [System.Windows.Controls.Image]::new()
        $image.Width = 40
        $image.Height = 40
        $image.Source = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$path)
        $border.Child = $image
        return $border
    }

    return New-IconBadge -Text $App.icon -Accent $App.accent
}

function Get-SelectedApps {
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($app in $script:Catalog) {
        if ($script:SelectedAppIds.Contains($app.id)) {
            [void]$selected.Add($app)
        }
    }
    return $selected
}

function Update-SelectedCount {
    if (-not $script:SelectedCountText) { return }
    if ($script:ActiveView -eq "Tweaks") {
        $script:SelectedCountText.Text = "Ajustes selecionados: $($script:SelectedTweakNames.Count)"
    } elseif ($script:ActiveView -eq "Appx") {
        $script:SelectedCountText.Text = "AppX selecionados: $($script:SelectedAppxNames.Count)"
    } else {
        $script:SelectedCountText.Text = "Apps selecionados: $($script:SelectedAppIds.Count)"
    }
}

function Set-AppSelection {
    param(
        [object]$App,
        [bool]$Selected
    )

    if (-not $App -or [string]::IsNullOrWhiteSpace($App.id)) { return }
    if ($Selected) {
        [void]$script:SelectedAppIds.Add($App.id)
    } else {
        [void]$script:SelectedAppIds.Remove($App.id)
    }
    Update-SelectedCount
}

function Clear-AppSelection {
    $script:SelectedAppIds.Clear()
    foreach ($child in $script:AppsPanel.Children) {
        $checkbox = $child.Tag
        if ($checkbox -and $checkbox -is [System.Windows.Controls.CheckBox]) {
            $checkbox.IsChecked = $false
        }
    }
    Update-SelectedCount
}

function Select-PresetApps {
    param([Parameter(Mandatory=$true)][string]$PresetName)

    $preset = $script:Presets.PSObject.Properties[$PresetName]
    if (-not $preset) {
        Write-Log "Preset nao encontrado: $PresetName"
        return
    }

    Clear-AppSelection
    foreach ($appId in @($preset.Value.apps)) {
        [void]$script:SelectedAppIds.Add($appId)
    }
    Refresh-AppGrid
    Write-Log "Preset aplicado: $PresetName ($($script:SelectedAppIds.Count) apps)."
}

function Select-InstalledApps {
    Invoke-SafeUiAction -Name "mostrar apps instalados" -Action {
        $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetCommand) {
            Write-Log "WinGet nao foi encontrado neste sistema."
            return
        }

        Write-Log "Lendo apps instalados pelo WinGet..."
        $originalEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
            $installedText = (& $wingetCommand.Source list --accept-source-agreements --disable-interactivity 2>&1) -join "`n"
        } finally {
            [Console]::OutputEncoding = $originalEncoding
        }

        Clear-AppSelection
        foreach ($app in $script:Catalog) {
            $packageId = ($app.id -replace "^msstore:", "")
            if ([string]::IsNullOrWhiteSpace($packageId)) { continue }
            $pattern = "(?im)[^\S\r\n]{2,}$([regex]::Escape($packageId))(?=[^\S\r\n]{2,}|$)"
            if ($installedText -match $pattern) {
                [void]$script:SelectedAppIds.Add($app.id)
            }
        }

        Refresh-AppGrid
        Write-Log "Apps instalados marcados: $($script:SelectedAppIds.Count)."
    }
}

function Set-TweakSelection {
    param(
        [object]$Tweak,
        [bool]$Selected
    )

    if (-not $Tweak -or [string]::IsNullOrWhiteSpace($Tweak.name)) { return }
    if ($Selected) {
        [void]$script:SelectedTweakNames.Add($Tweak.name)
    } else {
        [void]$script:SelectedTweakNames.Remove($Tweak.name)
    }
    Update-SelectedCount
}

function Clear-TweakSelection {
    $script:SelectedTweakNames.Clear()
    foreach ($child in $script:AppsPanel.Children) {
        $checkbox = $child.Tag
        if ($checkbox -and $checkbox -is [System.Windows.Controls.CheckBox]) {
            $checkbox.IsChecked = $false
        }
    }
    Update-SelectedCount
}

function Select-SafeTweaks {
    Clear-TweakSelection
    foreach ($tweak in (Get-AllTweaks | Where-Object { $_.safe })) {
        [void]$script:SelectedTweakNames.Add($tweak.name)
    }
    Show-TweaksView
    Write-Log "Ajustes seguros selecionados: $($script:SelectedTweakNames.Count)."
}

function New-AppCard {
    param([object]$App)

    $border = [System.Windows.Controls.Border]::new()
    $border.Margin = "5"
    $border.Padding = "9"
    $border.Width = 265
    $border.MinHeight = 72
    $border.BorderBrush = "#CBD5E1"
    $border.BorderThickness = "1"
    $border.CornerRadius = "12"
    $border.Background = "#FFFFFF"

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $checkColumn = [System.Windows.Controls.ColumnDefinition]::new()
    $checkColumn.Width = "Auto"
    $grid.ColumnDefinitions.Add($checkColumn)

    $row = [System.Windows.Controls.StackPanel]::new()
    $row.Orientation = "Horizontal"
    $row.Children.Add((New-AppIcon -App $App)) | Out-Null

    $stack = [System.Windows.Controls.StackPanel]::new()
    $name = [System.Windows.Controls.TextBlock]::new()
    $name.Text = $App.name
    $name.FontWeight = "SemiBold"
    $name.Foreground = "#0F172A"
    $name.TextWrapping = "Wrap"

    $desc = [System.Windows.Controls.TextBlock]::new()
    $desc.Text = $App.description
    $desc.Foreground = "#475569"
    $desc.Margin = "0,3,0,0"
    $desc.FontSize = 12
    $desc.TextWrapping = "Wrap"

    $id = [System.Windows.Controls.TextBlock]::new()
    $id.Text = $App.id
    $id.Foreground = "#64748B"
    $id.Margin = "0,4,0,0"
    $id.FontSize = 11
    $id.FontFamily = "Consolas"

    $stack.Children.Add($name) | Out-Null
    $stack.Children.Add($desc) | Out-Null
    $stack.Children.Add($id) | Out-Null
    $row.Children.Add($stack) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($row, 0)
    $grid.Children.Add($row) | Out-Null

    $checkbox = [System.Windows.Controls.CheckBox]::new()
    $checkbox.VerticalAlignment = "Center"
    $checkbox.Margin = "8,0,0,0"
    $checkbox.ToolTip = "Selecionar $($App.name)"
    $checkbox.Tag = $App
    $checkbox.IsChecked = $script:SelectedAppIds.Contains($App.id)
    $checkbox.Add_Checked({ Set-AppSelection -App $this.Tag -Selected $true })
    $checkbox.Add_Unchecked({ Set-AppSelection -App $this.Tag -Selected $false })
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 1)
    $grid.Children.Add($checkbox) | Out-Null

    $border.Child = $grid
    $border.Tag = $checkbox
    return $border
}

function New-InfoCard {
    param(
        [string]$Title,
        [string]$Body,
        [string]$Icon,
        [string]$Accent = "#2563EB"
    )

    $card = [System.Windows.Controls.Border]::new()
    $card.Margin = "5"
    $card.Padding = "10"
    $card.Width = 265
    $card.MinHeight = 88
    $card.BorderBrush = "#CBD5E1"
    $card.BorderThickness = "1"
    $card.CornerRadius = "12"
    $card.Background = "#FFFFFF"

    $row = [System.Windows.Controls.StackPanel]::new()
    $row.Orientation = "Horizontal"
    $row.Children.Add((New-IconBadge -Text $Icon -Accent $Accent -Size 34)) | Out-Null

    $stack = [System.Windows.Controls.StackPanel]::new()
    $titleBlock = [System.Windows.Controls.TextBlock]::new()
    $titleBlock.Text = $Title
    $titleBlock.FontWeight = "SemiBold"
    $titleBlock.FontSize = 14
    $titleBlock.Foreground = "#0F172A"

    $bodyBlock = [System.Windows.Controls.TextBlock]::new()
    $bodyBlock.Text = $Body
    $bodyBlock.Foreground = "#475569"
    $bodyBlock.Margin = "0,4,0,0"
    $bodyBlock.TextWrapping = "Wrap"
    $bodyBlock.FontSize = 12
    $bodyBlock.MaxWidth = 190

    $stack.Children.Add($titleBlock) | Out-Null
    $stack.Children.Add($bodyBlock) | Out-Null
    $row.Children.Add($stack) | Out-Null
    $card.Child = $row
    return $card
}

function New-TweakCard {
    param([object]$Tweak)

    $checkbox = [System.Windows.Controls.CheckBox]::new()
    $checkbox.Margin = "0,2,0,2"
    $checkbox.FontSize = 12
    $checkbox.Foreground = "#0F172A"
    $checkbox.Content = if ($Tweak.safe) { "$($Tweak.name)" } else { "$($Tweak.name) - planejado" }
    $checkbox.Tag = $Tweak
    $checkbox.IsEnabled = [bool]$Tweak.safe
    $checkbox.IsChecked = $script:SelectedTweakNames.Contains($Tweak.name)
    $checkbox.ToolTip = "$($Tweak.description)`nEscopo: $($Tweak.scope)"
    $checkbox.Add_Checked({ Set-TweakSelection -Tweak $this.Tag -Selected $true })
    $checkbox.Add_Unchecked({ Set-TweakSelection -Tweak $this.Tag -Selected $false })
    return $checkbox
}

function New-SectionHeader {
    param(
        [string]$Title,
        [string]$Subtitle = ""
    )

    $outer = [System.Windows.Controls.Border]::new()
    $outer.Width = 1100
    $outer.Margin = "5,10,5,5"
    $outer.Padding = "10,7"
    $outer.CornerRadius = "10"
    $outer.Background = "#E0E7FF"
    $outer.BorderBrush = "#C7D2FE"
    $outer.BorderThickness = "1"

    $panel = [System.Windows.Controls.StackPanel]::new()

    $titleBlock = [System.Windows.Controls.TextBlock]::new()
    $titleBlock.Text = $Title
    $titleBlock.FontSize = 14
    $titleBlock.FontWeight = "SemiBold"
    $titleBlock.Foreground = "#0F172A"
    $panel.Children.Add($titleBlock) | Out-Null

    if ($Subtitle) {
        $subtitleBlock = [System.Windows.Controls.TextBlock]::new()
        $subtitleBlock.Text = $Subtitle
        $subtitleBlock.FontSize = 12
        $subtitleBlock.Foreground = "#64748B"
        $subtitleBlock.Margin = "0,3,0,0"
        $panel.Children.Add($subtitleBlock) | Out-Null
    }

    $outer.Child = $panel
    return $outer
}

function Get-AllTweaks {
    $items = @()
    foreach ($category in $script:Tweaks.PSObject.Properties) {
        foreach ($tweak in @($category.Value)) {
            $items += [pscustomobject]@{
                category = $category.Name
                name = $tweak.name
                description = $tweak.description
                scope = $tweak.scope
                safe = [bool]$tweak.safe
                type = $tweak.type
                path = $tweak.path
                property = $tweak.property
                value = $tweak.value
                valueKind = $tweak.valueKind
            }
        }
    }
    return $items
}

function Set-RegistryTweak {
    param([Parameter(Mandatory=$true)][psobject]$Tweak)

    if ([string]::IsNullOrWhiteSpace($Tweak.path) -or [string]::IsNullOrWhiteSpace($Tweak.property)) {
        throw "Tweak de registro incompleto: $($Tweak.name)"
    }

    if (-not (Test-Path -LiteralPath $Tweak.path)) {
        New-Item -Path $Tweak.path -Force | Out-Null
    }

    $propertyType = if ([string]::IsNullOrWhiteSpace($Tweak.valueKind)) { "DWord" } else { $Tweak.valueKind }
    New-ItemProperty -Path $Tweak.path -Name $Tweak.property -Value $Tweak.value -PropertyType $propertyType -Force | Out-Null
}

function Invoke-TweakItem {
    param([Parameter(Mandatory=$true)][psobject]$Tweak)

    if (-not $Tweak.safe) {
        Write-Log "Tweak ignorado por nao estar marcado como seguro: $($Tweak.name)"
        return
    }

    switch ($Tweak.type) {
        "registry" {
            Set-RegistryTweak -Tweak $Tweak
            Write-Log "Tweak aplicado: $($Tweak.name)"
        }
        default {
            Write-Log "Tweak ainda nao implementado: $($Tweak.name)"
        }
    }
}

function Clear-MainPanel {
    $script:AppsPanel.Children.Clear()
}

function Write-Status {
    param([string]$Section, [string]$Detail)
    if ($script:StatusText) {
        $script:StatusText.Text = "$Section - $Detail"
    }
}

function Refresh-AppGrid {
    $script:ActiveView = "Install"
    $query = $script:SearchBox.Text.Trim().ToLowerInvariant()
    $category = $script:CategoryBox.SelectedItem.Tag

    Clear-MainPanel
    $apps = $script:Catalog | Where-Object {
        $category -eq "All" -or $_.category -eq $category
    } | Where-Object {
        if (-not $query) { return $true }
        $haystack = "$($_.name) $($_.id) $($_.category) $($_.description) $($_.tags -join ' ')".ToLowerInvariant()
        return $haystack.Contains($query)
    } | Sort-Object category, name

    $lastCategory = $null
    foreach ($app in $apps) {
        if ($app.category -ne $lastCategory) {
            $script:AppsPanel.Children.Add((New-SectionHeader -Title $app.category -Subtitle "Aplicativos disponiveis para instalacao, atualizacao ou remocao.")) | Out-Null
            $lastCategory = $app.category
        }
        $script:AppsPanel.Children.Add((New-AppCard -App $app)) | Out-Null
    }

    Update-SelectedCount
    Write-Status "Instalar" "$($apps.Count) apps visiveis"
}

function Show-TweaksView {
    $script:ActiveView = "Tweaks"
    Clear-MainPanel

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.Width = 930
    $grid.Margin = "4"
    $left = [System.Windows.Controls.ColumnDefinition]::new()
    $left.Width = "*"
    $right = [System.Windows.Controls.ColumnDefinition]::new()
    $right.Width = "*"
    $grid.ColumnDefinitions.Add($left)
    $grid.ColumnDefinitions.Add($right)

    $leftPanel = [System.Windows.Controls.StackPanel]::new()
    $rightPanel = [System.Windows.Controls.StackPanel]::new()

    $leftBorder = [System.Windows.Controls.Border]::new()
    $leftBorder.Padding = "10"
    $leftBorder.Margin = "0,0,5,0"
    $leftBorder.Background = "#FFFFFF"
    $leftBorder.BorderBrush = "#CBD5E1"
    $leftBorder.BorderThickness = "1"
    $leftBorder.CornerRadius = "8"
    $leftBorder.Child = $leftPanel

    $rightBorder = [System.Windows.Controls.Border]::new()
    $rightBorder.Padding = "10"
    $rightBorder.Margin = "5,0,0,0"
    $rightBorder.Background = "#FFFFFF"
    $rightBorder.BorderBrush = "#CBD5E1"
    $rightBorder.BorderThickness = "1"
    $rightBorder.CornerRadius = "8"
    $rightBorder.Child = $rightPanel

    [System.Windows.Controls.Grid]::SetColumn($leftBorder, 0)
    [System.Windows.Controls.Grid]::SetColumn($rightBorder, 1)
    $grid.Children.Add($leftBorder) | Out-Null
    $grid.Children.Add($rightBorder) | Out-Null

    $titleLeft = [System.Windows.Controls.TextBlock]::new()
    $titleLeft.Text = "Ajustes essenciais e avancados"
    $titleLeft.FontFamily = "Consolas"
    $titleLeft.FontSize = 13
    $titleLeft.Foreground = "#0F172A"
    $titleLeft.Margin = "0,0,0,6"
    $leftPanel.Children.Add($titleLeft) | Out-Null

    $titleRight = [System.Windows.Controls.TextBlock]::new()
    $titleRight.Text = "Preferencias rapidas"
    $titleRight.FontFamily = "Consolas"
    $titleRight.FontSize = 13
    $titleRight.Foreground = "#0F172A"
    $titleRight.Margin = "0,0,0,8"
    $rightPanel.Children.Add($titleRight) | Out-Null

    foreach ($tweak in (Get-AllTweaks | Sort-Object category, name)) {
        $headerText = $null
        if ($script:lastTweakCategory -ne $tweak.category) {
            $headerText = $tweak.category
            $script:lastTweakCategory = $tweak.category
        }

        $targetPanel = if ($tweak.category -in @("Aparencia", "Barra de tarefas e menu iniciar")) { $rightPanel } else { $leftPanel }
        if ($headerText) {
            $header = [System.Windows.Controls.TextBlock]::new()
            $header.Text = $headerText
            $header.FontFamily = "Consolas"
            $header.FontSize = 12
            $header.Margin = "0,8,0,3"
            $header.Foreground = "#334155"
            $targetPanel.Children.Add($header) | Out-Null
        }
        $targetPanel.Children.Add((New-TweakCard -Tweak $tweak)) | Out-Null
    }
    $script:lastTweakCategory = $null
    $script:AppsPanel.Children.Add($grid) | Out-Null
    $safeCount = @((Get-AllTweaks) | Where-Object { $_.safe }).Count
    Update-SelectedCount
    Write-Status "Ajustes" "$safeCount ajustes seguros disponiveis"
}

function Show-ConfigView {
    $script:ActiveView = "Config"
    Clear-MainPanel
    $adminStatus = if (Test-IsAdmin) { "Executando elevado." } else { "Nao elevado; algumas acoes podem pedir permissao." }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    $wingetStatus = if ($winget) { "Disponivel: $($winget.Source)" } else { "Nao encontrado no PATH desta sessao." }
    $presetCount = @($script:Presets.PSObject.Properties).Count
    $tweakCount = @((Get-AllTweaks)).Count
    $script:AppsPanel.Children.Add((New-SectionHeader -Title "Diagnostico do ambiente" -Subtitle "Leitura local do estado usado pelo Assistente G-LAB antes de executar acoes.")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Catalogo JSON" -Body $script:ConfigPath -Icon "JS" -Accent "#2563EB")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Administrador" -Body $adminStatus -Icon "AD" -Accent "#64748B")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "WinGet" -Body $wingetStatus -Icon "WG" -Accent "#7C3AED")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Predefinicoes" -Body "$presetCount predefinicoes carregadas de $script:PresetsPath" -Icon "PR" -Accent "#0EA5E9")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Ajustes" -Body "$tweakCount ajustes carregados de $script:TweaksPath" -Icon "AJ" -Accent "#16A34A")) | Out-Null
    Write-Status "Configurar" "Ambiente e configuracoes inspecionados"
}

function Show-UpdatesView {
    $script:ActiveView = "Updates"
    Clear-MainPanel
    $script:AppsPanel.Children.Add((New-SectionHeader -Title "Atualizacoes" -Subtitle "Fluxos de atualizacao usando WinGet com argumentos validados.")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Atualizar selecionados" -Body "Usa o mesmo fluxo validado de pacotes, com fonte winget/msstore por app." -Icon "AT" -Accent "#2563EB")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Atualizar todos" -Body "Executa winget upgrade --all --include-unknown com aceite de acordos e modo silencioso." -Icon "ALL" -Accent "#DC2626")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Registro" -Body "O resultado aparece no console de log abaixo." -Icon "LOG" -Accent "#111827")) | Out-Null
    Write-Status "Atualizar" "Acoes de atualizacao disponiveis"
}

function Show-AppxView {
    $script:ActiveView = "Appx"
    Clear-MainPanel
    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.Width = 930
    $panel.Margin = "6"
    $panel.Children.Add((New-SectionHeader -Title "Remocao de AppX" -Subtitle "Marque apps provisionados seguros para remocao. Itens sensiveis ficam bloqueados.")) | Out-Null
    foreach ($appx in $script:AppxCatalog) {
        $checkbox = [System.Windows.Controls.CheckBox]::new()
        $checkbox.Content = if ($appx.Safe) { "$($appx.Name) ($($appx.Package))" } else { "$($appx.Name) - sensivel/bloqueado" }
        $checkbox.Margin = "8,2,0,2"
        $checkbox.FontSize = 12
        $checkbox.Tag = $appx
        $checkbox.IsEnabled = [bool]$appx.Safe
        $checkbox.IsChecked = $script:SelectedAppxNames.Contains($appx.Package)
        $checkbox.Add_Checked({ Set-AppxSelection -Appx $this.Tag -Selected $true })
        $checkbox.Add_Unchecked({ Set-AppxSelection -Appx $this.Tag -Selected $false })
        $panel.Children.Add($checkbox) | Out-Null
    }
    $script:AppsPanel.Children.Add($panel) | Out-Null
    Update-SelectedCount
    Write-Status "AppX" "$(@($script:AppxCatalog | Where-Object Safe).Count) remocoes seguras disponiveis"
}

function Show-Win11View {
    $script:ActiveView = "Win11"
    Clear-MainPanel
    $script:AppsPanel.Children.Add((New-SectionHeader -Title "Windows 11 Creator" -Subtitle "Area para preparar ISO/USB do Windows 11. Por seguranca, a primeira versao abre a fonte oficial.")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Baixar Windows 11" -Body "Abre a pagina oficial da Microsoft para ISO, assistente de instalacao e media creation tool." -Icon "11" -Accent "#2563EB")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "AutoUnattend" -Body "Planejado: gerar arquivo de instalacao automatizada em etapa dedicada." -Icon "AU" -Accent "#7C3AED")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Drivers e debloat offline" -Body "Planejado: inserir drivers e aplicar ajustes em imagem offline." -Icon "ISO" -Accent "#0F766E")) | Out-Null
    Write-Status "Windows 11" "Criador preparado"
}

function Invoke-WingetForSelection {
    param([ValidateSet("install", "uninstall", "upgrade")][string]$Action)

    Invoke-SafeUiAction -Name "winget $Action" -Action {
        $apps = Get-SelectedApps
        if ($apps.Count -eq 0) {
            Write-Log "Nenhum app selecionado."
            return
        }

        $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetCommand) {
            Write-Log "WinGet nao foi encontrado neste sistema."
            return
        }

        foreach ($app in $apps) {
            Write-Log "${Action}: $($app.name)"
            $args = Get-WingetPackageArguments -Action $Action -PackageId $app.id
            if ($args.Count -eq 0) {
                Write-Log "Pacote ignorado: id vazio ou nao suportado para $($app.name)."
                continue
            }
            Invoke-LoggedProcess -FilePath $wingetCommand.Source -Arguments $args | Out-Null
        }
    }
}

function Invoke-UpgradeAll {
    Invoke-SafeUiAction -Name "winget upgrade --all" -Action {
        $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetCommand) {
            Write-Log "WinGet nao foi encontrado neste sistema."
            return
        }
        Invoke-LoggedProcess -FilePath $wingetCommand.Source -Arguments (Get-WingetUpgradeAllArguments) | Out-Null
    }
}

function Invoke-SafeTweaks {
    Invoke-SafeUiAction -Name "tweaks seguros" -Action {
        $selectedTweaks = @((Get-AllTweaks) | Where-Object { $_.safe -and $script:SelectedTweakNames.Contains($_.name) })
        if ($selectedTweaks.Count -eq 0) {
            Write-Log "Nenhum ajuste seguro selecionado."
            return
        }

        Write-Log "Aplicando $($selectedTweaks.Count) ajustes selecionados."
        foreach ($tweak in $selectedTweaks) {
            Invoke-TweakItem -Tweak $tweak
        }
        Write-Log "Ajustes selecionados finalizados."
    }
}

function Set-GLabDns {
    param([Parameter(Mandatory=$true)][psobject]$Preset)
    Invoke-SafeUiAction -Name "Configurar DNS" -Action {
        $adapters = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" })
        if ($adapters.Count -eq 0) { Write-Log "Nenhum adaptador de rede ativo encontrado."; return }
        foreach ($adapter in $adapters) {
            if ([string]::IsNullOrWhiteSpace($Preset.Primary)) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses
                Write-Log "DNS automatico restaurado em $($adapter.Name)."
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($Preset.Primary, $Preset.Secondary)
                Write-Log "DNS $($Preset.Name) aplicado em $($adapter.Name): $($Preset.Primary), $($Preset.Secondary)."
            }
        }
    }
}

function Invoke-SystemRepair {
    Invoke-SafeUiAction -Name "Reparo do sistema" -Action {
        Write-Log "Iniciando DISM /RestoreHealth."
        Invoke-LoggedProcess -FilePath "dism.exe" -Arguments @("/Online", "/Cleanup-Image", "/RestoreHealth") | Out-Null
        Write-Log "Iniciando SFC /scannow."
        Invoke-LoggedProcess -FilePath "sfc.exe" -Arguments @("/scannow") | Out-Null
    }
}

function Set-WindowsUpdateMode {
    param([ValidateSet("Padrao", "Seguranca", "Desativar")][string]$Mode)
    Invoke-SafeUiAction -Name "Configurar Windows Update" -Action {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        switch ($Mode) {
            "Padrao" {
                Remove-ItemProperty -Path $path -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $path -Name "AUOptions" -ErrorAction SilentlyContinue
                Write-Log "Windows Update restaurado para o comportamento padrao."
            }
            "Seguranca" {
                New-ItemProperty -Path $path -Name "AUOptions" -Value 3 -PropertyType DWord -Force | Out-Null
                Write-Log "Windows Update configurado para baixar e avisar antes de instalar."
            }
            "Desativar" {
                New-ItemProperty -Path $path -Name "NoAutoUpdate" -Value 1 -PropertyType DWord -Force | Out-Null
                Write-Log "Atualizacoes automaticas desativadas por politica local."
            }
        }
    }
}

function Set-AppxSelection {
    param([object]$Appx, [bool]$Selected)
    if (-not $Appx) { return }
    if ($Selected) { [void]$script:SelectedAppxNames.Add($Appx.Package) } else { [void]$script:SelectedAppxNames.Remove($Appx.Package) }
    Update-SelectedCount
}

function Invoke-AppxRemoval {
    Invoke-SafeUiAction -Name "Remover AppX" -Action {
        $selected = @($script:AppxCatalog | Where-Object { $script:SelectedAppxNames.Contains($_.Package) -and $_.Safe })
        if ($selected.Count -eq 0) { Write-Log "Nenhum AppX seguro selecionado para remocao."; return }
        foreach ($appx in $selected) {
            Write-Log "Removendo AppX: $($appx.Name)"
            Get-AppxPackage -Name $appx.Package -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $appx.Package } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Log "Remocao AppX finalizada."
    }
}

function Open-Windows11Creator {
    Invoke-SafeUiAction -Name "Windows 11 Creator" -Action {
        Write-Log "Abrindo download oficial do Windows 11. Criador de ISO/USB avancado sera implementado em etapa dedicada."
        Start-Process "https://www.microsoft.com/software-download/windows11"
    }
}

function Build-Ui {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Assistente G-LAB" Height="760" Width="1220" WindowStartupLocation="CenterScreen"
        Background="#EEF2F7" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="#0F172A"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="68"/>
            <RowDefinition Height="46"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="150"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#070B1A" Padding="18,14">
            <DockPanel LastChildFill="True">
                <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
                    <Border Width="48" Height="48" CornerRadius="14" Background="#111827" Margin="0,0,12,0" BorderBrush="#22D3EE" BorderThickness="1">
                        <TextBlock Text="GL" Foreground="#FFFFFF" FontWeight="Bold" FontSize="17" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Assistente G-LAB" FontSize="24" FontWeight="SemiBold" Foreground="#F8FAFC"/>
                        <TextBlock Text="Central de instalacao, ajustes e manutencao Windows" FontSize="12" Foreground="#93C5FD"/>
                    </StackPanel>
                </StackPanel>
                <Border DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center" Background="#0F172A" BorderBrush="#1E40AF" BorderThickness="1" CornerRadius="18" Padding="14,7">
                    <TextBlock x:Name="StatusText" Foreground="#BFDBFE"/>
                </Border>
            </DockPanel>
        </Border>

        <DockPanel Grid.Row="1" LastChildFill="True" Margin="16,12,16,8">
            <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                <Button x:Name="InstallTab" Content="Instalar" Width="118" Margin="0,0,8,0"/>
                <Button x:Name="TweaksTab" Content="Ajustes" Width="118" Margin="0,0,8,0"/>
                <Button x:Name="ConfigTab" Content="Configurar" Width="118" Margin="0,0,8,0"/>
                <Button x:Name="UpdatesTab" Content="Atualizar" Width="118" Margin="0,0,8,0"/>
                <Button x:Name="AppxTab" Content="AppX" Width="92" Margin="0,0,8,0"/>
                <Button x:Name="Win11Tab" Content="Win11" Width="92" Margin="0,0,8,0"/>
            </StackPanel>
            <TextBox x:Name="SearchBox" Height="31" Margin="10,0,0,0" Padding="10,0" VerticalContentAlignment="Center"
                     BorderBrush="#CBD5E1" Background="#FFFFFF" Foreground="#0F172A" ToolTip="Buscar por nome, categoria, id ou tag"/>
        </DockPanel>

        <Grid Grid.Row="2" Margin="16,0,16,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="230"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Padding="14" Background="#FFFFFF" BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="14">
                <StackPanel>
                    <TextBlock Text="Acoes" FontSize="16" FontWeight="SemiBold" Foreground="#0F172A" Margin="0,0,0,10"/>
                    <Button x:Name="InstallButton" Content="+ Instalar selecionados" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="UpgradeButton" Content="↑ Atualizar selecionados" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="UninstallButton" Content="− Desinstalar selecionados" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="UpgradeAllButton" Content="Atualizar todos os apps" Margin="0,0,0,10" Height="29"/>
                    <TextBlock Text="Predefinicoes" FontSize="13" FontWeight="SemiBold" Foreground="#334155" Margin="0,0,0,5"/>
                    <ComboBox x:Name="PresetBox" Height="29" Margin="0,0,0,5"/>
                    <Button x:Name="ApplyPresetButton" Content="Aplicar predefinicao" Margin="0,0,0,10" Height="29"/>
                    <TextBlock Text="DNS" FontSize="13" FontWeight="SemiBold" Foreground="#334155" Margin="0,0,0,5"/>
                    <ComboBox x:Name="DnsBox" Height="29" Margin="0,0,0,5"/>
                    <Button x:Name="ApplyDnsButton" Content="Aplicar DNS" Margin="0,0,0,10" Height="29"/>
                    <TextBlock Text="Gerenciador" FontSize="13" FontWeight="SemiBold" Foreground="#334155" Margin="0,0,0,5"/>
                    <RadioButton Content="WinGet" IsChecked="True" Margin="12,0,0,12"/>
                    <TextBlock Text="Selecao e sistema" FontSize="13" FontWeight="SemiBold" Foreground="#334155" Margin="0,0,0,5"/>
                    <Button x:Name="ClearButton" Content="Limpar selecao" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="InstalledButton" Content="Marcar instalados" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="SelectTweaksButton" Content="Selecionar ajustes seguros" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="ApplyTweaksButton" Content="Aplicar ajustes marcados" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="RemoveAppxButton" Content="Remover AppX marcados" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="RepairButton" Content="Reparar Windows" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="UpdateDefaultButton" Content="Updates: padrao" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="UpdateSecurityButton" Content="Updates: avisar" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="UpdateDisableButton" Content="Updates: desativar" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="Win11CreatorButton" Content="Abrir Win11 Creator" Margin="0,0,0,5" Height="29"/>
                    <Button x:Name="ReloadButton" Content="Recarregar catalogos" Margin="0,0,0,10" Height="29"/>
                    <Border Background="#F1F5F9" CornerRadius="10" Padding="10" Margin="0,4,0,0">
                        <StackPanel>
                            <TextBlock x:Name="SelectedCountText" Text="Selecionados: 0" FontWeight="SemiBold" Foreground="#0F172A"/>
                            <TextBlock x:Name="AdminText" Text="" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#047857"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Border>

            <DockPanel Grid.Column="1" Margin="10,0,0,0">
                <ComboBox x:Name="CategoryBox" DockPanel.Dock="Top" Height="30" Margin="0,0,0,6" Padding="8,0"/>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="Transparent">
                    <WrapPanel x:Name="AppsPanel"/>
                </ScrollViewer>
            </DockPanel>
        </Grid>

        <Border Grid.Row="3" Margin="16,10,16,14" Padding="10" Background="#0B1020" CornerRadius="14">
            <TextBox x:Name="LogBox" Background="#0F172A" Foreground="#E5E7EB" BorderThickness="0"
                     FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="Wrap"
                     VerticalScrollBarVisibility="Auto"/>
        </Border>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

$script:Catalog = Load-AppCatalog
$script:Tweaks = Load-TweakCatalog
$script:Presets = Load-PresetCatalog
$script:ValidationRan = $false
$window = Build-Ui
if (-not $window) {
    throw "Nao foi possivel carregar a janela WPF do Assistente G-LAB."
}

$script:SearchBox = $window.FindName("SearchBox")
$script:CategoryBox = $window.FindName("CategoryBox")
$script:PresetBox = $window.FindName("PresetBox")
$script:DnsBox = $window.FindName("DnsBox")
$script:AppsPanel = $window.FindName("AppsPanel")
$script:LogBox = $window.FindName("LogBox")
$script:SelectedCountText = $window.FindName("SelectedCountText")
$script:StatusText = $window.FindName("StatusText")
$adminText = $window.FindName("AdminText")

$categories = @([pscustomobject]@{ Label = "Todos"; Value = "All" }) + (($script:Catalog | Select-Object -ExpandProperty category -Unique | Sort-Object) | ForEach-Object {
    [pscustomobject]@{ Label = $_; Value = $_ }
})
foreach ($category in $categories) {
    $item = [System.Windows.Controls.ComboBoxItem]::new()
    $item.Content = $category.Label
    $item.Tag = $category.Value
    $script:CategoryBox.Items.Add($item) | Out-Null
}
$script:CategoryBox.SelectedIndex = 0

foreach ($preset in $script:Presets.PSObject.Properties) {
    $item = [System.Windows.Controls.ComboBoxItem]::new()
    $item.Content = "$($preset.Name) - $($preset.Value.description)"
    $item.Tag = $preset.Name
    $script:PresetBox.Items.Add($item) | Out-Null
}
if ($script:PresetBox.Items.Count -gt 0) {
    $script:PresetBox.SelectedIndex = 0
}

foreach ($dns in $script:DnsPresets) {
    $item = [System.Windows.Controls.ComboBoxItem]::new()
    $item.Content = $dns.Name
    $item.Tag = $dns
    $script:DnsBox.Items.Add($item) | Out-Null
}
if ($script:DnsBox.Items.Count -gt 0) {
    $script:DnsBox.SelectedIndex = 0
}

$window.FindName("InstallButton").Add_Click({ Invoke-SafeUiAction -Name "Instalar selecionados" -Action { Invoke-WingetForSelection -Action "install" } })
$window.FindName("UpgradeButton").Add_Click({ Invoke-SafeUiAction -Name "Atualizar selecionados" -Action { Invoke-WingetForSelection -Action "upgrade" } })
$window.FindName("UninstallButton").Add_Click({ Invoke-SafeUiAction -Name "Desinstalar selecionados" -Action { Invoke-WingetForSelection -Action "uninstall" } })
$window.FindName("UpgradeAllButton").Add_Click({ Invoke-SafeUiAction -Name "Atualizar todos os apps" -Action { Invoke-UpgradeAll } })
$window.FindName("ApplyPresetButton").Add_Click({
    if ($script:PresetBox.SelectedItem) {
        Select-PresetApps -PresetName $script:PresetBox.SelectedItem.Tag
    }
})
$window.FindName("InstalledButton").Add_Click({ Select-InstalledApps })
$window.FindName("SelectTweaksButton").Add_Click({ Select-SafeTweaks })
$window.FindName("ApplyTweaksButton").Add_Click({ Invoke-SafeUiAction -Name "Aplicar ajustes seguros" -Action { Invoke-SafeTweaks } })
$window.FindName("ApplyDnsButton").Add_Click({
    if ($script:DnsBox.SelectedItem) {
        Set-GLabDns -Preset $script:DnsBox.SelectedItem.Tag
    }
})
$window.FindName("RemoveAppxButton").Add_Click({ Invoke-AppxRemoval })
$window.FindName("RepairButton").Add_Click({ Invoke-SystemRepair })
$window.FindName("UpdateDefaultButton").Add_Click({ Set-WindowsUpdateMode -Mode "Padrao" })
$window.FindName("UpdateSecurityButton").Add_Click({ Set-WindowsUpdateMode -Mode "Seguranca" })
$window.FindName("UpdateDisableButton").Add_Click({ Set-WindowsUpdateMode -Mode "Desativar" })
$window.FindName("Win11CreatorButton").Add_Click({ Open-Windows11Creator })
$window.FindName("ReloadButton").Add_Click({
    $script:Catalog = Load-AppCatalog
    $script:Tweaks = Load-TweakCatalog
    $script:Presets = Load-PresetCatalog
    Test-AssistenteConfig
    Write-Log "Configuracoes recarregadas: $($script:Catalog.Count) apps, $(@((Get-AllTweaks)).Count) tweaks, $(@($script:Presets.PSObject.Properties).Count) presets."
    if ($script:ActiveView -eq "Tweaks") {
        Show-TweaksView
    } elseif ($script:ActiveView -eq "Config") {
        Show-ConfigView
    } elseif ($script:ActiveView -eq "Updates") {
        Show-UpdatesView
    } else {
        Refresh-AppGrid
    }
})
$window.FindName("ClearButton").Add_Click({
    if ($script:ActiveView -eq "Tweaks") {
        Clear-TweakSelection
    } elseif ($script:ActiveView -eq "Appx") {
        $script:SelectedAppxNames.Clear()
        Show-AppxView
    } else {
        Clear-AppSelection
    }
})

$window.FindName("InstallTab").Add_Click({ Refresh-AppGrid })
$window.FindName("TweaksTab").Add_Click({ Show-TweaksView })
$window.FindName("ConfigTab").Add_Click({ Show-ConfigView })
$window.FindName("UpdatesTab").Add_Click({ Show-UpdatesView })
$window.FindName("AppxTab").Add_Click({ Show-AppxView })
$window.FindName("Win11Tab").Add_Click({ Show-Win11View })
$script:SearchBox.Add_TextChanged({
    if ($script:ActiveView -eq "Install") { Refresh-AppGrid }
})
$script:CategoryBox.Add_SelectionChanged({
    if ($script:ActiveView -eq "Install") { Refresh-AppGrid }
})

if (Test-IsAdmin) {
    $adminText.Text = "Executando como administrador."
} else {
    $adminText.Text = "Sem administrador. Instalar apps pode pedir elevacao."
    $adminText.Foreground = "#B45309"
}

Write-Log "Assistente G-LAB iniciado. Catalogo carregado: $($script:Catalog.Count) apps."
Refresh-AppGrid
if ($ValidateOnly) {
    Test-AssistenteConfig
    $script:ValidationRan = $true
    "ValidateOnly OK: $($script:Catalog.Count) apps, $(@((Get-AllTweaks)).Count) tweaks e $(@($script:Presets.PSObject.Properties).Count) presets carregados."
    return
}
if (-not $window) {
    throw "A janela WPF nao foi inicializada. Execute novamente com powershell.exe -STA."
}

[void]$window.ShowDialog()
