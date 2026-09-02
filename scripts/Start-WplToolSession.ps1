[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$LauncherId,
    [switch]$Start,
    [switch]$AcceptRisk,
    [switch]$AcknowledgeManualTemperatureMonitoring,
    [switch]$PauseOnExit,
    [string]$LaunchSignalPath,
    [int]$TimeoutMinutes = -1
)

$ErrorActionPreference = 'Stop'
$record = $null
$recordPath = $null
$sessionId = $null
try {
    Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
    Import-Module (Join-Path $Root 'src\WinPortableLab.Process.psm1') -Force
    $launcherDocument = Read-WplJson -Path (Join-Path $Root 'config\tool-launchers.json')
    $launchers = @(foreach ($item in $launcherDocument) { $item })
    $launcher = @($launchers | Where-Object { [string]($_.id) -eq $LauncherId.Trim() }) | Select-Object -First 1
    if (-not $launcher) { throw "Unknown launcher: '$LauncherId' (root: '$Root'; configured: $(@($launchers.id) -join ', '))" }
} catch {
    $bootstrapError = [ordered]@{
        success=$false;message=$_.Exception.Message;launcherId=$LauncherId;sessionId=$null
        processId=$null;sessionRecordPath=$null;phase='bootstrap';createdAt=(Get-Date).ToString('o')
        error=[ordered]@{exceptionType=$_.Exception.GetType().FullName;category=[string]$_.CategoryInfo.Category;fullyQualifiedErrorId=$_.FullyQualifiedErrorId;scriptStackTrace=$_.ScriptStackTrace;position=[string]$_.InvocationInfo.PositionMessage}
    }
    try {
        if ($LaunchSignalPath) {
            $signalParent = Split-Path -Parent $LaunchSignalPath
            if ($signalParent) { New-Item -ItemType Directory -Path $signalParent -Force | Out-Null }
            $temporarySignal = "$LaunchSignalPath.$([guid]::NewGuid().ToString('N')).tmp"
            $bootstrapError | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporarySignal -Encoding utf8
            Move-Item -LiteralPath $temporarySignal -Destination $LaunchSignalPath -Force
        }
        if (Test-Path -LiteralPath $Root -PathType Container) {
            $bootstrapLog = Join-Path $Root ('logs\launcher-bootstrap-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $bootstrapLog) -Force | Out-Null
            $bootstrapError | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bootstrapLog -Encoding utf8
        }
    } catch { }
    $Host.UI.WriteErrorLine($bootstrapError.message)
    exit 1
}
$conditions = Read-WplJson -Path (Join-Path $Root 'config\stop-conditions.json')
$isRisky = [string]$launcher.risk -notmatch '^read-only'
$requiresManualTemperatureMonitoring = [string]$launcher.risk -match '^(?:high-load|very-high-load)$'
if ($TimeoutMinutes -lt 0) { $TimeoutMinutes = if($isRisky){[int]$conditions.defaultTimeoutMinutes}else{0} }
$executable = Resolve-WplExecutable -Root $Root -Launcher $launcher
# Record whether this launcher is backed by a user-declared path, so the session
# journal shows that the bundled binary was not the thing that ran.
$overrideTrust = Get-WplToolOverrideTrust -Root $Root -LauncherId ([string]$launcher.id)
$sessionId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
$sessionPath = Join-Path $Root ('sessions\{0}' -f $sessionId)
New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
$launcherArguments = @()
if ($launcher.PSObject.Properties.Name.Contains('arguments')) { $launcherArguments = @(ConvertTo-WplArgumentList -InputObject $launcher.arguments) }
$record = [ordered]@{
    schemaVersion=2;sessionId=$sessionId;launcherId=$LauncherId;risk=$launcher.risk;launchMode=$launcher.launchMode
    executable=if($executable){$executable.FullName}else{$null};arguments=$launcherArguments
    userDeclaredPath=if($overrideTrust){[ordered]@{path=$overrideTrust.Path;insideToolsRoot=$overrideTrust.InsideToolsRoot;signatureStatus=$overrideTrust.SignatureStatus;trusted=$overrideTrust.IsTrusted}}else{$null}
    temperatureMonitoringMode=if($requiresManualTemperatureMonitoring){$(if($AcknowledgeManualTemperatureMonitoring){'manual-operator-acknowledged'}else{'required-not-acknowledged'})}else{'not-required'}
    timeoutMinutes=$TimeoutMinutes;createdAt=(Get-Date).ToString('o');state='preview';sessionHostProcessId=$PID
    parentProcessId=$null;processId=$null;processIds=@();surrogateProcessObserved=$false;handoffToExistingInstance=$false;startedAt=$null;startupObservedMilliseconds=$null;endedAt=$null;exitCode=$null;stopReason=$null
}
try { $record.parentProcessId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId } catch { }
$recordPath = Join-Path $sessionPath 'session.json'
Write-WplJsonAtomic -Path $recordPath -InputObject $record

function Write-LaunchSignal([bool]$Success,[string]$Message,[Nullable[int]]$TargetProcessId) {
    if (-not $LaunchSignalPath) { return }
    $parent = Split-Path -Parent $LaunchSignalPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $signal = [ordered]@{
        success=$Success;message=$Message;launcherId=$LauncherId;sessionId=$sessionId
        processId=$TargetProcessId;sessionRecordPath=$recordPath;createdAt=(Get-Date).ToString('o')
    }
    Write-WplJsonAtomic -Path $LaunchSignalPath -InputObject $signal -Depth 4
}

trap {
    $message = $_.Exception.Message
    if ($record -is [Collections.IDictionary]) {
        $record['state']='failed'
        $record['endedAt']=(Get-Date).ToString('o')
        $record['stopReason']='launch-error'
        $record['error']=Get-WplErrorDetail -ErrorRecord $_
        try {
            Write-WplJsonAtomic -Path $recordPath -InputObject $record
            $record['error'] | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $sessionPath 'session-error.json') -Encoding utf8
        } catch { }
    }
    try { Write-LaunchSignal -Success $false -Message $message -TargetProcessId $null } catch { }
    $Host.UI.WriteErrorLine($message)
    exit 1
}
if (-not $Start) { $record | ConvertTo-Json -Depth 8; Write-Host "Preview only. Add -Start -AcceptRisk to launch."; exit 0 }
if (-not $AcceptRisk) { throw 'Explicit -AcceptRisk is required.' }
if ($requiresManualTemperatureMonitoring -and -not $AcknowledgeManualTemperatureMonitoring) {
    throw 'High-load sessions require -AcknowledgeManualTemperatureMonitoring. Keep HWiNFO sensors visible and stop the workload at the applicable hardware limit.'
}
if ($launcher.launchMode -eq 'external-boot') { throw 'External-boot tools cannot be launched from Windows.' }
if (-not $executable) { throw "Executable not found for launcher: $LauncherId" }

