$target = Join-Path $PSScriptRoot 'scripts/core/Invoke-LobsterDataMaintenanceRunner.ps1'
& $target @args
exit $LASTEXITCODE
