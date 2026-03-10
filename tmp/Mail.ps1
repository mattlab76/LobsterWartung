$target = Join-Path $PSScriptRoot 'scripts/core/Mail.ps1'
& $target @args
exit $LASTEXITCODE