$record.state='running'; $record.startedAt=(Get-Date).ToString('o')
if ([string]$launcher.launchMode -in @('cli','cli-help')) {
    $record.processId=$PID
    Write-WplJsonAtomic -Path $recordPath -InputObject $record
    Write-LaunchSignal -Success $true -Message 'CLI process started.' -TargetProcessId $PID
    $outputPath=Join-Path $sessionPath 'console-output.txt'
    Push-Location (Split-Path $executable.FullName)
    try { & $executable.FullName @launcherArguments 2>&1 | Tee-Object -FilePath $outputPath; $record.exitCode=$LASTEXITCODE }
    finally { Pop-Location }
    # Several console utilities return a non-zero code after printing usage text,
    # so a help invocation counts as successful whenever it produced output.
    $producedOutput = (Test-Path -LiteralPath $outputPath) -and ((Get-Item -LiteralPath $outputPath).Length -gt 0)
    $helpSucceeded = $launcher.launchMode -eq 'cli-help' -and $producedOutput
    $record.state=if($record.exitCode -eq 0 -or $helpSucceeded){'completed'}else{'failed'}
    if($helpSucceeded -and $record.exitCode -ne 0){ $record.stopReason='help-output-nonzero-exit' }
    $record.endedAt=(Get-Date).ToString('o')
    Write-WplJsonAtomic -Path $recordPath -InputObject $record
    if($PauseOnExit){Read-Host 'Press Enter to close'}
    $record | ConvertTo-Json -Depth 8
    exit $(if($helpSucceeded){0}else{$record.exitCode})
}

