[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$TaskName,

    [string]$TaskPath = '\AQG\',

    [switch]$IgnoreMissing,

    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'

# Feste Credentials (anpassen)
$FixedUserName = 'DOMAIN\anderer.user'
$FixedPasswordPlain = 'BITTE_PASSWORT_EINTRAGEN'

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
        param($TaskName, $TaskPath, $IgnoreMissing)

        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if (-not $task) {
            if ($IgnoreMissing) {
                return [PSCustomObject]@{
                    HostName = $env:COMPUTERNAME
                    TaskName = $TaskName
                    TaskPath = $TaskPath
                    Removed  = $false
                    Message  = 'Task nicht gefunden (ignoriert).'
                }
            }
            throw "Task nicht gefunden: $TaskPath$TaskName"
        }

        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false

        [PSCustomObject]@{
            HostName = $env:COMPUTERNAME
            TaskName = $TaskName
            TaskPath = $TaskPath
            Removed  = $true
            Message  = 'Task erfolgreich geloescht.'
        }
    }
    ArgumentList = @($TaskName, $TaskPath, [bool]$IgnoreMissing)
}

$result = Invoke-Command @invokeParams

[PSCustomObject]@{
    RequestedHost = $ComputerName
    ExecutedOn    = $result.HostName
    TaskName      = $result.TaskName
    TaskPath      = $result.TaskPath
    Removed       = $result.Removed
    Message       = $result.Message
}
