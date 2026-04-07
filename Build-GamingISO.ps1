[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IsoPath,

    [int]$EditionIndex,

    [string]$ComputerName = "GAMINGLAB-PC",

    [string]$LocalUsername = "gamer",

    [string]$LocalPassword,

    [string]$WorkingRoot,

    [string]$OutputRoot,

    [string]$IsoName = "Win11-GamingLab.iso"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
else {
    $scriptRoot = $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($WorkingRoot)) {
    $WorkingRoot = Join-Path $scriptRoot "work"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $scriptRoot "output"
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-Oscdimg {
    $command = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
        "C:\ADK\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "C:\ADK\Deployment Tools\x86\Oscdimg\oscdimg.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-IfExists {
    param([string]$LiteralPath)

    if (Test-Path -LiteralPath $LiteralPath) {
        try {
            if ((Split-Path -Path $LiteralPath -Leaf) -eq "mount") {
                try {
                    Dismount-WindowsImage -Path $LiteralPath -Discard | Out-Null
                }
                catch {
                }

                try {
                    dism /Cleanup-Wim | Out-Null
                }
                catch {
                }
            }

            attrib -R "$LiteralPath\*" /S /D 2>$null
            takeown /F $LiteralPath /R /D Y | Out-Null
            icacls $LiteralPath /grant Administrators:`(F`) /T /C | Out-Null
            Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
        }
        catch {
            throw "Klarte ikke å rydde bort '$LiteralPath'. Lukk eventuelle Explorer-vinduer i mappen og prøv igjen. Opprinnelig feil: $($_.Exception.Message)"
        }
    }
}

function Copy-IsoContents {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDrive,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    Write-Step "Kopierer ISO-innhold"
    robocopy "$SourceDrive\" "$Destination" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null

    if ($LASTEXITCODE -ge 8) {
        throw "Robocopy feilet med kode $LASTEXITCODE."
    }

    Write-Step "Fjerner ReadOnly-attributt fra arbeidskopien"
    attrib -R "$Destination\*" /S /D
}

function Get-InstallImagePath {
    param([string]$IsoRoot)

    $wim = Join-Path $IsoRoot "sources\install.wim"
    $esd = Join-Path $IsoRoot "sources\install.esd"

    if (Test-Path -LiteralPath $wim) { return $wim }
    if (Test-Path -LiteralPath $esd) { return $esd }

    throw "Fant ikke install.wim eller install.esd i ISO-strukturen."
}

function Show-EditionsAndExit {
    param([string]$ImagePath)

    Write-Step "Tilgjengelige editions"
    Get-WindowsImage -ImagePath $ImagePath |
        Select-Object ImageIndex, ImageName, Architecture |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "Kjør scriptet på nytt med -EditionIndex <nummer>." -ForegroundColor Yellow
}

function Invoke-RegExe {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$IgnoreErrors
    )

    $output = & reg.exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        if ($IgnoreErrors) {
            return $false
        }

        $message = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "reg.exe feilet med kode $exitCode."
        }

        throw $message
    }

    return $true
}

