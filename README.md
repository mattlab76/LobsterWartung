# Lobster Scheduler Manager

Webbasiertes Tool zur automatisierten Wartungssteuerung von Lobster-Servern via Windows Task Scheduler.

## Projektstruktur

```
LobsterWartung/
  LobsterSchedulerManager.html        GUI (im Browser oeffnen)
  Start-SchedulerManagerAPI.ps1        Lokale PowerShell REST-API (Port 8765)
  users.json                           Benutzerdaten (wird automatisch angelegt)
  docs/
    mail-mockup-stop.html              HTML-Mockup der Stop-Ergebnis-Mail
  deployment/
    Stop-LobsterService.ps1            Kern-Script: Dienst-Stopp + Log-Pruefung + Mail
    Start-LobsterService.ps1           Kern-Script: Dienst-Start + Log-Pruefung + Health-Check + Mail
    scripts/
      Stop-Backend.ps1                 Stoppt Backend (Windows-Dienst)
      Stop-Dmz.ps1                     Stoppt DMZ (Windows-Dienst, lokal auf DMZ-Host)
      Stop-BackendAndDmz.ps1           Stoppt DMZ remote + Backend lokal (Windows-Dienste)
      Stop-BackendViaWebserviceAndDmzService.ps1
                                       Backend via REST-API + DMZ via Windows-Dienst
      Stop-Backend-Webservice.ps1      Backend via Lobster-Webservice-URL
      Start-Backend.ps1                Startet Backend (Windows-Dienst)
      Start-Dmz.ps1                    Startet DMZ (Windows-Dienst, lokal auf DMZ-Host)
      Start-BackendAndDmz.ps1          Startet Backend + DMZ (orchestriert)
      Restart-Backend.ps1              (TODO) Backend neustarten
      Restart-BackendAndDmz.ps1        (TODO) Backend + DMZ neustarten
      Restart-Backend-Webservice.ps1   (TODO) Backend via Webservice neustarten
      Restart-BackendAndDmz-Webservice.ps1
                                       (TODO) Backend (Webservice) + DMZ neustarten
      Restart-Dmz.ps1                  (TODO) DMZ neustarten
    shared/
      Send-MaintenanceMail.ps1         Mail-Helper (HTML-Ergebnis-Tabelle)
```

---

## Schnellstart

### 1. API starten

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser   # einmalig
powershell -ExecutionPolicy Bypass -File Start-SchedulerManagerAPI.ps1
```

Beim ersten Start wird `users.json` mit Default-User **admin** / **admin** angelegt.

### 2. GUI oeffnen + anmelden

`LobsterSchedulerManager.html` im Browser oeffnen, mit **admin / admin** anmelden.
Beim ersten Login muss das Passwort geaendert werden.

**Offline-Modus:** Ist die API nicht erreichbar, kann ueber "Ohne Login fortfahren" der
manuelle Modus genutzt werden. PowerShell-Befehle werden generiert und koennen kopiert werden.
Der Auto-Modus steht im Offline-Modus nicht zur Verfuegung.

### 3. Ersteinrichtung

1. **Einstellungen** > **Benutzerverwaltung**: Weitere Benutzer anlegen (nur als Admin)
2. **Backend Hosts / DMZ Hosts**: Server-Hostnamen hinzufuegen
3. **Mail-Einstellungen**: SMTP-Server und Absender konfigurieren
4. **Standard-Werte**: Remote-Benutzername (DOMAIN\User) setzen
5. **Instanz-Zuordnung**: Health-Check-URLs den internen Backend- und DMZ-Hostnamen zuordnen
   (z.B. `http://editest.quehenberger.com:8080/dw/monitor/v1?dw=true` → Backend: `aqlbt101.bmlc.local`, DMZ: `aqlbt102.bmlc.local`)

---

## Benutzerverwaltung

Authentifizierung ueber die API (`users.json`, SHA256-Passwort-Hashing, Bearer-Token Sessions).

| Funktion | Zugriff |
|---|---|
| Login / Logout | Alle |
| Eigenes Passwort aendern | Alle (unter Einstellungen) |
| Benutzer anlegen / loeschen | Nur Admin |
| Passwort zuruecksetzen | Nur Admin |

Neue Benutzer erhalten den **Benutzernamen als initiales Passwort** und muessen es beim ersten Login aendern.

---

## Deployment auf den Servern

### Ordnerstruktur

