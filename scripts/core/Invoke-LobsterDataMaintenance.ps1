[CmdletBinding(DefaultParameterSetName='Remote')]
param(
    # --- LOCAL (Read / local service) ---
    [Parameter(ParameterSetName='Local', Mandatory=$true)]
    [string]$LogPath,

    # --- REMOTE (remote service / remote log) ---
    [Parameter(ParameterSetName='Remote', Mandatory=$true)]
    [string]$ComputerName,

    # Kept for compatibility with existing calls/wizard (may be used later for remote copy/execution).
    [Parameter(ParameterSetName='Remote', Mandatory=$true)]
    [string]$RemoteProjectPath,

    [Parameter(ParameterSetName='Remote', Mandatory=$true)]
    [string]$RemoteLogPath,

    # --- Action ---
    # Read  -> nur Logcheck + optional Mail (keine Service-Aktion)
    # Stop  -> Service stoppen + StartupType=Manual + Logcheck + optional Mail
    # Start -> (wenn nicht Running) StartupType=Automatic + Service starten + Logcheck + optional Mail
    [ValidateSet('Read','Stop','Start')]
    [string]$Action = 'Read',

    # Backward compatibility: old scripts/wizard used -StopMode (None|WindowsService|RestApi).
    # If -StopMode is supplied, it will be mapped to Action/WindowsService.
    [ValidateSet('None','WindowsService','RestApi')]
    [string]$StopMode = 'None',

    # Windows service name (used when Action=Stop/Start)
    [string]$ServiceName = 'Lobster Integration Server',

    # Only relevant when Action is Stop/Start:
    [ValidateSet('Remote','Local')]
    [string]$ServiceScope = 'Remote',

    # Notification
    [string]$NotifyMailTo = '',
    [string]$NotifySmtpServer = 'smtp.cust.bmlc.local',
    [string]$NotifyMailFrom = 'noreply@quehenberger.com',
    [switch]$SendNotification,

    # Interactive console wizard (asks for Action/ServiceScope)
    [switch]$Interactive,

    # Optional credential for remote actions
    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Select-FromConsoleMenu {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][hashtable]$Options,
        [int]$Default = 1
    )
    Write-Host ''
    Write-Host $Title
    foreach ($k in ($Options.Keys | Sort-Object {[int]$_})) {
        Write-Host ("  {0}) {1}" -f $k, $Options[$k])
    }
    $choice = Read-Host ("Auswahl [{0}]" -f $Default)
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $Default }
    if (-not $Options.ContainsKey([string]$choice)) {
        throw "Ungültige Auswahl: $choice"
    }
    return $Options[[string]$choice]
}

function Get-RemoteInvokeSplat {
    param([string]$ComputerName,[pscredential]$Credential)
    $splat = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
    if ($null -ne $Credential) { $splat.Credential = $Credential }
    return $splat
}

function Get-Config {
    param([string]$RemoteProjectPath)

    # Prefer "prod" config if present, else default config.
    $cfgDir = Join-Path $projectRoot 'config'
    $prod = Join-Path $cfgDir 'lobsterdata.maintenance.prod.config.psd1'
    $def  = Join-Path $cfgDir 'lobsterdata.maintenance.config.psd1'
    $prodLegacy = Join-Path $projectRoot 'lobsterdata.maintenance.prod.config.psd1'
    $defLegacy  = Join-Path $projectRoot 'lobsterdata.maintenance.config.psd1'

    if (Test-Path $prod) { return Import-PowerShellDataFile -LiteralPath $prod }
    if (Test-Path $def)  { return Import-PowerShellDataFile -LiteralPath $def }
    if (Test-Path $prodLegacy) { return Import-PowerShellDataFile -LiteralPath $prodLegacy }
    if (Test-Path $defLegacy)  { return Import-PowerShellDataFile -LiteralPath $defLegacy }
    return @{}
}

