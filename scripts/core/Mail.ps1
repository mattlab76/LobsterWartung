# Mail.ps1
# Mail-Versand fuer Wrapper-Monitor
Set-StrictMode -Version Latest

function Send-NotifyMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$To,
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Body,
        [Parameter(Mandatory=$true)][string]$SmtpServer,
        [string]$From = "noreply@quehenberger.com"
    )

    Send-MailMessage -From $From -To $To -Subject $Subject -Body $Body -BodyAsHtml -SmtpServer $SmtpServer
}
