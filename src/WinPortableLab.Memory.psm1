Set-StrictMode -Version Latest

# Native memory-list commands are intentionally compiled only when a cleanup
# operation or a privilege capability check first needs them. Importing this
# module must stay cheap for the normal inventory/check path.
$script:WplMemoryNativeTypeReady = $false
# SystemMemoryListInformation = 80; the native command values are
# MemoryEmptyWorkingSets = 2, MemoryFlushModifiedList = 3,
# MemoryPurgeStandbyList = 4 and MemoryPurgeLowPriorityStandbyList = 5.
$script:WplMemorySystemInformationClass = 80
$script:WplMemoryEmptyWorkingSets = 2
$script:WplMemoryFlushModifiedList = 3
$script:WplMemoryPurgeStandbyList = 4
$script:WplMemoryPurgeLowPriorityStandbyList = 5

function Initialize-WplMemoryNativeType {
    if ($script:WplMemoryNativeTypeReady) { return }
    if (-not ('WplMemoryNative' -as [type])) {
        # Cross-checked on 2026-09-12:
        # - Microsoft Learn NtSetSystemInformation documents the manual ntdll
        #   declaration, NTSTATUS return, pointer buffer and byte length:
        #   https://learn.microsoft.com/windows/win32/sysinfo/ntsetsysteminformation
        # - Microsoft Learn SetSystemFileCacheSize documents SIZE_T arguments,
        #   -1/-1 as the flush sentinel, flags=0 as "retain current limits", and
        #   SeIncreaseQuotaPrivilege:
        #   https://learn.microsoft.com/windows/win32/api/memoryapi/nf-memoryapi-setsystemfilecachesize
        # - The MIT-compatible MemListMgr implementation and the GPL Mem Reduct
        #   source both use SystemMemoryListInformation with the four commands
        #   below. We keep registry/combined-page/volume-cache operations out of
        #   this focused module: they are outside the requested native contract.
        #   https://github.com/fafalone/MemListMgr/blob/main/modMemListMgr.twin
        #   https://raw.githubusercontent.com/henrypp/memreduct/master/src/main.c
        $source = @'
using System;
using System.Runtime.InteropServices;

public static class WplMemoryNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct LUID
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID_AND_ATTRIBUTES
    {
        public LUID Luid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct TOKEN_PRIVILEGES
    {
        public uint PrivilegeCount;
        public LUID_AND_ATTRIBUTES Privileges;
    }

    [DllImport("ntdll.dll", ExactSpelling = true)]
    public static extern int NtSetSystemInformation(
        int SystemInformationClass,
        IntPtr SystemInformation,
        int SystemInformationLength);

    [DllImport("psapi.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    public static extern IntPtr OpenProcess(uint DesiredAccess, bool InheritHandle, int ProcessId);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", ExactSpelling = true)]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetSystemFileCacheSize(
        out UIntPtr MinimumFileCacheSize,
        out UIntPtr MaximumFileCacheSize,
        out uint Flags);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetSystemFileCacheSize(
        UIntPtr MinimumFileCacheSize,
        UIntPtr MaximumFileCacheSize,
        uint Flags);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool OpenProcessToken(
        IntPtr ProcessHandle,
        uint DesiredAccess,
        out IntPtr TokenHandle);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool LookupPrivilegeValue(
        string SystemName,
        string Name,
        out LUID Luid);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AdjustTokenPrivileges(
        IntPtr TokenHandle,
        bool DisableAllPrivileges,
        ref TOKEN_PRIVILEGES NewState,
        int BufferLength,
        IntPtr PreviousState,
        IntPtr ReturnLength);
}
'@
        [void](Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop)
    }
    $script:WplMemoryNativeTypeReady = $true
}

function Test-WplMemoryWindows {
    try { return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT } catch { return $false }
}

function Get-WplMemoryCimOne([string]$ClassName) {
    try {
        return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop | Select-Object -First 1)[0]
    }
    catch { return $null }
}

