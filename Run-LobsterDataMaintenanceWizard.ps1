$target = Join-Path $PSScriptRoot 'scripts/ui/Run-LobsterDataMaintenanceWizard.ps1'
& $target @args
exit $LASTEXITCODE
