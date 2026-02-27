# =========================
# Run-TestCase.ps1
# Batch-faehiger Test-Runner
#
# Beispiele:
#   1) Einzelner Test:   .\Run-TestCase.ps1 -Case TC01
#   2) Mehrere Tests:    .\Run-TestCase.ps1 -Case TC01,TC02,TC03
#   3) Alle Tests:       .\Run-TestCase.ps1 -All
# =========================

[CmdletBinding()]
param(
    [ValidateSet('TC01','TC02','TC03','TC04','TC05')]
    [string[]]$Case,

    [switch]$All
)

$root = $PSScriptRoot
$projectRoot = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $root "lobsterdata.test.config.psd1"
$cfg = Import-PowerShellDataFile -Path $cfgPath

$logsDir = Join-Path $root "testcases"
$runtimeDir = Join-Path $root "runtime"
$runtimeLog = Join-Path $runtimeDir "wrapper.log"
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

$map = @{
    'TC01' = 'TC01_OK_wrapper_stopped_last.log'
    'TC02' = 'TC02_WARN_wrapper_stopped_not_now.log'
    'TC03' = 'TC03_ERROR_wrapper_stopped_then_started.log'
    'TC04' = 'TC04_WARN_wrapper_not_stopped.log'
    'TC05' = 'TC05_WARN_wrapper_stopped_wrong_time.log'
}

# Erwartete Exit-Codes pro Testcase
$expected = @{
    'TC01' = 0  # OK
    'TC02' = 1  # WARN
    'TC03' = 2  # ERROR
    'TC04' = 1  # WARN
    'TC05' = 1  # WARN
}

function Shift-LogTimestamps {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][datetime]$TargetNearTime
    )

    $tsRegex = [regex]'(?<d>\b\d{4}(?<sep>[\/\.])\d{2}\k<sep>\d{2})\s+(?<t>\d{2}:\d{2}:\d{2})\b'

    $mStop = [regex]::Match($Text, 'STATUS\s*\|\s*wrapper\s*\|\s*(?<d>\d{4}[\/\.]\d{2}[\/\.]\d{2})\s+(?<t>\d{2}:\d{2}:\d{2})\s*\|\s*<--\s*Wrapper\s+Stopped', 'IgnoreCase')
    if (-not $mStop.Success) {
        $todayStr = (Get-Date).ToString('yyyy/MM/dd')
        return ($Text -replace '\b\d{4}[\/\.]\d{2}[\/\.]\d{2}\b', $todayStr)
    }

    $stopStr = ($mStop.Groups['d'].Value -replace '\.','/') + " " + $mStop.Groups['t'].Value
    $stopTime = [datetime]::ParseExact($stopStr, 'yyyy/MM/dd HH:mm:ss', $null)
    $targetStop = $TargetNearTime.AddSeconds(-30)
    $delta = $targetStop - $stopTime

    $sb = New-Object System.Text.StringBuilder
    $lastIndex = 0

    foreach ($m in $tsRegex.Matches($Text)) {
        $sb.Append($Text.Substring($lastIndex, $m.Index - $lastIndex)) | Out-Null

        $datePart = ($m.Groups['d'].Value -replace '\.','/') 
        $timePart = $m.Groups['t'].Value
        $orig = [datetime]::ParseExact("$datePart $timePart", 'yyyy/MM/dd HH:mm:ss', $null)
        $shifted = $orig + $delta

        $sep = $m.Groups['sep'].Value
        $fmt = if ($sep -eq '.') { 'yyyy.MM.dd HH:mm:ss' } else { 'yyyy/MM/dd HH:mm:ss' }
        $sb.Append($shifted.ToString($fmt)) | Out-Null

        $lastIndex = $m.Index + $m.Length
    }

    $sb.Append($Text.Substring($lastIndex)) | Out-Null
    return $sb.ToString()
}

function Invoke-OneCase {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('TC01','TC02','TC03','TC04','TC05')]
        [string]$One
    )

    # Snapshot-Ordner
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $runDir = Join-Path $runtimeDir ("runs\{0}_{1}" -f $stamp,$One)
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null

    # Quell-Log vorbereiten
    $srcFile = Join-Path $logsDir $map[$One]
    if (-not (Test-Path -LiteralPath $srcFile)) {
        throw "Testcase-Datei nicht gefunden: $srcFile"
    }

    # Fuer TC02 KEIN Timestamp-Shifting (soll absichtlich in der Vergangenheit liegen)
    $keepOriginal = @('TC02')

    # Fuer TC05 nur Datum auf heute setzen, Uhrzeiten beibehalten (Stopped soll zeitlich weit weg vom ScriptStart sein)
    $dateOnlyToday = @('TC05')

    if ($keepOriginal -contains $One) {
        Copy-Item -LiteralPath $srcFile -Destination $runtimeLog -Force
    } elseif ($dateOnlyToday -contains $One) {
        $raw = Get-Content -LiteralPath $srcFile -Raw -Encoding UTF8
        $todayStr = (Get-Date).ToString('yyyy/MM/dd')
        $raw = $raw -replace '\b\d{4}[/\.]\d{2}[/\.]\d{2}\b', $todayStr
        Set-Content -LiteralPath $runtimeLog -Value $raw -Encoding UTF8
    } else {
        $raw = Get-Content -LiteralPath $srcFile -Raw -Encoding UTF8
        $raw = Shift-LogTimestamps -Text $raw -TargetNearTime (Get-Date)
        Set-Content -LiteralPath $runtimeLog -Value $raw -Encoding UTF8
    }

    # Snapshot speichern
    Copy-Item -LiteralPath $runtimeLog -Destination (Join-Path $runDir "wrapper.log") -Force

    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "Testcase: $One -> $runtimeLog" -ForegroundColor Cyan
    Write-Host "Snapshot: $runDir" -ForegroundColor DarkGray
    Write-Host "Start:    $(Get-Date)" -ForegroundColor DarkGray

    # --- FIX Bug #3: -ConfigPath wird jetzt uebergeben ---
    & (Join-Path $projectRoot "Invoke-LobsterDataWrapperLogCheck.ps1") -ConfigPath $cfgPath
    $code = $LASTEXITCODE

    Write-Host "Ende:     $(Get-Date)  ExitCode=$code" -ForegroundColor DarkGray
    return $code
}


# ============================
# Cases bestimmen und ausfuehren
# ============================

[string[]]$casesToRun = @()

if ($All.IsPresent) {
    $casesToRun = @('TC01','TC02','TC03','TC04','TC05')
} elseif ($Case -and $Case.Count -gt 0) {
    $casesToRun = $Case
} else {
    Write-Host "Bitte -Case TC01 oder -All angeben." -ForegroundColor Yellow
    exit 1
}

$results = @()

foreach ($c in $casesToRun) {
    $exit = Invoke-OneCase -One $c
    $exp  = $expected[$c]
    $pass = ($exit -eq $exp)

    $results += [PSCustomObject]@{
        Case     = $c
        ExitCode = $exit
        Erwartet = $exp
        Status   = if ($pass) { 'PASS' } else { 'FAIL' }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host "Zusammenfassung:" -ForegroundColor White
$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) Test(s) FEHLGESCHLAGEN." -ForegroundColor Red
    exit 1
} else {
    Write-Host "Alle Tests bestanden." -ForegroundColor Green
    exit 0
}
