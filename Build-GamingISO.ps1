[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IsoPath,

    [int]$EditionIndex,

    [string]$WorkingRoot = (Join-Path $PSScriptRoot "work"),

    [string]$OutputRoot = (Join-Path $PSScriptRoot "output"),

    [string]$IsoName = "Win11-GamingLab.iso"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
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

function Apply-OfflineRegistryTweaks {
    param([string]$MountDir)

    Write-Step "Setter offline gaming-/støyreduksjonstweaks"

    $softwareHive = Join-Path $MountDir "Windows\System32\Config\SOFTWARE"
    $defaultHive = Join-Path $MountDir "Users\Default\NTUSER.DAT"

    reg load HKLM\GL_SOFTWARE $softwareHive | Out-Null
    reg load HKU\GL_DEFAULT $defaultHive | Out-Null

    try {
        reg add "HKLM\GL_SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKLM\GL_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v DisableEdgeDesktopShortcutCreation /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKLM\GL_SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" /v value /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKLM\GL_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f | Out-Null
        reg add "HKLM\GL_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 10 /f | Out-Null
        reg add "HKLM\GL_SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f | Out-Null

        reg add "HKU\GL_DEFAULT\Software\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null
    }
    finally {
        reg unload HKLM\GL_SOFTWARE | Out-Null
        reg unload HKU\GL_DEFAULT | Out-Null
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

    New-Item -ItemType Directory -Path $setupScripts -Force | Out-Null
    New-Item -ItemType Directory -Path $gamingLab -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $PayloadDir "SetupComplete.cmd") -Destination (Join-Path $setupScripts "SetupComplete.cmd") -Force
    Copy-Item -LiteralPath (Join-Path $PayloadDir "FirstLogon.ps1") -Destination (Join-Path $gamingLab "FirstLogon.ps1") -Force
}

function Write-Autounattend {
    param([string]$DestinationPath)

    Write-Step "Genererer autounattend.xml"

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>0414:00000414</InputLocale>
      <SystemLocale>nb-NO</SystemLocale>
      <UILanguage>nb-NO</UILanguage>
      <UserLocale>nb-NO</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <TimeZone>W. Europe Standard Time</TimeZone>
      <OOBE>
        <HideEULAPage>false</HideEULAPage>
        <HideOnlineAccountScreens>false</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
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

    $oscdimg = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if (-not $oscdimg) {
        Write-Host ""
        Write-Host "oscdimg.exe ble ikke funnet. ISO-strukturen er klar i: $IsoRoot" -ForegroundColor Yellow
        return
    }

    Write-Step "Bygger ny ISO"

    $bootData = "2#p0,e,b$IsoRoot\boot\etfsboot.com#pEF,e,b$IsoRoot\efi\microsoft\boot\efisys.bin"
    & $oscdimg.Source -m -o -u2 -udfver102 -bootdata:$bootData $IsoRoot $OutputIso
}

if (-not (Test-Administrator)) {
    throw "Dette scriptet må kjøres som administrator."
}

if (-not (Test-Path -LiteralPath $IsoPath)) {
    throw "Fant ikke ISO: $IsoPath"
}

$resolvedIso = (Resolve-Path -LiteralPath $IsoPath).Path
$scriptPayloadDir = Join-Path $PSScriptRoot "payload"
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

    Write-Autounattend -DestinationPath (Join-Path $isoRoot "autounattend.xml")

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
