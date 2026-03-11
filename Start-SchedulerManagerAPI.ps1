# ============================================================
# Start-SchedulerManagerAPI.ps1
# Lokaler HTTP-API-Backend für LobsterSchedulerManager.html
#
# Verwendung:
#   powershell -ExecutionPolicy Bypass -File Start-SchedulerManagerAPI.ps1
#   powershell -ExecutionPolicy Bypass -File Start-SchedulerManagerAPI.ps1 -Port 9000
#
# Beenden: CTRL+C im Konsolenfenster
# ============================================================
[CmdletBinding()]
param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'

# ---- Logging -----------------------------------------------
function Write-Log {
    param([string]$Msg, [string]$Color = 'White')
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color
}

# ---- HTTP-Antwort senden ------------------------------------
function Send-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [hashtable]$Data,
        [int]$StatusCode = 200
    )
    $json  = $Data | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode      = $StatusCode
    $Response.ContentType     = 'application/json; charset=utf-8'
    $Response.ContentLength64 = $bytes.Length
    $Response.Headers.Add('Access-Control-Allow-Origin',  '*')
    $Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

# ---- Request-Body lesen und als Objekt zurückgeben ----------
function Get-RequestBody {
    param([System.Net.HttpListenerRequest]$Request)
    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    $body   = $reader.ReadToEnd()
    $reader.Close()
    if ($body) { return $body | ConvertFrom-Json }
    return $null
}

# ---- Credential aus user/password im Request-Body erzeugen -
function New-CredentialFromBody {
    param($Body)
    $secPass = ConvertTo-SecureString $Body.password -AsPlainText -Force
    return [PSCredential]::new($Body.user, $secPass)
}

# ---- Listener starten ---------------------------------------
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Log "=============================================" -Color Cyan
Write-Log " Lobster Scheduler Manager – API gestartet" -Color Cyan
Write-Log " http://localhost:$Port/" -Color Cyan
Write-Log " CTRL+C zum Beenden" -Color Cyan
Write-Log "=============================================" -Color Cyan
Write-Log ""

