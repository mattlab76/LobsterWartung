#Requires -Version 5.1
# Stop-BackendAndDmz-Webservice.ps1
# Lobster-Dienst auf DMZ-Host (Windows-Dienst) und Backend-Host via Lobster-Webservice stoppen.
# Laeuft auf dem Backend-Host.
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string]       $BackendWebserviceUrl,
    [Parameter(Mandatory=$true)] [string]       $BackendWrapperLogPath,
    [Parameter(Mandatory=$true)] [string]       $DmzHost,
    [Parameter(Mandatory=$true)] [pscredential] $DmzCredential,
    [Parameter(Mandatory=$true)] [string]       $DmzServiceName,
    [Parameter(Mandatory=$true)] [string]       $DmzWrapperLogPath,
    [string] $DmzScriptPath    = 'C:\LobsterMaintenance\scripts\Stop-Dmz.ps1',
    [string] $MailTo           = '',
    [string] $MailFrom         = 'noreply@firma.local',
    [string] $SmtpServer       = '',
    [int]    $MaxWaitSeconds   = 300,
    [int]    $PollIntervalSeconds = 15
)
& "$PSScriptRoot\..\Invoke-LobsterShutdown.ps1" `
    -WebserviceUrl        $BackendWebserviceUrl `
    -WrapperLogPath       $BackendWrapperLogPath `
    -DmzHost              $DmzHost `
    -DmzCredential        $DmzCredential `
    -DmzServiceName       $DmzServiceName `
    -DmzWrapperLogPath    $DmzWrapperLogPath `
    -DmzScriptPath        $DmzScriptPath `
    -MailTo               $MailTo `
    -MailFrom             $MailFrom `
    -SmtpServer           $SmtpServer `
    -MaxWaitSeconds       $MaxWaitSeconds `
    -PollIntervalSeconds  $PollIntervalSeconds
exit $LASTEXITCODE