function Get-ActionConfig {
    param(
        [hashtable]$Config,
        [ValidateSet('Stop','Start','Read')]$Action
    )

    # New preferred sections
    $key = "{0}Config" -f $Action
    if ($Config.ContainsKey($key) -and $Config[$key] -is [hashtable]) {
        return $Config[$key]
    }

    # Fallback to legacy keys (stop-like behavior)
    return @{
        SuccessRegex               = if ($Action -eq 'Start') { 'Integration Server \(IS\) started .*system is ready' } else { 'Wrapper\s+Stopped' }
        TailLines                  = if ($Config.ContainsKey('WarnTailLines')) { [int]$Config.WarnTailLines } else { 200 }
        MaxAttempts                = if ($Config.ContainsKey('MaxAttempts')) { [int]$Config.MaxAttempts } else { 11 }
        AttemptSleepSeconds_Test   = if ($Config.ContainsKey('AttemptSleepSeconds_Test')) { [int]$Config.AttemptSleepSeconds_Test } else { 1 }
        AttemptSleepSeconds_Prod   = if ($Config.ContainsKey('AttemptSleepSeconds_Prod')) { [int]$Config.AttemptSleepSeconds_Prod } else { 30 }
        RecheckSleepSeconds_Test   = if ($Config.ContainsKey('RecheckSleepSeconds_Test')) { [int]$Config.RecheckSleepSeconds_Test } else { 1 }
        RecheckSleepSeconds_Prod   = if ($Config.ContainsKey('RecheckSleepSeconds_Prod')) { [int]$Config.RecheckSleepSeconds_Prod } else { 10 }
        IsTest                     = if ($Config.ContainsKey('IsTest')) { [bool]$Config.IsTest } else { $false }
    }
}

function Get-SleepSeconds {
    param([hashtable]$ActionConfig)
    if ($ActionConfig.ContainsKey('IsTest') -and $ActionConfig.IsTest) {
        return [int]$ActionConfig.AttemptSleepSeconds_Test
    }
    return [int]$ActionConfig.AttemptSleepSeconds_Prod
}

function Get-RecheckSeconds {
    param([hashtable]$ActionConfig)
    if ($ActionConfig.ContainsKey('IsTest') -and $ActionConfig.IsTest) {
        return [int]$ActionConfig.RecheckSleepSeconds_Test
    }
    return [int]$ActionConfig.RecheckSleepSeconds_Prod
}

function New-Result {
    param(
        [string]$Step,
        [string]$HostName,
        [ValidateSet('OK','INFO','WARN','ERROR')]$Level,
        [string]$Message,
        [int]$ExitCode = 0,
        [string[]]$LogLines = @()
    )
    return [PSCustomObject]@{
        Step     = $Step
        HostName = $HostName
        Level    = $Level
        Message  = $Message
        ExitCode = $ExitCode
        LogLines = @($LogLines)
    }
}

function Send-NotificationMail {
    param(
        [Parameter(Mandatory=$true)][object[]]$Results,
        [Parameter(Mandatory=$true)][string]$To,
        [Parameter(Mandatory=$true)][string]$SmtpServer,
        [Parameter(Mandatory=$true)][string]$From
    )

    $rows = foreach ($r in $Results) {
        $step = [System.Net.WebUtility]::HtmlEncode([string]$r.Step)
        $hostHtml = [System.Net.WebUtility]::HtmlEncode([string]$r.HostName)
        $lvl  = [System.Net.WebUtility]::HtmlEncode([string]$r.Level)
        $msg  = [System.Net.WebUtility]::HtmlEncode([string]$r.Message)
        "<tr><td>$step</td><td>$hostHtml</td><td>$lvl</td><td>$msg</td></tr>"
    }

    $logBlock = ''
    $firstWithLines = $Results | Where-Object { $_.LogLines -and $_.LogLines.Count -gt 0 } | Select-Object -First 1
    if ($firstWithLines) {
        $lines = ($firstWithLines.LogLines | Select-Object -Last 60) -join "`r`n"
        $logBlock = "<h3>Log (letzte 60 Zeilen)</h3><pre style='background:#f4f4f4;padding:10px;border:1px solid #ddd;white-space:pre-wrap;'>" +
                    [System.Net.WebUtility]::HtmlEncode($lines) + "</pre>"
    }

    $body = @"
<html>
  <body style="font-family:Segoe UI, Arial, sans-serif;">
    <h2>Lobster Maintenance</h2>
    <table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">
      <tr style="background:#eee;">
        <th>Step</th><th>Host</th><th>Level</th><th>Message</th>
      </tr>
      $($rows -join "`r`n")
    </table>
    $logBlock
  </body>
</html>
"@

    $subject = "Lobster Maintenance - {0}" -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
    Send-MailMessage -To $To -From $From -SmtpServer $SmtpServer -Subject $subject -Body $body -BodyAsHtml -ErrorAction Stop
}

