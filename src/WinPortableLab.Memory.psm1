Set-StrictMode -Version Latest

# Native memory-list commands are intentionally compiled only when a cleanup
# operation or a privilege capability check first needs them. Importing this
# module must stay cheap for the normal inventory/check path.
$script:WplMemoryNativeTypeReady = $false
$script:WplMemoryOsBuild = $null
# SystemMemoryListInformation = 80; the native command values are
# MemoryEmptyWorkingSets = 2, MemoryFlushModifiedList = 3,
# MemoryPurgeStandbyList = 4 and MemoryPurgeLowPriorityStandbyList = 5.
$script:WplMemorySystemInformationClass = 80
$script:WplMemoryEmptyWorkingSets = 2
$script:WplMemoryFlushModifiedList = 3
$script:WplMemoryPurgeStandbyList = 4
$script:WplMemoryPurgeLowPriorityStandbyList = 5
# The remaining Mem Reduct regions need three more information classes:
# SystemFileCacheInformationEx = 81 (system file cache), 
# SystemCombinePhysicalMemoryInformation = 130 (combine memory lists) and
# SystemRegistryReconciliationInformation = 155 (flush registry hives).
$script:WplMemoryFileCacheInformationClass = 81
$script:WplMemoryCombineMemoryClass = 130
$script:WplMemoryRegistryReconciliationClass = 155
# Mem Reduct gates two of the regions by operating-system version, so the
# module reports them as skipped instead of calling an absent class.
$script:WplMemoryWindows81Build = 9600
$script:WplMemoryWindows10Build = 10240

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
        # - Microsoft Learn CreateFile and FlushFileBuffers document the volume
        #   handle used to flush a whole volume's cache:
        #   https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers
        # - The MIT-compatible MemListMgr implementation and the GPL Mem Reduct
        #   source both use SystemMemoryListInformation with the four commands
        #   below. Mem Reduct's eight-region mask is reproduced in full, so the
        #   system file cache, combined memory lists, registry cache and volume
        #   cache regions are implemented here too.
        #   https://github.com/fafalone/MemListMgr/blob/main/modMemListMgr.twin
        #   https://raw.githubusercontent.com/henrypp/memreduct/master/src/main.c
        #   https://raw.githubusercontent.com/henrypp/memreduct/master/src/main.h
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

    // SystemCombinePhysicalMemoryInformation expects MEMORY_COMBINE_INFORMATION_EX.
    // A zeroed structure asks the kernel to combine every physical memory list.
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_COMBINE_INFORMATION_EX
    {
        public IntPtr Handle;
        public UIntPtr PagesCombined;
        public uint Flags;
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

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FlushFileBuffers(IntPtr hFile);
}
'@
        [void](Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop)
    }
    $script:WplMemoryNativeTypeReady = $true
}

function Test-WplMemoryWindows {
    try { return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT } catch { return $false }
}