Write-WplJsonAtomic -Path $recordPath -InputObject $record
$processesBeforeLaunch = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId,CreationDate)
$sessionStartedAt = Get-Date
$preLaunchInstanceIds = @(Get-WplSameImageProcessIds -ExecutablePath $executable.FullName)
$process = Start-WplProcess -FilePath $executable.FullName -WorkingDirectory (Split-Path $executable.FullName) -ArgumentList $launcherArguments
$record.processId=$process.Id
$record.processIds=@($process.Id)
Write-WplJsonAtomic -Path $recordPath -InputObject $record
$startup = Wait-WplProcessStartup -Process $process -ObservationMilliseconds 1000
$record.startupObservedMilliseconds = $startup.ObservedMilliseconds
$activeProcessIds = @(Get-WplRelatedProcessIds -RootProcessId $process.Id -ExecutablePath $executable.FullName -StartedAfter $sessionStartedAt -ExcludedProcesses $processesBeforeLaunch)
$record.processIds = @($activeProcessIds)
$record.surrogateProcessObserved = @($activeProcessIds | Where-Object { $_ -ne $process.Id }).Count -gt 0
$record.handoffToExistingInstance = (-not $startup.Running -and $startup.ExitCode -ne 0 -and -not $activeProcessIds.Count -and $preLaunchInstanceIds.Count -gt 0)
if (-not $startup.Running -and $startup.ExitCode -ne 0 -and -not $activeProcessIds.Count -and -not $record.handoffToExistingInstance) { throw "Process exited during startup with code $($startup.ExitCode)." }
Write-WplJsonAtomic -Path $recordPath -InputObject $record
Write-LaunchSignal -Success $true -Message $(if($activeProcessIds.Count){'Process started.'}elseif($record.handoffToExistingInstance){'Handed off to an already running instance.'}else{"Process completed during startup with code $($startup.ExitCode)."}) -TargetProcessId $(if($activeProcessIds.Count){[int]$activeProcessIds[0]}else{$process.Id})
$deadline=if($TimeoutMinutes -gt 0){(Get-Date).AddMinutes($TimeoutMinutes)}else{$null}
while ($activeProcessIds.Count) {
    if (Test-Path -LiteralPath (Join-Path $sessionPath 'CANCEL.REQUESTED')) { $record.stopReason='cancel-requested'; Stop-WplRelatedProcesses -ProcessIds $activeProcessIds; break }
    if ($deadline -and (Get-Date) -ge $deadline) { $record.stopReason='timeout'; Stop-WplRelatedProcesses -ProcessIds $activeProcessIds; break }
    if(-not $isRisky){
        Start-Sleep -Seconds ([int]$conditions.pollSeconds)
        $activeProcessIds = @(Get-WplRelatedProcessIds -RootProcessId $process.Id -ExecutablePath $executable.FullName -StartedAfter $sessionStartedAt -ExcludedProcesses $processesBeforeLaunch)
        $record.processIds = @($activeProcessIds)
        if(@($activeProcessIds | Where-Object { $_ -ne $process.Id }).Count){$record.surrogateProcessObserved=$true}
        continue
    }
    $availableMb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
    if ($availableMb -lt [int]$conditions.minimumFreeMemoryMb) { $record.stopReason='low-free-memory'; Stop-WplRelatedProcesses -ProcessIds $activeProcessIds; break }
    Start-Sleep -Seconds ([int]$conditions.pollSeconds)
    $activeProcessIds = @(Get-WplRelatedProcessIds -RootProcessId $process.Id -ExecutablePath $executable.FullName -StartedAfter $sessionStartedAt -ExcludedProcesses $processesBeforeLaunch)
    $record.processIds = @($activeProcessIds)
    if(@($activeProcessIds | Where-Object { $_ -ne $process.Id }).Count){$record.surrogateProcessObserved=$true}
}
$process.Refresh()
$record.state=if($record.stopReason){'stopped'}elseif($process.HasExited -and $process.ExitCode -ne 0 -and -not $record.surrogateProcessObserved -and -not $record.handoffToExistingInstance){'failed'}else{'completed'}
$record.endedAt=(Get-Date).ToString('o')
if ($process.HasExited) { $record.exitCode=$process.ExitCode }
if ($record.state -eq 'failed') { $record.stopReason='nonzero-exit' }
Write-WplJsonAtomic -Path $recordPath -InputObject $record
$record | ConvertTo-Json -Depth 8