function Get-WplMemoryProperty([object]$Object,[string]$Name) {
    if ($null -eq $Object) { return $null }
    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) { return $null }
        return $property.Value
    }
    catch { return $null }
}

function ConvertTo-WplMemoryBytes([object]$Kilobytes) {
    if ($null -eq $Kilobytes) { return $null }
    try {
        $value = [double]$Kilobytes
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { return $null }
        return [int64]($value * 1024)
    }
    catch { return $null }
}

function ConvertTo-WplMemoryInt64([object]$Value) {
    if ($null -eq $Value) { return $null }
    try {
        $converted = [int64]$Value
        if ($converted -lt 0) { return $null }
        return $converted
    }
    catch { return $null }
}

function Get-WplMemorySnapshot {
    [CmdletBinding()]
    param()

    # Both classes are optional inputs. A broken CIM provider should produce a
    # partially populated snapshot rather than preventing the GUI from opening.
    $os = Get-WplMemoryCimOne 'Win32_OperatingSystem'
    $perf = Get-WplMemoryCimOne 'Win32_PerfFormattedData_PerfOS_Memory'
    $total = ConvertTo-WplMemoryBytes (Get-WplMemoryProperty $os 'TotalVisibleMemorySize')
    $available = ConvertTo-WplMemoryBytes (Get-WplMemoryProperty $os 'FreePhysicalMemory')
    if ($null -eq $available) { $available = ConvertTo-WplMemoryInt64 (Get-WplMemoryProperty $perf 'AvailableBytes') }
    $used = if ($null -ne $total -and $null -ne $available) { [int64]([math]::Max(0,$total - $available)) } else { $null }
    $usedPercent = if ($null -ne $used -and $total -gt 0) { [math]::Round(($used / [double]$total) * 100,2) } else { $null }
    $systemCache = Get-WplMemoryProperty $perf 'SystemCacheResidentBytes'
    if ($null -eq $systemCache) { $systemCache = Get-WplMemoryProperty $perf 'CacheBytes' }

    [pscustomobject][ordered]@{
        TotalBytes = $total
        AvailableBytes = $available
        UsedBytes = $used
        UsedPercent = $usedPercent
        StandbyNormalBytes = ConvertTo-WplMemoryInt64 (Get-WplMemoryProperty $perf 'StandbyCacheNormalPriorityBytes')
        StandbyReserveBytes = ConvertTo-WplMemoryInt64 (Get-WplMemoryProperty $perf 'StandbyCacheReserveBytes')
        StandbyCoreBytes = ConvertTo-WplMemoryInt64 (Get-WplMemoryProperty $perf 'StandbyCacheCoreBytes')
        ModifiedBytes = ConvertTo-WplMemoryInt64 (Get-WplMemoryProperty $perf 'ModifiedPageListBytes')
        SystemCacheBytes = ConvertTo-WplMemoryInt64 $systemCache
        CapturedAt = Get-Date
    }
}

function Get-WplMemoryCleanupArea {
    [CmdletBinding()]
    param()

    # RecordOnly identifies an operation deliberately omitted from the default
    # Combined plan. Explicitly selecting it with -AcknowledgeRisk is supported
    # because Microsoft documents the -1/-1 cache-flush sentinel and this module
    # restores the exact values and flags read immediately before the call.
    @(
        [pscustomobject][ordered]@{ Id='WorkingSet'; RequiresElevation=$true; RecordOnly=$false; DescriptionKey='MemoryAreaWorkingSet' }
        [pscustomobject][ordered]@{ Id='SystemWorkingSet'; RequiresElevation=$true; RecordOnly=$false; DescriptionKey='MemoryAreaSystemWorkingSet' }
        [pscustomobject][ordered]@{ Id='ModifiedPageList'; RequiresElevation=$true; RecordOnly=$false; DescriptionKey='MemoryAreaModifiedPageList' }
        [pscustomobject][ordered]@{ Id='StandbyList'; RequiresElevation=$true; RecordOnly=$false; DescriptionKey='MemoryAreaStandbyList' }
        [pscustomobject][ordered]@{ Id='LowPriorityStandbyList'; RequiresElevation=$true; RecordOnly=$false; DescriptionKey='MemoryAreaLowPriorityStandbyList' }
        [pscustomobject][ordered]@{ Id='SystemFileCache'; RequiresElevation=$true; RecordOnly=$true; DescriptionKey='MemoryAreaSystemFileCache' }
    )
}

