#Requires -Version 5.1
<#
.SYNOPSIS
    Lobster-Dienst herunterfahren und Java-Wrapper-Stop verifizieren.

.DESCRIPTION
    Wird auf dem jeweiligen Host lokal ausgefuehrt.

    OHNE -DmzHost (DMZ-Modus / Standalone):
        - Stoppt den lokalen Lobster-Dienst
        - Prueft das Wrapper-Log bis "Wrapper Stopped" bestaetigt ist
        - Gibt ein Ergebnis-Objekt zurueck (fuer Invoke-Command auf Backend-Host)

    MIT -DmzHost (Backend-Modus / Orchestrator):
        - Startet zuerst den Shutdown auf dem DMZ-Host via Invoke-Command
        - Wartet auf das Ergebnis (nur kleines Ergebnis-Objekt, kein Log-Transfer)
        - Nur wenn DMZ OK: stoppt den lokalen Backend-Dienst und prueft Wrapper-Log
        - Sendet Ergebnis-Mail (OK oder Fehler)

.NOTES
    Deployment:
        Backend-Host: z.B. C:\LobsterMaintenance\Stop-LobsterService.ps1
        DMZ-Host:     z.B. C:\LobsterMaintenance\Stop-LobsterService.ps1

    Der Scheduled Task wird vom Lobster Scheduler Manager angelegt und
    ruft dieses Skript auf dem Backend-Host mit allen Parametern auf.

.EXAMPLE
    # Standalone / DMZ-Modus (direkt auf einem Host ausfuehren):
    .\Stop-LobsterService.ps1 `
        -ServiceName    "Lobster Integration Server" `
        -WrapperLogPath "D:\Lobster\IS\logs\wrapper.log"

.EXAMPLE
    # Backend-Modus (Orchestrator) – startet DMZ-Shutdown, dann lokal, dann Mail:
    .\Stop-LobsterService.ps1 `
        -ServiceName       "Lobster Integration Server" `
        -WrapperLogPath    "D:\Lobster\IS\logs\wrapper.log" `
        -DmzHost           "dmz-server01" `
        -DmzCredential     (Get-Credential) `
        -DmzServiceName    "Lobster Integration Server" `
        -DmzWrapperLogPath "D:\Lobster\IS\logs\wrapper.log" `
        -DmzScriptPath     "C:\LobsterMaintenance\Stop-LobsterService.ps1" `
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
    # Wenn gesetzt, wird zuerst der DMZ-Host heruntergefahren.
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
    # Maximale Wartezeit bis "Wrapper Stopped" im Log erscheint
    [int]$MaxWaitSeconds      = 300,

    # Intervall zwischen Log-Pruefungen
    [int]$PollIntervalSeconds = 15,

    # Anzahl der Zeilen die vom Log-Ende gelesen werden
    [int]$TailLines           = 50,

    # Zeitfenster in dem der Wrapper-Stopp-Timestamp liegen muss (+/- Minuten)
    [int]$TimeTolerance       = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────

