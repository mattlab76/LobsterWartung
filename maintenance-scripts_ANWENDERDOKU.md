# Wrapper-Monitor / LobsterData Maintenance – Anwenderdokumentation

Stand: 27.02.2026 (Paket: `maintenance-scripts`)

Diese Doku beschreibt die **Benutzung** der Skripte (aus Anwendersicht). Keine Entwicklungs-/Code-Doku.

---

## 1. Wofür ist das Paket gedacht?

Das Paket automatisiert typische **Wartungs-Abläufe** rund um den *Lobster Integration Server* (Windows-Dienst) und dessen **`wrapper.log`**:

- **Log lesen & bewerten** (Read-only)
- **Dienst stoppen** (optional local/remote) + **über wrapper.log verifizieren**
- **Dienst starten** (optional local/remote) + **über wrapper.log verifizieren**
- Optional: **Mailbenachrichtigung** (INFO/WARN/ERROR)
- Beim **Stop** wird der **Starttyp auf „Manuell“** gesetzt
- Beim **Start** wird der **Starttyp auf „Automatisch“** gesetzt

---

## 2. Voraussetzungen

- Windows mit PowerShell (typisch: Windows PowerShell 5.1)
- Leserechte auf die `wrapper.log`
- Für Mailversand: Erreichbarkeit des SMTP-Servers
- Für Stop/Start/StartupType:
  - PowerShell **als Administrator** starten (oder Task „Mit höchsten Privilegien“)
  - Berechtigungen, den Windows-Dienst zu steuern
- Für Remote-Funktionen (falls verwendet):
  - Netzwerk/Firewall erlaubt Zugriff
  - WinRM/Remoting verfügbar
  - Berechtigungen, remote Dienst/Log zu verwenden

---

## 3. Wichtig: Dienstname

Für `Stop-Service`/`Start-Service` wird der **Service-Name** verwendet. In eurem Fall ist er identisch mit dem DisplayName:

- **Name:** `Lobster Integration Server`
- **DisplayName:** `Lobster Integration Server`

Prüfen kannst du das so:

```powershell
Get-Service -DisplayName "Lobster Integration Server" | Select-Object Name, DisplayName, Status
```

---

## 4. Ordnerstruktur (wichtigste Dateien)

- **`Run-LobsterDataMaintenance.cmd`**  
  Produktiv-Entry-Point (für Scheduled Task geeignet). Erwartet 1 Parameter: Pfad zur `wrapper.log`.

- **`Invoke-LobsterDataMaintenanceRunner.ps1`**  
  Runner, der die Produktiv-Config lädt, eine Runtime-Config schreibt und die Log-Prüfung ausführt.

- **`Invoke-LobsterDataWrapperLogCheck.ps1`**  
  Zentrale Log-Prüfung (wertet die `wrapper.log` aus und liefert Exit-Codes).

- **`Invoke-LobsterDataMaintenance.ps1`**  
  „All-in-one“ Script für **Read/Stop/Start** (local/remote) + optional Mail. Das ist auch das Script, das der Wizard ausgibt.

- **`Run-LobsterDataMaintenanceWizard.ps1`** (+ `.cmd`)  
  Interaktiver Wizard, der **nur den Aufruf erzeugt** (er führt ihn nicht aus).

- Config:
  - **`lobsterdata.maintenance.prod.config.psd1`** (Produktivwerte)
  - **`lobsterdata.maintenance.config.psd1`** (Testwerte)
  - **`runtime\config-runtime.psd1`** (wird vom Runner erzeugt/überschrieben)

---

## 5. Schnellstart (empfohlen)

### 5.1 Produktiv: Read-only (einmalig)

Im Paketordner:

```powershell
.\Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"
```

Das ist der **empfohlene Standardweg** (robust + für Scheduled Task geeignet).

---

## 6. Wizard benutzen (interaktiv) – erzeugt nur den Befehl

Wizard starten:

```powershell
.\Run-LobsterDataMaintenanceWizard.ps1
```

Der Wizard fragt u.a.:
- Modus: **Read / Stop / Start**
- Scope: **Local / Remote**
- LogPath
- Mail (ja/nein) und Empfänger

Am Ende zeigt der Wizard:
- einen **mehrzeiligen PowerShell-Aufruf** (mit Backticks)
- einen **One-liner**

➡️ Den ausgegebenen Befehl kopierst du und führst ihn danach selbst aus.

---

## 7. Direkter PowerShell-Aufruf (Invoke-LobsterDataMaintenance.ps1)

### 7.1 Read-only (Local)

```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -Action Read `
  -LogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -SendNotification `
  -NotifyMailTo "matthias.haas@quehenberger.com"
```

Ohne Mail:

```powershell
.\Invoke-LobsterDataMaintenance.ps1 -Action Read -LogPath "D:\Lobster_data\IS\logs\wrapper.log"
```

### 7.2 Stop (Local) + StartupType → Manual + Log-Verifikation

> PowerShell als **Administrator** starten.