function Apply-OfflineRegistryTweaks {
    param([string]$MountDir)

    Write-Step "Setter offline gaming-/støyreduksjonstweaks"

    $softwareHive = Join-Path $MountDir "Windows\System32\Config\SOFTWARE"
    $defaultHive = Join-Path $MountDir "Users\Default\NTUSER.DAT"

    $softwareLoaded = $false
    $defaultLoaded = $false

    if (-not (Test-Path -LiteralPath $softwareHive) -or -not (Test-Path -LiteralPath $defaultHive)) {
        Write-Host "Advarsel: Offline registry-hiver ble ikke funnet. Hopper over offline registry-tweaks." -ForegroundColor Yellow
        return
    }

    Invoke-RegExe -Arguments @("unload", "HKLM\GL_SOFTWARE") -IgnoreErrors | Out-Null
    Invoke-RegExe -Arguments @("unload", "HKU\GL_DEFAULT") -IgnoreErrors | Out-Null

    try {
        $softwareLoaded = Invoke-RegExe -Arguments @("load", "HKLM\GL_SOFTWARE", $softwareHive) -IgnoreErrors
        $defaultLoaded = Invoke-RegExe -Arguments @("load", "HKU\GL_DEFAULT", $defaultHive) -IgnoreErrors

        if (-not $softwareLoaded -or -not $defaultLoaded) {
            Write-Host "Advarsel: Kunne ikke laste en eller flere offline registry-hiver. Hopper over offline registry-tweaks." -ForegroundColor Yellow
            return
        }

        Invoke-RegExe -Arguments @("add", "HKLM\GL_SOFTWARE\Policies\Microsoft\Dsh", "/v", "AllowNewsAndInterests", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKLM\GL_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer", "/v", "DisableEdgeDesktopShortcutCreation", "/t", "REG_DWORD", "/d", "1", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKLM\GL_SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR", "/v", "value", "/t", "REG_DWORD", "/d", "1", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKLM\GL_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile", "/v", "NetworkThrottlingIndex", "/t", "REG_DWORD", "/d", "4294967295", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKLM\GL_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile", "/v", "SystemResponsiveness", "/t", "REG_DWORD", "/d", "10", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKLM\GL_SOFTWARE\Policies\Microsoft\Windows\CloudContent", "/v", "DisableWindowsConsumerFeatures", "/t", "REG_DWORD", "/d", "1", "/f") | Out-Null

        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\GameBar", "/v", "AllowAutoGameMode", "/t", "REG_DWORD", "/d", "1", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\GameBar", "/v", "AutoGameModeEnabled", "/t", "REG_DWORD", "/d", "1", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "/v", "AppsUseLightTheme", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "/v", "SystemUsesLightTheme", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "/v", "HideFileExt", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "/v", "TaskbarMn", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "/v", "TaskbarDa", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
        Invoke-RegExe -Arguments @("add", "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Search", "/v", "SearchboxTaskbarMode", "/t", "REG_DWORD", "/d", "0", "/f") | Out-Null
    }
    finally {
        if ($softwareLoaded) {
            Invoke-RegExe -Arguments @("unload", "HKLM\GL_SOFTWARE") -IgnoreErrors | Out-Null
        }
        if ($defaultLoaded) {
            Invoke-RegExe -Arguments @("unload", "HKU\GL_DEFAULT") -IgnoreErrors | Out-Null
        }
    }
}

function Remove-ProvisionedApps {
    param([string]$MountDir)

    Write-Step "Fjerner utvalgte provisioned apps"

    $keepPatterns = @(
        "Microsoft.DesktopAppInstaller",
        "Microsoft.StorePurchaseApp",
        "Microsoft.WindowsStore",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.GamingApp",
        "Microsoft.VCLibs",
        "Microsoft.UI.Xaml"
    )

    $removePatterns = @(
        "Clipchamp.Clipchamp",
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.Copilot",
        "Microsoft.DevHome",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.MixedReality.Portal",
        "Microsoft.People",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.OutlookForWindows",
        "Microsoft.Todos",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.YourPhone",
        "MicrosoftTeams",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo"
    )

    $apps = Get-AppxProvisionedPackage -Path $MountDir

    foreach ($app in $apps) {
        $keep = $false
        foreach ($pattern in $keepPatterns) {
            if ($app.DisplayName -like "$pattern*") {
                $keep = $true
                break
            }
        }

        if ($keep) {
            continue
        }

        foreach ($pattern in $removePatterns) {
            if ($app.DisplayName -like "$pattern*") {
                Write-Host "Fjerner $($app.DisplayName)"
                Remove-AppxProvisionedPackage -Path $MountDir -PackageName $app.PackageName | Out-Null
                break
            }
        }
    }
}

function Inject-Payload {
    param(
        [string]$MountDir,
        [string]$PayloadDir
    )

    Write-Step "Legger inn post-install payload"

    $setupScripts = Join-Path $MountDir "Windows\Setup\Scripts"
    $gamingLab = Join-Path $MountDir "Windows\GamingLab"
    $rainmeterProfiles = Join-Path $PayloadDir "RainmeterProfiles"

    New-Item -ItemType Directory -Path $setupScripts -Force | Out-Null
    New-Item -ItemType Directory -Path $gamingLab -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $PayloadDir "SetupComplete.cmd") -Destination (Join-Path $setupScripts "SetupComplete.cmd") -Force
    Copy-Item -LiteralPath (Join-Path $PayloadDir "FirstLogon.ps1") -Destination (Join-Path $gamingLab "FirstLogon.ps1") -Force

    if (Test-Path -LiteralPath $rainmeterProfiles) {
        Copy-Item -LiteralPath $rainmeterProfiles -Destination (Join-Path $gamingLab "RainmeterProfiles") -Recurse -Force
    }
}

function Escape-XmlValue {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [System.Security.SecurityElement]::Escape($Value)
}

