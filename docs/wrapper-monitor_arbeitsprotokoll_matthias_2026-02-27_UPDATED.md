# Wrapper-Monitor / Maintenance-Scripts – Arbeitsprotokoll & Zusammenfassung (Stand: 27.02.2026)

Dieses Dokument fasst zusammen, **was wir bisher gemeinsam gemacht haben**, was ich am Paket **analysiert habe**, welche **Anpassungen** entstanden sind, welche **Downloads** erzeugt wurden und welche **Fehler** aktuell auftreten.

---

## 0) Ziel (was du erreichen willst)

- **Produktiv** ein Script ausführen, das:
  1) die produktive `wrapper.log` **liest/prüft** (Logcheck),
  2) optional **Windows-Dienst stoppen** (später: auch Start/Stop via REST API),
  3) optional **Mail versenden** (Report/Status).

- Zusätzlich: eine **Console-“GUI” (Wizard)**, die Schritt-für-Schritt fragt und
  - **nur den finalen Aufruf ausgibt** (print-only) oder später optional ausführt.

---

## 1) Analyse des ursprünglichen Pakets (Was macht was?)

### 1.1 Kernlogik: `Invoke-LobsterDataWrapperLogCheck.ps1`
- **Hauptfunktion**: prüft die `wrapper.log`, ob der Wrapper „gestoppt“ ist.
- Sucht u.a. nach:
  - Eintrag **„Wrapper Stopped“** am **heutigen Datum**
  - Zeitlich **nahe am Script-Start** (Toleranz)
  - „Stopped“ ist **letzter relevanter Eintrag** (sonst Warnung)
  - Fehlerfall: „Stopped“ und danach sofort wieder **„Started“** → Error
- Macht mehrere **Re-Reads** (Polling): `MaxAttempts` mit Sleep zwischen den Versuchen.

### 1.2 Helper: `LobsterDataWrapperLogCheck-Helpers.ps1`
- Enthält Hilfsfunktionen: Tail lesen, Regex/Pattern, Timestamp parse, OK/WARN/ERROR-Logik.

### 1.3 Produktiver Entry: `Run-LobsterDataMaintenance.cmd` + `Invoke-LobsterDataMaintenanceRunner.ps1`
- Dieser “Prod Runner” führt im Wesentlichen **nur den WrapperLogCheck** aus.
- Er ist **nicht** der volle Wartungsablauf (Service stop + Mail etc.).

### 1.4 Workflow: `Invoke-LobsterDataMaintenance.ps1` (größerer Ablauf)
- Gedacht als Orchestrierung:
  - (Remote) Dienst stoppen + Logcheck remote
  - Placeholder: Backend Stop via Webservice
  - lokal: Logcheck
  - optional: Mail
- In der ursprünglichen Variante gab es **Hardcoded Credentials** (Security-Risiko).

### 1.5 Mail: `Send-LobsterDataMaintenanceNotification.ps1` / `Mail.ps1`
- Baut HTML-Mail (mit Tabellen + Logzeilen) und sendet per SMTP.

### 1.6 Test-Harness: `Testenviremnt\...`
- Testcases, die wrapper.log kopieren/verschieben und Timestamps shiften.

---

## 2) Was du „produktiv“ ausführen wolltest (und wie)

