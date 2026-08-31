param(
    [switch]$NoProfile,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:Root "config\apps.json"
$script:IconRoot = Join-Path $script:Root "assets\icons"
$script:ActiveView = "Install"

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

function Load-AppCatalog {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "Catalogo nao encontrado: $script:ConfigPath"
    }
    return Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
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
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stdout.Trim()) { Write-Log $stdout.Trim() }
    if ($stderr.Trim()) { Write-Log $stderr.Trim() }
    Write-Log "Exit code: $($process.ExitCode)"
    return $process.ExitCode
}

function Invoke-SafeUiAction {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [string]$Name = "acao"
    )

    try {
        & $Action
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
    $badge.CornerRadius = "7"
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
    foreach ($child in $script:AppsPanel.Children) {
        $checkbox = $child.Tag
        if ($checkbox -and $checkbox.IsChecked) {
            [void]$selected.Add($checkbox.Tag)
        }
    }
    return $selected
}

function Update-SelectedCount {
    if (-not $script:SelectedCountText) { return }
    $count = (Get-SelectedApps).Count
    $script:SelectedCountText.Text = "Selecionados: $count"
}

function New-AppCard {
    param([object]$App)

    $border = [System.Windows.Controls.Border]::new()
    $border.Margin = "5"
    $border.Padding = "10"
    $border.MinHeight = 72
    $border.BorderBrush = "#CBD5E1"
    $border.BorderThickness = "1"
    $border.CornerRadius = "6"
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
    $checkbox.Tag = $App
    $checkbox.Add_Checked({ Update-SelectedCount })
    $checkbox.Add_Unchecked({ Update-SelectedCount })
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
    $card.Padding = "12"
    $card.BorderBrush = "#CBD5E1"
    $card.BorderThickness = "1"
    $card.CornerRadius = "6"
    $card.Background = "#FFFFFF"

    $row = [System.Windows.Controls.StackPanel]::new()
    $row.Orientation = "Horizontal"
    $row.Children.Add((New-IconBadge -Text $Icon -Accent $Accent -Size 34)) | Out-Null

    $stack = [System.Windows.Controls.StackPanel]::new()
    $titleBlock = [System.Windows.Controls.TextBlock]::new()
    $titleBlock.Text = $Title
    $titleBlock.FontWeight = "SemiBold"
    $titleBlock.Foreground = "#0F172A"

    $bodyBlock = [System.Windows.Controls.TextBlock]::new()
    $bodyBlock.Text = $Body
    $bodyBlock.Foreground = "#475569"
    $bodyBlock.Margin = "0,4,0,0"
    $bodyBlock.TextWrapping = "Wrap"

    $stack.Children.Add($titleBlock) | Out-Null
    $stack.Children.Add($bodyBlock) | Out-Null
    $row.Children.Add($stack) | Out-Null
    $card.Child = $row
    return $card
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
    $category = $script:CategoryBox.SelectedItem.Content

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
            $header = [System.Windows.Controls.TextBlock]::new()
            $header.Text = "- $($app.category)"
            $header.FontFamily = "Consolas"
            $header.FontSize = 15
            $header.Foreground = "#334155"
            $header.Margin = "8,14,0,4"
            $script:AppsPanel.Children.Add($header) | Out-Null
            $lastCategory = $app.category
        }
        $script:AppsPanel.Children.Add((New-AppCard -App $app)) | Out-Null
    }

    Update-SelectedCount
    Write-Status "Install" "$($apps.Count) apps visiveis"
}

function Show-TweaksView {
    $script:ActiveView = "Tweaks"
    Clear-MainPanel
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Explorer limpo" -Body "Mostra extensoes de arquivo e arquivos ocultos para o usuario atual." -Icon "EX" -Accent "#0EA5E9")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Privacidade basica" -Body "Espaco reservado para telemetria, apps em segundo plano e sugestoes do Windows." -Icon "PR" -Accent "#16A34A")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Performance" -Body "Espaco reservado para ajustes de inicializacao, energia e efeitos visuais." -Icon "PF" -Accent "#F59E0B")) | Out-Null
    Write-Status "Tweaks" "Tweaks seguros prontos"
}

function Show-ConfigView {
    $script:ActiveView = "Config"
    Clear-MainPanel
    $adminStatus = if (Test-IsAdmin) { "Executando elevado." } else { "Nao elevado; algumas acoes podem pedir permissao." }
    $wingetStatus = if (Get-Command winget -ErrorAction SilentlyContinue) { "Disponivel no PATH." } else { "Nao encontrado no PATH desta sessao." }
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Catalogo JSON" -Body $script:ConfigPath -Icon "JS" -Accent "#2563EB")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Administrador" -Body $adminStatus -Icon "AD" -Accent "#64748B")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "WinGet" -Body $wingetStatus -Icon "WG" -Accent "#7C3AED")) | Out-Null
    Write-Status "Config" "Ambiente inspecionado"
}