function Get-WplMemoryOsBuild {
    # Two regions only exist on newer kernels, so the build number decides
    # between a real call and an explicit skip. It is read once per session.
    if ($null -ne $script:WplMemoryOsBuild) { return $script:WplMemoryOsBuild }
    $build = $null
    $os = Get-WplMemoryCimOne 'Win32_OperatingSystem'
    $reported = Get-WplMemoryProperty $os 'BuildNumber'
    if ($null -ne $reported) { try { $build = [int]$reported } catch { $build = $null } }
    if ($null -eq $build -or $build -le 0) {
        try { $build = [int][Environment]::OSVersion.Version.Build } catch { $build = $null }
    }
    $script:WplMemoryOsBuild = $build
    return $build
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

function Get-WplMemoryUsedBytes([object]$TotalBytes,[object]$AvailableBytes) {
    # Both operands are cast to Int64 before comparing: an Int32 literal made
    # PowerShell bind Math.Max(Int32,Int32), which threw as soon as total memory
    # exceeded 2 GB. Keep the arithmetic pure so it is testable without CIM.
    if ($null -eq $TotalBytes -or $null -eq $AvailableBytes) { return $null }
    try { $delta = [int64]$TotalBytes - [int64]$AvailableBytes } catch { return $null }
    if ($delta -lt 0) { return [int64]0 }
    return $delta
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
    $used = Get-WplMemoryUsedBytes $total $available
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

    # The eight regions reproduce Mem Reduct's REDUCT_* mask exactly and in its
    # execution order. RecordOnly marks Mem Reduct's two "freeze" regions
    # (REDUCT_MASK_FREEZES: standby and modified lists). Mem Reduct keeps them out
    # of REDUCT_MASK_DEFAULT and they discard cached data irreversibly, so they
    # stay opt-in and acknowledged here as well. MinimumBuild mirrors the
    # operating-system gate Mem Reduct applies before each call.
    @(
        [pscustomobject][ordered]@{ Id='WorkingSet'; RequiresElevation=$true; RecordOnly=$false; MinimumBuild=$null; DescriptionKey='MemoryAreaWorkingSet' }
        [pscustomobject][ordered]@{ Id='SystemFileCache'; RequiresElevation=$true; RecordOnly=$false; MinimumBuild=$null; DescriptionKey='MemoryAreaSystemFileCache' }
        [pscustomobject][ordered]@{ Id='ModifiedFileCache'; RequiresElevation=$true; RecordOnly=$false; MinimumBuild=$null; DescriptionKey='MemoryAreaModifiedFileCache' }
        [pscustomobject][ordered]@{ Id='ModifiedPageList'; RequiresElevation=$true; RecordOnly=$true; MinimumBuild=$null; DescriptionKey='MemoryAreaModifiedPageList' }
        [pscustomobject][ordered]@{ Id='StandbyList'; RequiresElevation=$true; RecordOnly=$true; MinimumBuild=$null; DescriptionKey='MemoryAreaStandbyList' }
        [pscustomobject][ordered]@{ Id='LowPriorityStandbyList'; RequiresElevation=$true; RecordOnly=$false; MinimumBuild=$null; DescriptionKey='MemoryAreaLowPriorityStandbyList' }
        [pscustomobject][ordered]@{ Id='RegistryCache'; RequiresElevation=$true; RecordOnly=$false; MinimumBuild=$script:WplMemoryWindows81Build; DescriptionKey='MemoryAreaRegistryCache' }
        [pscustomobject][ordered]@{ Id='CombineMemoryLists'; RequiresElevation=$true; RecordOnly=$false; MinimumBuild=$script:WplMemoryWindows10Build; DescriptionKey='MemoryAreaCombineMemoryLists' }
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

function New-WplMemoryResult {
    param(
        [string]$Id,
        [bool]$Success,
        [bool]$Skipped,
        [object]$Status,
        [string]$StatusHex,
        [string]$Message,
        [object]$ProcessId,
        [object]$Detail
    )
    [pscustomobject][ordered]@{
        Id=$Id; Success=[bool]$Success; Skipped=[bool]$Skipped; ReportOnly=$false
        Status=$Status; StatusHex=$StatusHex; Message=$Message; ProcessId=$ProcessId
        Detail=$Detail
    }
}

function Get-WplVolumePaths {
    # Win32_Volume is used instead of Win32_LogicalDisk so mount-point-only
    # volumes without a drive letter are covered as well.
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($volume in @(Get-CimInstance -ClassName Win32_Volume -ErrorAction SilentlyContinue)) {
        $path = $null
        # Win32_Volume reports DriveLetter with the colon, so it is dropped
        # before the device-path prefix is rebuilt.
        if ($volume.DriveLetter) { $path = ('\\.\{0}:' -f ([string]$volume.DriveLetter).TrimEnd(':')) }
        elseif ($volume.DeviceID) { $path = ([string]$volume.DeviceID).TrimEnd('\') }
        if ($path -and -not $paths.Contains($path)) { $paths.Add($path) }
    }
    if (-not $paths.Count) {
        foreach ($disk in @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 3 })) {
            if ($disk.DeviceID) { $paths.Add(('{0}\' -f $disk.DeviceID)) }
        }
    }
    return @($paths)
}

function Invoke-WplVolumeCacheCleanup {
    # Mem Reduct reaches this region through NtCreateFile on the mount-manager
    # volume symbolic links. The documented CreateFile and FlushFileBuffers pair
    # on the same volume handles produces the identical cache flush, so the
    # public API is used instead of the undocumented device IOCTL.
    # The L suffix matters: 0xC0000000 alone is parsed as a negative Int32 and
    # cannot be cast to UInt32.
    $genericReadWrite = [uint32]0xC0000000L # GENERIC_READ | GENERIC_WRITE
    $shareReadWrite = [uint32]0x3L # FILE_SHARE_READ | FILE_SHARE_WRITE
    $openExisting = [uint32]0x3L
    $invalidHandle = [IntPtr]::new(-1)
    try { $volumes = @(Get-WplVolumePaths) }
    catch { return (New-WplMemoryResult -Id 'ModifiedFileCache' -Success $false -Skipped $false -Message ('Volumes could not be enumerated: {0}' -f $_.Exception.Message)) }
    if (-not $volumes.Count) {
        return (New-WplMemoryResult -Id 'ModifiedFileCache' -Success $false -Skipped $true -Message 'No mounted volumes were reported; the volume cache was not flushed.')
    }
    $flushed = [Collections.Generic.List[string]]::new()
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($volume in $volumes) {
        $handle = $invalidHandle
        try {
            $handle = [WplMemoryNative]::CreateFile($volume,$genericReadWrite,$shareReadWrite,[IntPtr]::Zero,$openExisting,0,[IntPtr]::Zero)
            if ($handle -eq $invalidHandle) {
                $failures.Add(('{0} (Win32 error {1})' -f $volume,[Runtime.InteropServices.Marshal]::GetLastWin32Error()))
                continue
            }
            if ([WplMemoryNative]::FlushFileBuffers($handle)) { $flushed.Add($volume) }
            else { $failures.Add(('{0} (Win32 error {1})' -f $volume,[Runtime.InteropServices.Marshal]::GetLastWin32Error())) }
        }
        catch { $failures.Add(('{0} ({1})' -f $volume,$_.Exception.Message)) }
        finally { if ($handle -ne $invalidHandle) { [void][WplMemoryNative]::CloseHandle($handle) } }
    }
    $total = $volumes.Count
    $message = if ($failures.Count -eq 0) { 'Flushed the write cache of {0} of {0} volumes.' -f $total }
        else { 'Flushed {0} of {1} volumes; failed: {2}' -f $flushed.Count,$total,($failures -join ', ') }
    New-WplMemoryResult -Id 'ModifiedFileCache' -Success ($failures.Count -eq 0) -Skipped ($flushed.Count -eq 0) -Message $message -Detail $flushed.Count
}

function Invoke-WplCombineMemoryLists {
    $buffer = [IntPtr]::Zero
    try {
        $size = [Runtime.InteropServices.Marshal]::SizeOf([type][WplMemoryNative+MEMORY_COMBINE_INFORMATION_EX])
        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
        # Mem Reduct passes a zeroed structure, which asks the kernel to combine
        # every physical memory list rather than one process-owned list.
        for ($offset = 0; $offset -lt $size; $offset++) { [Runtime.InteropServices.Marshal]::WriteByte($buffer,$offset,[byte]0) }
        $status = [WplMemoryNative]::NtSetSystemInformation([int]$script:WplMemoryCombineMemoryClass,$buffer,$size)
        $mapped = Get-WplNtStatusDescription $status
        New-WplMemoryResult -Id 'CombineMemoryLists' -Success ([bool]$mapped.Success) -Skipped $false -Status $mapped.Status -StatusHex $mapped.StatusHex -Message $mapped.Message -Detail $size
    }
    catch { New-WplMemoryResult -Id 'CombineMemoryLists' -Success $false -Skipped $false -Message $_.Exception.Message }
    finally { if ($buffer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) } }
}

function Invoke-WplRegistryCacheCleanup {
    # SystemRegistryReconciliationInformation flushes the registry hives to disk.
    # It changes no registry value and needs no buffer, only administrator rights.
    try {
        $status = [WplMemoryNative]::NtSetSystemInformation([int]$script:WplMemoryRegistryReconciliationClass,[IntPtr]::Zero,0)
        $mapped = Get-WplNtStatusDescription $status
        New-WplMemoryResult -Id 'RegistryCache' -Success ([bool]$mapped.Success) -Skipped $false -Status $mapped.Status -StatusHex $mapped.StatusHex -Message $mapped.Message
    }
    catch { New-WplMemoryResult -Id 'RegistryCache' -Success $false -Skipped $false -Message $_.Exception.Message }
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
    # Combined reproduces Mem Reduct's REDUCT_MASK_DEFAULT: every region except
    # the two freeze entries that Mem Reduct also leaves out of its default mask.
    $combined = @(Get-WplMemoryCleanupArea | Where-Object { -not $_.RecordOnly } | ForEach-Object Id)
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

function Get-WplMemoryCleanupStatistics([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Update-WplMemoryCleanupStatistics([string]$Path,[object]$DeltaBytes,[object]$Performed) {
    # Mem Reduct keeps its StatisticLastReduct and running totals in a config
    # file. The portable lab writes the same counters next to the per-run logs
    # instead of a registry key or an application settings file.
    $previous = Get-WplMemoryCleanupStatistics -Path $Path
    $total = [int64]0
    $count = 0
    if ($previous) {
        if ($null -ne $previous.TotalFreedBytes) { try { $total = [int64]$previous.TotalFreedBytes } catch { $total = [int64]0 } }
        if ($null -ne $previous.RunCount) { try { $count = [int]$previous.RunCount } catch { $count = 0 } }
    }
    $freed = if ($null -ne $DeltaBytes) { [int64]$DeltaBytes } else { [int64]0 }
    if ($freed -lt 0) { $freed = [int64]0 }
    $total = $total + $freed
    $count = $count + 1
    $record = [pscustomobject][ordered]@{
        schemaVersion = 1
        runCount = $count
        totalFreedBytes = $total
        lastFreedBytes = $freed
        lastAreas = @($Performed)
        lastCleanupAt = (Get-Date).ToString('o')
    }
    try {
        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding utf8
    }
    catch { }
    return $record
}

function Get-WplMemoryBoundedInt([object]$Value,[int]$Default,[int]$Minimum,[int]$Maximum) {
    $number = $Default
    if ($null -ne $Value) { try { $number = [int]$Value } catch { $number = $Default } }
    # Compared rather than clamped with Math.Min/Max so the module keeps its
    # absolute ban on Int32-sensitive Math calls in this file.
    if ($number -lt $Minimum) { $number = $Minimum }
    if ($number -gt $Maximum) { $number = $Maximum }
    return $number
}

function Get-WplMemoryMember([object]$Object,[string]$Name) {
    # Strict mode turns a missing property into a terminating error, so optional
    # members are read through this guard. A settings file written by an older
    # build keeps loading instead of failing the whole policy read.
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Object.$Name
}

function Get-WplMemoryAutoCleanupPolicy {
    <#
        Mem Reduct keeps its automatic reduction beside the manual mask with
        DEFAULT_AUTOREDUCT_VAL (90 percent), AUTOREDUCT_COOLDOWN (30 seconds)
        and DEFAULT_AUTOREDUCTINTERVAL_VAL (30 seconds). The same three values
        are the defaults here. The preference is stored in the portable
        configuration file, so an enabled automatic plan still leaves nothing
        behind on the host machine.
    #>
    param([string]$Path)

    $policy = [pscustomobject][ordered]@{
        Enabled = $false
        ThresholdPercent = 90
        CooldownSeconds = 30
        IntervalSeconds = 30
        Areas = @(Resolve-WplMemoryAreaIds @('Combined'))
        StartWithWindows = $false
    }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $policy }
    try { $store = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $policy }
    $saved = Get-WplMemoryMember -Object $store -Name 'memoryAutoCleanup'
    if (-not $saved) { return $policy }

    $policy.Enabled = [bool](Get-WplMemoryMember -Object $saved -Name 'enabled')
    $policy.StartWithWindows = [bool](Get-WplMemoryMember -Object $saved -Name 'startWithWindows')
    $policy.ThresholdPercent = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $saved -Name 'thresholdPercent') -Default 90 -Minimum 50 -Maximum 99
    $policy.CooldownSeconds = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $saved -Name 'cooldownSeconds') -Default 30 -Minimum 5 -Maximum 3600
    $policy.IntervalSeconds = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $saved -Name 'intervalSeconds') -Default 30 -Minimum 5 -Maximum 3600
    $areas = @()
    foreach ($area in @(Get-WplMemoryMember -Object $saved -Name 'areas')) { if ($area) { $areas += ([string]$area).Trim() } }
    if ($areas.Count) {
        try { $policy.Areas = @(Resolve-WplMemoryAreaIds $areas) }
        catch { $policy.Areas = @(Resolve-WplMemoryAreaIds @('Combined')) }
    }
    return $policy
}

function Set-WplMemoryAutoCleanupPolicy {
    # Only the memoryAutoCleanup member is replaced; every other setting in the
    # file (language and recommendation preferences) survives the write.
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Policy)

    $store = [ordered]@{}
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            if ($existing) {
                foreach ($property in $existing.PSObject.Properties) {
                    if ($property.Name -ne 'memoryAutoCleanup') { $store[$property.Name] = $property.Value }
                }
            }
        }
        catch { }
    }
    $store['memoryAutoCleanup'] = [ordered]@{
        enabled = [bool](Get-WplMemoryMember -Object $Policy -Name 'Enabled')
        thresholdPercent = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $Policy -Name 'ThresholdPercent') -Default 90 -Minimum 50 -Maximum 99
        cooldownSeconds = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $Policy -Name 'CooldownSeconds') -Default 30 -Minimum 5 -Maximum 3600
        intervalSeconds = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $Policy -Name 'IntervalSeconds') -Default 30 -Minimum 5 -Maximum 3600
        areas = @(Get-WplMemoryMember -Object $Policy -Name 'Areas')
        startWithWindows = [bool](Get-WplMemoryMember -Object $Policy -Name 'StartWithWindows')
    }
    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $store | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding utf8
    return (Get-WplMemoryAutoCleanupPolicy -Path $Path)
}

