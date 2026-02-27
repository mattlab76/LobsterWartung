param(
  [Parameter(Mandatory=$true)] [string]$ConfigPath,
  [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. "$PSScriptRoot\LobsterDataWrapperLogCheck-Helpers.ps1"

function Get-CfgValue {
  param(
    [hashtable]$Cfg,
    [Parameter(Mandatory=$true)][string]$Key,
    $Default
  )
  if ($null -ne $Cfg -and $Cfg.ContainsKey($Key)) { return $Cfg[$Key] }
  return $Default
}

$cfg = Import-PowerShellDataFile -Path $ConfigPath

$LogPath               = Get-CfgValue $cfg 'LogPath' (Join-Path $projectRoot 'runtime\wrapper.log')
$IsTest                = [bool](Get-CfgValue $cfg 'IsTest' $true)
$TimeToleranceMinutes  = [int](Get-CfgValue $cfg 'TimeToleranceMinutes' 5)
$WarnTailLines         = [int](Get-CfgValue $cfg 'WarnTailLines' 200)
$ErrorTailLines        = [int](Get-CfgValue $cfg 'ErrorTailLines' 200)
$MaxAttempts           = [int](Get-CfgValue $cfg 'MaxAttempts' 11)
$AttemptSleepSeconds   = if ($IsTest) { [int](Get-CfgValue $cfg 'AttemptSleepSeconds_Test' 1) } else { [int](Get-CfgValue $cfg 'AttemptSleepSeconds_Prod' 30) }
$RecheckSleepSeconds   = if ($IsTest) { [int](Get-CfgValue $cfg 'RecheckSleepSeconds_Test' 1) } else { [int](Get-CfgValue $cfg 'RecheckSleepSeconds_Prod' 10) }

$HostName = $env:COMPUTERNAME
if (-not $HostName) { $HostName = hostname }

$start = Get-Date
$today = $start.ToString('yyyy') + '[/.]' + $start.ToString('MM') + '[/.]' + $start.ToString('dd')

$patterns = New-WrapperPatterns -TodayString $today

function Emit-Result {
  param(
    [string]$Level,
    [string]$Message,
    [string[]]$LogLines = @(),
    [string]$HighlightPattern = '',
    [int]$ExitCode
  )

  Write-Host ""
  Write-Host "=== $Level ===" -ForegroundColor $(switch($Level) { 'OK' {'Green'} 'WARN' {'Yellow'} 'ERROR' {'Red'} })
  Write-Host $Message
  Write-Host ""

  $result = [PSCustomObject]@{
    HostName          = $HostName
    Level             = $Level
    Message           = $Message
    ExitCode          = $ExitCode
    Timestamp         = Get-Date
    LogPath           = $LogPath
    LogLines          = @($LogLines)
    HighlightPattern  = $HighlightPattern
    ScriptStart       = $start
  }

  if ($NoExit) {
    return $result
  }

  exit $ExitCode
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
  $linesCheck = Get-FileTailLines -Path $LogPath -TailLines $WarnTailLines
  if ($null -eq $linesCheck) { $linesCheck = @() }

  if (Is-ErrorStartImmediatelyAfterStopped -Lines $linesCheck -Patterns $patterns -ScriptStart $start -TimeToleranceMinutes $TimeToleranceMinutes) {
    $tail = Get-FileTailLines -Path $LogPath -TailLines 30
    if ($null -eq $tail) { $tail = @() }

    return (Emit-Result -Level 'ERROR' `
      -Message 'Der Wrapper wurde gestoppt, aber danach <strong>sofort wieder gestartet</strong>. Der Service laeuft wieder - der geplante Stopp war nicht erfolgreich.' `
      -LogLines $tail `
      -HighlightPattern '(Wrapper Stopped|Wrapper Started)' `
      -ExitCode 2)
  }

  $okInfo = Is-OkCandidate -Lines $linesCheck -Patterns $patterns -ScriptStart $start -TimeToleranceMinutes $TimeToleranceMinutes

  $ok   = [bool]$okInfo.Ok
  $near = [bool]$okInfo.Near
  $last = [bool]$okInfo.IsLast

  Write-Host ("[{0}] Attempt {1}/{2}: Ok={3} Near={4} IsLast={5}" -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'), $attempt, $MaxAttempts, $ok, $near, $last)

  if ($ok -and $near -and $last) {
    Start-Sleep -Seconds $RecheckSleepSeconds
    $linesRe = Get-FileTailLines -Path $LogPath -TailLines $WarnTailLines
    if ($null -eq $linesRe) { $linesRe = @() }
    $okInfo2 = Is-OkCandidate -Lines $linesRe -Patterns $patterns -ScriptStart $start -TimeToleranceMinutes $TimeToleranceMinutes

    if ([bool]$okInfo2.Ok -and [bool]$okInfo2.Near -and [bool]$okInfo2.IsLast) {
      $tail = Get-FileTailLines -Path $LogPath -TailLines 10
      if ($null -eq $tail) { $tail = @() }

      return (Emit-Result -Level 'OK' `
        -Message 'Der Wrapper wurde <strong>erfolgreich gestoppt</strong>. Keine weiteren Aktivitaeten im Log nach dem Stopp.' `
        -LogLines $tail `
        -HighlightPattern 'Wrapper Stopped' `
        -ExitCode 0)
    }
  }

  Start-Sleep -Seconds $AttemptSleepSeconds
}

$tailWarn = Get-FileTailLines -Path $LogPath -TailLines 30
if ($null -eq $tailWarn) { $tailWarn = @() }

$allTailLines = Get-FileTailLines -Path $LogPath -TailLines $WarnTailLines
$lastCheck = Is-OkCandidate -Lines $allTailLines -Patterns $patterns -ScriptStart $start -TimeToleranceMinutes $TimeToleranceMinutes

$reason = ''

if ($lastCheck.Index -ge 0) {
  if (-not $lastCheck.Near) {
    $stoppedTs = if ($lastCheck.Timestamp) { $lastCheck.Timestamp.ToString('dd.MM.yyyy HH:mm:ss') } else { '(unbekannt)' }
    $reason = "<strong>Gestoppt heute, aber falsche Uhrzeit.</strong><br><br>" +
              "Der Wrapper wurde heute um <strong>$stoppedTs</strong> gestoppt.<br>" +
              "Erwartet war ein Stopp im Zeitfenster <strong>$('{0:HH:mm:ss}' -f $start) &plusmn; $TimeToleranceMinutes Minuten</strong> (Skriptstart: $('{0:dd.MM.yyyy HH:mm:ss}' -f $start)).<br><br>" +
              "Der Stopp liegt ausserhalb dieses Fensters - moeglicherweise wurde der Wrapper zu einem anderen Zeitpunkt gestoppt."
  }
  elseif (-not $lastCheck.IsLast) {
    $reason = "<strong>'Wrapper Stopped' wurde gefunden, aber es gibt danach weitere Log-Eintraege.</strong><br><br>" +
              "Der Wrapper wurde moeglicherweise nicht dauerhaft gestoppt."
  }
  else {
    $reason = "Die OK-Bedingungen wurden nach $MaxAttempts Pruefungen nicht stabil erreicht."
  }
} else {
  $anyDateIdx = Find-LastMatchIndex -Lines $allTailLines -Regex $patterns.StoppedAnyDateRegex
  if ($anyDateIdx -ge 0) {
    $oldTs = Parse-WrapperTimestamp -Line $allTailLines[$anyDateIdx]
    $oldTsStr = if ($oldTs) { $oldTs.ToString('dd.MM.yyyy HH:mm:ss') } else { '(unbekannt)' }
    $reason = "<strong>Gestoppt, aber falsches Datum.</strong><br><br>" +
              "Der letzte 'Wrapper Stopped' Eintrag im Log ist vom <strong>$oldTsStr</strong>.<br>" +
              "Heute (<strong>$('{0:dd.MM.yyyy}' -f $start)</strong>) wurde <strong>kein</strong> Stopp gefunden.<br><br>" +
              "Moeglicherweise wurde der Wrapper seit dem letzten Stopp neu gestartet und laeuft seitdem."
  } else {
    $reason = "<strong>Kein 'Wrapper Stopped' im Log gefunden.</strong><br><br>" +
              "In den letzten $WarnTailLines Zeilen des Logs gibt es keinen Hinweis auf einen Wrapper-Stopp.<br>" +
              "Der Wrapper laeuft vermutlich noch."
  }
}

return (Emit-Result -Level 'WARN' `
  -Message $reason `
  -LogLines $tailWarn `
  -HighlightPattern '(Wrapper Stopped|Wrapper Started)' `
  -ExitCode 1)
