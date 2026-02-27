[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$RemoteScriptPath,

    [Parameter(Mandatory=$true)]
    [datetime]$StartTime,

    [string]$TaskName = ("WrapperMonitor_Test_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')),

    [string]$TaskPath = '\AQG\',

    [string]$TaskScriptArguments = '-All',

    [string]$TaskDescription = 'Wrapper-Monitor Testlauf (remote erstellt)',

    [Parameter(Mandatory=$true)]
    [string]$NotifyMailTo,

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
        throw "Kein -Credential uebergeben und feste Credentials sind nicht konfiguriert."
    }

    $sec = ConvertTo-SecureString -String $FixedPasswordPlain -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($FixedUserName, $sec)
}

$invokeParams = @{
    ComputerName = $ComputerName
    Credential   = $Credential
    ErrorAction  = 'Stop'
    ScriptBlock  = {
        param($RemoteScriptPath, $StartTime, $TaskName, $TaskPath, $TaskScriptArguments, $TaskDescription)

        if (-not (Test-Path -LiteralPath $RemoteScriptPath)) {
            throw "Script auf Remote-Host nicht gefunden: $RemoteScriptPath"
        }

        $escapedPath = $RemoteScriptPath.Replace('"', '""')
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$escapedPath`" $TaskScriptArguments"

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
        $trigger = New-ScheduledTaskTrigger -Once -At $StartTime
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Description $TaskDescription -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

        $info = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath | Get-ScheduledTaskInfo

        [PSCustomObject]@{
            HostName        = $env:COMPUTERNAME
            TaskName        = $TaskName
            TaskPath        = $TaskPath
            ScriptPath      = $RemoteScriptPath
            ScriptArguments = $TaskScriptArguments
            StartTime       = $StartTime
            NextRunTime     = $info.NextRunTime
            LastTaskResult  = $info.LastTaskResult
            CreatedAt       = Get-Date
        }
    }
    ArgumentList = @($RemoteScriptPath, $StartTime, $TaskName, $TaskPath, $TaskScriptArguments, $TaskDescription)
}

$result = Invoke-Command @invokeParams

$mailSubject = "Scheduled Task gesetzt auf $($result.HostName): $($result.TaskPath)$($result.TaskName)"
$mailBody = @"
Task wurde erfolgreich erstellt.

Host: $($result.HostName)
TaskPath: $($result.TaskPath)
TaskName: $($result.TaskName)
Script: $($result.ScriptPath)
Argumente: $($result.ScriptArguments)
Startzeit: $($result.StartTime)
Naechster Lauf: $($result.NextRunTime)
Erstellt am: $($result.CreatedAt)
"@

$mailSent = $false
try {
    Send-MailMessage -From $NotifyMailFrom -To $NotifyMailTo -Subject $mailSubject -Body $mailBody -SmtpServer $NotifySmtpServer -ErrorAction Stop
    $mailSent = $true
} catch {
    Write-Warning ("Mailversand fehlgeschlagen: {0}" -f $_.Exception.Message)
}

[PSCustomObject]@{
    RequestedHost = $ComputerName
    ExecutedOn    = $result.HostName
    TaskName      = $result.TaskName
    TaskPath      = $result.TaskPath
    ScriptPath    = $result.ScriptPath
    StartTime     = $result.StartTime
    NextRunTime   = $result.NextRunTime
    MailSent      = $mailSent
    NotifyTo      = $NotifyMailTo
}
