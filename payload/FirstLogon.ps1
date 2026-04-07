$ErrorActionPreference = "Stop"

function Test-IsElevated {
    $null = & fltmc.exe 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Ensure-Administrator {
    if (-not (Test-IsElevated)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
        exit 0
    }
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Add-Status {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Controls.TextBox]$OutputBox,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $OutputBox.AppendText("[$timestamp] $Message`r`n")
    $OutputBox.ScrollToEnd()
}

function Apply-UserTweaks {
    param([System.Windows.Controls.TextBox]$OutputBox)

    Add-Status -OutputBox $OutputBox -Message "Bruker gaming- og skrivebordstweaks."

    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Type ([Microsoft.Win32.RegistryValueKind]::String)
}

function Apply-VisualPerformanceMode {
    param([System.Windows.Controls.TextBox]$OutputBox)

    Add-Status -OutputBox $OutputBox -Message "Bruker visual-performance preset."

    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "0" -Type ([Microsoft.Win32.RegistryValueKind]::String)
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type ([Microsoft.Win32.RegistryValueKind]::Binary)
}

function Remove-CurrentUserApps {
    param(
        [string[]]$Patterns,
        [System.Windows.Controls.TextBox]$OutputBox
    )

    if (-not $Patterns -or $Patterns.Count -eq 0) {
        return
    }

    Add-Status -OutputBox $OutputBox -Message "Rydder bort unodvendige bruker-apper."

    $packages = Get-AppxPackage
    foreach ($pattern in $Patterns) {
        $matches = $packages | Where-Object { $_.Name -like $pattern }
        foreach ($pkg in $matches) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName | Out-Null
                Add-Status -OutputBox $OutputBox -Message "Fjernet $($pkg.Name)"
            }
            catch {
                Add-Status -OutputBox $OutputBox -Message "Kunne ikke fjerne $($pkg.Name)"
            }
        }
    }
}

function Remove-StartupNoise {
    param([System.Windows.Controls.TextBox]$OutputBox)

    Add-Status -OutputBox $OutputBox -Message "Fjerner vanlig oppstartsstoy."

    $runPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )

    $runNames = @(
        "OneDrive",
        "Teams",
        "Microsoft Teams",
        "Copilot",
        "Edge",
        "MicrosoftEdgeAutoLaunch_*"
    )

    foreach ($path in $runPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        foreach ($prop in (Get-ItemProperty -LiteralPath $path).PSObject.Properties) {
            foreach ($namePattern in $runNames) {
                if ($prop.Name -like $namePattern) {
                    Remove-ItemProperty -LiteralPath $path -Name $prop.Name -ErrorAction SilentlyContinue
                    Add-Status -OutputBox $OutputBox -Message "Deaktiverte autostart: $($prop.Name)"
                    break
                }
            }
        }
    }
}

function Apply-ProfileActions {
    param(
        [hashtable]$Profile,
        [System.Windows.Controls.TextBox]$OutputBox
    )

    Invoke-Step -OutputBox $OutputBox -StepName "Bloat cleanup" -Action {
        Remove-CurrentUserApps -Patterns $Profile.RemoveUserApps -OutputBox $OutputBox
    }

    if ($Profile.DisableStartupNoise) {
        Invoke-Step -OutputBox $OutputBox -StepName "Oppstartsopprydding" -Action {
            Remove-StartupNoise -OutputBox $OutputBox
        }
    }

    if ($Profile.ReduceVisualEffects) {
        Invoke-Step -OutputBox $OutputBox -StepName "Visual performance" -Action {
            Apply-VisualPerformanceMode -OutputBox $OutputBox
        }
    }
}