### 2.1 Runner-Aufruf (nur Logcheck; kein Mail)
Aus PowerShell im Paketordner:
```powershell
.\Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"
```
Wichtig: In PowerShell muss man `.\` verwenden (weil PS nicht automatisch aus dem current dir ausführt).

### 2.2 Frage: Zeitintervalle für Re-Read
- Nicht als Parameter am `.cmd`, sondern über die Config:
  - `MaxAttempts`
  - `AttemptSleepSeconds_Prod`
  - `RecheckSleepSeconds_Prod`

---

## 3) Feature-Umbaus (deine Anforderungen)

### 3.1 „Nicht stoppen, nur Log lesen + Mail senden“
Du wolltest: Dienststop **unterbinden** können, aber trotzdem Logcheck + Mail.

→ Wir haben begonnen, `Invoke-LobsterDataMaintenance.ps1` so zu ändern, dass es **Local** auch direkt mit `-LogPath` kann und `-StopMode None` akzeptiert.

### 3.2 Auswahl Stop-Methode: REST API vs Windows Dienst (REST = Placeholder)
Du wolltest:
1) Auswahl **REST API** oder **Windows Dienst**
2) REST API ist noch nicht implementiert → **soll abbrechen** mit Hinweis „nicht verfügbar“.

→ Wir haben Parameter eingeführt/angedacht:
- `-StopMode None | WindowsService | RestApi`
- Verhalten bei `RestApi`: Abbruch mit klarer Meldung.

### 3.3 Windows Dienst: Local vs Remote
Du wolltest bei Windows Dienst:
- zusätzlich: **Local** oder **Remote**.

→ Parameter/Logik:
- `-ServiceScope Local | Remote`

### 3.4 Wizard / Console-GUI
Du wolltest einen Wizard, der Punkt für Punkt fragt:
- Read-only vs Start/Stop
- Start = Placeholder “nicht verfügbar”
- Stop → REST API = Placeholder “nicht verfügbar”
- Stop → Windows Dienst → Local/Remote
- Read-only → Local/Remote
- danach Parameter abfragen
- **als erster Schritt nur Aufruf ausgeben**, Script NICHT starten

→ Dafür wurde ein Wizard-Script erstellt: `Run-LobsterDataMaintenanceWizard.ps1`

### 3.5 Zusätzliche Abfrage: Windows Dienstname
Du wolltest bei Windows Dienst zusätzlich:
- welchen **Dienstnamen** man stoppen will.

→ Dafür wurde ergänzt:
- `-ServiceName "<Dienstname>"` (Pflicht bei StopMode=WindowsService)
- Wizard fragt `ServiceName`.

---

## 4) Downloads / Artefakte die erzeugt wurden

> Hinweis: Manche ZIPs waren Zwischenstände/Hotfixes (Fix1/Fix2/…).

- `wrapper-monitor-final-packet-v20_skip-service-stop.zip`  
  → Erste Anpassung: Service-Stop überspringen.

- `wrapper-monitor-final-packet-v20_maintenance-updated-v2.zip`  
  → Maintenance-Script erweitert (StopMode/ServiceScope + Interactive).

- `wrapper-monitor-final-packet-v20_maintenance-updated-v2_with-gui-launcher.zip`  
  → Enthielt zusätzlich GUI-Launcher:
  - `Run-LobsterDataMaintenanceGui.ps1`
  - `Run-LobsterDataMaintenanceGui.cmd`

- `wrapper-monitor-final-packet-v20_wizard-print-only.zip`  
  → Wizard (print-only).

- `wrapper-monitor-final-packet-v20_wizard-print-only_fix1.zip`  
  → Fix: Backtick/Quote Parserfehler (erste `$pretty` Zeile).

- `wrapper-monitor-final-packet-v20_wizard-print-only_fix2.zip`  
  → Fix: weiterer Backtick/Quote Parserfehler im `-SendNotification` Pretty-Block.

- `wrapper-monitor-maintenance_wizard-and-maintenance-selfcontained.zip`  
  → Umbau: Wizard-Ausgabe soll als Aufruf direkt passen; Maintenance-Script nimmt Local `-LogPath`.

- `wrapper-monitor-maintenance_wizard-and-maintenance-selfcontained_v2_servicename.zip`  
  → Erweiterung: `-ServiceName` (Wizard fragt Dienstname, Maintenance-Script validiert).

- `wrapper-monitor-maintenance_selfcontained_v3_mail-fix.zip`  
  → Fix: Mail-Funktion nutzte `[System.Web.HttpUtility]` (in PS7 oft nicht verfügbar). Umgestellt auf `[System.Net.WebUtility]`.

- `wrapper-monitor-maintenance_selfcontained_v4_wizard-fix.zip` / `v5_wizard-fix2.zip`  
  → Fixes: Prompt-String Escaping / Quotes im Wizard.

---

## 5) Fehler, die aufgetreten sind (und Fixes)

### 5.1 PowerShell: `.cmd` ohne `.\`
**Fehler:**
> `Run-LobsterDataMaintenance.cmd : The term ... is not recognized ...`

**Fix:**
```powershell
.\Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"
```

### 5.2 Mail: `Unable to find type [System.Web.HttpUtility]`
**Fehler:**
> `Send-NotificationMail : Unable to find type [System.Web.HttpUtility].`

**Ursache:**
- In vielen Umgebungen (PowerShell 7 / Core) ist `System.Web` nicht geladen/verfügbar.

**Fix:**
- Umstellung auf:
  - `[System.Net.WebUtility]::HtmlEncode`
  - `[System.Net.WebUtility]::UrlEncode`

### 5.3 Wizard Parserfehler (Backtick/Quote)
**Fehlerklassen:**
- Backtick am Ende eines Double-Quote Strings → escaped das closing `"` → Parser kaputt.