function Test-WrapperLogPatternLocal {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$SuccessRegex,
        [Parameter(Mandatory=$true)][int]$TailLines
    )
    $tail = Get-Content -LiteralPath $Path -Tail $TailLines -ErrorAction Stop
    $hit = $tail | Where-Object { $_ -match $SuccessRegex } | Select-Object -First 1
    return @{ Hit = [bool]$hit; Tail = $tail }
}

function Test-WrapperLogPatternRemote {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][pscredential]$Credential,
        [Parameter(Mandatory=$true)][string]$RemoteLogPath,
        [Parameter(Mandatory=$true)][string]$SuccessRegex,
        [Parameter(Mandatory=$true)][int]$TailLines
    )
    $splat = Get-RemoteInvokeSplat -ComputerName $ComputerName -Credential $Credential
    $tail = Invoke-Command @splat -ScriptBlock {
        param($p,$tailN)
        Get-Content -LiteralPath $p -Tail $tailN -ErrorAction Stop
    } -ArgumentList $RemoteLogPath, $TailLines

    $hit = $tail | Where-Object { $_ -match $SuccessRegex } | Select-Object -First 1
    return @{ Hit = [bool]$hit; Tail = $tail }
}

function Invoke-WrapperLogPoll {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Local','Remote')]$Scope,
        [Parameter(Mandatory=$true)][string]$HostName,
        [Parameter(Mandatory=$true)][string]$LogPathOrRemote,
        [Parameter(Mandatory=$true)][string]$SuccessRegex,
        [Parameter(Mandatory=$true)][int]$TailLines,
        [Parameter(Mandatory=$true)][int]$MaxAttempts,
        [Parameter(Mandatory=$true)][int]$SleepSeconds,
        [pscredential]$Credential,
        [string]$StepName
    )

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $check = if ($Scope -eq 'Local') {
            Test-WrapperLogPatternLocal -Path $LogPathOrRemote -SuccessRegex $SuccessRegex -TailLines $TailLines
        } else {
            Test-WrapperLogPatternRemote -ComputerName $HostName -Credential $Credential -RemoteLogPath $LogPathOrRemote -SuccessRegex $SuccessRegex -TailLines $TailLines
        }

        if ($check.Hit) {
            return New-Result -Step $StepName -HostName $HostName -Level 'OK' -Message ("Pattern gefunden: {0} (Attempt {1}/{2})" -f $SuccessRegex, $i, $MaxAttempts) -ExitCode 0 -LogLines @($check.Tail)
        }

        if ($i -lt $MaxAttempts) {
            Start-Sleep -Seconds $SleepSeconds
        } else {
            return New-Result -Step $StepName -HostName $HostName -Level 'ERROR' -Message ("Pattern NICHT gefunden: {0} (nach {1} Versuchen)" -f $SuccessRegex, $MaxAttempts) -ExitCode 1 -LogLines @($check.Tail)
        }
    }
}

