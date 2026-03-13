#Requires -Version 5.1
# Start-BackendAndDmz.ps1
# Backend-Dienst und DMZ-Dienst starten.
# Startreihenfolge: zuerst Backend, dann DMZ.
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
& "$PSScriptRoot\..\Start-LobsterService.ps1" `
    -ServiceName          $BackendServiceName `
    -WrapperLogPath       $BackendWrapperLogPath `
    -DmzHost              $DmzHost `
    -DmzCredential        $DmzCredential `
    -DmzServiceName       $DmzServiceName `
    -DmzWrapperLogPath    $DmzWrapperLogPath `
    -MailTo               $MailTo `
    -MailFrom             $MailFrom `
    -SmtpServer           $SmtpServer `
    -MaxWaitSeconds       $MaxWaitSeconds `
    -PollIntervalSeconds  $PollIntervalSeconds
exit $LASTEXITCODE
