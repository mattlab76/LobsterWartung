# Lobster Scheduler Manager

Webbasiertes Tool zur automatisierten Wartungssteuerung von Lobster-Servern via Windows Task Scheduler.

## Komponenten

| Komponente | Beschreibung |
|---|---|
| `LobsterSchedulerManager.html` | Single-Page GUI (im Browser oeffnen) |
| `Start-SchedulerManagerAPI.ps1` | Lokale PowerShell REST-API (Port 8765) fuer den Auto-Modus |
| `deployment/` | Scripts fuer die Remote-Server |

## Schnellstart

### 1. GUI oeffnen

`LobsterSchedulerManager.html` direkt im Browser oeffnen. Alle Einstellungen werden im Browser (localStorage) gespeichert.

### 2. API starten (optional, fuer Auto-Modus)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
powershell -ExecutionPolicy Bypass -File Start-SchedulerManagerAPI.ps1
```

Die API laeuft auf `http://localhost:8765` und wird im Header der GUI als "API Online" angezeigt.

**Beenden:** Im Konsolenfenster `CTRL+C` druecken oder Fenster schliessen.

### 3. Ersteinrichtung in der GUI

1. **Einstellungen** Tab oeffnen
2. **Benutzer**: Name und Unternehmen eintragen
3. **Backend Hosts / DMZ Hosts**: Server-Hostnamen hinzufuegen
4. **Mail-Einstellungen**: SMTP-Server und Absender konfigurieren
5. **Standard-Werte**: Remote-Benutzername (DOMAIN\User) setzen

## Deployment auf den Servern

Die Scripts muessen auf jedem Lobster-Server bereitgestellt werden.

### Ordnerstruktur

Waehle einen Root-Ordner auf dem Server (z.B. `D:\EDI\maintenance-scripts`) und kopiere die Ordner `scripts\` und `shared\` hinein:

```
D:\EDI\maintenance-scripts\          <-- Root-Ordner (in GUI als "PS-Skript Root-Pfad" angeben)
  +-- scripts\
  |     Stop-Backend.ps1
  |     Stop-BackendAndDmz.ps1
  |     Stop-BackendViaWebserviceAndDmzService.ps1
  |     Stop-Dmz.ps1
  |     Start-Backend.ps1
  |     Start-BackendAndDmz.ps1
  |     Start-Dmz.ps1
  |     Restart-Backend.ps1
  |     Restart-BackendAndDmz.ps1
  |     ...
  +-- shared\
  |     Send-MaintenanceMail.ps1
  +-- Stop-LobsterService.ps1        <-- Kern-Script (wird von scripts\*.ps1 aufgerufen)
```

### Kopierbefehl (von diesem Repo)

```powershell
$ziel = "\\SERVERNAME\D$\EDI\maintenance-scripts"

# Scripts-Ordner
robocopy "deployment\scripts" "$ziel\scripts" /MIR

# Shared-Ordner
robocopy "deployment\shared" "$ziel\shared" /MIR

# Kern-Script
Copy-Item "deployment\Stop-LobsterService.ps1" "$ziel\Stop-LobsterService.ps1"
```

## Ausfuehrungsmodi

Im Schritt 2 (Zusammenfassung) stehen drei Modi zur Wahl:

| Modus | Beschreibung |
|---|---|
| **Automatisch** | API erstellt Task, prueft ihn und sendet Mail -- alles vollautomatisch. Setzt laufende API voraus. |
| **Manuell** | Zeigt Programm und Argumente an, die man im Task Scheduler (taskschd.msc) als Aktion hinterlegt. |
| **Schritt fuer Schritt** | Jeden Schritt einzeln pruefen und bestaetigen (mit oder ohne API). |

### Manueller Modus -- Task Scheduler Aktion

Wenn der manuelle Modus gewaehlt wird, zeigt die GUI:

- **Programm/Skript:** `powershell.exe`
- **Argumente:** `-ExecutionPolicy Bypass -NonInteractive -File "D:\EDI\maintenance-scripts\scripts\Stop-Backend.ps1" -MaxWaitSeconds 300 -PollIntervalSeconds 15`

Diese Werte im Windows Task Scheduler unter **Aktion** > **Programm/Script** und **Argumente hinzufuegen** eintragen.

## Script-Zuordnungen

Die GUI ordnet automatisch das passende Script anhand von Wartungstyp und Instanz-Typ zu. Die Zuordnungen koennen unter **Einstellungen** > **Script-Zuordnungen** angepasst werden.

Standard-Zuordnungen:

| Wartungstyp | Instanz Typ | Script |
|---|---|---|
| Stop-Lobster | Backend | `scripts\Stop-Backend.ps1` |
| Stop-Lobster | Backend und DMZ | `scripts\Stop-BackendAndDmz.ps1` |
| Stop-Lobster | Backend und DMZ (via Webservice) | `scripts\Stop-BackendViaWebserviceAndDmzService.ps1` |
| Stop-Lobster | DMZ | `scripts\Stop-Dmz.ps1` |
| Start-Lobster | Backend | `scripts\Start-Backend.ps1` |
| Start-Lobster | Backend und DMZ | `scripts\Start-BackendAndDmz.ps1` |
| ... | ... | ... |

## Voraussetzungen

- **Client (GUI + API):** Windows 10/11, PowerShell 5.1, moderner Browser
- **Remote-Server:** WinRM aktiviert, PowerShell Remoting erlaubt
- **Netzwerk:** Zugriff auf Remote-Hosts via WinRM (Port 5985/5986)

## Technische Details

- GUI: Standalone HTML/JS, kein Build-Prozess noetig
- API: `System.Net.HttpListener` auf Port 8765
- Alle PS-Skripte verwenden UTF-8 BOM Encoding (PowerShell 5.1 Kompatibilitaet)
- Pfade werden relativ ueber `$PSScriptRoot` aufgeloest