function Stop-LobsterServiceLocally {
    param([string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction Stop

    if ($svc.Status -eq 'Stopped') {
        return [PSCustomObject]@{ Ok=$true; Message="Dienst war bereits gestoppt: $Name" }
    }

    Stop-Service -Name $Name -Force -ErrorAction Stop
    Set-Service  -Name $Name -StartupType Manual -ErrorAction Stop

    return [PSCustomObject]@{ Ok=$true; Message="Dienst gestoppt: $Name" }
}

function Wait-WrapperStopped {
    param(
        [string]  $LogPath,
        [int]     $MaxSeconds,
        [int]     $PollSeconds,
        [int]     $Tail,
        [datetime]$Since,
        [int]     $ToleranceMinutes
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return [PSCustomObject]@{ Ok=$false; Message="Wrapper-Log nicht gefunden: $LogPath" }
    }

    $todayPart = $Since.ToString('yyyy') + '[/.]' + $Since.ToString('MM') + '[/.]' + $Since.ToString('dd')
    $deadline  = $Since.AddSeconds($MaxSeconds)

    $stoppedRx = [regex]::new(
        "^\s*STATUS\s*\|\s*wrapper\s*\|\s*${todayPart}\s+\d{2}:\d{2}:\d{2}\s*\|\s*<--\s*Wrapper\s+Stopped\s*$",
        'IgnoreCase')

    $startedRx = [regex]::new(
        "^\s*STATUS\s*\|\s*wrapper\s*\|\s*${todayPart}\s+\d{2}:\d{2}:\d{2}\s*\|\s*-->\s*Wrapper\s+Started\b",
        'IgnoreCase')

    $tsRx = [regex]::new(
        "^\s*STATUS\s*\|\s*wrapper\s*\|\s*(\d{4})[/.](\d{2})[/.](\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s*\|",
        'IgnoreCase')

    do {
        $lines = @(Get-Content -LiteralPath $LogPath -Tail $Tail -ErrorAction Stop)

        # Letzten "Wrapper Stopped" und "Wrapper Started" Index suchen
        $lastStopIdx  = -1
        $lastStartIdx = -1
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lastStopIdx  -lt 0 -and $stoppedRx.IsMatch($lines[$i])) { $lastStopIdx  = $i }
            if ($lastStartIdx -lt 0 -and $startedRx.IsMatch($lines[$i])) { $lastStartIdx = $i }
            if ($lastStopIdx -ge 0 -and $lastStartIdx -ge 0) { break }
        }

        # Fehler: Wrapper wurde nach Stopp sofort wieder gestartet
        if ($lastStopIdx -ge 0 -and $lastStartIdx -gt $lastStopIdx) {
            return [PSCustomObject]@{
                Ok      = $false
                Message = "Wrapper nach Stopp sofort wieder gestartet – Dienst laeuft wieder."
            }
        }

        if ($lastStopIdx -ge 0) {
            $m = $tsRx.Match($lines[$lastStopIdx])
            if ($m.Success) {
                $ts = [datetime]::new(
                    [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value,
                    [int]$m.Groups[4].Value, [int]$m.Groups[5].Value, [int]$m.Groups[6].Value)

                $deltaMin = [Math]::Abs(($ts - $Since).TotalMinutes)

                # Timestamp im Toleranzfenster und letzter Log-Eintrag?
                if ($deltaMin -le $ToleranceMinutes -and $lastStopIdx -eq ($lines.Count - 1)) {
                    return [PSCustomObject]@{
                        Ok      = $true
                        Message = "Wrapper erfolgreich gestoppt um $($ts.ToString('HH:mm:ss'))."
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
        Message = "Timeout: Wrapper-Stop nach $MaxSeconds Sekunden nicht bestaetigt."
    }
}

function Send-ResultMail {
    param(
        [string]$To,
        [string]$From,
        [string]$Smtp,
        [bool]  $Success,
        [string]$DmzMessage,
        [string]$BackendMessage
    )

    $status = if ($Success) { 'OK' } else { 'FEHLER' }
    $color  = if ($Success) { '#2e7d32' } else { '#c62828' }
    $icon   = if ($Success) { '&#10003;' } else { '&#10007;' }

    $subject = "Lobster Wartung – $status – $(Get-Date -Format 'dd.MM.yyyy HH:mm')"

    $enc = [System.Net.WebUtility]
    $body = @"
<html>
<body style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#333;">
  <h2 style="color:$color;">$icon Lobster Wartung – $status</h2>
  <table border="1" cellpadding="8" cellspacing="0"
         style="border-collapse:collapse;min-width:500px;">
    <tr style="background:#f0f0f0;">
      <th style="text-align:left;">Host</th>
      <th style="text-align:left;">Ergebnis</th>
    </tr>
    <tr>
      <td>DMZ-Host</td>
      <td>$($enc::HtmlEncode($DmzMessage))</td>
    </tr>
    <tr>
      <td>Backend-Host</td>
      <td>$($enc::HtmlEncode($BackendMessage))</td>
    </tr>
  </table>
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

if ([string]::IsNullOrEmpty($DmzScriptPath)) { $DmzScriptPath = "$PSScriptRoot\scripts\Stop-Dmz.ps1" }

$scriptStart       = Get-Date
$orchestratorMode  = -not [string]::IsNullOrWhiteSpace($DmzHost)

# ── DMZ-Modus / Standalone ────────────────────────────────────────────────────
if (-not $orchestratorMode) {

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Dienst stoppen: $ServiceName"
    $stopResult = Stop-LobsterServiceLocally -Name $ServiceName
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($stopResult.Message)"

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Warte auf Wrapper-Stop (max. $MaxWaitSeconds s) ..."
    $checkResult = Wait-WrapperStopped `
        -LogPath          $WrapperLogPath `
        -MaxSeconds       $MaxWaitSeconds `
        -PollSeconds      $PollIntervalSeconds `
        -Tail             $TailLines `
        -Since            $scriptStart `
        -ToleranceMinutes $TimeTolerance

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($checkResult.Message)"

    # Nur Ergebnis-Objekt zurueckgeben – kein Log-Transfer zum rufenden Host
    return [PSCustomObject]@{
        Host    = $env:COMPUTERNAME
        Ok      = $checkResult.Ok
        Message = if ($checkResult.Ok) { $checkResult.Message } else { "FEHLER: $($checkResult.Message)" }
    }
}

# ── Orchestrator-Modus (Backend-Host) ────────────────────────────────────────

Write-Host ""
Write-Host "=== [1/3] DMZ-Host herunterfahren: $DmzHost ==="

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

if (-not $dmzResult.Ok) {
    Write-Warning "DMZ-Shutdown fehlgeschlagen – Backend-Dienst wird NICHT gestoppt."

    if ($MailTo -and $SmtpServer) {
        Write-Host "=== [2/3] Mail senden (Fehler) ==="
        Send-ResultMail `
            -To             $MailTo `
            -From           $MailFrom `
            -Smtp           $SmtpServer `
            -Success        $false `
            -DmzMessage     $dmzResult.Message `
            -BackendMessage "Nicht ausgefuehrt (DMZ fehlgeschlagen)."
    }

    exit 1
}

Write-Host ""
Write-Host "=== [2/3] Backend-Dienst herunterfahren (lokal) ==="

$stopResult   = Stop-LobsterServiceLocally -Name $ServiceName
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($stopResult.Message)"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Warte auf Wrapper-Stop (max. $MaxWaitSeconds s) ..."
$backendResult = Wait-WrapperStopped `
    -LogPath          $WrapperLogPath `
    -MaxSeconds       $MaxWaitSeconds `
    -PollSeconds      $PollIntervalSeconds `
    -Tail             $TailLines `
    -Since            $scriptStart `
    -ToleranceMinutes $TimeTolerance

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Backend: $($backendResult.Message)"

if ($MailTo -and $SmtpServer) {
    Write-Host ""
    Write-Host "=== [3/3] Mail senden ==="
    Send-ResultMail `
        -To             $MailTo `
        -From           $MailFrom `
        -Smtp           $SmtpServer `
        -Success        $backendResult.Ok `
        -DmzMessage     $dmzResult.Message `
        -BackendMessage $backendResult.Message
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Mail gesendet an: $MailTo"
}

exit $(if ($backendResult.Ok) { 0 } else { 1 })
