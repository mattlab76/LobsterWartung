#Requires -Version 5.1
<#
.SYNOPSIS
    Gemeinsamer Mail-Helper fuer alle Lobster-Wartungs-Scripts.

.DESCRIPTION
    Stellt die Funktion Send-MaintenanceMail bereit.
    Wird von den Wrapper-Scripts per Dot-Sourcing eingebunden:

        . "$PSScriptRoot\..\shared\Send-MaintenanceMail.ps1"

.NOTES
    Deployment: auf allen Hosts unter dem shared\-Unterordner ablegen.
#>

function Send-MaintenanceMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]   $To,
        [Parameter(Mandatory=$true)] [string]   $Subject,
        [Parameter(Mandatory=$true)] [string]   $Body,
        [Parameter(Mandatory=$true)] [string]   $SmtpServer,
        [string] $From      = 'noreply@firma.local',
        [switch] $BodyAsHtml
    )

    $params = @{
        To         = $To
        From       = $From
        Subject    = $Subject
        Body       = $Body
        SmtpServer = $SmtpServer
        ErrorAction = 'Stop'
    }
    if ($BodyAsHtml) { $params.BodyAsHtml = $true }

    Send-MailMessage @params
}

function New-MaintenanceMailBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]   $Title,
        [Parameter(Mandatory=$true)] [bool]     $Success,
        [Parameter(Mandatory=$true)] [object[]] $Steps   # Array von [PSCustomObject]@{Label; Message; Ok}
    )

    $color  = if ($Success) { '#2e7d32' } else { '#c62828' }
    $status = if ($Success) { 'OK' } else { 'FEHLER' }
    $icon   = if ($Success) { '&#10003;' } else { '&#10007;' }
    $enc    = [System.Net.WebUtility]

    $rows = $Steps | ForEach-Object {
        $rowColor = if ($_.Ok) { '#e8f5e9' } else { '#ffebee' }
        $stepIcon = if ($_.Ok) { '&#10003;' } else { '&#10007;' }
        "<tr style='background:$rowColor;'>
          <td style='padding:7px 10px;'>$stepIcon $($enc::HtmlEncode($_.Label))</td>
          <td style='padding:7px 10px;'>$($enc::HtmlEncode($_.Message))</td>
        </tr>"
    }

    return @"
<html>
<body style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#333;">
  <h2 style="color:$color;">$icon $($enc::HtmlEncode($Title)) &ndash; $status</h2>
  <table border="1" cellpadding="0" cellspacing="0"
         style="border-collapse:collapse;min-width:500px;border-color:#ddd;">
    <thead>
      <tr style="background:#f0f0f0;">
        <th style="text-align:left;padding:8px 10px;border:1px solid #ddd;">Schritt</th>
        <th style="text-align:left;padding:8px 10px;border:1px solid #ddd;">Ergebnis</th>
      </tr>
    </thead>
    <tbody>$($rows -join '')</tbody>
  </table>
  <p style="color:#999;font-size:11px;margin-top:16px;">
    $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss') &ndash; $env:COMPUTERNAME
  </p>
</body>
</html>
"@
}