function Test-WplMemoryAutoCleanupDue {
    # Pure decision so the threshold, cooldown and interval rules can be
    # exercised without touching live memory. The cooldown is measured against
    # the persisted last-cleanup timestamp, so it survives a restart.
    param([object]$Policy,[object]$UsedPercent,[object]$LastRunAt,[object]$Now)

    $result = [pscustomobject][ordered]@{ Due=$false; Reason='disabled'; UsedPercent=$UsedPercent; ThresholdPercent=$null; CooldownSeconds=$null }
    if (-not $Policy -or -not [bool](Get-WplMemoryMember -Object $Policy -Name 'Enabled')) { return $result }
    $result.ThresholdPercent = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $Policy -Name 'ThresholdPercent') -Default 90 -Minimum 50 -Maximum 99
    $result.CooldownSeconds = Get-WplMemoryBoundedInt -Value (Get-WplMemoryMember -Object $Policy -Name 'CooldownSeconds') -Default 30 -Minimum 5 -Maximum 3600
    if ($null -eq $UsedPercent) { $result.Reason = 'unknown-usage'; return $result }
    $used = 0.0
    try { $used = [double]$UsedPercent } catch { $result.Reason = 'unknown-usage'; return $result }
    if ($used -lt $result.ThresholdPercent) { $result.Reason = 'below-threshold'; return $result }
    $moment = if ($Now) { [datetime]$Now } else { Get-Date }
    $previous = $null
    if ($LastRunAt) { try { $previous = [datetime]$LastRunAt } catch { $previous = $null } }
    if ($previous -and ($moment - $previous).TotalSeconds -lt $result.CooldownSeconds) { $result.Reason = 'cooldown'; return $result }
    $result.Due = $true
    $result.Reason = 'threshold-reached'
    return $result
}

