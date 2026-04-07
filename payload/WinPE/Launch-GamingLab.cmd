@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Gaming Lab Installer
color 0b

cls
echo.
echo ============================================================
echo                     GAMING LAB INSTALLER
echo ============================================================
echo.
echo  Windows Setup er skjult bak dette laget.
echo  Installasjonen fortsetter med Gaming Lab sin flyt.
echo.

set "MEDIA_DRIVE="
for %%D in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\setup.exe" (
        if exist "%%D:\sources\install.wim" set "MEDIA_DRIVE=%%D:"
        if exist "%%D:\sources\install.esd" set "MEDIA_DRIVE=%%D:"
    )
)

if not defined MEDIA_DRIVE (
    echo Fant ikke installasjonsmediet.
    echo.
    pause
    exit /b 1
)

set "UNATTEND_ARG="
if exist "%MEDIA_DRIVE%\autounattend.xml" (
    set "UNATTEND_ARG=/unattend:%MEDIA_DRIVE%\autounattend.xml"
    echo Fant automatisk oppsettsfil.
) else (
    echo Fant ikke autounattend.xml. Fortsetter med standard setup-parametre.
)

echo Installasjonsmedium: %MEDIA_DRIVE%
echo.
echo Trykk ENTER for aa starte installasjonen.
pause >nul

start "" /wait "%MEDIA_DRIVE%\setup.exe" %UNATTEND_ARG%
exit /b %errorlevel%
