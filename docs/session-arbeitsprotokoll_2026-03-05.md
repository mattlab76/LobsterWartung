# Arbeitsprotokoll – Session 05.03.2026

Dieses Dokument fasst zusammen, was in der heutigen Session gemacht wurde.

---

## 1) Repo geklont

Das Repository `LobsterWartung` wurde frisch von GitHub geklont:

```
git clone https://github.com/mattlab76/LobsterWartung.git
```

---

## 2) Bestandsaufnahme / Code-Review

Das gesamte Repo wurde durchgelesen und analysiert. Stand zum Zeitpunkt des Klonens:

### Was fertig und funktionsfähig war

- **`scripts/core/Invoke-LobsterDataMaintenance.ps1`**
  Vollständiges Orchestrierungs-Script mit `-Action Read|Stop|Start`, Local/Remote-Scope, Mail, Credential-Support.

- **`scripts/ui/Run-LobsterDataMaintenanceWizard.ps1`**
  Interaktiver Console-Wizard (print-only), fragt Schritt für Schritt und gibt den fertigen PowerShell-Aufruf aus.

- **`config/lobsterdata.maintenance.prod.config.psd1`**
  Produktiv-Config mit `IsTest = $false`, getrennten `StopConfig`- und `StartConfig`-Sektionen.

- **`Testenviremnt/`**
  Test-Harness mit 5 Testcases (TC01–TC05).

- **`docs/maintenance-scripts_ANWENDERDOKU.md`**
  Vollständige Anwenderdokumentation.

### Bekannte offene Punkte (aus Arbeitsprotokoll 27.02.2026)

| # | Thema | Status |
|---|-------|--------|
| 1 | Encoding-Problem (Umlaute in Konsole) | offen |
| 2 | REST API Stop-Mode | Placeholder, wirft Fehler mit Hinweis |
| 3 | Wizard gegen neue Maintenance-Version testen | offen |

### Hinweis: fehlender Push

Der letzte Arbeitsstand vom anderen Rechner (letzte Änderungen nach 27.02.2026) wurde **nicht gepusht** und ist vorerst nicht verfügbar. Das Repo enthält jedoch alle dokumentierten Features vollständig.

---

## 3) Neues Feature: LobsterSchedulerManager.html

### Ziel

Eine **Standalone-HTML-Seite** zur komfortablen Verwaltung von Windows Scheduled Tasks auf entfernten Hosts – ohne externe Dependencies, rein im Browser ausführbar.

### Datei

`LobsterSchedulerManager.html` (Projektroot)

### Features

#### 3 Tabs

| Tab | Inhalt |
|-----|--------|
| **Scheduler Eintrag** | 7-Schritte-Wizard zum Anlegen eines Scheduled Tasks |
| **Historie** | Alle gesetzten Einträge (persistent via localStorage) |
| **Einstellungen** | Konfigurierbare Dropdowns, Mail-Defaults, Standard-Werte |

#### Workflow (7 Schritte)

| Schritt | Was passiert |
|---------|-------------|
| 1 – Konfiguration | Alle Parameter eingeben; Skriptname und Task-Name werden automatisch ermittelt |
| 2 – Zusammenfassung | Review aller Angaben vor dem Fortfahren |
| 3 – Skript prüfen | Generiertes PS-Script prüft via `Invoke-Command` ob das `.ps1` am Remote-Host vorhanden ist |
| 4 – Scheduler setzen | PS-Script legt den Task via `Register-ScheduledTask` auf dem Remote-Host an |
| 5 – Eintrag prüfen | PS-Script verifiziert den Task via `Get-ScheduledTask` |
| 6 – Mail senden | Vorbefüllte Benachrichtigungsmail via `Send-MailMessage` |
| 7 – Abschluss | Eintrag wird in die Historie geschrieben |

Jeder Schritt mit PS-Script bietet:
- **Kopieren**-Button (Clipboard)
- **Download**-Button (`.ps1`-Datei mit UTF-8 BOM)
- Manueller Status-Button (OK / Fehler) → schaltet "Weiter" frei

