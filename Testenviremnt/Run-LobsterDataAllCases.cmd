@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-TestCase.ps1" -All
exit /b %ERRORLEVEL%