function Apply-SystemTweaks {
    param(
        [System.Windows.Controls.TextBox]$OutputBox,
        [bool]$LowLatency,
        [bool]$Privacy,
        [bool]$RgbLook
    )

    Add-Status -OutputBox $OutputBox -Message "Bruker systemtweaks."

    if (-not (Test-IsElevated)) {
        Add-Status -OutputBox $OutputBox -Message "Wizard-en er ikke kjort som administrator. Hopper over systemtweaks som krever forhoying."
        return
    }

    powercfg /S SCHEME_MIN | Out-Null

    if ($LowLatency) {
        reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f | Out-Null
        reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f | Out-Null
        reg add "HKLM\SOFTWARE\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" /f | Out-Null
        Add-Status -OutputBox $OutputBox -Message "Low-latency preset aktivert."
    }

    if ($Privacy) {
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v DisableEdgeDesktopShortcutCreation /t REG_DWORD /d 1 /f | Out-Null
        Add-Status -OutputBox $OutputBox -Message "Privacy-/noise-reduction preset aktivert."
    }

    if ($RgbLook) {
        reg add "HKCU\Control Panel\Colors" /v Background /t REG_SZ /d "12 12 18" /f | Out-Null
        Add-Status -OutputBox $OutputBox -Message "Cyber-look preset aktivert."
    }
}

function Install-WingetPackages {
    param(
        [string[]]$PackageIds,
        [System.Windows.Controls.TextBox]$OutputBox
    )

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        return
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Add-Status -OutputBox $OutputBox -Message "Winget ble ikke funnet. Hopper over appinstallasjon."
        return
    }

    foreach ($packageId in $PackageIds | Select-Object -Unique) {
        Add-Status -OutputBox $OutputBox -Message "Installerer $packageId"
        & $winget.Source install --id $packageId --exact --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            Add-Status -OutputBox $OutputBox -Message "$packageId installert."
        }
        else {
            Add-Status -OutputBox $OutputBox -Message "$packageId kunne ikke installeres automatisk."
        }
    }
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][System.Windows.Controls.TextBox]$OutputBox,
        [string]$DisplayName = $PackageId
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Add-Status -OutputBox $OutputBox -Message "Winget ble ikke funnet. Hopper over $DisplayName."
        return $false
    }

    Add-Status -OutputBox $OutputBox -Message "Installerer $DisplayName"
    & $winget.Source install --id $PackageId --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) {
        Add-Status -OutputBox $OutputBox -Message "$DisplayName installert."
        return $true
    }

    Add-Status -OutputBox $OutputBox -Message "$DisplayName kunne ikke installeres automatisk."
    return $false
}

function Get-RainmeterExecutablePath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} "Rainmeter\Rainmeter.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Rainmeter\Rainmeter.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command Rainmeter.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Install-RainmeterProfile {
    param(
        [hashtable]$Profile,
        [System.Windows.Controls.TextBox]$OutputBox
    )

    if (-not $Profile.RainmeterEnabled) {
        Add-Status -OutputBox $OutputBox -Message "Rainmeter er ikke aktivert for denne profilen."
        return
    }

    if (-not (Install-WingetPackage -PackageId "Rainmeter.Rainmeter" -OutputBox $OutputBox -DisplayName "Rainmeter")) {
        return
    }

    $sourceRoot = Join-Path $PSScriptRoot ("RainmeterProfiles\{0}" -f $Profile.RainmeterProfile)
    if (-not (Test-Path -LiteralPath $sourceRoot)) {
        Add-Status -OutputBox $OutputBox -Message "Fant ikke Rainmeter-profilen $($Profile.RainmeterProfile)."
        return
    }

    $documentsPath = [Environment]::GetFolderPath("MyDocuments")
    $skinsRoot = Join-Path $documentsPath ("Rainmeter\Skins\GamingLab\{0}" -f $Profile.RainmeterProfile)
    New-Item -ItemType Directory -Path $skinsRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot "*") -Destination $skinsRoot -Recurse -Force
    Add-Status -OutputBox $OutputBox -Message "Rainmeter-skin kopiert til Documents\Rainmeter\Skins\GamingLab\$($Profile.RainmeterProfile)"

    $rainmeterExe = Get-RainmeterExecutablePath
    if (-not $rainmeterExe) {
        Add-Status -OutputBox $OutputBox -Message "Fant ikke Rainmeter.exe etter installasjon."
        return
    }

    Start-Process -FilePath $rainmeterExe | Out-Null
    Start-Sleep -Seconds 2
    Start-Process -FilePath $rainmeterExe -ArgumentList "!ActivateConfig", "GamingLab\$($Profile.RainmeterProfile)", "$($Profile.RainmeterProfile).ini" | Out-Null
    Start-Process -FilePath $rainmeterExe -ArgumentList "!RefreshApp" | Out-Null
    Add-Status -OutputBox $OutputBox -Message "Rainmeter-profil aktivert: $($Profile.RainmeterProfile)"
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][System.Windows.Controls.TextBox]$OutputBox,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    try {
        & $Action
    }
    catch {
        Add-Status -OutputBox $OutputBox -Message "$StepName feilet: $($_.Exception.Message)"
    }
}