**Fixes:**
- Pretty-Ausgabezeilen mit Single Quotes oder ohne kritische Backticks im String.

### 5.4 Wizard Prompt Escaping `\"`
**Fehler:**
- PowerShell kennt `\"` nicht als Escape, daher werden Strings zerschnitten.

**Fix:**
- Prompt-Strings mit **Single Quotes** (und ggf. `"` innen ohne Escape).

---

## 6) Aktueller Fehler / aktuelles Verhalten (Status jetzt)

### 6.1 Wizard fragt bei „Nur Read“ direkt `ComputerName`
Aktuelles Verhalten:
- Du wählst:
  - `1) Nur Read (Log durchlesen + optional Mail)`
- Trotzdem kommt direkt:
  - `ComputerName (...)`

Erwartet wäre:
- nach „Nur Read“ zuerst:
  - `10) Read only: Lokal oder Remote?`
- und erst dann bei Remote:
  - `ComputerName ...`

### 6.2 Was wir dazu schon geprüft haben
Du hast geprüft:
```powershell
Select-String -Path .\Run-LobsterDataMaintenanceWizard.ps1 -Pattern '10\) Read only' -Context 0,2
Get-Item .\Run-LobsterDataMaintenanceWizard.ps1 | Select Name,Length,LastWriteTime
```
Ergebnis:
- die Datei enthält die Zeile:
  - `$scope = Read-Choice -Title "10) Read only: Lokal oder Remote?" ...`
- File-Länge: ~6322 Bytes
- LastWriteTime: 27.02.2026 10:58:42

**Trotzdem** scheint die Ausführung in den Remote-Zweig zu springen.

### 6.3 Nächster Schritt (für Debug)
(noch nicht umgesetzt in Code, nur als Vorschlag)
- Debug-Ausgabe direkt nach der Moduswahl:
  - `mode=[...]`
  - `mode-like-StartStop=...`
um zu sehen, ob `$mode` unerwartet als Start/Stop interpretiert wird.

---

## 7) Was am Ende “die Soll-CLI” war

Local Read + Mail (gewünscht):
```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -LogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -StopMode None `
  -SendNotification `
  -NotifyMailTo "matthias.haas@quehenberger.com"
```

Remote (Beispiel):
```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -ComputerName "aqlbt101.bmlc.local" `
  -RemoteProjectPath "<PFAD_AM_DMZ_ZUM_PAKETORDNER>" `
  -RemoteLogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -StopMode None `
  -SendNotification `
  -NotifyMailTo "matthias.haas@quehenberger.com"
```

WindowsService Stop (zusätzlich ServiceName):
```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -ComputerName "aqlbt101.bmlc.local" `
  -RemoteProjectPath "<PFAD_AM_DMZ_ZUM_PAKETORDNER>" `
  -RemoteLogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -StopMode WindowsService `
  -ServiceScope Remote `
  -ServiceName "LobsterIntegrationServer" `
  -SendNotification `
  -NotifyMailTo "matthias.haas@quehenberger.com"
```

---

## 8) Offene Punkte / ToDos

1) Wizard-Logik final stabilisieren:
   - nach „Nur Read“ muss **immer** die Local/Remote-Frage kommen
   - dann erst Parameter erfragen

2) Konsistenz der Parameter zwischen Wizard-Ausgabe und Maintenance-Script:
   - Local: `-LogPath` muss gehen
   - Remote: `-ComputerName`, `-RemoteProjectPath`, `-RemoteLogPath`
   - StopMode/ServiceScope/ServiceName sauber validieren

