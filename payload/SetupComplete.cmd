@echo off
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v GamingLabFirstLogon /t REG_SZ /d "powershell.exe -ExecutionPolicy Bypass -NoProfile -File \"%WINDIR%\GamingLab\FirstLogon.ps1\"" /f >nul 2>&1
exit /b 0
