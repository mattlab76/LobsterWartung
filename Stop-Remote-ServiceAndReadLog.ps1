$target = Join-Path $PSScriptRoot 'scripts/core/Stop-Remote-ServiceAndReadLog.ps1'
& $target @args
exit $LASTEXITCODE
