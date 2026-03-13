#Requires -Version 5.1
<#
.SYNOPSIS
    Lobster-Dienst starten und Java-Wrapper-Start verifizieren.

.DESCRIPTION
    Wird auf dem jeweiligen Host lokal ausgefuehrt.

    OHNE -DmzHost (DMZ-Modus / Standalone):
        - Startet den lokalen Lobster-Dienst
        - Prueft das Wrapper-Log bis "Integration Server (IS) started" bestaetigt ist
        - Gibt ein Ergebnis-Objekt zurueck (fuer Invoke-Command auf Backend-Host)

    MIT -DmzHost (Backend-Modus / Orchestrator):
        - Startet zuerst den lokalen Backend-Dienst und prueft Wrapper-Log
        - Nur wenn Backend OK: startet den DMZ-Host via Invoke-Command
        - Sendet Ergebnis-Mail (OK oder Fehler)

.NOTES
    Deployment:
        Backend-Host: z.B. C:\LobsterMaintenance\Start-LobsterService.ps1
        DMZ-Host:     z.B. C:\LobsterMaintenance\Start-LobsterService.ps1

    Der Scheduled Task wird vom Lobster Scheduler Manager angelegt und
    ruft dieses Skript auf dem Backend-Host mit allen Parametern auf.

.EXAMPLE
    # Standalone / DMZ-Modus (direkt auf einem Host ausfuehren):
    .\Start-LobsterService.ps1 `
        -ServiceName    "Lobster Integration Server" `
        -WrapperLogPath "D:\Lobster\IS\logs\wrapper.log"

