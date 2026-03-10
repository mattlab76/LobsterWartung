#Requires -Version 5.1
# Stop-Backend-Webservice.ps1
# Backend-Dienst via Lobster-Webservice stoppen. Kein DMZ.
# Hinweis: WebserviceUrl-Parameter wird in Invoke-LobsterShutdown.ps1 noch implementiert.
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string] $WebserviceUrl,
    [Parameter(Mandatory=$true)] [string] $WrapperLogPath,
    [string] $MailTo              = '',
    [string] $MailFrom            = 'noreply@firma.local',
    [string] $SmtpServer          = '',
    [int]    $MaxWaitSeconds      = 300,
    [int]    $PollIntervalSeconds = 15
)
& "$PSScriptRoot\..\Invoke-LobsterShutdown.ps1" `
    -WebserviceUrl        $WebserviceUrl `
    -WrapperLogPath       $WrapperLogPath `
    -MailTo               $MailTo `
    -MailFrom             $MailFrom `
    -SmtpServer           $SmtpServer `
    -MaxWaitSeconds       $MaxWaitSeconds `
    -PollIntervalSeconds  $PollIntervalSeconds
exit $LASTEXITCODE
