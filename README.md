# Win11 Gaming Loadout

Dette oppsettet lager en lokal, tilpasset Windows 11 "gaming build" fra en offisiell ISO uten å røre originalfilen.

Fokus:

- fjerne en del forhåndsinstallerte apper
- beholde Windows Update, Defender og Microsoft Store
- aktivere gaming- og ytelsesvennlige standardvalg
- legge inn en GUI-basert Gaming Loadout Wizard ved første innlogging
- bygge en ny ISO hvis `oscdimg.exe` finnes

Dette er bevisst tryggere enn mange ekstremt stripped varianter. Målet er en rask og ren gaming-build, ikke en ødelagt build som mister oppdateringer eller drivere.

## Loadout Wizard

Etter første innlogging starter en enkel GUI-wizard som er inspirert av "system loadout"-ideen:

- profiler: `Competitive`, `FiveM`, `Streamer`, `Creator`
- predefinerte tweaks per profil
- valgfri appinstallasjon med `winget`
- cyber/gaming-look som ekstra preset

Wizard-en kjører lokalt via PowerShell + WPF og krever ingen ekstra GUI-rammeverk.

## Krav

- Windows Terminal / PowerShell kjørt som administrator
- `DISM` er innebygd i Windows
- `oscdimg.exe` er valgfri, men nødvendig for å bygge ny bootbar ISO
  - følger vanligvis med Windows ADK

## Hva som gjøres

- kopierer innholdet fra ISO til en arbeidsmappe
- monterer `install.wim`
- fjerner utvalgte provisioned apps
- setter offline-registertweaks for mindre bakgrunnsstøy og mer gaming-fokus
- legger inn `SetupComplete.cmd` og en GUI-basert `FirstLogon.ps1`
- genererer `autounattend.xml`
- bygger ny ISO hvis verktøy finnes

## Hva som ikke gjøres

- ingen aktiverings- eller lisensomgåelser
- ingen TPM-/Secure Boot-bypass
- ingen fjerning av Windows Update eller Defender

## Kjøring

Eksempel:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd "C:\Users\Patri\Desktop\Fivem Scripts\OX Cyber skin\Storage Job\win11-gaming-build"
.\Build-GamingISO.ps1 -IsoPath "C:\Users\Patri\Downloads\Win11_25H2_Norwegian_x64_v2.iso"
```

Første kjøring uten `-EditionIndex` vil bare vise tilgjengelige editions og stoppe. Kjør så på nytt med ønsket index:

```powershell
.\Build-GamingISO.ps1 -IsoPath "C:\Users\Patri\Downloads\Win11_25H2_Norwegian_x64_v2.iso" -EditionIndex 6
```

Hvis `oscdimg.exe` ikke finnes, blir den ferdige ISO-strukturen liggende i `output\iso-root` og kan bygges senere.

## Output

- ISO-struktur: `output\iso-root`
- ferdig ISO: `output\Win11-GamingLab.iso` hvis `oscdimg.exe` er tilgjengelig