3) Placeholder-Flows:
   - Start Lobster: Meldung + umwählen/abbrechen
   - Stop via REST API: Meldung + umwählen/abbrechen

4) Encoding (Umlaute):
   - In deiner Ausgabe stand „fliegt spÃ¤ter…“ → Script-Datei/Console Encoding prüfen (UTF-8 vs OEM).

---

## 9) Aktuelle Fehlermeldung (wörtlich, zur Doku)
```
1) Was soll gemacht werden?
  1) Nur Read (Log durchlesen + optional Mail)
  2) Start/Stop Lobster Instanz (optional, fliegt spÃ¤ter evtl. raus)
Modus (1-2): 1
ComputerName (z.B. aqlbt101.bmlc.local): Das sollte da ja nicht kommen schon an der Stelle oder?
```

---

_Ende_

---
## 10) Hotfix 27.02.2026 – Wizard fragt bei „Nur Read“ fälschlich nach ComputerName

**Ursache:** In `Run-LobsterDataMaintenanceWizard.ps1` war die Read-only Scope-Abfrage (`10) Read only: Lokal oder Remote?`) versehentlich **im** `if ($mode -like "Start/Stop*")`-Block gelandet und `$serviceName` wurde danach wieder auf `$null` gesetzt.

**Fix:**
- Read-only Scope-Abfrage in einen `else`-Zweig verschoben.
- `$serviceName` sauber initialisiert und **nicht** mehr überschrieben.

Damit kommt nach Auswahl **„1) Nur Read“** wieder zuerst die Frage **Local/Remote** und `ComputerName` nur noch bei **Remote**.

---
## 11) Hotfixes 27.02.2026 – Invoke-LobsterDataMaintenance.ps1: Parser/Param + Mail + StartupType

### 11.1 Parser-Fehler beim direkten Aufruf
Symptom: PowerShell ParserError („Missing expression after ','“, „Unexpected token '`r`n'“, „Duplicate parameter $ServiceName“).

Fix:
- `param(...)`-Block bereinigt (keine kaputten Zeilenumbrüche/Kommas)
- `Invoke-Command { param(...) }` ohne doppelte Parameternamen

### 11.2 Mail-Funktion überschreibt Built-in Variable `$Host`
Symptom: `Cannot overwrite variable Host because it is read-only or constant.`

Fix:
- Parameter/Variable `$Host` bzw. `$host` umbenannt (PowerShell ist case-insensitive)

### 11.3 WindowsService Stop: StartupType auf Manual setzen + in Mail ausweisen
Anforderung:
- Nach erfolgreichem Stop den Dienst-Starttyp von **Automatisch** auf **Manuell** umstellen
- In der Mail sichtbar machen, dass das passiert ist

Fix:
- Nach Stop-Service wird `Set-Service -StartupType Manual` ausgeführt (local + remote)
- Results/Mail enthält jetzt einen eigenen Step „SetStartupType … Manual …“

### 11.4 WindowsService Stop schlug fehl obwohl ServiceName korrekt
Symptom:
- `Cannot open ... service on computer '.'` bei lokalem Stop

Ursache:
- fehlende Rechte (Service Control), nicht der Name

Fix/Handling:
- Hinweis: PowerShell **als Administrator** starten bzw. Task „Mit höchsten Privilegien“

---
## 12) Erweiterung 27.02.2026 – Start-Flow analog zu Stop (ohne Webservice-Requests)

Anforderung:
- Starten des Dienstes mit Vorab-Check: wenn bereits Running, dann nicht nochmal starten
- Starttyp von **Manuell** zurück auf **Automatisch** setzen
- Wrapper-Log prüfen auf:
  `Integration Server (IS) started ... system is ready...`
- getrennte Konfig (Start dauert anders als Stop)

Umsetzung:
- `Invoke-LobsterDataMaintenance.ps1` unterstützt jetzt `-Action Read|Stop|Start`
- Stop-Flow: Stop + StartupType Manual + Log-Polling
- Start-Flow: StartupType Automatic + (optional) Start + Log-Polling
- Config getrennt in `StopConfig` und `StartConfig` (Timeout/Intervall/Pattern)
- Wizard erzeugt die passenden Aufrufe für Read/Stop/Start

---
_Ende (Update)_