# --- Backward compatibility mapping (StopMode -> Action) ---
if ($StopMode -ne 'None') {
    if ($StopMode -eq 'RestApi') {
        throw 'StopMode=RestApi ist aktuell noch nicht verfügbar.'
    }
    # Old behavior: WindowsService stop
    $Action = 'Stop'
}

# Validate mandatory inputs depending on action
if (($Action -in @('Stop','Start')) -and [string]::IsNullOrWhiteSpace($ServiceName)) {
    throw "Wenn -Action $Action gesetzt ist, muss -ServiceName (Dienstname) angegeben werden."
}

# --- Optional interactive selection for Action / ServiceScope ---
if ($Interactive) {
    $Action = Select-FromConsoleMenu -Title 'Aktion auswählen' -Options @{
        '1' = 'Read'
        '2' = 'Stop'
        '3' = 'Start'
    } -Default 1

    if ($Action -in @('Stop','Start')) {
        $ServiceScope = Select-FromConsoleMenu -Title 'Windows Dienst: lokal oder remote?' -Options @{
            '1' = 'Local'
            '2' = 'Remote'
        } -Default 2
    }
}

$config = Get-Config -RemoteProjectPath $RemoteProjectPath
$actionConfig = Get-ActionConfig -Config $config -Action $Action
$sleepSeconds = Get-SleepSeconds -ActionConfig $actionConfig
$recheckSeconds = Get-RecheckSeconds -ActionConfig $actionConfig
$successRegex = [string]$actionConfig.SuccessRegex
$tailLines = [int]$actionConfig.TailLines
$maxAttempts = [int]$actionConfig.MaxAttempts

$results = @()

# --- Service action ---
if ($Action -eq 'Stop') {
    if ($ServiceScope -eq 'Local') {
        Stop-Service -Name $ServiceName -ErrorAction Stop
        $results += New-Result -Step 'StopService' -HostName $env:COMPUTERNAME -Level 'OK' -Message "Dienst gestoppt: $ServiceName (lokal)"
        Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop
        $results += New-Result -Step 'SetStartupType' -HostName $env:COMPUTERNAME -Level 'OK' -Message "StartupType gesetzt auf Manual: $ServiceName (lokal)"
    } else {
        if ($PSCmdlet.ParameterSetName -ne 'Remote') {
            throw 'ServiceScope=Remote erfordert den Remote-ParameterSet (ComputerName/RemoteProjectPath/RemoteLogPath).'
        }
        $splat = Get-RemoteInvokeSplat -ComputerName $ComputerName -Credential $Credential
        Invoke-Command @splat -ScriptBlock {
            param([string]$ServiceName)
            Stop-Service -Name $ServiceName -ErrorAction Stop
            Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop
        } -ArgumentList $ServiceName

        $results += New-Result -Step 'StopService' -HostName $ComputerName -Level 'OK' -Message "Dienst gestoppt: $ServiceName (remote)"
        $results += New-Result -Step 'SetStartupType' -HostName $ComputerName -Level 'OK' -Message "StartupType gesetzt auf Manual: $ServiceName (remote)"
    }
}