```
D:\EDI\maintenance-scripts\             <-- Root-Pfad (in GUI angeben)
  Stop-LobsterService.ps1              Kern-Script (Stopp)
  Start-LobsterService.ps1             Kern-Script (Start)
  scripts\
    Stop-Backend.ps1
    Stop-BackendAndDmz.ps1
    Stop-Dmz.ps1
    Start-Backend.ps1
    Start-BackendAndDmz.ps1
    Start-Dmz.ps1
    ...
  shared\
    Send-MaintenanceMail.ps1
```

### Kopierbefehl

```powershell
$ziel = "\\SERVERNAME\D$\EDI\maintenance-scripts"
robocopy "deployment" "$ziel" /E /MIR
```

---

## Scripts im Detail

### Stop-LobsterService.ps1 (Kern-Script)

Zentrale Stopp-Logik. Alle `scripts\Stop-*.ps1` Wrapper delegieren an dieses Script.
Es laeuft **lokal auf dem jeweiligen Server** (ggf. per Invoke-Command remote aufgerufen).

#### Parameter

| Parameter | Pflicht | Default | Beschreibung |
|---|---|---|---|
| `ServiceName` | Ja | - | Windows-Dienstname (z.B. "Lobster Integration Server") |
| `WrapperLogPath` | Ja | - | Pfad zur wrapper.log (z.B. D:\Lobster\IS\logs\wrapper.log) |
| `DmzHost` | Nein | - | Hostname des DMZ-Servers (aktiviert Orchestrator-Modus) |
| `DmzCredential` | Nein | - | PSCredential fuer den DMZ-Server |
| `DmzServiceName` | Nein | - | Windows-Dienstname auf dem DMZ-Host |
| `DmzWrapperLogPath` | Nein | - | Pfad zur wrapper.log auf dem DMZ-Host |
| `DmzScriptPath` | Nein | auto | Pfad zu Stop-Dmz.ps1 auf dem DMZ-Host |
| `MailTo` | Nein | - | Empfaenger-Adresse (leer = keine Mail) |
| `MailFrom` | Nein | noreply@firma.local | Absender-Adresse |
| `SmtpServer` | Nein | - | SMTP-Server (leer = keine Mail) |
| `MaxWaitSeconds` | Nein | 300 | Max. Wartezeit auf "Wrapper Stopped" |
| `PollIntervalSeconds` | Nein | 15 | Intervall zwischen Log-Pruefungen |
| `TailLines` | Nein | 50 | Anzahl Zeilen vom Log-Ende die gelesen werden |
| `TimeTolerance` | Nein | 5 | Toleranzfenster in Minuten fuer den Stopp-Zeitstempel |

#### Modus 1: Standalone / DMZ (ohne DmzHost)

Wird direkt auf einem einzelnen Host ausgefuehrt (z.B. auf dem DMZ-Host via Invoke-Command).

**Ablauf:**

```
1. Dienst pruefen
   - Ist der Dienst bereits gestoppt? → OK, weiter
   - Dienst laeuft → Stop-Service ausfuehren
   - Starttyp auf "Manual" setzen (verhindert automatischen Neustart)

2. Wrapper-Log ueberwachen (Polling-Schleife)
   - Liest die letzten 50 Zeilen der wrapper.log
   - Sucht per Regex nach dem Muster:
     STATUS | wrapper | YYYY/MM/DD HH:mm:ss | <-- Wrapper Stopped
   - Prueft bei Fund:
     a) Liegt der Zeitstempel innerhalb +/- 5 Minuten? (TimeTolerance)
     b) Ist es die LETZTE Zeile im Log? (kein Neustart danach)
     c) Gibt es NACH dem "Stopped" ein "Wrapper Started"?
        → JA = FEHLER: Dienst wurde sofort wieder gestartet
        → NEIN + Zeitstempel OK + letzte Zeile = ERFOLG

3. Ergebnis zurueckgeben als PSCustomObject:
   { Host, Ok (bool), Message (string), LogTail (string[]) }
```

**Moegliche Ergebnisse:**

| Ergebnis | Bedingung |
|---|---|
| OK | "Wrapper Stopped" gefunden, Zeitstempel im Fenster, letzte Log-Zeile |
| OK | Dienst war bereits gestoppt |
| FEHLER | Timeout – kein "Wrapper Stopped" nach MaxWaitSeconds |
| FEHLER | "Wrapper Stopped" gefunden, aber danach "Wrapper Started" (Neustart!) |
| FEHLER | wrapper.log nicht gefunden |

#### Modus 2: Orchestrator (mit DmzHost)

Laeuft auf dem **Backend-Host** und koordiniert beide Hosts.

**Ablauf:**

