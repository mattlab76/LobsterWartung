<#
.SYNOPSIS
  Interactive console wizard that ONLY PRINTS the command line for Invoke-LobsterDataMaintenance.ps1.
.DESCRIPTION
  This wizard asks step-by-step questions and then outputs the PowerShell call to run.
  IMPORTANT: It does NOT execute the maintenance script.
#>

[CmdletBinding()]
param()

function Read-Choice {
  param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string[]]$Options,
    [string]$Prompt = "Auswahl"
  )

  while ($true) {
    Write-Host ""
    Write-Host $Title
    for ($i=0; $i -lt $Options.Count; $i++) {
      $n = $i + 1
      Write-Host ("  {0}) {1}" -f $n, $Options[$i])
    }
    $raw = Read-Host "$Prompt (1-$($Options.Count))"
    if ($raw -match '^\d+$') {
      $idx = [int]$raw - 1
      if ($idx -ge 0 -and $idx -lt $Options.Count) { return $Options[$idx] }
    }
    Write-Host "Ungültige Eingabe. Bitte nochmal." -ForegroundColor Yellow
  }
}

function Read-YesNo {
  param([Parameter(Mandatory=$true)][string]$Question)
  while ($true) {
    $raw = Read-Host "$Question (j/n)"
    switch ($raw.Trim().ToLowerInvariant()) {
      'j' { return $true }
      'ja' { return $true }
      'y' { return $true }
      'yes' { return $true }
      'n' { return $false }
      'nein' { return $false }
      'no' { return $false }
    }
    Write-Host "Bitte 'j' oder 'n' eingeben." -ForegroundColor Yellow
  }
}

function Read-NonEmpty {
  param([Parameter(Mandatory=$true)][string]$Question)
  while ($true) {
    $raw = Read-Host $Question
    if (-not [string]::IsNullOrWhiteSpace($raw)) { return $raw.Trim() }
    Write-Host "Darf nicht leer sein." -ForegroundColor Yellow
  }
}

function Show-NotAvailable {
  param([Parameter(Mandatory=$true)][string]$Feature)
  Write-Host ""
  Write-Host ("{0} ist aktuell noch NICHT verfügbar." -f $Feature) -ForegroundColor Yellow
  $next = Read-Choice -Title "Wie weiter?" -Options @("Andere Auswahl treffen", "Abbrechen") -Prompt "Weiter"
  if ($next -eq "Abbrechen") {
    Write-Host "Abgebrochen." -ForegroundColor Cyan
    exit 3
  }
}

# 1) Read only vs Start/Stop
$mode = Read-Choice -Title "1) Was soll gemacht werden?" -Options @(
  "Nur Read (Log durchlesen + optional Mail)",
  "Start/Stop Lobster Instanz (optional, fliegt später evtl. raus)"
) -Prompt "Modus"

$stopMode     = "None"
$serviceScope = $null
$scope        = $null
$serviceName  = $null

if ($mode -like "Start/Stop*") {
  # 3) Start or Stop
  $startStop = Read-Choice -Title "3) Starten oder Stoppen?" -Options @("Start Lobster", "Stopp Lobster") -Prompt "Aktion"

  if ($startStop -eq "Start Lobster") {
    Show-NotAvailable -Feature "Start Lobster"
    $startStop = Read-Choice -Title "3) Starten oder Stoppen?" -Options @("Start Lobster", "Stopp Lobster") -Prompt "Aktion"
    if ($startStop -eq "Start Lobster") { Show-NotAvailable -Feature "Start Lobster" }
  }

  # 5) Stop method
  $stopMethod = Read-Choice -Title "5) Stopp-Methode?" -Options @("REST API", "Windows Dienst") -Prompt "Methode"
  if ($stopMethod -eq "REST API") {
    Show-NotAvailable -Feature "Stopp über REST API"
    $stopMethod = Read-Choice -Title "5) Stopp-Methode?" -Options @("REST API", "Windows Dienst") -Prompt "Methode"
    if ($stopMethod -eq "REST API") { Show-NotAvailable -Feature "Stopp über REST API" }
  }

  $stopMode = "WindowsService"

  # 7) Local vs Remote service
  $serviceScope = Read-Choice -Title "7) Windows Dienst: Lokal oder Remote?" -Options @("Local", "Remote") -Prompt "Scope"
  $serviceName  = Read-NonEmpty -Question 'ServiceName (Dienstname, z.B. "LobsterIntegrationServer")'
  $scope = $serviceScope
}
else {
  # 10) Read-only: Local or Remote  ✅ (das hat bei dir gefehlt/war kaputt)
  $scope = Read-Choice -Title "10) Read only: Lokal oder Remote?" -Options @("Local", "Remote") -Prompt "Scope"
}

