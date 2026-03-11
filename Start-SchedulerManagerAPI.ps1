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

# ---- Users-Datei -------------------------------------------
$script:UsersFile = Join-Path $PSScriptRoot 'users.json'
$script:Sessions  = @{}   # token → { username, displayName, role, expires }

function Get-UsersDb {
    if (Test-Path $script:UsersFile) {
        return @(Get-Content $script:UsersFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return @()
}

function Save-UsersDb {
    param([array]$Users)
    $Users | ConvertTo-Json -Depth 5 | Set-Content $script:UsersFile -Encoding UTF8
}

function Get-PasswordHash {
    param([string]$Plain)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plain)
    $hash  = $sha.ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace('-','').ToLower()
}

function New-SessionToken {
    $rng   = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $bytes = [byte[]]::new(32)
    $rng.GetBytes($bytes)
    return [BitConverter]::ToString($bytes).Replace('-','').ToLower()
}

function Initialize-UsersFile {
    if (-not (Test-Path $script:UsersFile)) {
        $adminHash = Get-PasswordHash 'admin'
        $defaultUsers = @(
            @{
                username      = 'admin'
                displayName   = 'Administrator'
                company       = ''
                role          = 'admin'
                passwordHash  = $adminHash
                mustChangePassword = $true
            }
        )
        Save-UsersDb $defaultUsers
        Write-Log "users.json mit Default-User 'admin' angelegt (Passwort: admin)" -Color Yellow
    }
}

function Test-Session {
    param([System.Net.HttpListenerRequest]$Request)
    $authHeader = $Request.Headers['Authorization']
    if (-not $authHeader) { return $null }
    $token = $authHeader -replace '^Bearer\s+', ''
    if ($script:Sessions.ContainsKey($token)) {
        $s = $script:Sessions[$token]
        if ($s.expires -gt (Get-Date)) { return $s }
        $script:Sessions.Remove($token)
    }
    return $null
}

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
    $Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type, Authorization')
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
Initialize-UsersFile

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
            $resp.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
            $resp.Headers.Add('Access-Control-Allow-Headers', 'Content-Type, Authorization')
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
                    Send-JsonResponse -Response $resp -Data @{ ok = $true; version = '1.1' }
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
                            param($name, $path, $script, $start, $author, $maxWait, $pollInt)

                            $action = New-ScheduledTaskAction `
                                -Execute  'powershell.exe' `
                                -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$script`" -MaxWaitSeconds $maxWait -PollIntervalSeconds $pollInt"

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
                            $ns  = $xml.Task.NamespaceURI
                            $ri  = $xml.Task.RegistrationInfo

                            foreach ($field in @(@{ Name='Author'; Value=$author }, @{ Name='Date'; Value=(Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') })) {
                                $node = $ri.SelectSingleNode($field.Name)
                                if ($node) {
                                    $node.InnerText = $field.Value
                                } else {
                                    $newNode = $xml.CreateElement($field.Name, $ns)
                                    $newNode.InnerText = $field.Value
                                    $ri.AppendChild($newNode) | Out-Null
                                }
                            }

                            Unregister-ScheduledTask -TaskName $name -TaskPath $path -Confirm:$false
                            $task = Register-ScheduledTask -TaskName $name -TaskPath $path -Xml $xml.OuterXml -Force

                            [PSCustomObject]@{
                                TaskName = $task.TaskName
                                TaskPath = $task.TaskPath
                                State    = $task.State.ToString()
                            }
                        } `
                        -ArgumentList $b.taskName, $b.taskPath, $b.scriptFull, $b.startTime, $b.user, `
                                      ([int]$b.maxWaitSeconds), ([int]$b.pollIntervalSeconds)

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

                # --------------------------------------------------
                # POST /login
                # Body: { username, password }
                # --------------------------------------------------
                '/login' {
                    $b = Get-RequestBody $req
                    $users = Get-UsersDb
                    $u = $users | Where-Object { $_.username -eq $b.username } | Select-Object -First 1

                    if (-not $u) {
                        Send-JsonResponse -Response $resp -StatusCode 401 -Data @{
                            ok = $false; message = 'Benutzername oder Passwort falsch'
                        }
                        Write-Log "  Login fehlgeschlagen: $($b.username) (nicht gefunden)" -Color Red
                        break
                    }

                    $hash = Get-PasswordHash $b.password
                    if ($hash -ne $u.passwordHash) {
                        Send-JsonResponse -Response $resp -StatusCode 401 -Data @{
                            ok = $false; message = 'Benutzername oder Passwort falsch'
                        }
                        Write-Log "  Login fehlgeschlagen: $($b.username) (falsches Passwort)" -Color Red
                        break
                    }

                    $token = New-SessionToken
                    $script:Sessions[$token] = @{
                        username    = $u.username
                        displayName = $u.displayName
                        company     = $u.company
                        role        = $u.role
                        expires     = (Get-Date).AddHours(12)
                    }

                    $mustChange = if ($u.mustChangePassword) { $true } else { $false }

                    Send-JsonResponse -Response $resp -Data @{
                        ok                 = $true
                        token              = $token
                        username           = $u.username
                        displayName        = $u.displayName
                        company            = $u.company
                        role               = $u.role
                        mustChangePassword = $mustChange
                    }
                    Write-Log "  Login OK: $($u.username) ($($u.displayName))" -Color Green
                }

                # --------------------------------------------------
                # POST /logout
                # Header: Authorization: Bearer <token>
                # --------------------------------------------------
                '/logout' {
                    $session = Test-Session $req
                    if ($session) {
                        $authHeader = $req.Headers['Authorization']
                        $token = $authHeader -replace '^Bearer\s+', ''
                        $script:Sessions.Remove($token)
                    }
                    Send-JsonResponse -Response $resp -Data @{ ok = $true }
                    Write-Log "  Logout" -Color DarkGray
                }

                # --------------------------------------------------
                # POST /change-password
                # Header: Authorization: Bearer <token>
                # Body: { oldPassword, newPassword }
                # --------------------------------------------------
                '/change-password' {
                    $session = Test-Session $req
                    if (-not $session) {
                        Send-JsonResponse -Response $resp -StatusCode 401 -Data @{
                            ok = $false; message = 'Nicht angemeldet'
                        }
                        break
                    }

                    $b     = Get-RequestBody $req
                    $users = Get-UsersDb
                    $u     = $users | Where-Object { $_.username -eq $session.username } | Select-Object -First 1

                    $oldHash = Get-PasswordHash $b.oldPassword
                    if ($oldHash -ne $u.passwordHash) {
                        Send-JsonResponse -Response $resp -StatusCode 400 -Data @{
                            ok = $false; message = 'Altes Passwort ist falsch'
                        }
                        break
                    }

                    $u.passwordHash = Get-PasswordHash $b.newPassword
                    $u.mustChangePassword = $false
                    Save-UsersDb $users
                    Send-JsonResponse -Response $resp -Data @{ ok = $true; message = 'Passwort geaendert' }
                    Write-Log "  Passwort geaendert: $($session.username)" -Color Green
                }

                # --------------------------------------------------
                # GET /session
                # Header: Authorization: Bearer <token>
                # --------------------------------------------------
                '/session' {
                    $session = Test-Session $req
                    if ($session) {
                        Send-JsonResponse -Response $resp -Data @{
                            ok          = $true
                            username    = $session.username
                            displayName = $session.displayName
                            company     = $session.company
                            role        = $session.role
                        }
                    } else {
                        Send-JsonResponse -Response $resp -StatusCode 401 -Data @{
                            ok = $false; message = 'Nicht angemeldet'
                        }
                    }
                }

                # --------------------------------------------------
                # GET /users  (nur Admin)
                # POST /users  (nur Admin) — Body: { username, password, displayName, company, role }
                # DELETE /users/<username>  (nur Admin)
                # --------------------------------------------------
                { $_ -eq '/users' -or $_ -like '/users/*' } {
                    $session = Test-Session $req
                    if (-not $session -or $session.role -ne 'admin') {
                        Send-JsonResponse -Response $resp -StatusCode 403 -Data @{
                            ok = $false; message = 'Nur Administratoren'
                        }
                        break
                    }

                    $users = Get-UsersDb

                    if ($req.HttpMethod -eq 'GET') {
                        # Liste ohne Passwort-Hashes
                        $safe = $users | ForEach-Object {
                            @{
                                username    = $_.username
                                displayName = $_.displayName
                                company     = $_.company
                                role        = $_.role
                                mustChangePassword = [bool]$_.mustChangePassword
                            }
                        }
                        Send-JsonResponse -Response $resp -Data @{ ok = $true; users = @($safe) }
                    }
                    elseif ($req.HttpMethod -eq 'POST') {
                        $b = Get-RequestBody $req
                        $exists = $users | Where-Object { $_.username -eq $b.username }
                        if ($exists) {
                            Send-JsonResponse -Response $resp -StatusCode 400 -Data @{
                                ok = $false; message = "Benutzer '$($b.username)' existiert bereits"
                            }
                            break
                        }
                        $newUser = [PSCustomObject]@{
                            username           = $b.username
                            displayName        = if ($b.displayName) { $b.displayName } else { $b.username }
                            company            = if ($b.company) { $b.company } else { '' }
                            role               = if ($b.role) { $b.role } else { 'user' }
                            passwordHash       = Get-PasswordHash $b.password
                            mustChangePassword = $true
                        }
                        $users = @($users) + @($newUser)
                        Save-UsersDb $users
                        Send-JsonResponse -Response $resp -Data @{ ok = $true; message = "Benutzer '$($b.username)' angelegt" }
                        Write-Log "  User angelegt: $($b.username)" -Color Green
                    }
                    elseif ($req.HttpMethod -eq 'DELETE') {
                        $delUser = $path -replace '/users/', ''
                        if ($delUser -eq $session.username) {
                            Send-JsonResponse -Response $resp -StatusCode 400 -Data @{
                                ok = $false; message = 'Eigenen Account kann man nicht loeschen'
                            }
                            break
                        }
                        $users = @($users | Where-Object { $_.username -ne $delUser })
                        Save-UsersDb $users
                        Send-JsonResponse -Response $resp -Data @{ ok = $true; message = "Benutzer '$delUser' geloescht" }
                        Write-Log "  User geloescht: $delUser" -Color Yellow
                    }
                }

                # --------------------------------------------------
                # POST /reset-password  (nur Admin)
                # Body: { username, newPassword }
                # --------------------------------------------------
                '/reset-password' {
                    $session = Test-Session $req
                    if (-not $session -or $session.role -ne 'admin') {
                        Send-JsonResponse -Response $resp -StatusCode 403 -Data @{
                            ok = $false; message = 'Nur Administratoren'
                        }
                        break
                    }
                    $b     = Get-RequestBody $req
                    $users = Get-UsersDb
                    $u     = $users | Where-Object { $_.username -eq $b.username } | Select-Object -First 1
                    if (-not $u) {
                        Send-JsonResponse -Response $resp -StatusCode 404 -Data @{
                            ok = $false; message = "Benutzer '$($b.username)' nicht gefunden"
                        }
                        break
                    }
                    $u.passwordHash = Get-PasswordHash $b.newPassword
                    $u.mustChangePassword = $true
                    Save-UsersDb $users
                    Send-JsonResponse -Response $resp -Data @{ ok = $true; message = "Passwort fuer '$($b.username)' zurueckgesetzt" }
                    Write-Log "  Passwort-Reset: $($b.username)" -Color Yellow
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
