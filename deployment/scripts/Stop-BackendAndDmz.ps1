#Requires -Version 5.1
# Stop-BackendAndDmz.ps1
# Lobster-Dienst auf DMZ-Host und Backend-Host stoppen (Windows-Dienst).
# Laeuft auf dem Backend-Host. Stoppt zuerst den DMZ-Dienst, dann den lokalen Backend-Dienst.
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string]       $BackendServiceName,
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
    -ServiceName          $BackendServiceName `
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
