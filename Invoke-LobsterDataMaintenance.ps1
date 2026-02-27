$target = Join-Path $PSScriptRoot 'scripts/core/Invoke-LobsterDataMaintenance.ps1'
& $target @args
exit $LASTEXITCODE
