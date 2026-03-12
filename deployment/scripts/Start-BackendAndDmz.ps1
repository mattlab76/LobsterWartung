#Requires -Version 5.1
# Start-BackendAndDmz.ps1
# Backend-Dienst und DMZ-Dienst starten.
# Startreihenfolge: zuerst Backend, dann DMZ.
# TODO: Invoke-LobsterStartup.ps1 implementieren (analog zu Invoke-LobsterShutdown.ps1)
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string]       $BackendServiceName,
    [Parameter(Mandatory=$true)] [string]       $BackendWrapperLogPath,
    [Parameter(Mandatory=$true)] [string]       $DmzHost,
    [Parameter(Mandatory=$true)] [pscredential] $DmzCredential,
    [Parameter(Mandatory=$true)] [string]       $DmzServiceName,
    [Parameter(Mandatory=$true)] [string]       $DmzWrapperLogPath,
    [string] $MailTo              = '',
    [string] $MailFrom            = 'noreply@firma.local',
    [string] $SmtpServer          = '',
    [int]    $MaxWaitSeconds      = 300,
    [int]    $PollIntervalSeconds = 15
)
throw 'Start-BackendAndDmz.ps1 ist noch nicht implementiert. Invoke-LobsterStartup.ps1 fehlt.'
