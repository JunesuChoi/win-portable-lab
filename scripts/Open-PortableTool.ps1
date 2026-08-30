[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Id,
    [switch]$List,
    [switch]$AcknowledgeRisk,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
Import-Module (Join-Path $Root 'src\WinPortableLab.Process.psm1') -Force
$launcherDocument = Read-WplJson -Path (Join-Path $Root 'config\tool-launchers.json')
$launchers = @(foreach ($item in $launcherDocument) { $item })

$installed = foreach ($launcher in $launchers) {
    $toolRoot = Join-Path $Root 'tools'
    $exe = Resolve-WplExecutable -Root $Root -Launcher $launcher
    $manifest = Get-ChildItem -LiteralPath $toolRoot -Filter 'INSTALL-MANIFEST.json' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).id -eq $launcher.catalogId } | Select-Object -First 1
    $installedState = [bool]$exe -or ($launcher.launchMode -eq 'external-boot' -and [bool]$manifest)
    $arguments = if ($launcher.PSObject.Properties.Name.Contains('arguments')) { @(ConvertTo-WplArgumentList -InputObject $launcher.arguments) } else { @() }
    [pscustomobject]@{Id=$launcher.id;CatalogId=$launcher.catalogId;Mode=$launcher.launchMode;Risk=$launcher.risk;Installed=$installedState;Executable=if($exe){$exe.FullName}else{$null};Arguments=$arguments}
}

if ($List -or -not $Id) { $installed | Format-Table -AutoSize; if (-not $Id) { return } }
$selected = $installed | Where-Object Id -eq $Id | Select-Object -First 1
if (-not $selected) { throw (Get-WplText -Key UnknownLaunchId -Language $Language -ArgumentList @($Id)) }
if (-not $selected.Installed) { throw (Get-WplText -Key NotInstalled -Language $Language -ArgumentList @($Id)) }
if ($selected.Mode -eq 'external-boot') { throw (Get-WplText -Key ExternalBootOnly -Language $Language -ArgumentList @($Id)) }

if ($selected.Risk -notmatch '^read-only' -and -not $AcknowledgeRisk) {
    throw (Get-WplText -Key RiskBlocked -Language $Language -ArgumentList @($Id,$selected.Risk))
}

$selectedArguments = @($selected.Arguments | Where-Object { $null -ne $_ })
$launchId = '{0}-{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$selected.Id,([guid]::NewGuid().ToString('N').Substring(0,8))
$launchRecordPath = Join-Path $Root ('logs\tool-launches\{0}.json' -f $launchId)
$launchRecord = [ordered]@{
    schemaVersion=1;launchId=$launchId;launcherId=$selected.Id;executable=$selected.Executable
    arguments=$selectedArguments;requestedAt=(Get-Date).ToString('o');state='starting';processId=$null
    startupObservedMilliseconds=$null;exitCode=$null;error=$null
}
Write-WplJsonAtomic -Path $launchRecordPath -InputObject $launchRecord
try {
    $process = Start-WplProcess -FilePath $selected.Executable -WorkingDirectory (Split-Path $selected.Executable) -ArgumentList $selectedArguments
    $launchRecord.processId = $process.Id
    $startup = Wait-WplProcessStartup -Process $process -ObservationMilliseconds 1000
    $launchRecord.startupObservedMilliseconds = $startup.ObservedMilliseconds
    $launchRecord.exitCode = $startup.ExitCode
    if (-not $startup.Running -and $startup.ExitCode -ne 0) { throw "Process exited during startup with code $($startup.ExitCode)." }
    $launchRecord.state = if ($startup.Running) { 'started' } else { 'completed-during-startup' }
    Write-WplJsonAtomic -Path $launchRecordPath -InputObject $launchRecord
} catch {
    $launchRecord.state = 'failed'
    $launchRecord.error = Get-WplErrorDetail -ErrorRecord $_
    Write-WplJsonAtomic -Path $launchRecordPath -InputObject $launchRecord
    throw
}
Write-Host (Get-WplText -Key Started -Language $Language -ArgumentList @($Id,$selected.Executable)) -ForegroundColor Green
