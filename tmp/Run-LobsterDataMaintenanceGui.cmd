@echo off
setlocal
REM Console-GUI launcher for Invoke-LobsterDataMaintenance.ps1
REM Usage:
REM   Run-LobsterDataMaintenanceGui.cmd "<ComputerName>" "<RemoteProjectPath>" "<RemoteLogPath>" ["<NotifyMailTo>"]

if "%~1"=="" (
  echo Usage: %~nx0 "<ComputerName>" "<RemoteProjectPath>" "<RemoteLogPath>" ["<NotifyMailTo>"]
  exit /b 99
)
if "%~2"=="" (
  echo Usage: %~nx0 "<ComputerName>" "<RemoteProjectPath>" "<RemoteLogPath>" ["<NotifyMailTo>"]
  exit /b 99
)
if "%~3"=="" (
  echo Usage: %~nx0 "<ComputerName>" "<RemoteProjectPath>" "<RemoteLogPath>" ["<NotifyMailTo>"]
  exit /b 99
)

set COMPUTER=%~1
set REMOTEPROJECT=%~2
set REMOTELOG=%~3
set MAILTO=%~4

if "%MAILTO%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-LobsterDataMaintenanceGui.ps1" -ComputerName "%COMPUTER%" -RemoteProjectPath "%REMOTEPROJECT%" -RemoteLogPath "%REMOTELOG%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-LobsterDataMaintenanceGui.ps1" -ComputerName "%COMPUTER%" -RemoteProjectPath "%REMOTEPROJECT%" -RemoteLogPath "%REMOTELOG%" -SendNotification -NotifyMailTo "%MAILTO%"
)

exit /b %ERRORLEVEL%