function Invoke-WplMemoryAutoCleanup {
    param([object]$Policy,[string]$StatsPath,[switch]$Report)

    if (-not $Policy) { $Policy = Get-WplMemoryAutoCleanupPolicy }
    $snapshot = Get-WplMemorySnapshot
    $statistics = if ($StatsPath) { Get-WplMemoryCleanupStatistics -Path $StatsPath } else { $null }
    $lastRun = Get-WplMemoryMember -Object $statistics -Name 'lastCleanupAt'
    $due = Test-WplMemoryAutoCleanupDue -Policy $Policy -UsedPercent $snapshot.UsedPercent -LastRunAt $lastRun
    $planAreas = @(Get-WplMemoryMember -Object $Policy -Name 'Areas')
    $summary = [ordered]@{
        Requested = $planAreas
        Performed = $false
        ReportOnly = [bool]$Report
        Reason = $due.Reason
        UsedPercent = $snapshot.UsedPercent
        ThresholdPercent = $due.ThresholdPercent
        CooldownSeconds = $due.CooldownSeconds
        Snapshot = $snapshot
        Cleanup = $null
    }
    if (-not $due.Due) { return [pscustomobject]$summary }
    # The two freeze regions stay outside the default plan. An automatic plan
    # that points at them still needs the explicit acknowledgement, so the
    # resident path can never silently discard reclaimable pages.
    $freezeIds = @(Get-WplMemoryCleanupArea | Where-Object { $_.RecordOnly } | ForEach-Object Id)
    $freezeSelected = @($planAreas | Where-Object { $freezeIds -contains $_ })
    if ($freezeSelected.Count -gt 0) { throw ('Automatic cleanup cannot use the opt-in freeze regions: {0}.' -f ($freezeSelected -join ', ')) }
    $summary.Cleanup = Clear-WplSystemMemory -Area $planAreas -Report:$Report -StatsPath $StatsPath
    $summary.Performed = -not [bool]$Report
    return [pscustomobject]$summary
}

