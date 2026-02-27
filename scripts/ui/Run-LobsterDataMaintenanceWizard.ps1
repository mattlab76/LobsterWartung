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

# 1) Action
$actionChoice = Read-Choice -Title "1) Was soll gemacht werden?" -Options @(
  "Read (Log durchlesen + optional Mail)",
  "Stop (Windows Dienst stoppen + StartupType Manual + Logcheck)",
  "Start (wenn nicht Running: StartupType Automatic + Start + Logcheck)"
) -Prompt "Aktion"

$action = switch ($actionChoice) {
  {$_ -like "Read*"}  { "Read" }
  {$_ -like "Stop*"}  { "Stop" }
  default             { "Start" }
}

# 2) Scope (log scope always needed)
$scope = Read-Choice -Title "2) Lokal oder Remote?" -Options @("Local", "Remote") -Prompt "Scope"

$serviceScope = $null
$serviceName = $null

if ($action -in @("Stop","Start")) {
  # Service scope can be chosen independent of log scope, but keep it simple: same as scope
  $serviceScope = $scope
  $serviceName = Read-NonEmpty -Question 'ServiceName (Dienst-Name, wie bei "Get-Service -Name ...")'
}

# 3) Collect parameters
$logPath = $null
$computerName = $null
$remoteProjectPath = $null
$remoteLogPath = $null

if ($scope -eq "Local") {
  $logPath = Read-NonEmpty -Question "LogPath (vollständiger Pfad zur wrapper.log)"
} else {
  $computerName = Read-NonEmpty -Question "ComputerName (z.B. aqlbt101.bmlc.local)"
  $remoteProjectPath = Read-NonEmpty -Question "RemoteProjectPath (Pfad am Remote Host zum Paketordner)"
  $remoteLogPath = Read-NonEmpty -Question "RemoteLogPath (vollständiger Pfad zur wrapper.log am Remote Host)"
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
  $parts.Add("-ComputerName"); $parts.Add(('"{0}"' -f $computerName))
  $parts.Add("-RemoteProjectPath"); $parts.Add(('"{0}"' -f $remoteProjectPath))
  $parts.Add("-RemoteLogPath"); $parts.Add(('"{0}"' -f $remoteLogPath))
}

$parts.Add("-Action"); $parts.Add($action)

if ($action -in @("Stop","Start")) {
  $parts.Add("-ServiceName"); $parts.Add(('"{0}"' -f $serviceName))
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
$pretty += ('  -Action {0} `' -f $action)

if ($action -in @("Stop","Start")) {
  $pretty += ('  -ServiceName "{0}" `' -f $serviceName)
  $pretty += ('  -ServiceScope {0} `' -f $serviceScope)
}

if ($sendMail) {
  $pretty += '  -SendNotification `'
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
