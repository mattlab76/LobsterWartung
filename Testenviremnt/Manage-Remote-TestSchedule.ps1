[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$setScript = Join-Path $root 'Set-Remote-TestSchedule.ps1'
$removeScript = Join-Path $root 'Remove-Remote-TestSchedule.ps1'

if (-not (Test-Path -LiteralPath $setScript)) {
    throw "Nicht gefunden: $setScript"
}
if (-not (Test-Path -LiteralPath $removeScript)) {
    throw "Nicht gefunden: $removeScript"
}

Write-Host ""
Write-Host "Remote Scheduler Menu" -ForegroundColor Cyan
Write-Host "1) Task anlegen"
Write-Host "2) Task loeschen"
Write-Host ""

$choice = Read-Host "Auswahl (1/2)"
if ($choice -ne '1' -and $choice -ne '2') {
    throw "Ungueltige Auswahl. Bitte 1 oder 2 eingeben."
}

$computer = Read-Host "Remote Host (z.B. aqlbt101.bmlc.local)"
$user = Read-Host "User (DOMAIN\\user)"
if ([string]::IsNullOrWhiteSpace($user)) {
    throw "User darf nicht leer sein."
}

$password = Read-Host "Passwort fuer Remote-Host" -AsSecureString
if ($null -eq $password -or $password.Length -eq 0) {
    throw "Passwort wurde nicht eingegeben."
}

$cred = New-Object System.Management.Automation.PSCredential($user, $password)

if ($choice -eq '1') {
    $remoteScript = Read-Host "Remote Script-Pfad (z.B. C:\New folder\wrapper-monitor-4-files\Run-TestCase.ps1)"
    $startRaw = Read-Host "Startzeit (Format: yyyy-MM-dd HH:mm:ss)"
    $taskName = Read-Host "TaskName"
    $taskPath = Read-Host "TaskPath [Enter fuer \\AQG\\]"
    if ([string]::IsNullOrWhiteSpace($taskPath)) { $taskPath = '\AQG\' }

    $args = Read-Host "Script-Argumente [Enter fuer -All]"
    if ([string]::IsNullOrWhiteSpace($args)) { $args = '-All' }

    $mailTo = Read-Host "Mail an"

    try {
        $startTime = [datetime]::ParseExact($startRaw, 'yyyy-MM-dd HH:mm:ss', $null)
    } catch {
        throw "Startzeit ungueltig. Bitte genau 'yyyy-MM-dd HH:mm:ss' verwenden."
    }

    & $setScript `
        -ComputerName $computer `
        -RemoteScriptPath $remoteScript `
        -StartTime $startTime `
        -TaskName $taskName `
        -TaskPath $taskPath `
        -TaskScriptArguments $args `
        -NotifyMailTo $mailTo `
        -Credential $cred
}
else {
    $taskName = Read-Host "TaskName"
    $taskPath = Read-Host "TaskPath [Enter fuer \\AQG\\]"
    if ([string]::IsNullOrWhiteSpace($taskPath)) { $taskPath = '\AQG\' }

    $ignoreMissingRaw = Read-Host "Wenn Task fehlt ignorieren? (j/n, Enter=n)"
    $ignoreMissing = $false
    if ($ignoreMissingRaw -match '^(j|J|y|Y)$') { $ignoreMissing = $true }

    if ($ignoreMissing) {
        & $removeScript -ComputerName $computer -TaskName $taskName -TaskPath $taskPath -IgnoreMissing -Credential $cred
    } else {
        & $removeScript -ComputerName $computer -TaskName $taskName -TaskPath $taskPath -Credential $cred
    }
}
