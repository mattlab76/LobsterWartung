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
      Stop-Backend.ps1                 Stoppt Backend-Dienst (Windows-Service)
      Stop-Dmz.ps1                     Stoppt DMZ-Dienst (laeuft auf DMZ-Host)
      Stop-BackendAndDmz.ps1           Stoppt DMZ + Backend (orchestriert, Windows-Dienste)
      Stop-BackendViaWebserviceAndDmzService.ps1
                                       Stoppt Backend via REST-API, DMZ via Windows-Dienst
      Stop-Backend-Webservice.ps1      Stoppt Backend via Lobster-Webservice-URL
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
      Send-MaintenanceMail.ps1         Mail-Helper (Send-MaintenanceMail, New-MaintenanceMailBody)
```

## Schnellstart

### 1. API starten

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser   # einmalig
powershell -ExecutionPolicy Bypass -File Start-SchedulerManagerAPI.ps1
```

Beim ersten Start wird `users.json` mit dem Default-User **admin** (Passwort: **admin**) angelegt.

**Beenden:** `CTRL+C` im Konsolenfenster oder Fenster schliessen.

### 2. GUI oeffnen

`LobsterSchedulerManager.html` im Browser oeffnen und mit **admin / admin** anmelden.
Beim ersten Login muss das Passwort geaendert werden.

### 3. Ersteinrichtung

1. **Einstellungen** > **Benutzerverwaltung**: Weitere Benutzer anlegen (nur als Admin)
2. **Backend Hosts / DMZ Hosts**: Server-Hostnamen hinzufuegen
3. **Mail-Einstellungen**: SMTP-Server und Absender konfigurieren
4. **Standard-Werte**: Remote-Benutzername (DOMAIN\User) und PS-Skript Root-Pfad setzen

## Benutzerverwaltung

Die Authentifizierung erfolgt ueber die API (`users.json`, SHA256-Passwort-Hashing).

| Funktion | Zugriff |
|---|---|
| Login / Logout | Alle |
| Eigenes Passwort aendern | Alle (unter Einstellungen) |
| Benutzer anlegen / loeschen | Nur Admin |
| Passwort zuruecksetzen | Nur Admin |

Neue Benutzer erhalten ihr **Benutzername als initiales Passwort** und muessen es beim ersten Login aendern.

## Deployment auf den Servern

### Ordnerstruktur

Waehle einen Root-Ordner auf dem Server (z.B. `D:\EDI\maintenance-scripts`) und kopiere die drei Unterverzeichnisse hinein:

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

# Alles auf einmal
robocopy "deployment" "$ziel" /E /MIR
```

Oder einzeln:

```powershell
robocopy "deployment\scripts" "$ziel\scripts" /MIR
robocopy "deployment\shared"  "$ziel\shared"  /MIR
Copy-Item "deployment\Stop-LobsterService.ps1" "$ziel\Stop-LobsterService.ps1"
```

## PowerShell Scripts im Detail

### Stop-LobsterService.ps1 (Kern-Script)

Zentrale Logik fuer den Dienst-Stopp. Wird von allen `scripts\Stop-*.ps1` Wrappern aufgerufen.

**Funktionsweise:**
1. Setzt den Dienst-Starttyp auf **Manual** (verhindert automatischen Neustart)
2. Stoppt den Windows-Dienst
3. Pollt die `wrapper.log` auf das Muster **"Wrapper Stopped"** (konfigurierbare Wartezeit)
4. Validiert den Zeitstempel (innerhalb +/-5 Min Toleranz)
5. Prueft, ob der Dienst danach wieder gestartet wurde (Fehlerfall)
6. Sendet optional eine HTML-Mail mit dem Ergebnis

**Orchestrator-Modus** (Backend + DMZ):
- Stoppt zuerst den DMZ-Dienst remote via `Invoke-Command`
- Dann den lokalen Backend-Dienst
- Sendet eine kombinierte Mail mit allen Ergebnissen

### Wrapper-Scripts (deployment/scripts/)

Jedes Wrapper-Script setzt die richtigen Parameter und delegiert an `Stop-LobsterService.ps1`:

| Script | Beschreibung | Dienst-Stop via |
|---|---|---|
| `Stop-Backend.ps1` | Nur Backend stoppen | Windows-Dienst |
| `Stop-Dmz.ps1` | Nur DMZ stoppen (laeuft lokal auf DMZ-Host) | Windows-Dienst |
| `Stop-BackendAndDmz.ps1` | DMZ remote stoppen, dann Backend lokal | Windows-Dienst + Invoke-Command |
| `Stop-BackendViaWebserviceAndDmzService.ps1` | Backend via REST-API, DMZ via Dienst | Webservice-URL + Windows-Dienst |
| `Stop-Backend-Webservice.ps1` | Nur Backend via Webservice-URL | Webservice-URL |

### Send-MaintenanceMail.ps1 (shared/)

Stellt zwei Funktionen bereit:
- **`Send-MaintenanceMail`** -- Sendet eine Mail via SMTP
- **`New-MaintenanceMailBody`** -- Generiert einen HTML-Body mit Ergebnis-Tabelle (Schritte + Status)

### Start/Restart-Scripts (TODO)

Die Start- und Restart-Scripts sind als Platzhalter angelegt. Sie werfen aktuell einen Fehler:
`Invoke-LobsterStartup.ps1 fehlt.`

Sobald `Start-LobsterService.ps1` (analog zu `Stop-LobsterService.ps1`) implementiert ist,
koennen diese Scripts aktiviert werden.

## API-Endpunkte

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/ping` | Health-Check |
| POST | `/login` | Anmeldung (username, password) |
| POST | `/logout` | Abmeldung |
| GET | `/session` | Aktuelle Session pruefen |
| POST | `/change-password` | Eigenes Passwort aendern |
| GET | `/users` | Benutzerliste (nur Admin) |
| POST | `/users` | Benutzer anlegen (nur Admin) |
| DELETE | `/users/{name}` | Benutzer loeschen (nur Admin) |
| POST | `/reset-password` | Passwort zuruecksetzen (nur Admin) |
| POST | `/check-script` | Prueft ob Script auf Remote-Host existiert |
| POST | `/create-task` | Scheduled Task auf Remote-Host erstellen |
| POST | `/verify-task` | Scheduled Task pruefen |
| POST | `/send-mail` | Mail senden |

## Ausfuehrungsmodi

| Modus | Beschreibung |
|---|---|
| **Automatisch** | API erstellt Task, prueft ihn und sendet Mail -- vollautomatisch. API muss laufen. |
| **Manuell** | Zeigt Programm + Argumente, die man im Task Scheduler als Aktion hinterlegt. |
| **Schritt fuer Schritt** | Jeden Schritt einzeln pruefen und bestaetigen. |

## Voraussetzungen

- **Client:** Windows 10/11, PowerShell 5.1, moderner Browser
- **Remote-Server:** WinRM aktiviert, PowerShell Remoting erlaubt
- **Netzwerk:** Zugriff auf Remote-Hosts via WinRM (Port 5985/5986)

## Technische Details

- GUI: Standalone HTML/JS, kein Build-Prozess
- API: `System.Net.HttpListener` auf Port 8765
- Auth: SHA256-Passwort-Hashing, Bearer-Token Sessions (12h Gueltigkeit)
- Alle PS-Skripte verwenden UTF-8 BOM Encoding (PowerShell 5.1 Kompatibilitaet)
- Pfade werden relativ ueber `$PSScriptRoot` aufgeloest