```
Schritt [1/3] – DMZ herunterfahren
   - Invoke-Command auf DmzHost mit DmzCredential
   - Ruft Stop-Dmz.ps1 auf dem DMZ-Host auf (= Standalone-Modus)
   - Wartet auf Ergebnis-Objekt
   - DMZ FEHLER? → Abbruch, Backend wird NICHT gestoppt
     → Fehler-Mail senden (wenn konfiguriert) → Exit 1

Schritt [2/3] – Backend herunterfahren (lokal)
   - Nur wenn DMZ erfolgreich war
   - Gleicher Ablauf wie Standalone-Modus (Dienst stoppen, Log pruefen)

Schritt [3/3] – Mail senden
   - HTML-Mail mit Ergebnis-Tabelle (DMZ + Backend)
   - Spalten: Host | Ergebnis
   - Letzte Log-Zeilen von Backend und DMZ als <pre>-Block
   - Farbe: Gruen (OK) oder Rot (FEHLER)
   - Nur wenn MailTo UND SmtpServer gesetzt
```

**Exit-Codes:**

| Code | Bedeutung |
|---|---|
| 0 | Alles OK (Backend + ggf. DMZ erfolgreich gestoppt) |
| 1 | Fehler (DMZ oder Backend fehlgeschlagen) |

---

### Start-LobsterService.ps1 (Kern-Script)

Zentrale Start-Logik. Alle `scripts\Start-*.ps1` Wrapper delegieren an dieses Script.
Analog zum Stop-Script, aber mit umgekehrter Reihenfolge: **Backend zuerst, dann DMZ**.

#### Parameter

| Parameter | Pflicht | Default | Beschreibung |
|---|---|---|---|
| `ServiceName` | Ja | - | Windows-Dienstname (z.B. "Lobster Integration Server") |
| `WrapperLogPath` | Ja | - | Pfad zur wrapper.log |
| `DmzHost` | Nein | - | Hostname des DMZ-Servers (aktiviert Orchestrator-Modus) |
| `DmzCredential` | Nein | - | PSCredential fuer den DMZ-Server |
| `DmzServiceName` | Nein | - | Windows-Dienstname auf dem DMZ-Host |
| `DmzWrapperLogPath` | Nein | - | Pfad zur wrapper.log auf dem DMZ-Host |
| `DmzScriptPath` | Nein | auto | Pfad zu Start-Dmz.ps1 auf dem DMZ-Host |
| `MailTo` | Nein | - | Empfaenger-Adresse (leer = keine Mail) |
| `MailFrom` | Nein | noreply@firma.local | Absender-Adresse |
| `SmtpServer` | Nein | - | SMTP-Server (leer = keine Mail) |
| `MaxWaitSeconds` | Nein | 300 | Max. Wartezeit auf "system is ready" |
| `PollIntervalSeconds` | Nein | 15 | Intervall zwischen Log-Pruefungen |
| `TailLines` | Nein | 50 | Anzahl Zeilen vom Log-Ende die gelesen werden |
| `TimeTolerance` | Nein | 5 | Toleranzfenster in Minuten fuer den Start-Zeitstempel |
| `HealthCheckUrl` | Nein | - | Lobster Monitor REST API URL (z.B. `http://host:8080/dw/monitor/v1?dw=true`) |
| `HealthCheckCredential` | Nein | - | Zugangsdaten fuer die Monitor-API |
| `HealthCheckTimeoutSec` | Nein | 15 | HTTP-Timeout fuer den Health-Check |
| `DmzHealthCheckUrl` | Nein | - | Monitor-URL fuer den DMZ-Host (nur Orchestrator) |

#### Modus 1: Standalone / DMZ (ohne DmzHost)

**Ablauf:**

```
1. Dienst pruefen
   - Laeuft der Dienst bereits? → AlreadyRunning
     → Letzten Stopp/Start aus wrapper.log lesen (ohne Datum-Filter)
   - Dienst gestoppt → Starttyp auf "Automatic" setzen + Start-Service

2. Wrapper-Log ueberwachen (nur bei neuem Start)
   - Sucht per Regex nach dem Muster:
     INFO | jvm 1 | YYYY/MM/DD HH:mm:ss | Integration Server (IS) started in NNN ms, system is ready
   - Prueft ob Zeitstempel im Toleranzfenster liegt
   - Erkennt Fehler: "Wrapper Stopped" NACH "system is ready" = Dienst abgestuerzt

3. Health-Check (optional, immer – auch bei AlreadyRunning)
   - HTTP GET auf HealthCheckUrl
   - Parst Antwort auf: _data status = Alive (oder _DMZ status = Alive)
   - Prueft HTTP status, Lizenz-Notfallmodus
   - Ergebnis fliesst in overallSuccess ein

4. Ergebnis zurueckgeben als PSCustomObject:
   { Host, Ok (bool), Message (string), LogTail (string[]) }
```

