$target = Join-Path $PSScriptRoot 'scripts/core/Send-LobsterDataMaintenanceNotification.ps1'
& $target @args
exit $LASTEXITCODE
