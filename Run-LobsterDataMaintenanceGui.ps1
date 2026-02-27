$target = Join-Path $PSScriptRoot 'scripts/ui/Run-LobsterDataMaintenanceGui.ps1'
& $target @args
exit $LASTEXITCODE