**Moegliche Ergebnisse:**

| Ergebnis | Bedingung |
|---|---|
| OK | "system is ready" gefunden, Zeitstempel im Fenster + Health-Check Alive |
| OK | Dienst lief bereits + Health-Check Alive |
| FEHLER | Timeout – kein "system is ready" nach MaxWaitSeconds |
| FEHLER | "Wrapper Stopped" nach dem Start (Dienst abgestuerzt) |
| FEHLER | Health-Check: `_data status` ist nicht "Alive" |
| FEHLER | Health-Check: HTTP-Fehler oder Verbindung fehlgeschlagen |
| FEHLER | wrapper.log nicht gefunden |

#### Modus 2: Orchestrator (mit DmzHost)

Laeuft auf dem **Backend-Host** und koordiniert beide Hosts.
**Reihenfolge:** Zuerst Backend starten, dann DMZ (umgekehrt zum Stop).

**Ablauf:**

```
Schritt [1/3] – Backend starten (lokal)
   - Dienst starten + wrapper.log auf "system is ready" pruefen
   - Health-Check Backend ausfuehren (wenn HealthCheckUrl gesetzt)
   - Backend FEHLER? → Abbruch, DMZ wird NICHT gestartet
     → Fehler-Mail senden (wenn konfiguriert) → Exit 1

Schritt [2/3] – DMZ starten (remote)
   - Nur wenn Backend erfolgreich war
   - Invoke-Command auf DmzHost mit DmzCredential
   - Ruft Start-Dmz.ps1 auf dem DMZ-Host auf (= Standalone-Modus)
   - Health-Check DMZ ausfuehren (wenn DmzHealthCheckUrl gesetzt)

Schritt [3/3] – Mail senden
   - HTML-Mail mit Ergebnis-Tabelle (Backend + DMZ)
   - System-Status-Bloecke (gefilterte Monitor-API-Antwort, blauer Hintergrund)
   - Letzte Log-Zeilen von Backend und DMZ als <pre>-Block
   - Nur wenn MailTo UND SmtpServer gesetzt
```

#### Health-Check (Lobster Monitor REST API)

Der Health-Check prueft nach dem Start ob der Lobster Integration Server wirklich betriebsbereit ist.
Er wird **immer** ausgefuehrt wenn eine URL angegeben ist – auch wenn der Dienst bereits lief.

**Endpunkt:** `http(s)://<host>:<port>/dw/monitor/v1?dw=true`

**Authentifizierung:** Lobster-User oder "Monitorplain"-Partner mit HTTP-Channel "MONITORDATA".
Die Zugangsdaten werden ueber den Parameter `-HealthCheckCredential` als PSCredential uebergeben.

**Prueflogik:**

| Feld | Erwartung | Auswirkung |
|---|---|---|
| `_data status` | `Alive` | Kernpruefung – muss erfuellt sein |
| `_DMZ status` | `Alive` | Alternative Kernpruefung fuer DMZ-Instanzen |
| `License emergency mode active` | `false` | Warnung in Zusammenfassung wenn `true` |

**In der Ergebnis-Mail angezeigte Felder:**

- `Server's local time`, `_data status`, `_DMZ status`, `HTTP status`, `startupservice status`
- `_data queued jobs`, `_data unresolved`
- `Total memory`, `Used memory`
- `Lobster IS Version`, `Lobster_data Version`
- `License emergency mode active`, `FTP status`, `SSH status`, `failed services`

**Exit-Codes:**

| Code | Bedeutung |
|---|---|
| 0 | Alles OK (Backend + ggf. DMZ gestartet, Health-Checks bestanden) |
| 1 | Fehler (Start fehlgeschlagen oder Health-Check nicht bestanden) |

---

### Ergebnis-Mails

Beide Kern-Scripts senden HTML-Mails mit folgender Struktur:

```
+------------------------------------------------------+
| ✓ Lobster Stop/Start - OK        (oder ✗ ... FEHLER) |
+------------------------------------------------------+
| Host          | Ergebnis                              |
|---------------|---------------------------------------|
| Backend-Host  | Dienst gestoppt/gestartet um HH:mm:ss |
| DMZ-Host      | Dienst gestoppt/gestartet um HH:mm:ss |
+------------------------------------------------------+

System-Status – Backend  (nur bei Start + HealthCheckUrl)
┌──────────────────────────────────────┐
│ _data status = Alive                 │  (blauer Hintergrund)
│ HTTP status = OK                     │
│ Lobster IS Version = 4.x.x          │
│ ...                                  │
└──────────────────────────────────────┘

Letzte Log-Zeilen – Backend
┌──────────────────────────────────────┐
│ STATUS | wrapper | ... | Started     │  (grauer Hintergrund)
│ INFO   | jvm 1   | ... | system ...  │
│ ...                                  │
└──────────────────────────────────────┘

Zeitstempel – HOSTNAME
```

