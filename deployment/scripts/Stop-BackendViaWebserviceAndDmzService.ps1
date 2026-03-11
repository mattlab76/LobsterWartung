#Requires -Version 5.1
# Stop-BackendViaWebserviceAndDmzService.ps1
# Backend-Dienst via Lobster-Webservice stoppen + DMZ-Dienst via Windows-Dienst stoppen.
# Laeuft auf dem Backend-Host. Hinweis: DMZ kann nicht via Webservice gestoppt werden.
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string]       $BackendWebserviceUrl,
    [Parameter(Mandatory=$true)] [string]       $BackendWrapperLogPath,
    [Parameter(Mandatory=$true)] [string]       $DmzHost,
    [Parameter(Mandatory=$true)] [pscredential] $DmzCredential,
    [Parameter(Mandatory=$true)] [string]       $DmzServiceName,
    [Parameter(Mandatory=$true)] [string]       $DmzWrapperLogPath,
    [string] $DmzScriptPath    = '',
    [string] $MailTo           = '',
    [string] $MailFrom         = 'noreply@firma.local',
    [string] $SmtpServer       = '',
    [int]    $MaxWaitSeconds   = 300,
    [int]    $PollIntervalSeconds = 15
)
if ([string]::IsNullOrEmpty($DmzScriptPath)) { $DmzScriptPath = "$PSScriptRoot\Stop-Dmz.ps1" }

& "$PSScriptRoot\..\Stop-LobsterService.ps1" `
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