Ensure-Administrator

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$profiles = @{
    Competitive = @{
        Title = "Competitive"
        Description = "Maks fokus pa FPS, lav stoy og rask desktop."
        Packages = @("Valve.Steam", "Discord.Discord", "7zip.7zip")
        LowLatency = $true
        Privacy = $true
        RgbLook = $false
        RainmeterEnabled = $false
        RainmeterProfile = "Competitive"
        DisableStartupNoise = $true
        ReduceVisualEffects = $true
        RemoveUserApps = @(
            "Clipchamp.Clipchamp*",
            "Microsoft.GetHelp*",
            "Microsoft.Getstarted*",
            "Microsoft.MicrosoftOfficeHub*",
            "Microsoft.MicrosoftSolitaireCollection*",
            "Microsoft.PowerAutomateDesktop*",
            "Microsoft.WindowsFeedbackHub*",
            "Microsoft.YourPhone*",
            "Microsoft.ZuneMusic*",
            "Microsoft.ZuneVideo*",
            "MicrosoftTeams*"
        )
    }
    FiveM = @{
        Title = "FiveM"
        Description = "Bygget for GTA V, FiveM, Discord og en ren roleplay-rigg."
        Packages = @("Valve.Steam", "Discord.Discord", "VideoLAN.VLC", "7zip.7zip")
        LowLatency = $true
        Privacy = $true
        RgbLook = $true
        RainmeterEnabled = $true
        RainmeterProfile = "FiveM"
        DisableStartupNoise = $true
        ReduceVisualEffects = $true
        RemoveUserApps = @(
            "Clipchamp.Clipchamp*",
            "Microsoft.GetHelp*",
            "Microsoft.Getstarted*",
            "Microsoft.MicrosoftOfficeHub*",
            "Microsoft.MicrosoftSolitaireCollection*",
            "Microsoft.PowerAutomateDesktop*",
            "Microsoft.WindowsFeedbackHub*",
            "Microsoft.YourPhone*",
            "MicrosoftTeams*"
        )
    }
    Streamer = @{
        Title = "Streamer"
        Description = "Gaming + streaming med OBS, Discord og mer creator-klare defaults."
        Packages = @("Valve.Steam", "Discord.Discord", "OBSProject.OBSStudio", "VideoLAN.VLC", "7zip.7zip")
        LowLatency = $false
        Privacy = $true
        RgbLook = $true
        RainmeterEnabled = $true
        RainmeterProfile = "Streamer"
        DisableStartupNoise = $true
        ReduceVisualEffects = $true
        RemoveUserApps = @(
            "Clipchamp.Clipchamp*",
            "Microsoft.GetHelp*",
            "Microsoft.Getstarted*",
            "Microsoft.MicrosoftOfficeHub*",
            "Microsoft.MicrosoftSolitaireCollection*",
            "Microsoft.PowerAutomateDesktop*",
            "Microsoft.WindowsFeedbackHub*",
            "Microsoft.YourPhone*",
            "Microsoft.ZuneMusic*",
            "Microsoft.ZuneVideo*",
            "MicrosoftTeams*",
            "Microsoft.OutlookForWindows*"
        )
    }
    Creator = @{
        Title = "Creator"
        Description = "Mer balansert setup for gaming, redigering og daglig arbeid."
        Packages = @("Google.Chrome", "OBSProject.OBSStudio", "VideoLAN.VLC", "7zip.7zip", "Microsoft.VisualStudioCode")
        LowLatency = $false
        Privacy = $false
        RgbLook = $true
        RainmeterEnabled = $true
        RainmeterProfile = "Creator"
        DisableStartupNoise = $false
        ReduceVisualEffects = $false
        RemoveUserApps = @(
            "Microsoft.MicrosoftSolitaireCollection*",
            "Microsoft.WindowsFeedbackHub*"
        )
    }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gaming Lab Tweak Center"
        Width="1180"
        Height="800"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanMinimize"
        Background="#F5F7FB"
        Foreground="#111827"
        FontFamily="Segoe UI Variable Display">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" CornerRadius="28" Padding="28" Background="#FFFFFF" BorderBrush="#D7DFEA" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock FontSize="13" FontWeight="SemiBold" Foreground="#2563EB" Text="GAMING LAB"/>
          <TextBlock Margin="0,6,0,0" FontSize="36" FontWeight="SemiBold" Text="Tweak Center"/>
          <TextBlock Margin="0,8,0,0" FontSize="15" Foreground="#4B5563" Text="Apply a recommended Windows 11 profile, then fine-tune privacy, visuals, apps, and optional desktop modules." TextWrapping="Wrap"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#F8FAFC" CornerRadius="22" Padding="18" BorderBrush="#D7DFEA" BorderThickness="1">
          <StackPanel>
            <TextBlock FontSize="12" Foreground="#64748B" Text="MODE"/>
            <TextBlock FontSize="18" FontWeight="SemiBold" Text="Windows 11 Companion"/>
            <TextBlock Margin="0,4,0,0" Foreground="#64748B" Text="Profiles, tweaks, desktop, and apps"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
    <Grid Grid.Row="1" Margin="0,18,0,18">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2.2*"/>
        <ColumnDefinition Width="1.15*"/>
      </Grid.ColumnDefinitions>
      <Grid Grid.Column="0" Margin="0,0,18,0">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock FontSize="24" FontWeight="SemiBold" Text="Choose a profile"/>
          <TextBlock Margin="0,4,0,0" Foreground="#6B7280" Text="Recommended presets are designed to feel close to a clean, well-tuned Windows 11 install."/>
        </StackPanel>
        <UniformGrid Grid.Row="1" Margin="0,14,0,18" Columns="2">
          <RadioButton x:Name="ProfileCompetitive" GroupName="Profile" Margin="0,0,12,12" IsChecked="True">
            <Border CornerRadius="24" Padding="20" Background="#FFFFFF" BorderBrush="#D6DFEA" BorderThickness="1">
              <StackPanel>
                <TextBlock FontSize="13" FontWeight="SemiBold" Foreground="#2563EB" Text="RECOMMENDED"/>
                <TextBlock Margin="0,6,0,0" FontSize="22" FontWeight="SemiBold" Text="Competitive"/>
                <TextBlock Margin="0,8,0,0" Foreground="#4B5563" Text="FPS first, lower background noise, fewer distractions, cleaner desktop defaults." TextWrapping="Wrap"/>
              </StackPanel>
            </Border>
          </RadioButton>
          <RadioButton x:Name="ProfileFiveM" GroupName="Profile" Margin="0,0,0,12">
            <Border CornerRadius="24" Padding="20" Background="#FFFFFF" BorderBrush="#D6DFEA" BorderThickness="1">
              <StackPanel>
                <TextBlock FontSize="13" FontWeight="SemiBold" Foreground="#7C3AED" Text="PROFILE"/>
                <TextBlock Margin="0,6,0,0" FontSize="22" FontWeight="SemiBold" Text="FiveM"/>
                <TextBlock Margin="0,8,0,0" Foreground="#4B5563" Text="Roleplay-oriented setup with Discord, Steam, and optional desktop styling." TextWrapping="Wrap"/>
              </StackPanel>
            </Border>
          </RadioButton>
          <RadioButton x:Name="ProfileStreamer" GroupName="Profile" Margin="0,0,12,0">
            <Border CornerRadius="24" Padding="20" Background="#FFFFFF" BorderBrush="#D6DFEA" BorderThickness="1">
              <StackPanel>
                <TextBlock FontSize="13" FontWeight="SemiBold" Foreground="#059669" Text="RECOMMENDED"/>
                <TextBlock Margin="0,6,0,0" FontSize="22" FontWeight="SemiBold" Text="Streamer"/>
                <TextBlock Margin="0,8,0,0" Foreground="#4B5563" Text="Balanced gaming and streaming defaults with OBS, Discord, and reduced desktop noise." TextWrapping="Wrap"/>
              </StackPanel>
            </Border>
          </RadioButton>
          <RadioButton x:Name="ProfileCreator" GroupName="Profile">
            <Border CornerRadius="24" Padding="20" Background="#FFFFFF" BorderBrush="#D6DFEA" BorderThickness="1">
              <StackPanel>
                <TextBlock FontSize="13" FontWeight="SemiBold" Foreground="#EA580C" Text="PROFILE"/>
                <TextBlock Margin="0,6,0,0" FontSize="22" FontWeight="SemiBold" Text="Creator"/>
                <TextBlock Margin="0,8,0,0" Foreground="#4B5563" Text="A broader setup for gaming, coding, media work, and day-to-day Windows usage." TextWrapping="Wrap"/>
              </StackPanel>
            </Border>
          </RadioButton>
        </UniformGrid>
        <Border Grid.Row="2" Background="#FFFFFF" CornerRadius="24" Padding="22" BorderBrush="#D6DFEA" BorderThickness="1">
          <StackPanel>
            <TextBlock FontSize="24" FontWeight="SemiBold" Text="Optional modules"/>
            <TextBlock Margin="0,4,0,0" Foreground="#6B7280" Text="Recommended options are selected automatically based on the profile you choose." TextWrapping="Wrap"/>
            <CheckBox x:Name="InstallPackagesCheck" Margin="0,18,0,0" IsChecked="True" FontSize="15" Content="Install curated apps with winget"/>
            <CheckBox x:Name="InstallRainmeterCheck" Margin="0,10,0,0" FontSize="15" Content="Install Rainmeter desktop module"/>
            <CheckBox x:Name="LowLatencyCheck" Margin="0,10,0,0" FontSize="15" Content="Apply advanced low-latency tuning"/>
            <CheckBox x:Name="PrivacyCheck" Margin="0,10,0,0" FontSize="15" Content="Reduce privacy noise, tips, and consumer content"/>
            <CheckBox x:Name="RgbLookCheck" Margin="0,10,0,0" FontSize="15" Content="Apply desktop styling and accent tweaks"/>
            <TextBlock Margin="0,16,0,0" Foreground="#6B7280" Text="Apps and Rainmeter require internet access. Advanced low-latency tuning is more aggressive than the recommended defaults." TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </Grid>
      <Border Grid.Column="1" Background="#FFFFFF" CornerRadius="24" Padding="18" BorderBrush="#D6DFEA" BorderThickness="1">
        <DockPanel LastChildFill="True">
          <TextBlock DockPanel.Dock="Top" FontSize="24" FontWeight="SemiBold" Text="Activity"/>
          <TextBox x:Name="OutputBox"
                   Margin="0,16,0,0"
                   Background="#F8FAFC"
                   Foreground="#1F2937"
                   BorderBrush="#E5E7EB"
                   BorderThickness="1"
                   FontFamily="Consolas"
                   FontSize="13"
                   AcceptsReturn="True"
                   VerticalScrollBarVisibility="Auto"
                   TextWrapping="Wrap"
                   IsReadOnly="True"/>
        </DockPanel>
      </Border>
    </Grid>
    <DockPanel Grid.Row="2">
      <TextBlock VerticalAlignment="Center" Foreground="#6B7280" Text="Tip: Streamer and Competitive are the safest starting points if you want a more official-feeling Windows 11 setup with less clutter." TextWrapping="Wrap"/>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="CloseButton" Width="130" Height="42" Margin="0,0,12,0" Content="Close" Background="#FFFFFF" Foreground="#111827" BorderBrush="#D6DFEA"/>
        <Button x:Name="ApplyButton" Width="230" Height="42" Content="Apply recommended setup" Background="#2563EB" Foreground="#FFFFFF" BorderBrush="#2563EB" FontWeight="SemiBold"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$profileCompetitive = $window.FindName("ProfileCompetitive")
$profileFiveM = $window.FindName("ProfileFiveM")
$profileStreamer = $window.FindName("ProfileStreamer")
$profileCreator = $window.FindName("ProfileCreator")
$installPackagesCheck = $window.FindName("InstallPackagesCheck")
$installRainmeterCheck = $window.FindName("InstallRainmeterCheck")
$lowLatencyCheck = $window.FindName("LowLatencyCheck")
$privacyCheck = $window.FindName("PrivacyCheck")
$rgbLookCheck = $window.FindName("RgbLookCheck")
$applyButton = $window.FindName("ApplyButton")
$closeButton = $window.FindName("CloseButton")
$outputBox = $window.FindName("OutputBox")

function Get-SelectedProfileKey {
    if ($profileFiveM.IsChecked) { return "FiveM" }
    if ($profileStreamer.IsChecked) { return "Streamer" }
    if ($profileCreator.IsChecked) { return "Creator" }
    return "Competitive"
}

function Sync-OptionsFromProfile {
    $selectedProfile = $profiles[(Get-SelectedProfileKey)]
    $installRainmeterCheck.IsChecked = $selectedProfile.RainmeterEnabled
    $lowLatencyCheck.IsChecked = $selectedProfile.LowLatency
    $privacyCheck.IsChecked = $selectedProfile.Privacy
    $rgbLookCheck.IsChecked = $selectedProfile.RgbLook
    Add-Status -OutputBox $outputBox -Message "Profil valgt: $($selectedProfile.Title) - $($selectedProfile.Description)"
}

$profileCompetitive.Add_Checked({ Sync-OptionsFromProfile })
$profileFiveM.Add_Checked({ Sync-OptionsFromProfile })
$profileStreamer.Add_Checked({ Sync-OptionsFromProfile })
$profileCreator.Add_Checked({ Sync-OptionsFromProfile })

$closeButton.Add_Click({
    $window.Close()
})

$applyButton.Add_Click({
    $applyButton.IsEnabled = $false
    $closeButton.IsEnabled = $false

    try {
        $selectedProfile = $profiles[(Get-SelectedProfileKey)]
        Add-Status -OutputBox $outputBox -Message "Starter bygging av loadout: $($selectedProfile.Title)"

        if (-not (Test-IsElevated)) {
            Add-Status -OutputBox $outputBox -Message "Mangler administratorrettigheter. Godkjenn UAC-prompten hvis den vises, eller start scriptet manuelt som administrator."
        }

        Invoke-Step -OutputBox $outputBox -StepName "Brukertweaks" -Action {
            Apply-UserTweaks -OutputBox $outputBox
        }
        Invoke-Step -OutputBox $outputBox -StepName "Profiltilpasning" -Action {
            Apply-ProfileActions -Profile $selectedProfile -OutputBox $outputBox
        }
        Invoke-Step -OutputBox $outputBox -StepName "Systemtweaks" -Action {
            Apply-SystemTweaks -OutputBox $outputBox -LowLatency ([bool]$lowLatencyCheck.IsChecked) -Privacy ([bool]$privacyCheck.IsChecked) -RgbLook ([bool]$rgbLookCheck.IsChecked)
        }

        if ([bool]$installPackagesCheck.IsChecked) {
            Invoke-Step -OutputBox $outputBox -StepName "Appinstallasjon" -Action {
                Install-WingetPackages -PackageIds $selectedProfile.Packages -OutputBox $outputBox
            }
        }
        else {
            Add-Status -OutputBox $outputBox -Message "Appinstallasjon ble hoppet over."
        }

        if ([bool]$installRainmeterCheck.IsChecked) {
            Invoke-Step -OutputBox $outputBox -StepName "Rainmeter" -Action {
                Install-RainmeterProfile -Profile $selectedProfile -OutputBox $outputBox
            }
        }
        else {
            Add-Status -OutputBox $outputBox -Message "Rainmeter-modulen ble hoppet over."
        }

        Add-Status -OutputBox $outputBox -Message "Ferdig. Explorer restartes for a laste inn noen av endringene."
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Process explorer.exe
        [System.Windows.MessageBox]::Show("Gaming Lab-loadout er ferdig satt opp.", "Gaming Lab", "OK", "Information") | Out-Null
    }
    catch {
        Add-Status -OutputBox $outputBox -Message "Feil: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Gaming Lab - Feil", "OK", "Error") | Out-Null
    }
    finally {
        $applyButton.IsEnabled = $true
        $closeButton.IsEnabled = $true
    }
})

Sync-OptionsFromProfile
[void]$window.ShowDialog()
