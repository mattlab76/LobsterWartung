# Session-Protokoll – 10.03.2026

## Was heute gemacht wurde

### 1. Architektur-Diskussion & Klärung

Wir haben die Architektur des gesamten Systems von Grund auf durchdacht:

**Lokal (Admin-PC):**
- `LobsterSchedulerManager.html` — Weboberfläche
- `Start-SchedulerManagerAPI.ps1` — lokaler HTTP-Listener (localhost:8765)
- Die lokale API macht **nur zwei Dinge**: Scheduled Task auf Remote-Host anlegen + Mail schicken dass der Task angelegt wurde

**Auf den Servern (Backend-Host + DMZ-Host):**
- Alle PowerShell-Scripts laufen **auf den Servern selbst**, nicht lokal
- Kein dauerndes Hin-und-Her während der Wartung
- Nur ein kleines Ergebnis-Objekt reist vom DMZ-Host zurück zum Backend-Host

---

### 2. Stop-Sequenz (Architektur)

```
Scheduled Task (Backend-Host, läuft zur Wartungszeit)
    │
    ├─► [1] Invoke-Command → DMZ-Host
    │         Script läuft LOKAL auf DMZ-Host:
    │         • Dienst stoppen
    │         • wrapper.log lokal lesen & prüfen
    │         • Nur { Ok, Message } zurückgeben
    │
    ├─► [2] Wenn DMZ OK:
    │         Backend-Dienst lokal stoppen
    │         wrapper.log lokal lesen & prüfen
    │
    └─► [3] Mail: Alles OK oder Fehler (mit Details beider Hosts)
```

**Vorteil:** Das komplette Log bleibt auf dem jeweiligen Host. Nur das Ergebnis (OK/Fehler + eine Zeile Text) geht über die Leitung.

---

### 3. Neues Deployment-Paket (`deployment/`)

