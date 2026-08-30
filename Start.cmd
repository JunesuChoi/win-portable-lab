@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0"
set "PSModulePath=%USERPROFILE%\Documents\WindowsPowerShell\Modules;%ProgramFiles%\WindowsPowerShell\Modules;%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Start-WinPortableLab.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo WinPortableLab failed with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
