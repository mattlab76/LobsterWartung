# =========================
# Invoke-LobsterDataMaintenanceRunner.ps1
# Produktiv-Aufruf fuer Invoke-LobsterDataWrapperLogCheck
#
# Beispiele:
#   .\Invoke-LobsterDataMaintenanceRunner.ps1 -LogPath "D:\Lobster_data\IS\logs\wrapper.log"
# =========================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# --- Basis-Konfiguration laden ---
$baseCfgPath = Join-Path $projectRoot "config/lobsterdata.maintenance.prod.config.psd1"
if (-not (Test-Path -LiteralPath $baseCfgPath)) {
    $baseCfgPath = Join-Path $projectRoot "lobsterdata.maintenance.prod.config.psd1"
}
if (-not (Test-Path -LiteralPath $baseCfgPath)) {
    throw "Konfigurationsdatei nicht gefunden: $baseCfgPath"
}

$cfg = Import-PowerShellDataFile -Path $baseCfgPath

# --- Parameter einsetzen ---
$cfg['LogPath'] = $LogPath

# --- Pruefen ob Log-Datei existiert ---
if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Host "FEHLER: Log-Datei nicht gefunden: $LogPath" -ForegroundColor Red
    exit 99
}

# --- Runtime-Config schreiben ---
$runtimeDir = Join-Path $projectRoot "runtime"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$runtimeCfg = Join-Path $runtimeDir "config-runtime.psd1"

# PSD1 als Text erzeugen
$psd1 = @"
@{
  LogPath                = '$($cfg['LogPath'] -replace "'","''")'
  IsTest                 = `$$($cfg['IsTest'])
  TimeToleranceMinutes   = $($cfg['TimeToleranceMinutes'])
  WarnTailLines          = $($cfg['WarnTailLines'])
  ErrorTailLines         = $($cfg['ErrorTailLines'])
  MaxAttempts            = $($cfg['MaxAttempts'])
  AttemptSleepSeconds_Test  = $($cfg['AttemptSleepSeconds_Test'])
  AttemptSleepSeconds_Prod  = $($cfg['AttemptSleepSeconds_Prod'])
  RecheckSleepSeconds_Test  = $($cfg['RecheckSleepSeconds_Test'])
  RecheckSleepSeconds_Prod  = $($cfg['RecheckSleepSeconds_Prod'])
}
"@

Set-Content -LiteralPath $runtimeCfg -Value $psd1 -Encoding UTF8

# --- Ausfuehren ---
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host "LobsterData WrapperLogCheck PRODUKTIV" -ForegroundColor Cyan
Write-Host "  Log:    $LogPath" -ForegroundColor White
Write-Host "  Start:  $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor DarkGray

& (Join-Path $scriptRoot "Invoke-LobsterDataWrapperLogCheck.ps1") -ConfigPath $runtimeCfg
$code = $LASTEXITCODE

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host "Ende: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')  ExitCode=$code" -ForegroundColor DarkGray

exit $code