if ($Action -eq 'Start') {
    if ($ServiceScope -eq 'Local') {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
        $results += New-Result -Step 'SetStartupType' -HostName $env:COMPUTERNAME -Level 'OK' -Message "StartupType gesetzt auf Automatic: $ServiceName (lokal)"

        if ($svc.Status -eq 'Running') {
            $results += New-Result -Step 'StartService' -HostName $env:COMPUTERNAME -Level 'INFO' -Message "Dienst läuft bereits, Start übersprungen: $ServiceName (lokal)"
        } else {
            Start-Service -Name $ServiceName -ErrorAction Stop
            $results += New-Result -Step 'StartService' -HostName $env:COMPUTERNAME -Level 'OK' -Message "Dienst gestartet: $ServiceName (lokal)"
        }
    } else {
        if ($PSCmdlet.ParameterSetName -ne 'Remote') {
            throw 'ServiceScope=Remote erfordert den Remote-ParameterSet (ComputerName/RemoteProjectPath/RemoteLogPath).'
        }
        $splat = Get-RemoteInvokeSplat -ComputerName $ComputerName -Credential $Credential

        $remoteStatus = Invoke-Command @splat -ScriptBlock {
            param([string]$ServiceName)
            $svc = Get-Service -Name $ServiceName -ErrorAction Stop
            Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
            if ($svc.Status -eq 'Running') { return 'Running' }
            Start-Service -Name $ServiceName -ErrorAction Stop
            return 'Started'
        } -ArgumentList $ServiceName

        $results += New-Result -Step 'SetStartupType' -HostName $ComputerName -Level 'OK' -Message "StartupType gesetzt auf Automatic: $ServiceName (remote)"
        if ($remoteStatus -eq 'Running') {
            $results += New-Result -Step 'StartService' -HostName $ComputerName -Level 'INFO' -Message "Dienst läuft bereits, Start übersprungen: $ServiceName (remote)"
        } else {
            $results += New-Result -Step 'StartService' -HostName $ComputerName -Level 'OK' -Message "Dienst gestartet: $ServiceName (remote)"
        }
    }
}

# --- Log poll/check (uses ActionConfig.SuccessRegex) ---
if ($PSCmdlet.ParameterSetName -eq 'Local') {
    $logRes = Invoke-WrapperLogPoll -Scope 'Local' -HostName $env:COMPUTERNAME -LogPathOrRemote $LogPath -SuccessRegex $successRegex -TailLines $tailLines -MaxAttempts $maxAttempts -SleepSeconds $sleepSeconds -StepName 'LocalWrapperLogCheck'
    $results += $logRes
} else {
    $logRes = Invoke-WrapperLogPoll -Scope 'Remote' -HostName $ComputerName -LogPathOrRemote $RemoteLogPath -SuccessRegex $successRegex -TailLines $tailLines -MaxAttempts $maxAttempts -SleepSeconds $sleepSeconds -Credential $Credential -StepName 'RemoteWrapperLogCheck'
    $results += $logRes
}

# Optional recheck once more after success (useful after stop/start)
if (($Action -in @('Stop','Start')) -and ($results[-1].ExitCode -eq 0) -and $recheckSeconds -gt 0) {
    Start-Sleep -Seconds $recheckSeconds
    if ($PSCmdlet.ParameterSetName -eq 'Local') {
        $re = Invoke-WrapperLogPoll -Scope 'Local' -HostName $env:COMPUTERNAME -LogPathOrRemote $LogPath -SuccessRegex $successRegex -TailLines $tailLines -MaxAttempts 1 -SleepSeconds 0 -StepName 'LocalWrapperLogRecheck'
    } else {
        $re = Invoke-WrapperLogPoll -Scope 'Remote' -HostName $ComputerName -LogPathOrRemote $RemoteLogPath -SuccessRegex $successRegex -TailLines $tailLines -MaxAttempts 1 -SleepSeconds 0 -Credential $Credential -StepName 'RemoteWrapperLogRecheck'
    }
    $results += $re
}

# --- Mail notification ---
if ($SendNotification) {
    if ([string]::IsNullOrWhiteSpace($NotifyMailTo)) {
        throw 'Wenn -SendNotification gesetzt ist, muss -NotifyMailTo angegeben werden.'
    }
    Send-NotificationMail -Results $results -To $NotifyMailTo -SmtpServer $NotifySmtpServer -From $NotifyMailFrom
    $results += New-Result -Step 'Notification' -HostName $env:COMPUTERNAME -Level 'OK' -Message 'Mail wurde versendet.'
} else {
    $results += New-Result -Step 'Notification' -HostName $env:COMPUTERNAME -Level 'INFO' -Message 'Mailversand deaktiviert.'
}

# Output summary to console
$results | Format-Table Step,HostName,Level,Message -AutoSize
exit (($results | Measure-Object -Property ExitCode -Maximum).Maximum)
