[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$RemoteProjectPath,

    [Parameter(Mandatory=$true)]
    [string]$RemoteLogPath,

    [switch]$SendNotification,

    [string]$NotifyMailTo = '',

    [string]$NotifySmtpServer = 'smtp.cust.bmlc.local',

    [string]$NotifyMailFrom = 'noreply@quehenberger.com',

    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'

# Feste Credentials (anpassen)
$FixedUserName = 'lobster'
$FixedPasswordPlain = 'ed2w$3nn'

if (-not $PSBoundParameters.ContainsKey('Credential')) {
    if ([string]::IsNullOrWhiteSpace($FixedUserName) -or [string]::IsNullOrWhiteSpace($FixedPasswordPlain)) {
        throw 'Kein -Credential uebergeben und feste Credentials sind nicht konfiguriert.'
    }

    $sec = ConvertTo-SecureString -String $FixedPasswordPlain -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($FixedUserName, $sec)
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$notifyEnabled = $SendNotification.IsPresent
if ($notifyEnabled -and [string]::IsNullOrWhiteSpace($NotifyMailTo)) {
    throw '-NotifyMailTo ist erforderlich, wenn -SendNotification gesetzt ist.'
}

$results = @()
$notificationResult = $null

try {
    $remoteMonitorResult = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
        param($RemoteProjectPath, $RemoteLogPath)

        $monitorScript = Join-Path $RemoteProjectPath 'Invoke-LobsterDataWrapperLogCheck.ps1'
        if (-not (Test-Path -LiteralPath $monitorScript)) {
            throw "Invoke-LobsterDataWrapperLogCheck.ps1 nicht gefunden: $monitorScript"
        }

        $tmpCfg = Join-Path $env:TEMP ("lobsterdata-dmz-logonly-{0}.psd1" -f ([guid]::NewGuid().ToString('N')))
        $escapedPath = $RemoteLogPath.Replace("'", "''")
        $cfg = @"
@{
  LogPath = '$escapedPath'
  IsTest = `$false
  TimeToleranceMinutes = 5
  WarnTailLines = 200
  ErrorTailLines = 200
  MaxAttempts = 11
  AttemptSleepSeconds_Test = 1
  AttemptSleepSeconds_Prod = 30
  RecheckSleepSeconds_Test = 1
  RecheckSleepSeconds_Prod = 10
}
"@

        Set-Content -LiteralPath $tmpCfg -Value $cfg -Encoding UTF8
        try {
            & $monitorScript -ConfigPath $tmpCfg -NoExit
        } finally {
            Remove-Item -LiteralPath $tmpCfg -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList $RemoteProjectPath, $RemoteLogPath

    $remoteMonitorResult | Add-Member -NotePropertyName Step -NotePropertyValue 'DmzWrapperLogCheck' -Force
    $results += $remoteMonitorResult
} catch {
    $results += [PSCustomObject]@{
        Step     = 'DmzWrapperLogCheck'
        HostName = $ComputerName
        Level    = 'ERROR'
        ExitCode = 2
        Message  = "Wrapper-Logcheck auf DMZ fehlgeschlagen: $($_.Exception.Message)"
        LogLines = @()
    }
}

if ($notifyEnabled) {
    try {
        $notificationResult = & (Join-Path $projectRoot 'Send-LobsterDataMaintenanceNotification.ps1') `
            -Results $results `
            -To $NotifyMailTo `
            -SmtpServer $NotifySmtpServer `
            -From $NotifyMailFrom `
            -Subject ("LobsterData DMZ Log-Only Test - {0}" -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'))
    } catch {
        $results += [PSCustomObject]@{
            Step     = 'Notification'
            HostName = $env:COMPUTERNAME
            Level    = 'ERROR'
            ExitCode = 2
            Message  = "Mailversand fehlgeschlagen: $($_.Exception.Message)"
            LogLines = @()
        }
    }
}

$overallExitCode = 0
if ($results | Where-Object { $_.Level -eq 'ERROR' }) {
    $overallExitCode = 2
} elseif ($results | Where-Object { $_.Level -eq 'WARN' }) {
    $overallExitCode = 1
}

[PSCustomObject]@{
    Name             = 'LobsterData DMZ Log-Only Test'
    RequestedHost    = $ComputerName
    OverallExitCode  = $overallExitCode
    NotificationSent = [bool]($notificationResult)
    Results          = $results
}

exit $overallExitCode
