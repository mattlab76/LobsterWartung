@{
  # --- Wird vom lokalen Runner ueberschrieben ---
  LogPath = ''

  # Produktivmodus
  IsTest = $false

  # Time window for "near ScriptStart" check
  TimeToleranceMinutes = 5

  # How many lines from the end of the log are considered for checks
  WarnTailLines  = 200
  ErrorTailLines = 200

  # Polling behavior (Prod: 11 Versuche x 30 Sek = ca. 5.5 Min Wartezeit)
  MaxAttempts = 10
  AttemptSleepSeconds_Test = 1
  AttemptSleepSeconds_Prod = 1

  # Recheck delay
  RecheckSleepSeconds_Test = 1
  RecheckSleepSeconds_Prod = 1



  # --- NEU: getrennte Konfiguration für Stop/Start ---
  StopConfig = @{
    # Erfolgs-Pattern im wrapper.log (Stop)
    SuccessRegex = 'Wrapper\s+Stopped'

    # Wie viele Logzeilen am Ende geprüft werden
    TailLines = 200

    # Polling (Stop): z.B. 18x10s = 3 Minuten
    MaxAttempts = 18
    AttemptSleepSeconds_Test = 1
    AttemptSleepSeconds_Prod = 10

    # Optionaler Recheck nach Erfolg
    RecheckSleepSeconds_Test = 1
    RecheckSleepSeconds_Prod = 5

    # übernimmt Standard-IsTest, kann aber pro Section überschrieben werden
    IsTest = $false
  }

  StartConfig = @{
    # Erfolgs-Pattern im wrapper.log (Start)
    # Beispielzeile:
    # INFO   | jvm 1    | 2026/02/27 13:14:50 | Integration Server (IS) started in 199605 ms, system is ready...
    SuccessRegex = 'Integration Server \(IS\) started .*system is ready'

    TailLines = 300

    # Polling (Start): z.B. 40x10s = 6:40 Minuten
    MaxAttempts = 40
    AttemptSleepSeconds_Test = 1
    AttemptSleepSeconds_Prod = 10

    RecheckSleepSeconds_Test = 1
    RecheckSleepSeconds_Prod = 5

    IsTest = $false
  }

}