.EXAMPLE
    # Backend-Modus (Orchestrator) – startet Backend, dann DMZ, dann Mail:
    .\Start-LobsterService.ps1 `
        -ServiceName       "Lobster Integration Server" `
        -WrapperLogPath    "D:\Lobster\IS\logs\wrapper.log" `
        -DmzHost           "dmz-server01" `
        -DmzCredential     (Get-Credential) `
        -DmzServiceName    "Lobster Integration Server" `
        -DmzWrapperLogPath "D:\Lobster\IS\logs\wrapper.log" `
        -DmzScriptPath     "C:\LobsterMaintenance\Start-LobsterService.ps1" `
        -MailTo            "admin@firma.local" `
        -SmtpServer        "smtp.firma.local"
#>

[CmdletBinding()]
param(
    # Lokaler Dienst (auf dem Host wo das Skript laeuft)
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$true)]
    [string]$WrapperLogPath,

    # ── Orchestrator-Modus: nur auf Backend-Host setzen ──────────────────────
    # Wenn gesetzt, wird nach dem Backend-Start auch der DMZ-Host gestartet.
    [string]$DmzHost            = '',
    [pscredential]$DmzCredential,
    [string]$DmzServiceName     = '',
    [string]$DmzWrapperLogPath  = '',

    # Pfad zu diesem Skript auf dem DMZ-Host (leer = wird aus $PSScriptRoot abgeleitet)
    [string]$DmzScriptPath      = '',

    # ── Mail-Benachrichtigung (nur im Orchestrator-Modus) ────────────────────
    [string]$MailTo      = '',
    [string]$MailFrom    = 'noreply@firma.local',
    [string]$SmtpServer  = '',

    # ── Wrapper-Log-Pruefung ─────────────────────────────────────────────────
    # Maximale Wartezeit bis "system is ready" im Log erscheint
    [int]$MaxWaitSeconds      = 300,

    # Intervall zwischen Log-Pruefungen
    [int]$PollIntervalSeconds = 15,

    # Anzahl der Zeilen die vom Log-Ende gelesen werden
    [int]$TailLines           = 50,

    # Zeitfenster in dem der Start-Timestamp liegen muss (+/- Minuten)
    [int]$TimeTolerance       = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────

function Start-LobsterServiceLocally {
    param([string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction Stop

    if ($svc.Status -eq 'Running') {
        return [PSCustomObject]@{ Ok=$true; AlreadyRunning=$true; Message="Dienst laeuft bereits: $Name" }
    }

    Set-Service  -Name $Name -StartupType Automatic -ErrorAction Stop
    Start-Service -Name $Name -ErrorAction Stop

    return [PSCustomObject]@{ Ok=$true; AlreadyRunning=$false; Message="Dienst gestartet: $Name" }
}

function Get-WrapperLastStatus {
    param(
        [string] $LogPath,
        [int]    $Tail
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return [PSCustomObject]@{
            Ok      = $true
            Message = "Dienst laeuft bereits. Wrapper-Log nicht gefunden: $LogPath"
            LogTail = @()
        }
    }

    $lines = @(Get-Content -LiteralPath $LogPath -Tail $Tail -ErrorAction Stop)

    # Letzten "Wrapper Stopped" und "system is ready" suchen (ohne Datum-Filter)
    $stoppedRx = [regex]::new(
        '^\s*STATUS\s*\|\s*wrapper\s*\|\s*(\d{4})[/.](\d{2})[/.](\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s*\|\s*<--\s*Wrapper\s+Stopped',
        'IgnoreCase')
    $readyRx   = [regex]::new(
        '^\s*INFO\s*\|\s*jvm\s+\d+\s*\|\s*(\d{4})[/.](\d{2})[/.](\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s*\|\s*Integration Server \(IS\) started in \d+ ms,\s*system is ready',
        'IgnoreCase')

    $lastStop  = $null
    $lastStart = $null
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if (-not $lastStop) {
            $m = $stoppedRx.Match($lines[$i])
            if ($m.Success) {
                $lastStop = [datetime]::new(
                    [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value,
                    [int]$m.Groups[4].Value, [int]$m.Groups[5].Value, [int]$m.Groups[6].Value)
            }
        }
        if (-not $lastStart) {
            $m = $readyRx.Match($lines[$i])
            if ($m.Success) {
                $lastStart = [datetime]::new(
                    [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value,
                    [int]$m.Groups[4].Value, [int]$m.Groups[5].Value, [int]$m.Groups[6].Value)
            }
        }
        if ($lastStop -and $lastStart) { break }
    }

    $parts = @("Dienst laeuft bereits.")
    if ($lastStop)  { $parts += "Letzter Stopp: $($lastStop.ToString('dd.MM.yyyy HH:mm:ss'))" }
    if ($lastStart) { $parts += "Letzter Start: $($lastStart.ToString('dd.MM.yyyy HH:mm:ss'))" }

    return [PSCustomObject]@{
        Ok      = $true
        Message = $parts -join ' '
        LogTail = $lines
    }
}

function Wait-WrapperStarted {
    param(
        [string]  $LogPath,
        [int]     $MaxSeconds,
        [int]     $PollSeconds,
        [int]     $Tail,
        [datetime]$Since,
        [int]     $ToleranceMinutes
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return [PSCustomObject]@{ Ok=$false; Message="Wrapper-Log nicht gefunden: $LogPath"; LogTail=@() }
    }

    $todayPart = $Since.ToString('yyyy') + '[/.]' + $Since.ToString('MM') + '[/.]' + $Since.ToString('dd')
    $deadline  = $Since.AddSeconds($MaxSeconds)

    # Erfolgsmuster: "Integration Server (IS) started in NNN ms, system is ready..."
    $readyRx = [regex]::new(
        "^\s*INFO\s*\|\s*jvm\s+\d+\s*\|\s*${todayPart}\s+(\d{2}):(\d{2}):(\d{2})\s*\|\s*Integration Server \(IS\) started in \d+ ms,\s*system is ready",
        'IgnoreCase')

    # Fehlermuster: Wrapper wurde nach Start wieder gestoppt
    $stoppedRx = [regex]::new(
        "^\s*STATUS\s*\|\s*wrapper\s*\|\s*${todayPart}\s+\d{2}:\d{2}:\d{2}\s*\|\s*<--\s*Wrapper\s+Stopped\s*$",
        'IgnoreCase')

    # Timestamp-Extraktion aus der INFO-Zeile
    $tsRx = [regex]::new(
        "^\s*INFO\s*\|\s*jvm\s+\d+\s*\|\s*(\d{4})[/.](\d{2})[/.](\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s*\|",
        'IgnoreCase')

    do {
        $lines = @(Get-Content -LiteralPath $LogPath -Tail $Tail -ErrorAction Stop)

        # Letzten "system is ready" und "Wrapper Stopped" Index suchen
        $lastReadyIdx = -1
        $lastStopIdx  = -1
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lastReadyIdx -lt 0 -and $readyRx.IsMatch($lines[$i])) { $lastReadyIdx = $i }
            if ($lastStopIdx  -lt 0 -and $stoppedRx.IsMatch($lines[$i])) { $lastStopIdx  = $i }
            if ($lastReadyIdx -ge 0 -and $lastStopIdx -ge 0) { break }
        }

        # Fehler: Wrapper wurde nach Start wieder gestoppt
        if ($lastReadyIdx -ge 0 -and $lastStopIdx -gt $lastReadyIdx) {
            return [PSCustomObject]@{
                Ok      = $false
                Message = "Wrapper nach Start wieder gestoppt - Dienst ist nicht mehr aktiv."
                LogTail = $lines
            }
        }

        if ($lastReadyIdx -ge 0) {
            $m = $tsRx.Match($lines[$lastReadyIdx])
            if ($m.Success) {
                $ts = [datetime]::new(
                    [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value,
                    [int]$m.Groups[4].Value, [int]$m.Groups[5].Value, [int]$m.Groups[6].Value)

                $deltaMin = [Math]::Abs(($ts - $Since).TotalMinutes)

                # Timestamp im Toleranzfenster?
                # (kein Check auf letzte Zeile – nach "system is ready" folgen weitere Log-Eintraege)
                if ($deltaMin -le $ToleranceMinutes) {
                    return [PSCustomObject]@{
                        Ok      = $true
                        Message = "Integration Server gestartet um $($ts.ToString('HH:mm:ss'))."
                        LogTail = $lines
                    }
                }
            }
        }

        if ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $PollSeconds
        }

    } while ((Get-Date) -lt $deadline)

    return [PSCustomObject]@{
        Ok      = $false
        Message = "Timeout: IS-Start nach $MaxSeconds Sekunden nicht bestaetigt."
        LogTail = $lines
    }
}

function Format-LogTailHtml {
    param(
        [string]$Label,
        [string[]]$Lines
    )
    if (-not $Lines -or $Lines.Count -eq 0) { return '' }

    $enc = [System.Net.WebUtility]
    $escaped = ($Lines | ForEach-Object { $enc::HtmlEncode($_) }) -join "`n"

    return @"
  <h3 style="color:#555;margin-top:24px;">Letzte Log-Zeilen &ndash; $($enc::HtmlEncode($Label))</h3>
  <pre style="background:#f5f5f5;border:1px solid #ddd;padding:12px;font-size:12px;
              font-family:Consolas,monospace;overflow-x:auto;max-width:800px;line-height:1.5;">$escaped</pre>
