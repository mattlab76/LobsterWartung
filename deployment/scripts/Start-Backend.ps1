#Requires -Version 5.1
# Start-Backend.ps1
# Nur den lokalen Backend-Dienst starten (Windows-Dienst). Kein DMZ.
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string] $ServiceName,
    [Parameter(Mandatory=$true)] [string] $WrapperLogPath,
    [string] $MailTo              = '',
    [string] $MailFrom            = 'noreply@firma.local',
    [string] $SmtpServer          = '',
    [int]    $MaxWaitSeconds      = 300,
    [int]    $PollIntervalSeconds = 15
)
& "$PSScriptRoot\..\Start-LobsterService.ps1" `
    -ServiceName          $ServiceName `
    -WrapperLogPath       $WrapperLogPath `
    -MailTo               $MailTo `
    -MailFrom             $MailFrom `
    -SmtpServer           $SmtpServer `
    -MaxWaitSeconds       $MaxWaitSeconds `
    -PollIntervalSeconds  $PollIntervalSeconds
exit $LASTEXITCODE
