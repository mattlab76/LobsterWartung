[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$true)]
    [string]$RemoteLogPath,

    [int]$TailLines = 200,

    [int]$WaitSeconds = 30,

    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'

# Feste Credentials (anpassen)
$FixedUserName = 'lobster'
$FixedPasswordPlain = 'ed2w$3nn'

if ($TailLines -lt 1) {
    throw '-TailLines muss >= 1 sein.'
}

if ($WaitSeconds -lt 1) {
    throw '-WaitSeconds muss >= 1 sein.'
}

if (-not $PSBoundParameters.ContainsKey('Credential')) {
    if ([string]::IsNullOrWhiteSpace($FixedUserName) -or [string]::IsNullOrWhiteSpace($FixedPasswordPlain)) {
        throw 'Kein -Credential uebergeben und feste Credentials sind nicht konfiguriert.'
    }

    $sec = ConvertTo-SecureString -String $FixedPasswordPlain -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($FixedUserName, $sec)
}

$invokeParams = @{
    ComputerName = $ComputerName
    Credential   = $Credential
    ErrorAction  = 'Stop'
    ScriptBlock  = {
        param($ServiceName, $RemoteLogPath, $TailLines, $WaitSeconds)

        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        $statusBefore = $svc.Status.ToString()
        $stopAttempted = $false

        if ($svc.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $stopAttempted = $true

            $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($WaitSeconds))
            $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        }

        if (-not (Test-Path -LiteralPath $RemoteLogPath)) {
            throw "Log-Datei auf Remote-Host nicht gefunden: $RemoteLogPath"
        }

        $lines = @(Get-Content -LiteralPath $RemoteLogPath -Tail $TailLines -ErrorAction Stop)

        [PSCustomObject]@{
            HostName      = $env:COMPUTERNAME
            ServiceName   = $ServiceName
            StatusBefore  = $statusBefore
            StatusAfter   = $svc.Status.ToString()
            StopAttempted = $stopAttempted
            LogPath       = $RemoteLogPath
            LogLineCount  = $lines.Count
            LogLines      = $lines
            Timestamp     = Get-Date
        }
    }
    ArgumentList = @($ServiceName, $RemoteLogPath, $TailLines, $WaitSeconds)
}

$result = Invoke-Command @invokeParams

[PSCustomObject]@{
    RequestedHost = $ComputerName
    ExecutedOn    = $result.HostName
    ServiceName   = $result.ServiceName
    StatusBefore  = $result.StatusBefore
    StatusAfter   = $result.StatusAfter
    StopAttempted = $result.StopAttempted
    LogPath       = $result.LogPath
    LogLineCount  = $result.LogLineCount
    LogLines      = $result.LogLines
    Timestamp     = $result.Timestamp
}
