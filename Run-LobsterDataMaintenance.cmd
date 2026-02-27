@echo off
setlocal

:: ==========================================================
:: LobsterData - Produktiv-Start
::
:: Aufruf:
::   Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"
::
:: Parameter:
::   1 = Pfad zur wrapper.log
:: ==========================================================

cd /d "%~dp0"

if "%~1"=="" (
    echo.
    echo   LobsterData - Produktiv-Start
    echo   ==================================
    echo.
    echo   Aufruf:
    echo     Run-LobsterDataMaintenance.cmd "Pfad\zur\wrapper.log"
    echo.
    echo   Beispiel:
    echo     Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"
    echo.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-LobsterDataMaintenanceRunner.ps1" -LogPath "%~1"
exit /b %ERRORLEVEL%
