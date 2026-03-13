#Requires -Version 5.1
# Start-Dmz.ps1
# Nur den lokalen DMZ-Dienst starten.
# Laeuft direkt auf dem DMZ-Host (via Invoke-Command vom Backend-Host aufgerufen).
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)] [string] $ServiceName,
    [Parameter(Mandatory=$true)] [string] $WrapperLogPath,
    [int] $MaxWaitSeconds      = 300,
    [int] $PollIntervalSeconds = 15
)
& "$PSScriptRoot\..\Start-LobsterService.ps1" `
    -ServiceName          $ServiceName `
    -WrapperLogPath       $WrapperLogPath `
    -MaxWaitSeconds       $MaxWaitSeconds `
    -PollIntervalSeconds  $PollIntervalSeconds
exit $LASTEXITCODE