function Test-WplMemoryCleanupSupport {
    [CmdletBinding()]
    param()

    $isWindows = Test-WplMemoryWindows
    $isElevated = $false
    $notes = [Collections.Generic.List[string]]::new()
    if ($isWindows) {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $isElevated = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch { $notes.Add('Windows elevation state could not be read.') }
    }
    else { $notes.Add('Native memory cleanup is available only on Windows.') }

    $profile = [pscustomobject]@{ CanEnable=$false; Error=$null }
    $quota = [pscustomobject]@{ CanEnable=$false; Error=$null }
    if ($isWindows) {
        $profile = Test-WplMemoryPrivilege 'SeProfileSingleProcessPrivilege'
        $quota = Test-WplMemoryPrivilege 'SeIncreaseQuotaPrivilege'
        if (-not $profile.CanEnable) { $notes.Add('SeProfileSingleProcessPrivilege is unavailable to the current token.') }
        if (-not $quota.CanEnable) { $notes.Add('SeIncreaseQuotaPrivilege is unavailable to the current token.') }
        if (-not $isElevated) { $notes.Add('Run as administrator before executing a cleanup.') }
    }

    [pscustomobject][ordered]@{
        IsWindows = [bool]$isWindows
        IsElevated = [bool]$isElevated
        CanEnableSeProfileSingleProcess = [bool]$profile.CanEnable
        CanEnableSeIncreaseQuota = [bool]$quota.CanEnable
        Notes = @($notes)
    }
}