try {
    while ($listener.IsListening) {

        $context = $listener.GetContext()
        $req     = $context.Request
        $resp    = $context.Response
        $path    = $req.Url.AbsolutePath.TrimEnd('/')

        Write-Log "$($req.HttpMethod) $path"

        # CORS Preflight
        if ($req.HttpMethod -eq 'OPTIONS') {
            $resp.Headers.Add('Access-Control-Allow-Origin',  '*')
            $resp.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            $resp.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
            $resp.StatusCode = 204
            $resp.Close()
            continue
        }

        try {
            switch ($path) {

                # --------------------------------------------------
                # GET /ping  – Health-Check
                # --------------------------------------------------
                '/ping' {
                    Send-JsonResponse -Response $resp -Data @{ ok = $true; version = '1.0' }
                    Write-Log '  → pong' -Color DarkGray
                }

                # --------------------------------------------------
                # POST /check-script
                # Body: { host, user, password, scriptPath, scriptName, wrapperLogPath }
                # --------------------------------------------------
                '/check-script' {
                    $b    = Get-RequestBody $req
                    $cred = New-CredentialFromBody $b

                    $result = Invoke-Command `
                        -ComputerName $b.host `
                        -Credential   $cred `
                        -ScriptBlock  {
                            param($p, $s, $logPath)
                            $fullPath = Join-Path $p $s
                            [PSCustomObject]@{
                                ScriptExists = Test-Path -LiteralPath $fullPath
                                LogExists    = Test-Path -LiteralPath $logPath
                                ScriptPath   = $fullPath
                                LogPath      = $logPath
                            }
                        } `
                        -ArgumentList $b.scriptPath, $b.scriptName, $b.wrapperLogPath

                    $ok = [bool]$result.ScriptExists

                    Send-JsonResponse -Response $resp -Data @{
                        ok           = $ok
                        scriptExists = [bool]$result.ScriptExists
                        logExists    = [bool]$result.LogExists
                        scriptPath   = $result.ScriptPath
                        logPath      = $result.LogPath
                        message      = if ($ok) { 'Skript gefunden' } else { 'Skript NICHT gefunden' }
                    }
                    Write-Log "  Skript: $($result.ScriptExists)  Log: $($result.LogExists)" `
                              -Color $(if ($ok) { 'Green' } else { 'Red' })
                }

                # --------------------------------------------------
                # POST /create-task
                # Body: { host, user, password, taskName, taskPath, scriptFull, startTime }
                # --------------------------------------------------
                '/create-task' {
                    $b    = Get-RequestBody $req
                    $cred = New-CredentialFromBody $b

                    $result = Invoke-Command `
                        -ComputerName $b.host `
                        -Credential   $cred `
                        -ScriptBlock  {
                            param($name, $path, $script, $start, $author)

                            $action = New-ScheduledTaskAction `
                                -Execute  'powershell.exe' `
                                -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$script`""

                            $trigger = New-ScheduledTaskTrigger -Once -At ([datetime]$start)

                            $settings = New-ScheduledTaskSettingsSet `
                                -ExecutionTimeLimit (New-TimeSpan -Hours 3) `
                                -MultipleInstances  IgnoreNew `
                                -StartWhenAvailable

                            Register-ScheduledTask `
                                -TaskName $name `
                                -TaskPath $path `
                                -Action   $action `
                                -Trigger  $trigger `
                                -Settings $settings `
                                -RunLevel Highest `
                                -Force | Out-Null

                            # Author und Created per XML-Patch setzen
                            $xml = [xml](Export-ScheduledTask -TaskName $name -TaskPath $path)
                            $xml.Task.RegistrationInfo.Author = $author
                            $xml.Task.RegistrationInfo.Date   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                            Unregister-ScheduledTask -TaskName $name -TaskPath $path -Confirm:$false
                            $task = Register-ScheduledTask -TaskName $name -TaskPath $path -Xml $xml.OuterXml -Force

                            [PSCustomObject]@{
                                TaskName = $task.TaskName
                                TaskPath = $task.TaskPath
                                State    = $task.State.ToString()
                            }
                        } `
                        -ArgumentList $b.taskName, $b.taskPath, $b.scriptFull, $b.startTime, $b.user

                    Send-JsonResponse -Response $resp -Data @{
                        ok       = $true
                        taskName = $result.TaskName
                        taskPath = $result.TaskPath
                        state    = $result.State
                        message  = "Task registriert: $($result.TaskPath)$($result.TaskName)"
                    }
                    Write-Log "  Task erstellt: $($result.TaskPath)$($result.TaskName) [$($result.State)]" -Color Green
                }

                # --------------------------------------------------
                # POST /verify-task
                # Body: { host, user, password, taskName, taskPath }
                # --------------------------------------------------
                '/verify-task' {
                    $b    = Get-RequestBody $req
                    $cred = New-CredentialFromBody $b

                    $result = Invoke-Command `
                        -ComputerName $b.host `
                        -Credential   $cred `
                        -ScriptBlock  {
                            param($name, $path)
                            $t = Get-ScheduledTask -TaskName $name -TaskPath $path `
                                                   -ErrorAction SilentlyContinue
                            if ($t) {
                                $info = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                                [PSCustomObject]@{
                                    Found       = $true
                                    TaskName    = $t.TaskName
                                    TaskPath    = $t.TaskPath
                                    State       = $t.State.ToString()
                                    NextRunTime = if ($info) {
                                        $info.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss')
                                    } else { '' }
                                }
                            } else {
                                [PSCustomObject]@{ Found = $false }
                            }
                        } `
                        -ArgumentList $b.taskName, $b.taskPath

                    if ($result.Found) {
                        Send-JsonResponse -Response $resp -Data @{
                            ok          = $true
                            taskName    = $result.TaskName
                            taskPath    = $result.TaskPath
                            state       = $result.State
                            nextRunTime = $result.NextRunTime
                            message     = "Task gefunden | Status: $($result.State) | Nächster Lauf: $($result.NextRunTime)"
                        }
                        Write-Log "  Task: $($result.State)  Nächster Lauf: $($result.NextRunTime)" -Color Green
                    } else {
                        Send-JsonResponse -Response $resp -StatusCode 404 -Data @{
                            ok      = $false
                            message = "Task nicht gefunden: $($b.taskPath)$($b.taskName)"
                        }
                        Write-Log "  Task NICHT gefunden" -Color Red
                    }
                }

                # --------------------------------------------------
                # POST /send-mail
                # Body: { smtpServer, from, to, subject, body }
                # --------------------------------------------------
                '/send-mail' {
                    $b = Get-RequestBody $req

                    Send-MailMessage `
                        -SmtpServer $b.smtpServer `
                        -From       $b.from `
                        -To         $b.to `
                        -Subject    $b.subject `
                        -Body       $b.body `
                        -Encoding   UTF8

                    Send-JsonResponse -Response $resp -Data @{
                        ok      = $true
                        message = "Mail gesendet an: $($b.to)"
                    }
                    Write-Log "  Mail gesendet an $($b.to)" -Color Green
                }

                default {
                    Send-JsonResponse -Response $resp -StatusCode 404 -Data @{
                        ok      = $false
                        message = "Unbekannter Endpunkt: $path"
                    }
                    Write-Log "  [404] Unbekannter Endpunkt" -Color Yellow
                }
            }

        } catch {
            $errMsg = $_.Exception.Message
            Write-Log "  [FEHLER] $errMsg" -Color Red
            try {
                Send-JsonResponse -Response $resp -StatusCode 500 -Data @{
                    ok      = $false
                    message = $errMsg
                }
            } catch { <# Response bereits geschlossen #> }
        }
    }

} finally {
    $listener.Stop()
    Write-Log 'API gestoppt.' -Color Yellow
}