function Show-UpdatesView {
    $script:ActiveView = "Updates"
    Clear-MainPanel
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Atualizar selecionados" -Body "Selecione apps na aba Install e use Upgrade Selected." -Icon "UP" -Accent "#2563EB")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Atualizar todos" -Body "Executa winget upgrade --all com aceite de acordos." -Icon "ALL" -Accent "#DC2626")) | Out-Null
    $script:AppsPanel.Children.Add((New-InfoCard -Title "Registro" -Body "O resultado aparece no console de log abaixo." -Icon "LOG" -Accent "#111827")) | Out-Null
    Write-Status "Updates" "Acoes de update disponiveis"
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
            $args = @($Action, "--id", $app.id, "--exact", "--accept-package-agreements", "--accept-source-agreements")
            if ($Action -eq "install" -or $Action -eq "upgrade") {
                $args += "--silent"
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
        Invoke-LoggedProcess -FilePath $wingetCommand.Source -Arguments @("upgrade", "--all", "--accept-package-agreements", "--accept-source-agreements") | Out-Null
    }
}

function Invoke-SafeTweaks {
    Invoke-SafeUiAction -Name "tweaks seguros" -Action {
        Write-Log "Aplicando tweaks seguros de interface."
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
        Write-Log "Extensoes e arquivos ocultos agora ficam visiveis para o usuario atual."
    }
}

