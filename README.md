# LobsterWartung

Neu strukturierte Ablage, ohne Aenderung der bestehenden Aufrufpfade.

## Struktur
- `scripts/core/` - Kernlogik (Maintenance, Runner, LogCheck, Helper, Notification)
- `scripts/ui/` - interaktive Launcher/Wizard (PowerShell)
- `config/` - statische Konfiguration (`*.psd1`)
- `docs/` - Dokumentation und Arbeitsprotokolle
- `runtime/` - Laufzeitkonfiguration/Artefakte
- `Testenviremnt/` - bestehendes Test-Harness (unveraenderter Ordnername)

## Kompatibilitaet
Die bisherigen Skriptnamen im Projektroot bleiben erhalten und leiten auf die neue Struktur weiter. Dadurch funktionieren bestehende Aufrufe, `.cmd`-Starter und Remote-Pfade weiter.

## Einstieg
- Produktiv-Start: `Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"`
- GUI-Start: `Run-LobsterDataMaintenanceGui.cmd "<ComputerName>" "<RemoteProjectPath>" "<RemoteLogPath>"`
- Wizard: `Run-LobsterDataMaintenanceWizard.cmd`

Weitere Details: `docs/README.txt`
