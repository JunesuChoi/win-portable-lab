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

Export-ModuleMember -Function ConvertTo-WplArgumentList,ConvertTo-WplWindowsCommandLine,Start-WplProcess,Wait-WplProcessStartup,Write-WplJsonAtomic,Get-WplErrorDetail