function Build-Ui {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Assistente G-LAB" Height="790" Width="1240" WindowStartupLocation="CenterScreen"
        Background="#E5E7EB" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#94A3B8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="56"/>
            <RowDefinition Height="42"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="155"/>
        </Grid.RowDefinitions>

        <DockPanel Grid.Row="0" LastChildFill="True">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
                <Border Width="40" Height="40" CornerRadius="8" Background="#111827" Margin="0,0,10,0">
                    <TextBlock Text="GL" Foreground="#FFFFFF" FontWeight="Bold" FontSize="15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel>
                    <TextBlock Text="Assistente G-LAB" FontSize="22" FontWeight="SemiBold" Foreground="#0F172A"/>
                    <TextBlock Text="Central local de instalacao, ajustes e manutencao Windows" FontSize="12" Foreground="#475569"/>
                </StackPanel>
            </StackPanel>
            <TextBlock x:Name="StatusText" DockPanel.Dock="Right" VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="#334155"/>
        </DockPanel>

        <DockPanel Grid.Row="1" LastChildFill="True">
            <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                <Button x:Name="InstallTab" Content="Install" Width="112" Margin="0,0,6,0"/>
                <Button x:Name="TweaksTab" Content="Tweaks" Width="112" Margin="0,0,6,0"/>
                <Button x:Name="ConfigTab" Content="Config" Width="112" Margin="0,0,6,0"/>
                <Button x:Name="UpdatesTab" Content="Updates" Width="112" Margin="0,0,6,0"/>
            </StackPanel>
            <TextBox x:Name="SearchBox" Height="30" Margin="12,0,0,0" VerticalContentAlignment="Center"/>
        </DockPanel>

        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="235"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Padding="10" Background="#FFFFFF" BorderBrush="#94A3B8" BorderThickness="1" CornerRadius="6">
                <StackPanel>
                    <TextBlock Text="Actions" FontFamily="Consolas" FontSize="15" Margin="0,0,0,8"/>
                    <Button x:Name="InstallButton" Content="[+] Install Selected" Margin="0,0,0,5" Height="30"/>
                    <Button x:Name="UpgradeButton" Content="[^] Upgrade Selected" Margin="0,0,0,5" Height="30"/>
                    <Button x:Name="UninstallButton" Content="[-] Uninstall Selected" Margin="0,0,0,5" Height="30"/>
                    <Button x:Name="UpgradeAllButton" Content="[A] Upgrade All Apps" Margin="0,0,0,12" Height="30"/>
                    <TextBlock Text="Package Manager" FontFamily="Consolas" FontSize="14" Margin="0,0,0,5"/>
                    <RadioButton Content="WinGet" IsChecked="True" Margin="12,0,0,12"/>
                    <TextBlock Text="Selection" FontFamily="Consolas" FontSize="14" Margin="0,0,0,5"/>
                    <Button x:Name="ClearButton" Content="[x] Clear Selection" Margin="0,0,0,5" Height="30"/>
                    <Button x:Name="ApplyTweaksButton" Content="[*] Apply Safe Tweaks" Margin="0,0,0,5" Height="30"/>
                    <Button x:Name="ReloadButton" Content="[r] Reload Catalog" Margin="0,0,0,12" Height="30"/>
                    <TextBlock x:Name="SelectedCountText" Text="Selecionados: 0" Margin="0,8,0,0"/>
                    <TextBlock x:Name="AdminText" Text="" Margin="0,12,0,0" TextWrapping="Wrap" Foreground="#047857"/>
                </StackPanel>
            </Border>

            <DockPanel Grid.Column="1" Margin="10,0,0,0">
                <ComboBox x:Name="CategoryBox" DockPanel.Dock="Top" Height="30" Margin="0,0,0,8"/>
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <UniformGrid x:Name="AppsPanel" Columns="3"/>
                </ScrollViewer>
            </DockPanel>
        </Grid>

        <Border Grid.Row="3" Margin="0,8,0,0" Padding="8" Background="#0F172A" CornerRadius="6">
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
$window = Build-Ui
if (-not $window) {
    throw "Nao foi possivel carregar a janela WPF do Assistente G-LAB."
}

$script:SearchBox = $window.FindName("SearchBox")
$script:CategoryBox = $window.FindName("CategoryBox")
$script:AppsPanel = $window.FindName("AppsPanel")
$script:LogBox = $window.FindName("LogBox")
$script:SelectedCountText = $window.FindName("SelectedCountText")
$script:StatusText = $window.FindName("StatusText")
$adminText = $window.FindName("AdminText")

$categories = @("All") + ($script:Catalog | Select-Object -ExpandProperty category -Unique | Sort-Object)
foreach ($category in $categories) {
    $item = [System.Windows.Controls.ComboBoxItem]::new()
    $item.Content = $category
    $script:CategoryBox.Items.Add($item) | Out-Null
}
$script:CategoryBox.SelectedIndex = 0

$window.FindName("InstallButton").Add_Click({ Invoke-SafeUiAction -Name "Install Selected" -Action { Invoke-WingetForSelection -Action "install" } })
$window.FindName("UpgradeButton").Add_Click({ Invoke-SafeUiAction -Name "Upgrade Selected" -Action { Invoke-WingetForSelection -Action "upgrade" } })
$window.FindName("UninstallButton").Add_Click({ Invoke-SafeUiAction -Name "Uninstall Selected" -Action { Invoke-WingetForSelection -Action "uninstall" } })
$window.FindName("UpgradeAllButton").Add_Click({ Invoke-SafeUiAction -Name "Upgrade All Apps" -Action { Invoke-UpgradeAll } })
$window.FindName("ApplyTweaksButton").Add_Click({ Invoke-SafeUiAction -Name "Apply Safe Tweaks" -Action { Invoke-SafeTweaks } })
$window.FindName("ReloadButton").Add_Click({
    $script:Catalog = Load-AppCatalog
    Write-Log "Catalogo recarregado: $($script:Catalog.Count) apps."
    Refresh-AppGrid
})
$window.FindName("ClearButton").Add_Click({
    foreach ($child in $script:AppsPanel.Children) {
        if ($child.Tag) { $child.Tag.IsChecked = $false }
    }
    Update-SelectedCount
})

$window.FindName("InstallTab").Add_Click({ Refresh-AppGrid })
$window.FindName("TweaksTab").Add_Click({ Show-TweaksView })
$window.FindName("ConfigTab").Add_Click({ Show-ConfigView })
$window.FindName("UpdatesTab").Add_Click({ Show-UpdatesView })
$script:SearchBox.Add_TextChanged({ Refresh-AppGrid })
$script:CategoryBox.Add_SelectionChanged({ Refresh-AppGrid })

if (Test-IsAdmin) {
    $adminText.Text = "Executando como administrador."
} else {
    $adminText.Text = "Sem administrador. Instalar apps pode pedir elevacao."
    $adminText.Foreground = "#B45309"
}

Write-Log "Assistente G-LAB iniciado. Catalogo carregado: $($script:Catalog.Count) apps."
Refresh-AppGrid
if ($ValidateOnly) {
    "ValidateOnly OK: $($script:Catalog.Count) apps carregados."
    return
}
if (-not $window) {
    throw "A janela WPF nao foi inicializada. Execute novamente com powershell.exe -STA."
}

[void]$window.ShowDialog()
