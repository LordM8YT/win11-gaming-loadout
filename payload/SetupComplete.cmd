@echo off
reg load HKU\GL_DEFAULT "%SystemDrive%\Users\Default\NTUSER.DAT" >nul 2>&1
reg add "HKU\GL_DEFAULT\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v GamingLabFirstLogon /t REG_SZ /d "powershell.exe -ExecutionPolicy Bypass -NoProfile -File \"%WINDIR%\GamingLab\FirstLogon.ps1\"" /f >nul 2>&1
reg unload HKU\GL_DEFAULT >nul 2>&1
exit /b 0
