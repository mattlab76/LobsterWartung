<#
.SYNOPSIS
  Console-GUI launcher for Invoke-LobsterDataMaintenance.ps1.
.DESCRIPTION
  This wrapper only collects the "base" parameters and then starts
  Invoke-LobsterDataMaintenance.ps1 in interactive mode (-Interactive),
  so the user can choose StopMode/ServiceScope via the console menus.
#>

[CmdletBinding()]
param(
  # Remote target (only used when remote actions/log read are selected)
  [Parameter(Mandatory=$true)]
  [string]$ComputerName,

  # Path on the remote host where the maintenance-scripts folder lives
  # (required for remote execution / remote log read)
  [Parameter(Mandatory=$true)]
  [string]$RemoteProjectPath,

  # Full path to wrapper.log on the remote host
  [Parameter(Mandatory=$true)]
  [string]$RemoteLogPath,

  # Optional: send notification mail
  [switch]$SendNotification,

  # Mail recipient (required when -SendNotification is set)
  [string]$NotifyMailTo
)

if ($SendNotification -and [string]::IsNullOrWhiteSpace($NotifyMailTo)) {
  throw "Wenn -SendNotification gesetzt ist, muss -NotifyMailTo angegeben werden."
}

$scriptPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "core/Invoke-LobsterDataMaintenance.ps1"
if (-not (Test-Path $scriptPath)) {
  throw "Invoke-LobsterDataMaintenance.ps1 wurde nicht gefunden im core-Ordner: $scriptPath"
}

# Build argument list
$argsList = @(
  "-ComputerName", $ComputerName,
  "-RemoteProjectPath", $RemoteProjectPath,
  "-RemoteLogPath", $RemoteLogPath,
  "-Interactive"
)

if ($SendNotification) {
  $argsList += "-SendNotification"
  $argsList += @("-NotifyMailTo", $NotifyMailTo)
}

# Hand off to the main script
& $scriptPath @argsList
exit $LASTEXITCODE