Ein HTML-Mockup der Stop-Mail findet sich unter `docs/mail-mockup-stop.html`.

---

### Wrapper-Scripts (deployment/scripts/)

Jedes Wrapper-Script setzt die passenden Parameter und ruft das zugehoerige Kern-Script auf.
Alle Wrapper geben den Exit-Code des Kern-Scripts weiter (`exit $LASTEXITCODE`).

#### Stop-Backend.ps1

**Zweck:** Stoppt nur den lokalen Backend-Dienst (Windows-Service). Kein DMZ.

**Ablauf:**
1. Ruft Stop-LobsterService.ps1 im Standalone-Modus auf
2. Dienst wird per `Stop-Service` gestoppt
3. Starttyp wird auf Manual gesetzt
4. wrapper.log wird auf "Wrapper Stopped" geprueft

**Parameter:** ServiceName, WrapperLogPath, MailTo, MailFrom, SmtpServer, MaxWaitSeconds, PollIntervalSeconds

---

#### Stop-Dmz.ps1

**Zweck:** Stoppt nur den lokalen DMZ-Dienst. Laeuft **direkt auf dem DMZ-Host** (nicht remote).
Wird typischerweise vom Backend-Host per `Invoke-Command` aufgerufen.

**Ablauf:**
1. Ruft Stop-LobsterService.ps1 im Standalone-Modus auf
2. Dienst wird per `Stop-Service` gestoppt
3. Starttyp wird auf Manual gesetzt
4. wrapper.log wird auf "Wrapper Stopped" geprueft
5. Gibt Ergebnis-Objekt an den rufenden Host zurueck (kein Log-Transfer)

**Parameter:** ServiceName, WrapperLogPath, MaxWaitSeconds, PollIntervalSeconds
**Hinweis:** Kein Mail-Versand – Mail wird nur vom Orchestrator (Backend-Host) gesendet.

---

#### Stop-BackendAndDmz.ps1

**Zweck:** Orchestrierter Stopp von DMZ und Backend. Laeuft auf dem **Backend-Host**.
Stoppt zuerst DMZ remote, dann Backend lokal. Beide via Windows-Dienst.

**Ablauf:**
1. Verbindet sich per `Invoke-Command` zum DMZ-Host (Credential noetig)
2. Fuehrt Stop-Dmz.ps1 auf dem DMZ-Host aus
3. Wartet auf DMZ-Ergebnis
4. DMZ fehlgeschlagen? → Abbruch, Backend bleibt laufen, Fehler-Mail
5. DMZ OK → Backend-Dienst lokal stoppen + Log pruefen
6. Ergebnis-Mail mit beiden Resultaten senden

**Parameter:** BackendServiceName, BackendWrapperLogPath, DmzHost, DmzCredential,
DmzServiceName, DmzWrapperLogPath, DmzScriptPath (optional), MailTo, MailFrom, SmtpServer,
MaxWaitSeconds, PollIntervalSeconds

---

#### Stop-BackendViaWebserviceAndDmzService.ps1

**Zweck:** Backend via Lobster-REST-API stoppen, DMZ via Windows-Dienst.
Fuer Umgebungen wo der Backend-Dienst nicht per `Stop-Service` gestoppt werden soll,
sondern ueber den Lobster-Webservice-Endpunkt.

**Ablauf:**
1. DMZ wird per `Invoke-Command` + Windows-Dienst gestoppt (wie bei Stop-BackendAndDmz)
2. Backend wird via HTTP-Request an die Webservice-URL gestoppt (statt Stop-Service)
3. wrapper.log wird trotzdem auf "Wrapper Stopped" geprueft
4. Ergebnis-Mail mit beiden Resultaten

**Parameter:** BackendWebserviceUrl, BackendWrapperLogPath, DmzHost, DmzCredential,
DmzServiceName, DmzWrapperLogPath, DmzScriptPath (optional), MailTo, MailFrom, SmtpServer,
MaxWaitSeconds, PollIntervalSeconds

---

#### Stop-Backend-Webservice.ps1

**Zweck:** Backend via Lobster-Webservice-URL stoppen. Kein DMZ. Standalone.

