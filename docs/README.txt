Wrapper-Monitor v20

Aenderungen gegenueber v19:
- NEU: Run-LobsterDataMaintenance.cmd fuer Produktivbetrieb
- NEU: lobsterdata.maintenance.prod.config.psd1 als Basis-Konfiguration (IsTest=false, Prod-Sleeps)
- NEU: Invoke-LobsterDataMaintenanceRunner.ps1 als Produktiv-Runner
- NEU: Invoke-LobsterDataWrapperLogCheck.ps1 als zentrale Log-Pruefung
- NEU: Testskripte in .\Testenviremnt\ getrennt

Produktiv-Start:
  Run-LobsterDataMaintenance.cmd "D:\Lobster_data\IS\logs\wrapper.log"

  Parameter:
    1 = Pfad zur wrapper.log

  Scheduled Task (Beispiel):
    Programm:   C:\Windows\System32\cmd.exe
    Argumente:  /c "D:\Pfad\wrapper-monitor\Run-LobsterDataMaintenance.cmd" "D:\Lobster_data\IS\logs\wrapper.log"
    Starten in: D:\Pfad\wrapper-monitor\

Tests:
- Alle Cases:  .\Testenviremnt\Run-LobsterDataAllCases.cmd
- Ein Case:    .\Testenviremnt\Run-LobsterDataOneCase.cmd TC01

Testcases:
- TC01: Wrapper erfolgreich gestoppt               -> OK    (Exit 0)
- TC02: Wrapper gestoppt, aber gestern (nicht heute)-> WARN  (Exit 1)
- TC03: Wrapper gestoppt, danach wieder gestartet   -> ERROR (Exit 2)
- TC04: Wrapper laeuft normal, kein Stopped im Log  -> WARN  (Exit 1)
- TC05: Wrapper gestoppt heute, aber falsche Uhrzeit-> WARN  (Exit 1)

Start:
- Alle Cases:  .\Testenviremnt\Run-LobsterDataAllCases.cmd
- Ein Case:    .\Testenviremnt\Run-LobsterDataOneCase.cmd TC01

Hinweis:
- Mailversand ist in Send-LobsterDataMaintenanceNotification.ps1 getrennt.
- Logs werden pro Run in .\runtime\runs\<timestamp>_<TCxx> gespeichert.
