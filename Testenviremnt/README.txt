Testenviremnt
============

Zweck:
- Enthält nur Test-Harness und Testdaten.
- Uebersteuert produktive Defaults (z.B. Logquellen, Testcases, Scheduler-Tests).

Skripte:
- Run-LobsterDataAllCases.cmd / Run-LobsterDataOneCase.cmd
  Starten lokale Testcases ueber Run-TestCase.ps1.
- Invoke-LobsterDataDmzStopAndReadTest.ps1
  Testet DMZ-Dienststopp + Remote-WrapperLogCheck vom Backend aus.
- Run-Remote-Tests.ps1, Set/Remove/Manage-Remote-TestSchedule.ps1
  Remote-Teststeuerung.

Wichtig:
- Produktivlogik liegt im Projektroot (z.B. Invoke-LobsterDataWrapperLogCheck.ps1).
- Testskripte rufen produktive Logik gezielt mit Test-Config auf.