**Ablauf:**
1. Ruft Stop-LobsterService.ps1 mit WebserviceUrl statt ServiceName auf
2. HTTP-Request an die Webservice-URL
3. wrapper.log wird auf "Wrapper Stopped" geprueft

**Parameter:** WebserviceUrl, WrapperLogPath, MailTo, MailFrom, SmtpServer,
MaxWaitSeconds, PollIntervalSeconds

---

#### Start-Backend.ps1

**Zweck:** Startet nur den lokalen Backend-Dienst (Windows-Service). Kein DMZ.

**Ablauf:**
1. Ruft Start-LobsterService.ps1 im Standalone-Modus auf
2. Dienst wird per `Start-Service` gestartet (Starttyp auf Automatic)
3. wrapper.log wird auf "system is ready" geprueft
4. Health-Check wird ausgefuehrt (wenn HealthCheckUrl gesetzt)

**Parameter:** ServiceName, WrapperLogPath, MailTo, MailFrom, SmtpServer,
HealthCheckUrl, HealthCheckCredential, MaxWaitSeconds, PollIntervalSeconds

---

#### Start-Dmz.ps1

**Zweck:** Startet nur den lokalen DMZ-Dienst. Laeuft **direkt auf dem DMZ-Host**.
Wird typischerweise vom Backend-Host per `Invoke-Command` aufgerufen.

**Ablauf:**
1. Ruft Start-LobsterService.ps1 im Standalone-Modus auf
2. Dienst wird per `Start-Service` gestartet
3. wrapper.log wird auf "system is ready" geprueft
4. Gibt Ergebnis-Objekt an den rufenden Host zurueck

**Parameter:** ServiceName, WrapperLogPath, MaxWaitSeconds, PollIntervalSeconds
**Hinweis:** Kein Mail-Versand und kein Health-Check – beides wird nur vom Orchestrator gesendet/ausgefuehrt.

---

#### Start-BackendAndDmz.ps1

**Zweck:** Orchestrierter Start von Backend und DMZ. Laeuft auf dem **Backend-Host**.
Startet zuerst Backend lokal, dann DMZ remote (umgekehrt zum Stop).

**Ablauf:**
1. Backend-Dienst lokal starten + wrapper.log auf "system is ready" pruefen
2. Health-Check Backend ausfuehren
3. Backend fehlgeschlagen? → Abbruch, DMZ wird NICHT gestartet, Fehler-Mail
4. Backend OK → Invoke-Command auf DMZ-Host, Start-Dmz.ps1 ausfuehren
5. Health-Check DMZ ausfuehren
6. Ergebnis-Mail mit beiden Resultaten + System-Status + Log-Zeilen senden

**Parameter:** BackendServiceName, BackendWrapperLogPath, DmzHost, DmzCredential,
DmzServiceName, DmzWrapperLogPath, MailTo, MailFrom, SmtpServer,
HealthCheckUrl, DmzHealthCheckUrl, HealthCheckCredential, MaxWaitSeconds, PollIntervalSeconds

---

#### Restart-*.ps1

**Status:** Platzhalter. Werden aktiviert sobald die Restart-Logik implementiert ist.

| Script | Geplante Funktion |
|---|---|
| Restart-Backend.ps1 | Backend stoppen + starten |
| Restart-Dmz.ps1 | DMZ stoppen + starten |
| Restart-BackendAndDmz.ps1 | DMZ + Backend stoppen, dann Backend + DMZ starten |
| Restart-Backend-Webservice.ps1 | Backend via Webservice stoppen + starten |
| Restart-BackendAndDmz-Webservice.ps1 | Backend (Webservice) + DMZ stoppen + starten |

---

### Send-MaintenanceMail.ps1 (shared/)

Mail-Helper der von Stop-LobsterService.ps1 per Dot-Sourcing eingebunden werden kann.

**Funktionen:**

#### Send-MaintenanceMail

Sendet eine E-Mail via SMTP.

| Parameter | Pflicht | Beschreibung |
|---|---|---|
| To | Ja | Empfaenger-Adresse |
| Subject | Ja | Betreff |
| Body | Ja | Mail-Body (Text oder HTML) |
| SmtpServer | Ja | SMTP-Server |
| From | Nein | Absender (Default: noreply@firma.local) |
| BodyAsHtml | Nein | Switch: Body als HTML senden |

#### New-MaintenanceMailBody

Generiert einen HTML-Body mit Ergebnis-Tabelle.

