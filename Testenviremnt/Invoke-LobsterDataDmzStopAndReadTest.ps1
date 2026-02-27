[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$RemoteProjectPath,

    [Parameter(Mandatory=$true)]
    [string]$RemoteLogPath,

    [string]$RemoteServiceName = 'Lobster Integration Server',

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

$steps = @()

# 1) DMZ Dienst stoppen
$stopOk = $false
try {
    $svc = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
        param($RemoteServiceName)

        $service = Get-Service -Name $RemoteServiceName -ErrorAction Stop
        $before = $service.Status.ToString()

        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Stop-Service -Name $RemoteServiceName -Force -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
            $service = Get-Service -Name $RemoteServiceName -ErrorAction Stop
        }

        [PSCustomObject]@{
            HostName      = $env:COMPUTERNAME
            ServiceName   = $RemoteServiceName
            StatusBefore  = $before
            StatusAfter   = $service.Status.ToString()
        }
    } -ArgumentList $RemoteServiceName

    $stopOk = $true
    $steps += [PSCustomObject]@{
        Step     = 'DmzServiceStop'
        HostName = $svc.HostName
        Level    = 'OK'
        ExitCode = 0
        Message  = "Dienst '$($svc.ServiceName)' wurde gestoppt ($($svc.StatusBefore) -> $($svc.StatusAfter))."
        Details  = $svc
    }
} catch {
    $steps += [PSCustomObject]@{
        Step     = 'DmzServiceStop'
        HostName = $ComputerName
        Level    = 'ERROR'
        ExitCode = 2
        Message  = "Dienst-Stop auf DMZ fehlgeschlagen: $($_.Exception.Message)"
    }
}

# 2) Wrapper-Log auf DMZ auswerten
if ($stopOk) {
    try {
        $monitor = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            param($RemoteProjectPath, $RemoteLogPath)

            $monitorScript = Join-Path $RemoteProjectPath 'Invoke-LobsterDataWrapperLogCheck.ps1'
            if (-not (Test-Path -LiteralPath $monitorScript)) {
                throw "Invoke-LobsterDataWrapperLogCheck.ps1 nicht gefunden: $monitorScript"
            }

            $tmpCfg = Join-Path $env:TEMP ("lobsterdata-dmz-test-{0}.psd1" -f ([guid]::NewGuid().ToString('N')))
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

        $steps += [PSCustomObject]@{
            Step     = 'DmzWrapperLogCheck'
            HostName = $monitor.HostName
            Level    = $monitor.Level
            ExitCode = $monitor.ExitCode
            Message  = $monitor.Message
            Details  = $monitor
        }
    } catch {
        $steps += [PSCustomObject]@{
            Step     = 'DmzWrapperLogCheck'
            HostName = $ComputerName
            Level    = 'ERROR'
            ExitCode = 2
            Message  = "Wrapper-Logcheck auf DMZ fehlgeschlagen: $($_.Exception.Message)"
        }
    }
} else {
    $steps += [PSCustomObject]@{
        Step     = 'DmzWrapperLogCheck'
        HostName = $ComputerName
        Level    = 'WARN'
        ExitCode = 1
        Message  = 'Uebersprungen, weil der Dienst-Stop fehlgeschlagen ist.'
    }
}

$overallExitCode = 0
if ($steps | Where-Object { $_.Level -eq 'ERROR' }) {
    $overallExitCode = 2
} elseif ($steps | Where-Object { $_.Level -eq 'WARN' }) {
    $overallExitCode = 1
}

[PSCustomObject]@{
    Name            = 'LobsterData DMZ Stop and Log Read Test'
    RequestedHost   = $ComputerName
    OverallExitCode = $overallExitCode
    Steps           = $steps
}

exit $overallExitCode