function Clear-WplSystemMemory {
    [CmdletBinding()]
    param(
        [string[]]$Area = @('Combined'),
        [int[]]$ProcessId,
        [switch]$Report,
        [switch]$AcknowledgeRisk,
        [string]$StatsPath
    )

    $areas = @(Get-WplMemoryCleanupArea)
    $areaIds = @(Resolve-WplMemoryAreaIds $Area)
    $processIds = @($ProcessId | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    $before = Get-WplMemorySnapshot
    $requested = [ordered]@{ Areas=@($areaIds); ProcessIds=@($processIds) }
    $results = [Collections.Generic.List[object]]::new()
    $performed = [Collections.Generic.List[string]]::new()

    if ($Report) {
        foreach ($id in $areaIds) { $results.Add([pscustomobject][ordered]@{ Id=$id; Success=$false; Skipped=$false; ReportOnly=$true; Status=$null; StatusHex=$null; Message='Plan only; no native cleanup was executed.'; ProcessId=$null; Detail=$null }) }
        foreach ($id in $processIds) { $results.Add([pscustomobject][ordered]@{ Id=('Process:{0}' -f $id); Success=$false; Skipped=$false; ReportOnly=$true; Status=$null; StatusHex=$null; Message='Plan only; no process working-set cleanup was executed.'; ProcessId=$id; Detail=$null }) }
        return [pscustomobject][ordered]@{ Requested=$requested; Performed=@(); ReportOnly=$true; Before=$before; After=$before; DeltaBytes=0; Results=@($results); Statistics=$null }
    }

    if (-not (Test-WplMemoryWindows)) { throw 'Native memory cleanup is available only on Windows.' }
    # The freeze regions are the only ones Mem Reduct keeps out of its default
    # mask, and they discard reclaimable and not-yet-written pages, so they need
    # an explicit acknowledgement before a real call.
    $freezeIds = @($areas | Where-Object { $_.RecordOnly } | ForEach-Object Id)
    $freezeAreas = @($areaIds | Where-Object { $freezeIds -contains $_ })
    if ($freezeAreas.Count -gt 0 -and -not $AcknowledgeRisk) {
        throw "Memory areas requiring risk acknowledgement were selected: $($freezeAreas -join ', '). Re-run with -AcknowledgeRisk."
    }
    $support = Test-WplMemoryCleanupSupport
    if (-not $support.IsElevated) { throw 'Administrator rights are required to execute native memory cleanup.' }
    # A live call to SystemCombinePhysicalMemoryInformation returns
    # STATUS_PRIVILEGE_NOT_HELD without SeProfileSingleProcessPrivilege, so it
    # belongs to the same privilege group as the memory-list commands.
    $profileIds = @('WorkingSet','ModifiedPageList','StandbyList','LowPriorityStandbyList','CombineMemoryLists')
    $needsProfilePrivilege = @($areaIds | Where-Object { $profileIds -contains $_ }).Count -gt 0
    if ($needsProfilePrivilege -and -not $support.CanEnableSeProfileSingleProcess) { throw 'SeProfileSingleProcessPrivilege could not be enabled; native memory-list cleanup was not executed.' }
    if ($areaIds -contains 'SystemFileCache' -and -not $support.CanEnableSeIncreaseQuota) { throw 'SeIncreaseQuotaPrivilege could not be enabled; system file-cache cleanup was not executed.' }
    Initialize-WplMemoryNativeType

    $build = Get-WplMemoryOsBuild
    foreach ($id in $areaIds) {
        $area = $areas | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($area -and $area.MinimumBuild -and ($null -eq $build -or $build -lt $area.MinimumBuild)) {
            $results.Add([pscustomobject][ordered]@{ Id=$id; Success=$false; Skipped=$true; ReportOnly=$false; Status=$null; StatusHex=$null; Message=('This Windows build ({0}) does not provide the {1} region; build {2} or later is required.' -f $build,$id,$area.MinimumBuild); ProcessId=$null; Detail=$null })
            continue
        }
        $result = switch ($id) {
            'WorkingSet' { Invoke-WplMemoryListCommand $id $script:WplMemoryEmptyWorkingSets; break }
            'ModifiedPageList' { Invoke-WplMemoryListCommand $id $script:WplMemoryFlushModifiedList; break }
            'StandbyList' { Invoke-WplMemoryListCommand $id $script:WplMemoryPurgeStandbyList; break }
            'LowPriorityStandbyList' { Invoke-WplMemoryListCommand $id $script:WplMemoryPurgeLowPriorityStandbyList; break }
            'SystemFileCache' { Invoke-WplSystemFileCacheCleanup; break }
            'ModifiedFileCache' { Invoke-WplVolumeCacheCleanup; break }
            'RegistryCache' { Invoke-WplRegistryCacheCleanup; break }
            'CombineMemoryLists' { Invoke-WplCombineMemoryLists; break }
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
    $statistics = if ($StatsPath) { Update-WplMemoryCleanupStatistics -Path $StatsPath -DeltaBytes $delta -Performed $performed } else { $null }
    [pscustomobject][ordered]@{ Requested=$requested; Performed=@($performed); ReportOnly=$false; Before=$before; After=$after; DeltaBytes=$delta; Results=@($results); Statistics=$statistics }
}

Export-ModuleMember -Function Get-WplMemorySnapshot,Get-WplMemoryCleanupArea,Test-WplMemoryCleanupSupport,Get-WplMemoryCleanupStatistics,Get-WplMemoryAutoCleanupPolicy,Set-WplMemoryAutoCleanupPolicy,Test-WplMemoryAutoCleanupDue,Invoke-WplMemoryAutoCleanup,Clear-WplSystemMemory
