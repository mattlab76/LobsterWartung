@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
  echo Usage: Run-LobsterDataOneCase.cmd TC01
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-TestCase.ps1" -Case %1
exit /b %ERRORLEVEL%
