#Requires -Version 5.1
# Stop-Backend.ps1
# Nur den lokalen Backend-Dienst stoppen (Windows-Dienst). Kein DMZ.
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string] $ServiceName,
    [Parameter(Mandatory=$true)] [string] $WrapperLogPath,
    [string] $MailTo              = '',
    [string] $MailFrom            = 'noreply@firma.local',
    [string] $SmtpServer          = '',
    [int]    $MaxWaitSeconds      = 300,
    [int]    $PollIntervalSeconds = 15
)
& "$PSScriptRoot\..\Invoke-LobsterShutdown.ps1" `
    -ServiceName          $ServiceName `
    -WrapperLogPath       $WrapperLogPath `
    -MailTo               $MailTo `
    -MailFrom             $MailFrom `
    -SmtpServer           $SmtpServer `
    -MaxWaitSeconds       $MaxWaitSeconds `
    -PollIntervalSeconds  $PollIntervalSeconds
exit $LASTEXITCODE
