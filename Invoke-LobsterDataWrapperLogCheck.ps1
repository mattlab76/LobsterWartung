$target = Join-Path $PSScriptRoot 'scripts/core/Invoke-LobsterDataWrapperLogCheck.ps1'
& $target @args
exit $LASTEXITCODE
