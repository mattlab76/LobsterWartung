# Lobster Scheduler Manager

Webbasiertes Tool zur automatisierten Wartungssteuerung von Lobster-Servern via Windows Task Scheduler.

## Projektstruktur

```
LobsterWartung/
  LobsterSchedulerManager.html        GUI (im Browser oeffnen)
  Start-SchedulerManagerAPI.ps1        Lokale PowerShell REST-API (Port 8765)
  users.json                           Benutzerdaten (wird automatisch angelegt)
  deployment/
    Stop-LobsterService.ps1            Kern-Script: Dienst-Stopp + Log-Pruefung + Mail
    scripts/
      Stop-Backend.ps1                 Stoppt Backend (Windows-Dienst)
      Stop-Dmz.ps1                     Stoppt DMZ (Windows-Dienst, lokal auf DMZ-Host)
      Stop-BackendAndDmz.ps1           Stoppt DMZ remote + Backend lokal (Windows-Dienste)
      Stop-BackendViaWebserviceAndDmzService.ps1
                                       Backend via REST-API + DMZ via Windows-Dienst
      Stop-Backend-Webservice.ps1      Backend via Lobster-Webservice-URL
      Start-Backend.ps1                (TODO) Backend starten
      Start-BackendAndDmz.ps1          (TODO) Backend + DMZ starten
      Start-Dmz.ps1                    (TODO) DMZ starten
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

### 3. Ersteinrichtung

1. **Einstellungen** > **Benutzerverwaltung**: Weitere Benutzer anlegen (nur als Admin)
2. **Backend Hosts / DMZ Hosts**: Server-Hostnamen hinzufuegen
3. **Mail-Einstellungen**: SMTP-Server und Absender konfigurieren
4. **Standard-Werte**: Remote-Benutzername (DOMAIN\User) und PS-Skript Root-Pfad setzen

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
  Stop-LobsterService.ps1              Kern-Script
  scripts\
    Stop-Backend.ps1
    Stop-BackendAndDmz.ps1
    Stop-Dmz.ps1
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
   { Host, Ok (bool), Message (string) }
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
   - Farbe: Gruen (OK) oder Rot (FEHLER)
   - Nur wenn MailTo UND SmtpServer gesetzt
```

**Exit-Codes:**

| Code | Bedeutung |
|---|---|
| 0 | Alles OK (Backend + ggf. DMZ erfolgreich gestoppt) |
| 1 | Fehler (DMZ oder Backend fehlgeschlagen) |

---

### Wrapper-Scripts (deployment/scripts/)

Jedes Wrapper-Script setzt die passenden Parameter und ruft `Stop-LobsterService.ps1` auf.
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

#### Start-*.ps1 und Restart-*.ps1

**Status:** Platzhalter. Alle werfen aktuell den Fehler:
```
Invoke-LobsterStartup.ps1 fehlt.
```

Werden aktiviert sobald `Start-LobsterService.ps1` (analog zu Stop-LobsterService.ps1) implementiert ist.

| Script | Geplante Funktion |
|---|---|
| Start-Backend.ps1 | Backend-Dienst starten, wrapper.log auf "Started" pruefen |
| Start-Dmz.ps1 | DMZ-Dienst starten (lokal auf DMZ-Host) |
| Start-BackendAndDmz.ps1 | Backend + DMZ starten (orchestriert) |
| Restart-Backend.ps1 | Backend stoppen + starten |
| Restart-Dmz.ps1 | DMZ stoppen + starten |
| Restart-BackendAndDmz.ps1 | DMZ + Backend stoppen + starten |
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

## Ausfuehrungsmodi (GUI)

| Modus | Beschreibung |
|---|---|
| **Automatisch** | API erstellt Task, prueft ihn und sendet Mail – vollautomatisch. API muss laufen. |
| **Manuell** | Zeigt Programm + Argumente die man im Task Scheduler als Aktion hinterlegt. |
| **Schritt fuer Schritt** | Jeden Schritt einzeln pruefen und bestaetigen. |

---

## Voraussetzungen

- **Client:** Windows 10/11, PowerShell 5.1, moderner Browser
- **Remote-Server:** WinRM aktiviert, PowerShell Remoting erlaubt
- **Netzwerk:** Zugriff auf Remote-Hosts via WinRM (Port 5985/5986)

## Technische Details

- GUI: Standalone HTML/JS, kein Build-Prozess
- API: `System.Net.HttpListener` auf Port 8765
- Auth: SHA256-Passwort-Hashing, Bearer-Token Sessions (12h Gueltigkeit)
- Encoding: Alle PS-Skripte verwenden UTF-8 BOM (PowerShell 5.1 Kompatibilitaet)
- Pfade: Relativ ueber `$PSScriptRoot` aufgeloest
- Wrapper-Log-Regex: `STATUS | wrapper | YYYY/MM/DD HH:mm:ss | <-- Wrapper Stopped`
