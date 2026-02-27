# LobsterDataWrapperLogCheck-Helpers.ps1
# Hilfsfunktionen für wrapper.log Monitoring
Set-StrictMode -Version Latest

function New-WrapperPatterns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TodayString
    )

    return [PSCustomObject]@{
        Today = $TodayString
        StoppedRegex = [regex]::new("^\s*STATUS\s*\|\s*wrapper\s*\|\s*${TodayString}\s+\d{2}:\d{2}:\d{2}\s*\|\s*<--\s*Wrapper\s+Stopped\s*$", 'IgnoreCase')
        StoppedAnyDateRegex = [regex]::new("^\s*STATUS\s*\|\s*wrapper\s*\|\s*\d{4}[/.]\d{2}[/.]\d{2}\s+\d{2}:\d{2}:\d{2}\s*\|\s*<--\s*Wrapper\s+Stopped\s*$", 'IgnoreCase')
        StartedRegex = [regex]::new("^\s*STATUS\s*\|\s*wrapper\s*\|\s*${TodayString}\s+\d{2}:\d{2}:\d{2}\s*\|\s*-->\s*Wrapper\s+Started\s+as\s+Service\s*$", 'IgnoreCase')
        WrapperStartLooseRegex = [regex]::new("^\s*STATUS\s*\|\s*wrapper\s*\|\s*${TodayString}\s+\d{2}:\d{2}:\d{2}\s*\|\s*-->\s*Wrapper\s+Started\b.*$", 'IgnoreCase')
        AnyDateRegex = [regex]::new("\b\d{4}[/.]\d{2}[/.]\d{2}\b", 'None')
        TimestampRegex = [regex]::new("^\s*STATUS\s*\|\s*wrapper\s*\|\s*(\d{4}[/.]\d{2}[/.]\d{2})\s+(\d{2}:\d{2}:\d{2})\s*\|", 'IgnoreCase')
    }
}

function Get-WrapperLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )

    if (-not (Test-Path -LiteralPath $LogPath)) { return @() }

    [string[]]$lines = @(Get-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop)
    return @($lines | Where-Object { $_ -ne $null -and $_.Trim() -ne '' })
}

function Get-LastNLines {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Lines = @(),
        [int]$Count = 20
    )
    if (-not $Lines) { return @() }
    if ($Lines.Count -le $Count) { return $Lines }
    return $Lines[($Lines.Count-$Count)..($Lines.Count-1)]
}

# --- FIX Bug #1: fehlende Funktion ergaenzt ---
function Get-FileTailLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$TailLines = 200
    )
    $all = Get-WrapperLines -LogPath $Path
    return Get-LastNLines -Lines $all -Count $TailLines
}

function Find-LastMatchIndex {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Lines = @(),
        [Parameter(Mandatory=$true)]
        [regex]$Regex
    )
    if (-not $Lines -or $Lines.Count -eq 0) { return -1 }
    for ($i = $Lines.Count-1; $i -ge 0; $i--) {
        if ($Regex.IsMatch($Lines[$i])) { return $i }
    }
    return -1
}

function Parse-WrapperTimestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Line
    )
    if ($Line -match '^\s*STATUS\s*\|\s*wrapper\s*\|\s*(\d{4})[/.](\d{2})[/.](\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s*\|') {
        try {
            return [datetime]::new([int]$Matches[1],[int]$Matches[2],[int]$Matches[3],[int]$Matches[4],[int]$Matches[5],[int]$Matches[6])
        } catch { return $null }
    }
    return $null
}

function Is-OkCandidate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Lines = @(),
        [Parameter(Mandatory=$true)]
        $Patterns,
        [Parameter(Mandatory=$true)]
        [datetime]$ScriptStart,
        [int]$TimeToleranceMinutes = 5
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return [PSCustomObject]@{ Ok=$false; Near=$false; IsLast=$false; Index=-1; Timestamp=$null }
    }

    $idx = Find-LastMatchIndex -Lines $Lines -Regex $Patterns.StoppedRegex
    if ($idx -lt 0) {
        return [PSCustomObject]@{ Ok=$false; Near=$false; IsLast=$false; Index=-1; Timestamp=$null }
    }

    $ts = Parse-WrapperTimestamp -Line $Lines[$idx]
    $near = $false
    if ($ts) {
        $delta = [Math]::Abs(($ts - $ScriptStart).TotalMinutes)
        $near = ($delta -le $TimeToleranceMinutes)
    }

    $isLast = ($idx -eq ($Lines.Count-1))

    $ok = ($near -and $isLast)
    return [PSCustomObject]@{ Ok=$ok; Near=$near; IsLast=$isLast; Index=$idx; Timestamp=$ts }
}

function Is-ErrorStartImmediatelyAfterStopped {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$Lines = @(),
        [Parameter(Mandatory=$true)]
        $Patterns,
        [Parameter(Mandatory=$true)]
        [datetime]$ScriptStart,
        [int]$TimeToleranceMinutes = 5
    )

    if (-not $Lines -or $Lines.Count -lt 2) { return $false }

    $stoppedIdx = Find-LastMatchIndex -Lines $Lines -Regex $Patterns.StoppedRegex
    if ($stoppedIdx -lt 0) { return $false }

    # Timestamp-Naehe pruefen
    $ts = Parse-WrapperTimestamp -Line $Lines[$stoppedIdx]
    if (-not $ts) { return $false }
    $delta = [Math]::Abs(($ts - $ScriptStart).TotalMinutes)
    if ($delta -gt $TimeToleranceMinutes) { return $false }

    # Wurde NACH dem letzten Stopped irgendwo ein Start gefunden?
    $startedIdx = Find-LastMatchIndex -Lines $Lines -Regex $Patterns.WrapperStartLooseRegex
    if ($startedIdx -gt $stoppedIdx) { return $true }

    return $false
}