| Parameter | Pflicht | Beschreibung |
|---|---|---|
| Title | Ja | Ueberschrift (z.B. "Lobster Wartung") |
| Success | Ja | Bool: Gesamtergebnis OK oder Fehler |
| Steps | Ja | Array von Objekten: @{Label; Message; Ok} |

**Erzeugt:**
- Gruene Ueberschrift bei Erfolg, rote bei Fehler
- Tabelle mit einer Zeile pro Schritt
- Gruener Hintergrund fuer OK-Schritte, roter fuer Fehler-Schritte
- Zeitstempel und Hostname im Footer

---

### Start-SchedulerManagerAPI.ps1

Lokale REST-API die als Vermittler zwischen der Browser-GUI und den Remote-Servern fungiert.

**Startet auf:** `http://localhost:8765`

#### Ablauf beim Start:
1. Prueft ob `users.json` existiert, legt sie ggf. mit Default-User "admin" an
2. Startet einen HTTP-Listener
3. Wartet in einer Endlos-Schleife auf Requests

#### API-Endpunkte

| Methode | Pfad | Auth | Beschreibung |
|---|---|---|---|
| GET | `/ping` | Nein | Health-Check, gibt Version zurueck |
| POST | `/login` | Nein | Anmeldung mit username/password, gibt Bearer-Token zurueck |
| POST | `/logout` | Ja | Session beenden |
| GET | `/session` | Ja | Aktuelle Session pruefen (username, role, etc.) |
| POST | `/change-password` | Ja | Eigenes Passwort aendern (altes + neues PW) |
| GET | `/users` | Admin | Alle Benutzer auflisten (ohne Passwort-Hashes) |
| POST | `/users` | Admin | Neuen Benutzer anlegen |
| DELETE | `/users/{name}` | Admin | Benutzer loeschen (nicht sich selbst) |
| POST | `/reset-password` | Admin | Passwort eines Users zuruecksetzen |
| POST | `/check-script` | Nein | Per Invoke-Command pruefen ob Script auf Remote-Host existiert |
| POST | `/create-task` | Nein | Scheduled Task auf Remote-Host erstellen (Register-ScheduledTask) |
| POST | `/verify-task` | Nein | Scheduled Task auf Remote-Host pruefen (Get-ScheduledTask) |
| POST | `/send-mail` | Nein | Mail ueber SMTP senden |

#### /create-task im Detail

Erstellt einen Windows Scheduled Task auf dem Remote-Host:

```
1. Verbindet sich per Invoke-Command + Credential zum Ziel-Host
2. Erstellt ScheduledTaskAction:
   Programm:  powershell.exe
   Argumente: -ExecutionPolicy Bypass -NonInteractive -File "<scriptPfad>"
              -MaxWaitSeconds <wert> -PollIntervalSeconds <wert>
3. Erstellt ScheduledTaskTrigger (einmalig, zum angegebenen Zeitpunkt)
4. Erstellt ScheduledTaskSettingsSet:
   - ExecutionTimeLimit: 3 Stunden
   - MultipleInstances: IgnoreNew
   - StartWhenAvailable: aktiviert
5. Register-ScheduledTask mit RunLevel Highest
6. XML-Patch: Setzt Author und Created-Datum im RegistrationInfo-Knoten
   (Node wird erzeugt falls nicht vorhanden)
7. Re-Registriert den Task mit der gepatchten XML
8. Gibt TaskName, TaskPath und State zurueck
```

---

## GUI (LobsterSchedulerManager.html)

Standalone HTML-Seite, laeuft lokal im Browser. Kein Build-Prozess, kein Server noetig (ausser API fuer Auto-Modus).

### Schritt 1 – Konfiguration

Formularfelder:

| Feld | Pflicht | Beschreibung |
|---|---|---|
| UserID | Ja | Benutzername des Ausfuehrenden |
| Wartungstyp | Ja | Stop-Lobster, Start-Lobster, Restart-Lobster, Start-Wartung |
| Instanz Typ | Ja | Backend, DMZ, Backend und DMZ, Backend (via Webservice), ... |
| Scheduler Location | Ja | Ordner im Task Scheduler (z.B. AQG) |
| Backend Host | Ja* | Hostname des Backend-Servers (*nur wenn Instanz-Typ Backend enthaelt) |
| DMZ Host | Ja* | Hostname des DMZ-Servers (*nur wenn Instanz-Typ DMZ enthaelt) |
| Benutzername (Remote) | Ja | DOMAIN\User fuer WinRM-Verbindung |
| Passwort (Remote) | Ja | Passwort fuer WinRM-Verbindung |
| Startzeitpunkt | Ja | Datum und Uhrzeit fuer den Scheduled Task |
| PS-Skript Root-Pfad | Ja | Root-Ordner der Scripts auf dem Ziel-Host |
| Wrapper Log Pfad | Ja | Vollstaendiger Pfad zur wrapper.log |
| Windows Service Name | Ja | Name des Windows-Dienstes |
| Health Check URL | Nein | Lobster Monitor REST API URL (nur bei Start-Scripts relevant) |
| Max. Wartezeit | Nein | Timeout in Sekunden (Default: 300) |
| Pruefintervall | Nein | Polling-Intervall in Sekunden (Default: 15) |