"@
}

function Send-ResultMail {
    param(
        [string]$To,
        [string]$From,
        [string]$Smtp,
        [bool]  $Success,
        [string]$DmzMessage,
        [string]$BackendMessage,
        [string[]]$BackendLogTail = @(),
        [string[]]$DmzLogTail    = @()
    )

    $status = if ($Success) { 'OK' } else { 'FEHLER' }
    $color  = if ($Success) { '#2e7d32' } else { '#c62828' }
    $icon   = if ($Success) { '&#10003;' } else { '&#10007;' }

    $subject = "Lobster Start - $status - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"

    $enc = [System.Net.WebUtility]

    $backendLogHtml = Format-LogTailHtml -Label 'Backend' -Lines $BackendLogTail
    $dmzLogHtml     = Format-LogTailHtml -Label 'DMZ'     -Lines $DmzLogTail

    $body = @"
<html>
<body style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#333;">
  <h2 style="color:$color;">$icon Lobster Start - $status</h2>
  <table border="1" cellpadding="8" cellspacing="0"
         style="border-collapse:collapse;min-width:500px;">
    <tr style="background:#f0f0f0;">
      <th style="text-align:left;">Host</th>
      <th style="text-align:left;">Ergebnis</th>
    </tr>
    <tr>
      <td>Backend-Host</td>
      <td>$($enc::HtmlEncode($BackendMessage))</td>
    </tr>
    <tr>
      <td>DMZ-Host</td>
      <td>$($enc::HtmlEncode($DmzMessage))</td>
    </tr>
  </table>
$backendLogHtml
$dmzLogHtml
  <p style="color:#999;font-size:11px;margin-top:20px;">
    $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss') &ndash; $env:COMPUTERNAME
  </p>
</body>
</html>
"@

    Send-MailMessage `
        -To $To -From $From -SmtpServer $Smtp `
        -Subject $subject -Body $body -BodyAsHtml `
        -ErrorAction Stop
}

# ── Hauptlogik ────────────────────────────────────────────────────────────────

if ([string]::IsNullOrEmpty($DmzScriptPath)) { $DmzScriptPath = "$PSScriptRoot\scripts\Start-Dmz.ps1" }

$scriptStart       = Get-Date
$orchestratorMode  = -not [string]::IsNullOrWhiteSpace($DmzHost)

# ── DMZ-Modus / Standalone ────────────────────────────────────────────────────
if (-not $orchestratorMode) {

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Dienst starten: $ServiceName"
    $startResult = Start-LobsterServiceLocally -Name $ServiceName
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($startResult.Message)"

    if ($startResult.AlreadyRunning) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Lese letzten Status aus Wrapper-Log ..."
        $checkResult = Get-WrapperLastStatus -LogPath $WrapperLogPath -Tail $TailLines
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Warte auf IS-Start (max. $MaxWaitSeconds s) ..."
        $checkResult = Wait-WrapperStarted `
            -LogPath          $WrapperLogPath `
            -MaxSeconds       $MaxWaitSeconds `
            -PollSeconds      $PollIntervalSeconds `
            -Tail             $TailLines `
            -Since            $scriptStart `
            -ToleranceMinutes $TimeTolerance
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($checkResult.Message)"

    if ($MailTo -and $SmtpServer) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Mail senden ..."
        Send-ResultMail `
            -To              $MailTo `
            -From            $MailFrom `
            -Smtp            $SmtpServer `
            -Success         $checkResult.Ok `
            -DmzMessage      'n/a (Backend-Only)' `
            -BackendMessage  $checkResult.Message `
            -BackendLogTail  $checkResult.LogTail
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Mail gesendet an: $MailTo"
    }

    # Nur Ergebnis-Objekt zurueckgeben – kein Log-Transfer zum rufenden Host
    return [PSCustomObject]@{
        Host    = $env:COMPUTERNAME
        Ok      = $checkResult.Ok
        Message = if ($checkResult.Ok) { $checkResult.Message } else { "FEHLER: $($checkResult.Message)" }
        LogTail = $checkResult.LogTail
    }
}