```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -Action Stop `
  -StopMode WindowsService `
  -ServiceName "Lobster Integration Server" `
  -ServiceScope Local `
  -LogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -SendNotification `
  -NotifyMailTo "matthias.haas@quehenberger.com"
```

Was passiert:
- Dienst wird gestoppt
- Starttyp wird auf **Manuell** gesetzt
- `wrapper.log` wird **gepollt**, bis das Stop-Kriterium gefunden wurde oder Timeout erreicht ist
- Mail enthält die einzelnen Schritte (inkl. „StartupType gesetzt auf Manual“)

### 7.3 Start (Local) + Vorab-Check + StartupType → Automatic + Log-Verifikation

> PowerShell als **Administrator** starten.

```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -Action Start `
  -StopMode WindowsService `
  -ServiceName "Lobster Integration Server" `
  -ServiceScope Local `
  -LogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -SendNotification `
  -NotifyMailTo "matthias.haas@quehenberger.com"
```

Was passiert:
- Starttyp wird auf **Automatisch** gesetzt
- Wenn der Dienst bereits **Running** ist: **kein Start** (nur Info + Logcheck)
- Wenn nicht Running: Dienst wird gestartet
- `wrapper.log` wird **gepollt**, bis das Start-Kriterium gefunden wurde oder Timeout erreicht ist
- Mail enthält die einzelnen Schritte (inkl. „StartupType gesetzt auf Automatic“)

### 7.4 Remote (Read/Stop/Start)

Remote-Aufruf ist analog, aber mit:
- `-ComputerName`
- `-RemoteProjectPath`
- `-RemoteLogPath`
- `-ServiceScope Remote`

Beispiel **Remote Start**:

```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -Action Start `
  -ComputerName "aqlbt101.bmlc.local" `
  -RemoteProjectPath "D:\Pfad\maintenance-scripts" `
  -RemoteLogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -StopMode WindowsService `
  -ServiceName "Lobster Integration Server" `
  -ServiceScope Remote `
  -SendNotification `
  -NotifyMailTo "team@domain.tld"
```

---

## 8. Log-Kriterien (Start/Stop)

Die relevanten Log-Kriterien sind in der Config hinterlegt.

### Start-Kriterium (Beispiel aus eurer Logdatei)

Es wird auf eine Zeile dieser Art geprüft:

```text
INFO   | jvm 1    | 2026/02/27 13:14:50 | Integration Server (IS) started in 199605 ms, system is ready...
```

### Stop-Kriterium
Das Stop-Kriterium bleibt wie bisher (in der Config definiert) und wird ebenfalls über Polling verifiziert.

---

## 9. Getrennte Config für Stop vs. Start (unterschiedliche Dauer)

Es gibt zwei getrennte Bereiche in der Config:

- `StopConfig`  → Timeout/Intervall/Kriterien für **Stop**
- `StartConfig` → Timeout/Intervall/Kriterien für **Start**

Grund: Stop und Start dauern unterschiedlich lang.

Du passt diese Werte in **`lobsterdata.maintenance.prod.config.psd1`** (Produktiv) oder **`lobsterdata.maintenance.config.psd1`** (Test) an.

---

## 10. Mailbenachrichtigung

Aktivieren per:
- `-SendNotification`
- `-NotifyMailTo "empfaenger@domain.tld"`

Standardwerte (wenn nicht überschrieben):
- SMTP Server: `smtp.cust.bmlc.local`
- From: `noreply@quehenberger.com`

Override (optional):

```powershell
.\Invoke-LobsterDataMaintenance.ps1 `
  -Action Read `
  -LogPath "D:\Lobster_data\IS\logs\wrapper.log" `
  -SendNotification `
  -NotifyMailTo "team@domain.tld" `
  -NotifySmtpServer "smtp.server.local" `
  -NotifyMailFrom "noreply@domain.tld"
```

Die Mail enthält (je nach Modus) die einzelnen ausgeführten Schritte, z.B.:
- Stop/Start-Service
- SetStartupType (Manual/Automatic)
- Wrapper-Logcheck (found/not found + Dauer)

---

## 11. Ergebnis verstehen (Konsole / Exit-Code)

Die Log-Prüfung liefert ein Ergebnislevel:
- **OK** → ExitCode **0**
- **WARN** → ExitCode **1**
- **ERROR** → ExitCode **2**
- Technischer Fehler (z.B. Log nicht gefunden) → typischerweise ExitCode **99**

---

## 12. Scheduled Task (Windows Aufgabenplanung)

Beispiel (Read-only) – Programm/Argumente:

- Programm: `C:\Windows\System32\cmd.exe`
- Argumente:
  ```text
  /c "D:\Pfad\wrapper-monitor\Run-LobsterDataMaintenance.cmd" "D:\Lobster_data\IS\logs\wrapper.log"
  ```
- „Starten in“: `D:\Pfad\wrapper-monitor\`

Empfehlung:
- „**Mit höchsten Privilegien ausführen**“ (wenn Zugriff auf Log/Dienst nötig ist)