**Automatisch ermittelt:**
- PS-Skript Name (aus Script-Zuordnung)
- Scheduler Task Name (generiert)

**Auto-Fill:** Wenn eine Health Check URL gewaehlt wird und dazu eine Instanz-Zuordnung
in den Einstellungen existiert, werden Backend-Host und DMZ-Host automatisch befuellt.

### Schritt 2 – Zusammenfassung & Ausfuehrung

Zeigt alle Konfigurationswerte in einer Uebersichtstabelle und bietet zwei Modi:

| Modus | Beschreibung |
|---|---|
| **Automatisch** | API erstellt Task, prueft ihn und sendet Mail – vollautomatisch. API muss laufen. |
| **Manuell** | Zeigt fertige PowerShell-Befehle zum Kopieren: Direkt-Ausfuehrung und Scheduled-Task-Erstellung. |

Im manuellen Modus werden die generierten PS-Befehle automatisch mit allen relevanten Parametern
befuellt, inklusive `-HealthCheckUrl` und `-DmzHealthCheckUrl` bei Start-Scripts.

### Einstellungen

| Karte | Beschreibung |
|---|---|
| Benutzerverwaltung | Benutzer anlegen/loeschen (nur Admin) |
| Backend Hosts | Liste der Backend-Server-Hostnamen |
| DMZ Hosts | Liste der DMZ-Server-Hostnamen |
| Scheduler Locations | Task-Scheduler-Ordner (z.B. AQG) |
| Mail-Einstellungen | SMTP-Server, Absender, Standard-Empfaenger |
| PS-Skript Pfade | Root-Pfade fuer die Scripts auf den Servern |
| Wrapper Log Pfade | Pfade zu den wrapper.log-Dateien |
| Windows Service Names | Dienstnamen (z.B. "Lobster Integration Server") |
| Standard-Werte | Standard-Benutzername |
| Script-Zuordnungen | Wartungstyp + Instanz-Typ → Script-Datei (SCRIPT_MAP) |
| Instanz-Zuordnung | Health-Check-URL → Backend-Host + DMZ-Host Mapping |
| Backup & Import | Einstellungen + Historie als JSON exportieren/importieren |

Alle Einstellungen werden im **localStorage** des Browsers gespeichert und ueberleben
ein Ersetzen der HTML-Datei (z.B. bei Updates).

### Offline-Modus

Wenn die API nicht erreichbar ist, kann die GUI ueber "Ohne Login fortfahren" im
manuellen Modus genutzt werden:

- PowerShell-Befehle werden generiert und koennen kopiert werden
- Auto-Modus ist nicht verfuegbar (ausgegraut)
- Passwort-Aenderung ist nicht moeglich
- Logout kehrt zum Login-Screen zurueck

---

## Voraussetzungen

- **Client:** Windows 10/11, PowerShell 5.1, moderner Browser
- **Remote-Server:** WinRM aktiviert, PowerShell Remoting erlaubt
- **Netzwerk:** Zugriff auf Remote-Hosts via WinRM (Port 5985/5986)
- **Health-Check:** Lobster Monitor-Endpunkt erreichbar (HTTP/HTTPS), Zugangsdaten konfiguriert

## Technische Details

- GUI: Standalone HTML/JS, kein Build-Prozess
- API: `System.Net.HttpListener` auf Port 8765
- Auth: SHA256-Passwort-Hashing, Bearer-Token Sessions (12h Gueltigkeit)
- Encoding: Alle PS-Skripte verwenden UTF-8 BOM (PowerShell 5.1 Kompatibilitaet)
- Pfade: Relativ ueber `$PSScriptRoot` aufgeloest
- Stop-Log-Regex: `STATUS | wrapper | YYYY/MM/DD HH:mm:ss | <-- Wrapper Stopped`
- Start-Log-Regex: `INFO | jvm 1 | YYYY/MM/DD HH:mm:ss | Integration Server (IS) started in NNN ms, system is ready`
- Health-Check-Regex: `_data status = Alive` (oder `_DMZ status = Alive`)