function Test-WplMemoryPrivilege([string]$PrivilegeName) {
    if (-not (Test-WplMemoryWindows)) { return [pscustomobject]@{ CanEnable=$false; Error='not-windows' } }
    try { Initialize-WplMemoryNativeType } catch { return [pscustomobject]@{ CanEnable=$false; Error=$_.Exception.Message } }
    $token = [IntPtr]::Zero
    try {
        $tokenAccess = [uint32]0x28 # TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES
        if (-not [WplMemoryNative]::OpenProcessToken([WplMemoryNative]::GetCurrentProcess(),$tokenAccess,[ref]$token)) {
            return [pscustomobject]@{ CanEnable=$false; Error=('OpenProcessToken:{0}' -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        }
        $luid = New-Object WplMemoryNative+LUID
        if (-not [WplMemoryNative]::LookupPrivilegeValue($null,$PrivilegeName,[ref]$luid)) {
            return [pscustomobject]@{ CanEnable=$false; Error=('LookupPrivilegeValue:{0}' -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
        }
        $attributes = New-Object WplMemoryNative+LUID_AND_ATTRIBUTES
        $attributes.Luid = $luid
        $attributes.Attributes = [uint32]0x2 # SE_PRIVILEGE_ENABLED
        $state = New-Object WplMemoryNative+TOKEN_PRIVILEGES
        $state.PrivilegeCount = 1
        $state.Privileges = $attributes
        $adjusted = [WplMemoryNative]::AdjustTokenPrivileges($token,$false,[ref]$state,0,[IntPtr]::Zero,[IntPtr]::Zero)
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        return [pscustomobject]@{ CanEnable=([bool]$adjusted -and $lastError -ne 1300); Error=if($adjusted -and $lastError -eq 1300){'ERROR_NOT_ALL_ASSIGNED'}else{$lastError} }
    }
    catch { return [pscustomobject]@{ CanEnable=$false; Error=$_.Exception.Message } }
    finally { if ($token -ne [IntPtr]::Zero) { [void][WplMemoryNative]::CloseHandle($token) } }
}

function Get-WplNtStatusDescription([int]$Status) {
    $unsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes($Status),0)
    $hex = '0x{0:X8}' -f $unsigned
    $message = switch ($hex) {
        '0x00000000' { 'Completed successfully.'; break }
        '0xC0000061' { 'The required privilege is not held by the current process.'; break }
        '0xC000000D' { 'Windows rejected the memory command as an invalid parameter.'; break }
        '0xC0000001' { 'Windows reported a general native memory-management failure.'; break }
        default { 'Windows returned NTSTATUS {0}.' -f $hex }
    }
    [pscustomobject]@{ Success=($unsigned -eq 0); Status=[int]$Status; StatusHex=$hex; Message=$message }
}

function Invoke-WplMemoryListCommand([string]$AreaId,[int]$Command) {
    $buffer = [IntPtr]::Zero
    try {
        # SystemMemoryListInformation expects one 4-byte SYSTEM_MEMORY_LIST_COMMAND
        # allocated with Marshal.AllocHGlobal(4) and populated by Marshal.WriteInt32.
        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,[int]$Command)
        $status = [WplMemoryNative]::NtSetSystemInformation([int]$script:WplMemorySystemInformationClass,$buffer,4)
        $mapped = Get-WplNtStatusDescription $status
        [pscustomobject][ordered]@{
            Id=$AreaId; Success=[bool]$mapped.Success; Skipped=$false; ReportOnly=$false
            Status=$mapped.Status; StatusHex=$mapped.StatusHex; Message=$mapped.Message; ProcessId=$null
        }
    }
    catch {
        [pscustomobject][ordered]@{
            Id=$AreaId; Success=$false; Skipped=$false; ReportOnly=$false; Status=$null
            StatusHex=$null; Message=$_.Exception.Message; ProcessId=$null
        }
    }
    finally { if ($buffer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) } }
}

function New-WplMemoryFlushSentinel {
    # Microsoft documents SetSystemFileCacheSize((SIZE_T)-1,(SIZE_T)-1,0)
    # as the flush request; UIntPtr keeps that sentinel pointer-width safe.
    if ([UIntPtr]::Size -eq 4) { return [UIntPtr]::new([uint32]::MaxValue) }
    return [UIntPtr]::new([uint64]::MaxValue)
}

function Invoke-WplSystemFileCacheCleanup {
    $minimum = [UIntPtr]::Zero
    $maximum = [UIntPtr]::Zero
    $flags = [uint32]0
    $readSucceeded = $false
    try {
        if (-not [WplMemoryNative]::GetSystemFileCacheSize([ref]$minimum,[ref]$maximum,[ref]$flags)) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            return [pscustomobject][ordered]@{ Id='SystemFileCache'; Success=$false; Skipped=$false; ReportOnly=$false; Status=$null; StatusHex=$null; Message=('GetSystemFileCacheSize failed with Win32 error {0}.' -f $errorCode); ProcessId=$null; Restored=$false }
        }
        $readSucceeded = $true
        $sentinel = New-WplMemoryFlushSentinel
        $flushed = [WplMemoryNative]::SetSystemFileCacheSize($sentinel,$sentinel,0)
        $flushError = if ($flushed) { $null } else { [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
        $restored = [WplMemoryNative]::SetSystemFileCacheSize($minimum,$maximum,$flags)
        $restoreError = if ($restored) { $null } else { [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
        $success = [bool]$flushed -and [bool]$restored
        $message = if (-not $flushed) { 'SetSystemFileCacheSize flush failed with Win32 error {0}.' -f $flushError }
            elseif (-not $restored) { 'The file cache flush completed, but restoring the previous cache limits failed with Win32 error {0}.' -f $restoreError }
            else { 'The system file cache was flushed and its previous limits were restored.' }
        [pscustomobject][ordered]@{ Id='SystemFileCache'; Success=$success; Skipped=$false; ReportOnly=$false; Status=$null; StatusHex=$null; Message=$message; ProcessId=$null; Restored=$restored }
    }
    catch {
        # A read succeeded before the exception in normal operation. Try to
        # restore in the catch path as a final safety net when values are known.
        $restored = $false
        if ($readSucceeded) {
            try { $restored = [WplMemoryNative]::SetSystemFileCacheSize($minimum,$maximum,$flags) } catch { $restored = $false }
        }
        [pscustomobject][ordered]@{ Id='SystemFileCache'; Success=$false; Skipped=$false; ReportOnly=$false; Status=$null; StatusHex=$null; Message=$_.Exception.Message; ProcessId=$null; Restored=$restored }
    }
}

function Invoke-WplProcessWorkingSet([int]$ProcessId) {
    $processAccess = [uint32]0x0500 # PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA
    $handle = [IntPtr]::Zero
    try {
        $handle = [WplMemoryNative]::OpenProcess($processAccess,$false,$ProcessId)
        if ($handle -eq [IntPtr]::Zero) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            return [pscustomobject][ordered]@{ Id=('Process:{0}' -f $ProcessId); Success=$false; Skipped=$true; ReportOnly=$false; Status=$null; StatusHex=$null; Message=('Process handle was not available (Win32 error {0}); skipped.' -f $errorCode); ProcessId=$ProcessId }
        }
        if ([WplMemoryNative]::EmptyWorkingSet($handle)) {
            return [pscustomobject][ordered]@{ Id=('Process:{0}' -f $ProcessId); Success=$true; Skipped=$false; ReportOnly=$false; Status=0; StatusHex='0x00000000'; Message='Process working set emptied.'; ProcessId=$ProcessId }
        }
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($errorCode -eq 5) {
            return [pscustomobject][ordered]@{ Id=('Process:{0}' -f $ProcessId); Success=$false; Skipped=$true; ReportOnly=$false; Status=$null; StatusHex=$null; Message=('Process working-set access was denied (Win32 error 5); skipped.'); ProcessId=$ProcessId }
        }
        [pscustomobject][ordered]@{ Id=('Process:{0}' -f $ProcessId); Success=$false; Skipped=$false; ReportOnly=$false; Status=$null; StatusHex=$null; Message=('EmptyWorkingSet failed with Win32 error {0}.' -f $errorCode); ProcessId=$ProcessId }
    }
    catch {
        [pscustomobject][ordered]@{ Id=('Process:{0}' -f $ProcessId); Success=$false; Skipped=$true; ReportOnly=$false; Status=$null; StatusHex=$null; Message=('Process could not be opened; skipped: {0}' -f $_.Exception.Message); ProcessId=$ProcessId }
    }
    finally { if ($handle -ne [IntPtr]::Zero) { [void][WplMemoryNative]::CloseHandle($handle) } }
}

function Resolve-WplMemoryAreaIds([string[]]$Area) {
    $values = if ($null -eq $Area -or $Area.Count -eq 0) { @('Combined') } else { @($Area) }
    $known = @(Get-WplMemoryCleanupArea | ForEach-Object Id)
    $combined = @('WorkingSet','SystemWorkingSet','ModifiedPageList','StandbyList','LowPriorityStandbyList')
    $resolved = [Collections.Generic.List[string]]::new()
    foreach ($value in $values) {
        foreach ($candidate in ([string]$value -split ',')) {
            $id = $candidate.Trim()
            if (-not $id) { continue }
            if ($id -ieq 'Combined') { $items = $combined }
            elseif ($known -contains $id) { $items = @($id) }
            else { throw "Unknown memory cleanup area '$id'." }
            foreach ($item in $items) { if (-not $resolved.Contains($item)) { $resolved.Add($item) } }
        }
    }
    return @($resolved)
}

function Clear-WplSystemMemory {
    [CmdletBinding()]
    param(
        [string[]]$Area = @('Combined'),
        [int[]]$ProcessId,
        [switch]$Report,
        [switch]$AcknowledgeRisk
    )

    $areaIds = @(Resolve-WplMemoryAreaIds $Area)
    $processIds = @($ProcessId | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    $before = Get-WplMemorySnapshot
    $requested = [ordered]@{ Areas=@($areaIds); ProcessIds=@($processIds) }
    $results = [Collections.Generic.List[object]]::new()
    $performed = [Collections.Generic.List[string]]::new()

    if ($Report) {
        foreach ($id in $areaIds) { $results.Add([pscustomobject][ordered]@{ Id=$id; Success=$false; Skipped=$false; ReportOnly=$true; Status=$null; StatusHex=$null; Message='Plan only; no native cleanup was executed.'; ProcessId=$null }) }
        foreach ($id in $processIds) { $results.Add([pscustomobject][ordered]@{ Id=('Process:{0}' -f $id); Success=$false; Skipped=$false; ReportOnly=$true; Status=$null; StatusHex=$null; Message='Plan only; no process working-set cleanup was executed.'; ProcessId=$id }) }
        return [pscustomobject][ordered]@{ Requested=$requested; Performed=@(); ReportOnly=$true; Before=$before; After=$before; DeltaBytes=0; Results=@($results) }
    }

    if (-not (Test-WplMemoryWindows)) { throw 'Native memory cleanup is available only on Windows.' }
    $riskyAreas = @($areaIds | Where-Object { $_ -notin @('WorkingSet','SystemWorkingSet') })
    if ($riskyAreas.Count -gt 0 -and -not $AcknowledgeRisk) {
        throw "Memory areas requiring risk acknowledgement were selected: $($riskyAreas -join ', '). Re-run with -AcknowledgeRisk."
    }
    $support = Test-WplMemoryCleanupSupport
    if (-not $support.IsElevated) { throw 'Administrator rights are required to execute native memory cleanup.' }
    $needsProfilePrivilege = @($areaIds | Where-Object { $_ -ne 'SystemFileCache' }).Count -gt 0
    if ($needsProfilePrivilege -and -not $support.CanEnableSeProfileSingleProcess) { throw 'SeProfileSingleProcessPrivilege could not be enabled; native memory-list cleanup was not executed.' }
    if ($areaIds -contains 'SystemFileCache' -and -not $support.CanEnableSeIncreaseQuota) { throw 'SeIncreaseQuotaPrivilege could not be enabled; system file-cache cleanup was not executed.' }
    Initialize-WplMemoryNativeType

    foreach ($id in $areaIds) {
        $result = switch ($id) {
            'WorkingSet' { Invoke-WplMemoryListCommand $id $script:WplMemoryEmptyWorkingSets; break }
            'SystemWorkingSet' { Invoke-WplMemoryListCommand $id $script:WplMemoryEmptyWorkingSets; break }
            'ModifiedPageList' { Invoke-WplMemoryListCommand $id $script:WplMemoryFlushModifiedList; break }
            'StandbyList' { Invoke-WplMemoryListCommand $id $script:WplMemoryPurgeStandbyList; break }
            'LowPriorityStandbyList' { Invoke-WplMemoryListCommand $id $script:WplMemoryPurgeLowPriorityStandbyList; break }
            'SystemFileCache' { Invoke-WplSystemFileCacheCleanup; break }
        }
        $results.Add($result)
        if ($result.Success) { $performed.Add($id) }
    }
    foreach ($id in $processIds) {
        $result = Invoke-WplProcessWorkingSet $id
        $results.Add($result)
        if ($result.Success) { $performed.Add(('Process:{0}' -f $id)) }
    }
    $after = Get-WplMemorySnapshot
    $delta = if ($null -ne $before.UsedBytes -and $null -ne $after.UsedBytes) { [int64]($before.UsedBytes - $after.UsedBytes) } else { $null }
    [pscustomobject][ordered]@{ Requested=$requested; Performed=@($performed); ReportOnly=$false; Before=$before; After=$after; DeltaBytes=$delta; Results=@($results) }
}

Export-ModuleMember -Function Get-WplMemorySnapshot,Get-WplMemoryCleanupArea,Test-WplMemoryCleanupSupport,Clear-WplSystemMemory