Wird auf **Backend-Host** und **DMZ-Host** deployed (z.B. `C:\LobsterMaintenance\`):

```
deployment/
├── Invoke-LobsterShutdown.ps1        ← Kern-Script (auf beide Hosts)
├── shared/
│   └── Send-MaintenanceMail.ps1      ← Mail-Helper für alle Scripts
└── scripts/
    ├── Stop-BackendAndDmz.ps1        ✅ fertig
    ├── Stop-BackendAndDmz-Webservice.ps1  ✅ fertig
    ├── Stop-Backend.ps1              ✅ fertig
    ├── Stop-Backend-Webservice.ps1   ✅ fertig
    ├── Stop-Dmz.ps1                  ✅ fertig
    ├── Start-BackendAndDmz.ps1       ⏳ Platzhalter
    ├── Start-Backend.ps1             ⏳ Platzhalter
    ├── Start-Dmz.ps1                 ⏳ Platzhalter
    ├── Restart-BackendAndDmz.ps1     ⏳ Platzhalter
    ├── Restart-BackendAndDmz-Webservice.ps1  ⏳ Platzhalter
    ├── Restart-Backend.ps1           ⏳ Platzhalter
    ├── Restart-Backend-Webservice.ps1 ⏳ Platzhalter
    └── Restart-Dmz.ps1               ⏳ Platzhalter
```

#### `Invoke-LobsterShutdown.ps1` — zwei Modi

| Modus | Wann | Was passiert |
|-------|------|-------------|
| **Standalone / DMZ-Modus** | Kein `-DmzHost` Parameter | Stoppt lokalen Dienst, prüft wrapper.log lokal, gibt `{ Ok, Message }` zurück |
| **Orchestrator-Modus** | `-DmzHost` gesetzt | Ruft sich via `Invoke-Command` auf DMZ-Host auf → wartet auf Ergebnis → stoppt lokalen Backend-Dienst → Mail |

#### `Send-MaintenanceMail.ps1` — zwei Funktionen

- `Send-MaintenanceMail` — sendet HTML-Mail über SMTP
- `New-MaintenanceMailBody` — erstellt strukturierten HTML-Body mit Schritt-Tabelle (grün/rot je Schritt)

#### Wrapper-Scripts (`scripts/`)

Jedes Script ist ~15 Zeilen und ruft nur `Invoke-LobsterShutdown.ps1` mit den richtigen Parametern auf.
Neuer Wartungstyp = neuen Wrapper schreiben, fertig.

---

### 4. HTML — SCRIPT_MAP konfigurierbar

**Vorher:** SCRIPT_MAP war hardcodiert im JavaScript — neue Scripts erforderten HTML-Edit.

**Nachher:**
- `scriptMappings[]` liegt in `localStorage` als Array von `{ mt, it, script }` Objekten
- `defaultSettings()` enthält alle Standard-Zuordnungen als Startwerte
- Neuer Settings-Tab Bereich **"Script-Zuordnungen"** — Tabelle mit allen Einträgen, Add/Delete ohne HTML-Edit
- Die Dropdowns "Wartungstyp" und "Instanz Typ" im Formular befüllen sich dynamisch aus den gespeicherten Mappings
- Wenn Wartungstyp gewechselt wird, filtert der Instanz-Typ Dropdown automatisch die passenden Optionen
- `needsBackend(instanceType)` / `needsDmz(instanceType)` — prüfen per Regex ob "Backend" oder "DMZ" im Namen vorkommt → funktioniert automatisch für alle zukünftigen Instanz-Typen ohne Codeänderung

---

### 5. Repo-Aufräumung

- Alle alten Root-Stubs + CMD-Files → `tmp/` (historisch erhalten)
- `scripts/ui/` (alter Wizard) → `tmp/ui/`
- `scripts/core/` bleibt noch vorhanden (wird schrittweise durch `deployment/` ersetzt)

---

## Wie das System insgesamt funktioniert

### Gesamtübersicht

```
┌─────────────────────────────────────────────────────┐
│  Admin-PC (lokal)                                   │
│                                                     │
│  LobsterSchedulerManager.html                       │
│    • Formular ausfüllen (Wartungstyp, Host, Zeit)   │
│    • Start-Button → ruft lokale API                 │
│                                                     │
│  Start-SchedulerManagerAPI.ps1 (localhost:8765)     │
│    • POST /create-task  → Scheduled Task anlegen    │
│    • POST /verify-task  → Task prüfen               │
│    • POST /send-mail    → Bestätigungsmail senden   │
└──────────────────────┬──────────────────────────────┘
                       │ WinRM (Invoke-Command)
                       │ Task anlegen + verifizieren
                       ▼
┌─────────────────────────────────────────────────────┐
│  Backend-Host (Windows Server)                      │
│                                                     │
│  Scheduled Task (läuft zur Wartungszeit)            │
│    └─► deployment\scripts\Stop-BackendAndDmz.ps1   │
│          └─► Invoke-LobsterShutdown.ps1             │
│                │                                    │
│                │ Invoke-Command (WinRM)             │
│                ▼                                    │
│         ┌──────────────────────────────┐           │
│         │  DMZ-Host                    │           │
│         │  Invoke-LobsterShutdown.ps1  │           │
│         │  • Dienst lokal stoppen      │           │
│         │  • wrapper.log lokal prüfen  │           │
│         │  • { Ok, Message } zurück    │           │
│         └──────────────────────────────┘           │
│                │                                    │
│                ▼ (nur wenn DMZ OK)                  │
│          Backend-Dienst lokal stoppen               │
│          wrapper.log lokal prüfen                   │
│          Mail senden (OK oder Fehler)               │
└─────────────────────────────────────────────────────┘
```

### Formular-Logik (HTML)

1. **Wartungstyp** wählen (z.B. "Stop-Lobster")
2. **Instanz Typ** wählen (gefiltert auf passende Optionen, z.B. "Backend und DMZ")
3. → Script-Name wird **automatisch** aus den konfigurierbaren Script-Zuordnungen ermittelt
4. Restliche Felder ausfüllen (Host, Zeitpunkt, Credentials, Pfade)
5. **Start** → API legt Task an, prüft, schickt Bestätigungsmail

### Script-Zuordnungen (konfigurierbar)

Im Settings-Tab unter "Script-Zuordnungen" können jederzeit neue Mappings hinzugefügt werden:

| Wartungstyp | Instanz Typ | Script-Name |
|-------------|-------------|-------------|
| Stop-Lobster | Backend und DMZ | Stop-BackendAndDmz.ps1 |
| Stop-Lobster | DMZ | Stop-Dmz.ps1 |
| ... | ... | ... |
| **Eigenes-Script** | **Eigener-Typ** | **MeinScript.ps1** |

Neue Einträge erscheinen sofort in den Dropdowns — kein HTML-Edit nötig.

### Wrapper-Log Prüfung

`Invoke-LobsterShutdown.ps1` prüft den Java-Wrapper-Stop anhand des `wrapper.log`:
- Sucht nach `STATUS | wrapper | <Datum> HH:mm:ss | <-- Wrapper Stopped`
- Timestamp muss im ±5-Minuten-Fenster des Skriptstarts liegen
- `Wrapper Stopped` muss der **letzte** Eintrag im Log sein
- Fehler wenn danach ein `Wrapper Started` auftaucht (sofortiger Neustart)
- Polling alle 15 Sekunden, max. 300 Sekunden Wartezeit (konfigurierbar)

---

## Offene Punkte (nächste Schritte)

| # | Thema | Priorität |
|---|-------|-----------|
| 1 | `Invoke-LobsterStartup.ps1` schreiben (Start/Restart-Sequenz analog zu Shutdown) | Hoch |
| 2 | Backend via Webservice in `Invoke-LobsterShutdown.ps1` einbauen (`-WebserviceUrl`) | Mittel |
| 3 | Scripts auf Backend- und DMZ-Host deployen (`C:\LobsterMaintenance\`) | Hoch |
| 4 | `Start-SchedulerManagerAPI.ps1` produktiv testen (Auto-Modus End-to-End) | Hoch |
| 5 | `scripts/core/` endgültig entfernen (durch `deployment/` abgelöst) | Niedrig |
| 6 | Credentials-Strategie für Scheduled Task klären (Service-Account vs. gespeichert) | Mittel |