# ── Orchestrator-Modus (Backend-Host) ────────────────────────────────────────

Write-Host ""
Write-Host "=== [1/3] Backend-Dienst starten (lokal) ==="

$startResult   = Start-LobsterServiceLocally -Name $ServiceName
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($startResult.Message)"

if ($startResult.AlreadyRunning) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Lese letzten Status aus Wrapper-Log ..."
    $backendResult = Get-WrapperLastStatus -LogPath $WrapperLogPath -Tail $TailLines
} else {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Warte auf IS-Start (max. $MaxWaitSeconds s) ..."
    $backendResult = Wait-WrapperStarted `
        -LogPath          $WrapperLogPath `
        -MaxSeconds       $MaxWaitSeconds `
        -PollSeconds      $PollIntervalSeconds `
        -Tail             $TailLines `
        -Since            $scriptStart `
        -ToleranceMinutes $TimeTolerance
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Backend: $($backendResult.Message)"

if (-not $backendResult.Ok) {
    Write-Warning "Backend-Start fehlgeschlagen – DMZ-Dienst wird NICHT gestartet."

    if ($MailTo -and $SmtpServer) {
        Write-Host "=== [2/3] Mail senden (Fehler) ==="
        Send-ResultMail `
            -To              $MailTo `
            -From            $MailFrom `
            -Smtp            $SmtpServer `
            -Success         $false `
            -BackendMessage  $backendResult.Message `
            -DmzMessage      "Nicht ausgefuehrt (Backend fehlgeschlagen)." `
            -BackendLogTail  $backendResult.LogTail
    }

    exit 1
}

Write-Host ""
Write-Host "=== [2/3] DMZ-Host starten: $DmzHost ==="

$dmzResult = $null
try {
    $dmzResult = Invoke-Command `
        -ComputerName $DmzHost `
        -Credential   $DmzCredential `
        -ScriptBlock  {
            param($path, $svc, $log, $maxWait, $poll, $tail, $tol)
            & $path `
                -ServiceName          $svc `
                -WrapperLogPath       $log `
                -MaxWaitSeconds       $maxWait `
                -PollIntervalSeconds  $poll `
                -TailLines            $tail `
                -TimeTolerance        $tol
        } `
        -ArgumentList $DmzScriptPath, $DmzServiceName, $DmzWrapperLogPath, `
                      $MaxWaitSeconds, $PollIntervalSeconds, $TailLines, $TimeTolerance

} catch {
    $dmzResult = [PSCustomObject]@{
        Host    = $DmzHost
        Ok      = $false
        Message = "Verbindungsfehler zu DMZ-Host: $_"
    }
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] DMZ: $($dmzResult.Message)"

$overallSuccess = $backendResult.Ok -and $dmzResult.Ok

if ($MailTo -and $SmtpServer) {
    Write-Host ""
    Write-Host "=== [3/3] Mail senden ==="
    Send-ResultMail `
        -To              $MailTo `
        -From            $MailFrom `
        -Smtp            $SmtpServer `
        -Success         $overallSuccess `
        -BackendMessage  $backendResult.Message `
        -DmzMessage      $dmzResult.Message `
        -BackendLogTail  $backendResult.LogTail `
        -DmzLogTail      $(if ($dmzResult.LogTail) { $dmzResult.LogTail } else { @() })
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Mail gesendet an: $MailTo"
}

exit $(if ($overallSuccess) { 0 } else { 1 })
