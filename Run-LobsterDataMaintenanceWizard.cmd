@echo off
setlocal
REM Wizard launcher (prints the command; does NOT execute the maintenance script)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-LobsterDataMaintenanceWizard.ps1"
exit /b %ERRORLEVEL%
