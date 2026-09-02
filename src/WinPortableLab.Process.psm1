Set-StrictMode -Version Latest

function ConvertTo-WplArgumentList {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject)

    $result = [Collections.Generic.List[string]]::new()
    $append = {
        param([AllowNull()][object]$Value,[int]$Depth)
        if ($Depth -gt 16) { throw 'Launcher arguments exceed the supported nesting depth.' }
        if ($null -eq $Value) { return }
        if ($Value -is [string]) { $result.Add([string]$Value); return }
        if ($Value -is [Collections.IDictionary]) { throw 'Launcher arguments cannot contain an object or dictionary.' }
        if ($Value -is [Collections.IEnumerable]) {
            foreach ($item in $Value) { & $append $item ($Depth + 1) }
            return
        }
        $result.Add([Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture))
    }
    & $append $InputObject 0
    return $result.ToArray()
}

function ConvertTo-WplWindowsCommandLine {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$ArgumentList = @())

    $encoded = foreach ($argument in $ArgumentList) {
        if ($null -eq $argument) { continue }
        if ($argument.Length -gt 0 -and $argument -notmatch '[\s"]') { $argument; continue }
        $builder = [Text.StringBuilder]::new()
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($character in $argument.ToCharArray()) {
            if ($character -eq '\') { $backslashes++; continue }
            if ($character -eq '"') {
                [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
                [void]$builder.Append('"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)); $backslashes = 0 }
            [void]$builder.Append($character)
        }
        if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
        [void]$builder.Append('"')
        $builder.ToString()
    }
    return ($encoded -join ' ')
}

function Start-WplProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$WorkingDirectory,
        [AllowEmptyCollection()][string[]]$ArgumentList = @()
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Executable not found: $FilePath" }
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $WorkingDirectory = Split-Path -Parent $FilePath }
    $parameters = @{ FilePath=$FilePath; WorkingDirectory=$WorkingDirectory; PassThru=$true; ErrorAction='Stop' }
    if ($ArgumentList.Count -gt 0) {
        # Windows PowerShell 5.1 joins string[] itself and loses required quoting.
        # Supplying one CommandLineToArgvW-compatible string behaves consistently in 5.1 and 7.
        $parameters.ArgumentList = ConvertTo-WplWindowsCommandLine -ArgumentList $ArgumentList
    }
    return Start-Process @parameters
}

function Wait-WplProcessStartup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [ValidateRange(0,30000)][int]$ObservationMilliseconds = 1000
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds ([Math]::Min(100,[Math]::Max(1,$ObservationMilliseconds - [int]$watch.ElapsedMilliseconds)))
        $Process.Refresh()
        if ($Process.HasExited) {
            return [pscustomobject]@{ Running=$false; ExitCode=$Process.ExitCode; ObservedMilliseconds=[int]$watch.ElapsedMilliseconds }
        }
    } while ($watch.ElapsedMilliseconds -lt $ObservationMilliseconds)
    return [pscustomobject]@{ Running=$true; ExitCode=$null; ObservedMilliseconds=[int]$watch.ElapsedMilliseconds }
}

function Get-WplRelatedProcessIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$RootProcessId,
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][datetime]$StartedAfter,
        [object[]]$ExcludedProcesses = @()
    )

    $rows = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate)
    $excluded = @{}
    foreach ($item in @($ExcludedProcesses)) {
        if ($null -eq $item) { continue }
        if ($item -is [int]) { $excluded[[int]$item] = $null; continue }
        $excluded[[int]$item.ProcessId] = $item.CreationDate
    }
    $related = [Collections.Generic.HashSet[int]]::new()
    if ($rows.ProcessId -contains $RootProcessId) { [void]$related.Add($RootProcessId) }

    # Some utilities replace their bootstrap process with a second process of
    # the same executable. Exclude every PID that existed before launch and use
    # a tight creation window so an old resident copy is never adopted.
    $imageName = [IO.Path]::GetFileName($ExecutablePath)
    $threshold = $StartedAfter.AddSeconds(-2)
    foreach ($row in $rows) {
        $processId = [int]$row.ProcessId
        $created = $row.CreationDate
        # A PID can be recycled between the pre-launch snapshot and this poll.
        # Compare its creation timestamp with the old process identity instead
        # of excluding the number forever.
        if ($excluded.ContainsKey($processId)) {
            $oldCreated = $excluded[$processId]
            if ($null -eq $oldCreated -or (-not $created) -or [datetime]$created -eq [datetime]$oldCreated) { continue }
        }
        $sameImage = ([string]$row.ExecutablePath -and [string]$row.ExecutablePath -ieq $ExecutablePath) -or ([string]$row.Name -ieq $imageName)
        if ($sameImage -and $created -and [datetime]$created -ge $threshold) { [void]$related.Add($processId) }
    }

    do {
        $added = $false
        foreach ($row in $rows) {
            $processId = [int]$row.ProcessId
            if (-not $related.Contains($processId) -and $related.Contains([int]$row.ParentProcessId)) {
                [void]$related.Add($processId)
                $added = $true
            }
        }
    } while ($added)
    return @($related | Sort-Object)
}

function Get-WplSameImageProcessIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ExecutablePath)

    # Handoff detection: single-instance utilities exit immediately, often with
    # a non-zero code, when an instance of the same image is already running.
    # A live same-image process therefore means the launch worked. Path
    # equality is the strong match; processes whose path cannot be read still
    # count when the image name matches, because the launcher itself usually
    # runs elevated and the launch record already pins the executable path.
    $imageName = [IO.Path]::GetFileName($ExecutablePath)
    $filter = "Name = '$($imageName.Replace("'","''"))'"
    $rows = @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
    return @($rows |
        Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath -ieq $ExecutablePath } |
        ForEach-Object { [int]$_.ProcessId } |
        Sort-Object -Unique)
}

function Stop-WplRelatedProcesses {
    [CmdletBinding()]
    param([AllowEmptyCollection()][int[]]$ProcessIds = @())
    # Children are normally assigned higher PIDs, but ordering descending is
    # only a best effort; Stop-Process is repeated by the caller on the next poll.
    foreach ($id in @($ProcessIds | Sort-Object -Descending)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

function Write-WplJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$InputObject,
        [ValidateRange(1,100)][int]$Depth = 8
    )

    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temporaryPath -Encoding utf8
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backupPath = "$temporaryPath.bak"
            try {
                try { [IO.File]::Replace($temporaryPath,$Path,$backupPath,$true) }
                catch [PlatformNotSupportedException] { Move-Item -LiteralPath $temporaryPath -Destination $Path -Force }
                catch [IO.IOException] { Move-Item -LiteralPath $temporaryPath -Destination $Path -Force }
            } finally {
                if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
            }
        } else {
            Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function Get-WplErrorDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord)
    [ordered]@{
        message = $ErrorRecord.Exception.Message
        exceptionType = $ErrorRecord.Exception.GetType().FullName
        category = [string]$ErrorRecord.CategoryInfo.Category
        fullyQualifiedErrorId = $ErrorRecord.FullyQualifiedErrorId
        scriptStackTrace = $ErrorRecord.ScriptStackTrace
        position = [string]$ErrorRecord.InvocationInfo.PositionMessage
    }
}

Export-ModuleMember -Function ConvertTo-WplArgumentList,ConvertTo-WplWindowsCommandLine,Start-WplProcess,Wait-WplProcessStartup,Get-WplRelatedProcessIds,Get-WplSameImageProcessIds,Stop-WplRelatedProcesses,Write-WplJsonAtomic,Get-WplErrorDetail