function Write-Autounattend {
    param(
        [string]$DestinationPath,
        [string]$ComputerName,
        [string]$LocalUsername,
        [string]$LocalPassword
    )

    Write-Step "Genererer autounattend.xml"

    $safeComputerName = Escape-XmlValue -Value $ComputerName
    $safeLocalUsername = Escape-XmlValue -Value $LocalUsername
    $hideOnlineAccountScreens = if ([string]::IsNullOrWhiteSpace($LocalUsername)) { "false" } else { "true" }
    $autoLogonBlock = ""
    $firstLogonCommandsBlock = ""

    $localAccountBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($LocalUsername)) {
        $passwordBlock = ""
        $autoLogonPasswordBlock = ""
        if (-not [string]::IsNullOrWhiteSpace($LocalPassword)) {
            $safePassword = Escape-XmlValue -Value $LocalPassword
            $passwordBlock = @"
          <Password>
            <Value>$safePassword</Value>
            <PlainText>true</PlainText>
          </Password>
"@
            $autoLogonPasswordBlock = @"
        <Password>
          <Value>$safePassword</Value>
          <PlainText>true</PlainText>
        </Password>
"@
        }

        $localAccountBlock = @"
      <RegisteredOrganization>Gaming Lab</RegisteredOrganization>
      <RegisteredOwner>$safeLocalUsername</RegisteredOwner>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            $passwordBlock
            <Description>Gaming Lab local account</Description>
            <DisplayName>$safeLocalUsername</DisplayName>
            <Group>Administrators</Group>
            <Name>$safeLocalUsername</Name>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
"@

        $autoLogonBlock = @"
      <AutoLogon>
$autoLogonPasswordBlock
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>$safeLocalUsername</Username>
      </AutoLogon>
"@

        $firstLogonCommandsBlock = @"
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Gaming Lab First Logon</Description>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%WINDIR%\GamingLab\FirstLogon.ps1"</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
"@
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>0414:00000414</InputLocale>
      <SystemLocale>nb-NO</SystemLocale>
      <UILanguage>nb-NO</UILanguage>
      <UserLocale>nb-NO</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$safeComputerName</ComputerName>
      <TimeZone>W. Europe Standard Time</TimeZone>
$autoLogonBlock
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>$hideOnlineAccountScreens</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>
$firstLogonCommandsBlock
$localAccountBlock
    </component>
  </settings>
</unattend>
"@

    Set-Content -LiteralPath $DestinationPath -Value $xml -Encoding UTF8
}

function Build-IsoIfPossible {
    param(
        [string]$IsoRoot,
        [string]$OutputIso
    )

    $oscdimg = Find-Oscdimg
    if (-not $oscdimg) {
        Write-Host ""
        Write-Host "oscdimg.exe ble ikke funnet i PATH eller vanlige ADK-mapper. ISO-strukturen er klar i: $IsoRoot" -ForegroundColor Yellow
        return
    }

    Write-Step "Bygger ny ISO"

    $bootData = "2#p0,e,b$IsoRoot\boot\etfsboot.com#pEF,e,b$IsoRoot\efi\microsoft\boot\efisys.bin"
    & $oscdimg -m -o -u2 -udfver102 -bootdata:$bootData $IsoRoot $OutputIso
}

if (-not (Test-Administrator)) {
    throw "Dette scriptet må kjøres som administrator."
}

if (-not (Test-Path -LiteralPath $IsoPath)) {
    throw "Fant ikke ISO: $IsoPath"
}

$resolvedIso = (Resolve-Path -LiteralPath $IsoPath).Path
$scriptPayloadDir = Join-Path $scriptRoot "payload"
$isoRoot = Join-Path $OutputRoot "iso-root"
$mountDir = Join-Path $WorkingRoot "mount"

New-Item -ItemType Directory -Path $WorkingRoot -Force | Out-Null
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Remove-IfExists -LiteralPath $mountDir
New-Item -ItemType Directory -Path $mountDir | Out-Null
Remove-IfExists -LiteralPath $isoRoot

$diskImage = $null
$volume = $null

try {
    Write-Step "Monterer ISO"
    $diskImage = Mount-DiskImage -ImagePath $resolvedIso -PassThru
    $volume = $diskImage | Get-Volume
    $drive = "$($volume.DriveLetter):"

    Copy-IsoContents -SourceDrive $drive -Destination $isoRoot

    $installImage = Get-InstallImagePath -IsoRoot $isoRoot
    if (Test-Path -LiteralPath $installImage) {
        Set-ItemProperty -LiteralPath $installImage -Name IsReadOnly -Value $false
    }

    if (-not $EditionIndex) {
        Show-EditionsAndExit -ImagePath $installImage
        return
    }

    Write-Step "Monterer Windows image (index $EditionIndex)"
    Mount-WindowsImage -ImagePath $installImage -Index $EditionIndex -Path $mountDir | Out-Null

    Remove-ProvisionedApps -MountDir $mountDir
    Apply-OfflineRegistryTweaks -MountDir $mountDir
    Inject-Payload -MountDir $mountDir -PayloadDir $scriptPayloadDir

    Write-Step "Lagrer endringer"
    Dismount-WindowsImage -Path $mountDir -Save | Out-Null

    Write-Autounattend -DestinationPath (Join-Path $isoRoot "autounattend.xml") -ComputerName $ComputerName -LocalUsername $LocalUsername -LocalPassword $LocalPassword

    $outputIso = Join-Path $OutputRoot $IsoName
    Build-IsoIfPossible -IsoRoot $isoRoot -OutputIso $outputIso

    Write-Host ""
    Write-Host "Ferdig. Output ligger i: $OutputRoot" -ForegroundColor Green
}
catch {
    if (Test-Path -LiteralPath $mountDir) {
        try {
            Dismount-WindowsImage -Path $mountDir -Discard | Out-Null
        }
        catch {
        }
    }

    throw
}
finally {
    if ($diskImage) {
        Dismount-DiskImage -ImagePath $resolvedIso -ErrorAction SilentlyContinue
    }
}