# Collect parameters depending on scope
$logPath          = $null
$computerName     = $null
$remoteProjectPath= $null
$remoteLogPath    = $null

if ($scope -eq "Local") {
  $logPath = Read-NonEmpty -Question "LogPath (vollständiger Pfad zur wrapper.log)"
} else {
  $computerName      = Read-NonEmpty -Question "ComputerName (z.B. aqlbt101.bmlc.local)"
  $remoteProjectPath = Read-NonEmpty -Question "RemoteProjectPath (Pfad am Remote Host zum Paketordner)"
  $remoteLogPath     = Read-NonEmpty -Question "RemoteLogPath (vollständiger Pfad zur wrapper.log am Remote Host)"
}

$sendMail = Read-YesNo -Question "SendNotification (Mail senden)?"
$notifyTo = $null
if ($sendMail) {
  $notifyTo = Read-NonEmpty -Question "NotifyMailTo (Empfänger Mailadresse)"
}

# Build command (printed only)
$parts = New-Object System.Collections.Generic.List[string]
$parts.Add(".\Invoke-LobsterDataMaintenance.ps1")

if ($scope -eq "Local") {
  $parts.Add("-LogPath"); $parts.Add(('"{0}"' -f $logPath))
} else {
  $parts.Add("-ComputerName");      $parts.Add(('"{0}"' -f $computerName))
  $parts.Add("-RemoteProjectPath"); $parts.Add(('"{0}"' -f $remoteProjectPath))
  $parts.Add("-RemoteLogPath");     $parts.Add(('"{0}"' -f $remoteLogPath))
}

$parts.Add("-StopMode"); $parts.Add($stopMode)

if ($stopMode -eq "WindowsService") {
  $parts.Add("-ServiceName");  $parts.Add(('"{0}"' -f $serviceName))
  $parts.Add("-ServiceScope"); $parts.Add($serviceScope)
}

if ($sendMail) {
  $parts.Add("-SendNotification")
  $parts.Add("-NotifyMailTo"); $parts.Add(('"{0}"' -f $notifyTo))
}

# Pretty multiline
$pretty = @()
$pretty += '.\Invoke-LobsterDataMaintenance.ps1 `'
if ($scope -eq "Local") {
  $pretty += ('  -LogPath "{0}" `' -f $logPath)
} else {
  $pretty += ('  -ComputerName "{0}" `' -f $computerName)
  $pretty += ('  -RemoteProjectPath "{0}" `' -f $remoteProjectPath)
  $pretty += ('  -RemoteLogPath "{0}" `' -f $remoteLogPath)
}
$pretty += ('  -StopMode {0} `' -f $stopMode)
if ($stopMode -eq "WindowsService") {
  $pretty += ('  -ServiceName "{0}" `' -f $serviceName)
  $pretty += ('  -ServiceScope {0} `' -f $serviceScope)
}
if ($sendMail) {
  $pretty += "  -SendNotification `"
  $pretty += ('  -NotifyMailTo "{0}"' -f $notifyTo)
} else {
  $pretty[-1] = $pretty[-1].TrimEnd(' `')
}

Write-Host ""
Write-Host "===== AUFRUF (wird NICHT ausgeführt) =====" -ForegroundColor Cyan
Write-Host ""
Write-Host ($pretty -join "`r`n")
Write-Host ""
Write-Host "----- One-liner -----" -ForegroundColor DarkCyan
Write-Host ($parts -join " ")
Write-Host ""