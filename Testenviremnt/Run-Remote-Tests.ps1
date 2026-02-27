[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$RemoteProjectPath,

    [string[]]$Cases,

    [switch]$All,

    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'

# Feste Credentials (anpassen)
$FixedUserName = 'lobster'
$FixedPasswordPlain = 'ed2w$3nn'

if (-not $All.IsPresent -and (-not $Cases -or $Cases.Count -eq 0)) {
    throw "Bitte -All oder -Cases angeben."
}

if (-not $PSBoundParameters.ContainsKey('Credential')) {
    if ([string]::IsNullOrWhiteSpace($FixedUserName) -or [string]::IsNullOrWhiteSpace($FixedPasswordPlain)) {
        throw "Kein -Credential uebergeben und feste Credentials sind nicht konfiguriert."
    }

    $sec = ConvertTo-SecureString -String $FixedPasswordPlain -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($FixedUserName, $sec)
}

$invokeParams = @{
    ComputerName = $ComputerName
    ErrorAction  = 'Stop'
    ScriptBlock  = {
        param($RemoteProjectPath, $Cases, $All)

        $runner = Join-Path $RemoteProjectPath 'Run-TestCase.ps1'
        if (-not (Test-Path -LiteralPath $runner)) {
            throw "Run-TestCase.ps1 nicht gefunden: $runner"
        }

        Set-Location -LiteralPath $RemoteProjectPath

        if ($All) {
            $output = & $runner -All *>&1
        } else {
            $output = & $runner -Case $Cases *>&1
        }

        [PSCustomObject]@{
            HostName  = $env:COMPUTERNAME
            StartTime = (Get-Date)
            ExitCode  = $LASTEXITCODE
            Output    = @($output | ForEach-Object { $_.ToString() })
        }
    }
    ArgumentList = @($RemoteProjectPath, $Cases, [bool]$All)
    Credential = $Credential
}

$result = Invoke-Command @invokeParams

$ok = ($result.ExitCode -eq 0)

[PSCustomObject]@{
    RequestedHost = $ComputerName
    ExecutedOn    = $result.HostName
    ExitCode      = $result.ExitCode
    Success       = $ok
    Output        = $result.Output
}