#### Formular-Parameter

| Parameter | Typ | Hinweis |
|-----------|-----|---------|
| UserID | Text | Pflicht |
| Wartungstyp | Dropdown | Start-Wartung, Restart-Lobster, Stop-Lobster, Start-Lobster (Update-Lobster kommt später) |
| Instanz Typ | Dropdown | Backend und DMZ, B+D (via Webservice), Backend, Backend (via Webservice), DMZ |
| Backend Host | Dropdown (Settings) | Nur sichtbar wenn Instanztyp Backend enthält |
| DMZ Host | Dropdown (Settings) | Nur sichtbar wenn Instanztyp DMZ enthält |
| Benutzername | Text | Standard-Wert aus Einstellungen |
| Passwort | Password | Toggle Anzeigen/Verbergen; Sicherheitswarnung in Schritt 4 |
| Startzeitpunkt | datetime-local | Default: morgen 02:00 |
| Scheduler Location | Dropdown (Settings) | Default: AQG |
| PS-Skript Pfad | Text | Pfad auf dem Remote-Host |

#### Script-Mapping (Wartungstyp + Instanztyp → PS-Dateiname)

| Wartungstyp | Instanz Typ | Script |
|-------------|-------------|--------|
| Stop-Lobster / Start-Wartung | Backend und DMZ | `Stop-BackendAndDmz.ps1` / `Start-BackendAndDmz.ps1` |
| Stop-Lobster / Start-Wartung | Backend und DMZ (via Webservice) | `Stop-BackendAndDmz-Webservice.ps1` |
| Stop-Lobster / Start-Wartung | Backend | `Stop-Backend.ps1` / `Start-Backend.ps1` |
| Stop-Lobster / Start-Wartung | Backend (via Webservice) | `Stop-Backend-Webservice.ps1` |
| Stop-Lobster / Start-Wartung | DMZ | `Stop-Dmz.ps1` / `Start-Dmz.ps1` |
| Restart-Lobster | alle | `Restart-*.ps1` (analog) |

Scripts laufen **immer vom Backend-Host aus** (oder DMZ-Host wenn kein Backend gewählt).

#### Einstellungen (persistent via localStorage)

- **Backend Hosts** – Liste, Add/Remove, füllt Dropdown in Schritt 1
- **DMZ Hosts** – Liste, Add/Remove, füllt Dropdown in Schritt 1
- **Scheduler Locations** – Liste (Default: `AQG`)
- **Mail-Einstellungen** – SMTP Server, From, Standard-Empfänger
- **Standard-Werte** – Benutzername, PS-Skript-Pfad (werden beim Start vorausgefüllt)

---

## 4) Offene Punkte / Nächste Schritte

1. **PS-Scripts auf dem Backend-Host ablegen**
   Die HTML-Seite referenziert folgende Scripts (müssen noch erstellt werden):
   - `Stop-BackendAndDmz.ps1`
   - `Stop-BackendAndDmz-Webservice.ps1`
   - `Stop-Backend.ps1`
   - `Stop-Backend-Webservice.ps1`
   - `Stop-Dmz.ps1`
   - `Start-BackendAndDmz.ps1`
   - `Start-Backend.ps1`
   - `Start-Dmz.ps1`
   - `Restart-*.ps1` (analog)

   → Diese werden **Punkt für Punkt** gemeinsam erarbeitet.

2. **Einstellungen in HTML-Seite befüllen**
   Backend-Hosts, DMZ-Hosts und Scheduler Location(s) in den Einstellungen eintragen.

3. **Encoding-Problem** in `Invoke-LobsterDataMaintenance.ps1` / Wizard (Umlaute) bei Bedarf fixen.

4. **Produktiv-Test** des bestehenden Maintenance-Scripts auf dem Zielsystem.

---

_Ende Session 05.03.2026_
