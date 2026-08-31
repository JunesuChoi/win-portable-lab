[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $root -Requested $Language

function Invoke-SafeCollection {
    param([Parameter(Mandatory)][scriptblock]$Action)
    try {
        return @(& $Action)
    }
    catch {
        return @([pscustomobject]@{ Error = $_.Exception.Message })
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'UNKNOWN-PC' }
$safeName = $computerName -replace '[^A-Za-z0-9._-]', '_'
$reportDirectory = Join-Path $OutputRoot "$safeName-$timestamp"
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null

$admin = Test-IsAdministrator
$secureBoot = try { Confirm-SecureBootUEFI } catch { $null }

$inventory = [ordered]@{
    SchemaVersion = '0.2.0'
    CapturedAt = (Get-Date).ToString('o')
    ComputerName = $computerName
    IsAdministrator = $admin
    CollectionMode = if($admin){'elevated-detailed'}else{'standard-limited'}
    SecureBoot = $secureBoot
    OperatingSystem = Invoke-SafeCollection {
        Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime, InstallDate, Locale, OSLanguage, ProductType, WindowsDirectory, SystemDrive
    }
    ComputerSystem = Invoke-SafeCollection {
        Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemType, TotalPhysicalMemory, HypervisorPresent, PCSystemType, PowerState
    }
    Processor = Invoke-SafeCollection {
        Get-CimInstance Win32_Processor | Select-Object Name, Manufacturer, ProcessorId, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, CurrentClockSpeed, VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions, SocketDesignation
    }
    BaseBoard = Invoke-SafeCollection {
        Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, Version
    }
    Bios = Invoke-SafeCollection {
        Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SMBIOSMajorVersion, SMBIOSMinorVersion, Status
    }
    MemoryModules = Invoke-SafeCollection {
        Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, DeviceLocator, Manufacturer, PartNumber, SerialNumber, Capacity, Speed, ConfiguredClockSpeed, ConfiguredVoltage, MinVoltage, MaxVoltage, SMBIOSMemoryType, FormFactor, DataWidth, TotalWidth, InterleavePosition, PositionInRow
    }
    Graphics = Invoke-SafeCollection {
        Get-CimInstance Win32_VideoController | Select-Object Name, AdapterCompatibility, DriverVersion, DriverDate, AdapterRAM, VideoModeDescription, PNPDeviceID
    }
    Batteries = Invoke-SafeCollection {
        Get-CimInstance Win32_Battery | Select-Object Name, DeviceID, DesignVoltage, Chemistry, EstimatedChargeRemaining
    }
    DiskDrives = Invoke-SafeCollection {
        Get-CimInstance Win32_DiskDrive | Select-Object Model, InterfaceType, MediaType, FirmwareRevision, Size, Status, PNPDeviceID
    }
    PhysicalDisks = Invoke-SafeCollection {
        Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size, FirmwareVersion
    }
    Volumes = Invoke-SafeCollection {
        Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystemType, HealthStatus, OperationalStatus, Size, SizeRemaining, AllocationUnitSize
    }
    Partitions = Invoke-SafeCollection {
        Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, Type, Size, IsBoot, IsSystem, IsActive, IsReadOnly, IsOffline
    }
    StorageReliability = Invoke-SafeCollection {
        Get-PhysicalDisk | ForEach-Object {
            $disk = $_
            $counter = $null
            try { $counter = $disk | Get-StorageReliabilityCounter -ErrorAction Stop }
            catch {
                [pscustomobject]@{FriendlyName=$disk.FriendlyName;Available=$false;Error=$_.Exception.Message}
            }
            if($counter){[pscustomobject]@{
                FriendlyName = $disk.FriendlyName
                Available = $true
                Temperature = $counter.Temperature
                TemperatureMax = $counter.TemperatureMax
                Wear = $counter.Wear
                PowerOnHours = $counter.PowerOnHours
                ReadErrorsTotal = $counter.ReadErrorsTotal
                ReadErrorsUncorrected = $counter.ReadErrorsUncorrected
                WriteErrorsTotal = $counter.WriteErrorsTotal
                WriteErrorsUncorrected = $counter.WriteErrorsUncorrected
            }}
        }
    }
    PnpProblems = Invoke-SafeCollection {
        Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object Class, FriendlyName, InstanceId, Status, Problem
    }
    StorageControllers = Invoke-SafeCollection {
        Get-PnpDevice -PresentOnly | Where-Object Class -in @('SCSIAdapter','HDC','Storage') | Select-Object Class, FriendlyName, InstanceId, Status, Problem
    }
    NetworkAdapters = Invoke-SafeCollection {
        Get-CimInstance Win32_NetworkAdapter | Where-Object PhysicalAdapter | Select-Object Name, Manufacturer, AdapterType, NetConnectionStatus, Speed, PNPDeviceID
    }
    SignedDrivers = Invoke-SafeCollection {
        Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceName | Select-Object DeviceName, DeviceClass, DriverProviderName, DriverVersion, DriverDate, IsSigned, Signer, InfName
    }
    Tpm = Invoke-SafeCollection {
        Get-Tpm -ErrorAction Stop | Select-Object TpmPresent, TpmReady, TpmEnabled, TpmActivated, TpmOwned, RestartPending, ManufacturerIdTxt, ManufacturerVersion, AutoProvisioning
    }
    BitLockerVolumes = Invoke-SafeCollection {
        Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus, EncryptionMethod, EncryptionPercentage, LockStatus, AutoUnlockEnabled
    }
    DeviceGuard = Invoke-SafeCollection {
        Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop |
            Select-Object VirtualizationBasedSecurityStatus, SecurityServicesConfigured, SecurityServicesRunning, RequiredSecurityProperties, AvailableSecurityProperties, CodeIntegrityPolicyEnforcementStatus, UsermodeCodeIntegrityPolicyEnforcementStatus
    }
    HotFixes = Invoke-SafeCollection {
        Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 50 HotFixID, Description, InstalledOn
    }
    PageFiles = Invoke-SafeCollection {
        Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
    }
    PowerPlan = Invoke-SafeCollection {
        Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan | Where-Object IsActive |
            Select-Object ElementName, InstanceID, IsActive
    }
}

$eventStart = [DateTime]::Now.AddDays(-7)
$events = Invoke-SafeCollection {
    $providers = @(
        'Microsoft-Windows-WHEA-Logger',
        'Microsoft-Windows-Kernel-PnP',
        'Microsoft-Windows-Kernel-Power',
        'Microsoft-Windows-WER-SystemErrorReporting',
        'disk',
        'Display',
        'Service Control Manager'
    )

    # Windows PowerShell 5.1 can serialize StartTime through the current UI
    # culture before FilterHashtable consumes it. Limit the initial read and
    # compare DateTime values in-process to keep the filter locale-independent.
    # Level and ProviderName are locale-independent, so they are pushed into the
    # server-side filter; only the timestamp comparison stays in-process. Reading
    # 5000 unfiltered records cost about 7s versus under 1s filtered.
    $filtered = $null
    try {
        $filtered = @(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2,3;ProviderName=$providers} -MaxEvents 2000 -ErrorAction Stop)
    }
    catch {
        # An empty result is a legitimate outcome, not a filter failure, so it
        # must not trigger the expensive unfiltered fallback read.
        if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { $filtered = @() }
        else { $filtered = $null }
    }
    if ($null -eq $filtered) {
        $filtered = @(Get-WinEvent -LogName 'System' -MaxEvents 5000 -ErrorAction Stop |
            Where-Object { $_.Level -in @(1, 2, 3) -and $_.ProviderName -in $providers })
    }
    $filtered |
        Where-Object { $_.TimeCreated -ge $eventStart } |
        Select-Object -First 500 TimeCreated, ProviderName, Id, LevelDisplayName, Message
}

$inventoryPath = Join-Path $reportDirectory 'hardware.json'
$eventsPath = Join-Path $reportDirectory 'events.json'
$summaryPath = Join-Path $reportDirectory 'summary.html'

$inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inventoryPath -Encoding utf8
$events | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $eventsPath -Encoding utf8

$labels = if($Language -eq 'ko'){@{Computer='컴퓨터';Captured='수집 시각';Administrator='관리자 권한';Mode='수집 수준';SecureBoot='보안 부팅';CPU='CPU';GPU='GPU';Memory='메모리 모듈';Pnp='현재 PnP 문제';Events='관련 시스템 이벤트';Unavailable='확인 불가';Title='WinPortableLab 시스템 정보 보고서';Storage='저장장치 신뢰성';Volumes='볼륨과 파티션';Security='TPM · BitLocker · Device Guard 상태';Drivers='장치와 서명 드라이버';Raw='원시 데이터'}}else{@{Computer='Computer';Captured='Captured';Administrator='Administrator';Mode='Collection mode';SecureBoot='Secure Boot';CPU='CPU';GPU='GPU';Memory='Memory modules';Pnp='Present PnP problems';Events='Relevant system events';Unavailable='Unavailable';Title='WinPortableLab inventory report';Storage='Storage reliability';Volumes='Volumes and partitions';Security='TPM, BitLocker and Device Guard status';Drivers='Devices and signed drivers';Raw='Raw data'}}
$summaryRows = @(
    [pscustomobject]@{ Item = $labels.Computer; Value = $computerName }
    [pscustomobject]@{ Item = $labels.Captured; Value = $inventory.CapturedAt }
    [pscustomobject]@{ Item = $labels.Administrator; Value = $admin }
    [pscustomobject]@{ Item = $labels.Mode; Value = $inventory.CollectionMode }
    [pscustomobject]@{ Item = $labels.SecureBoot; Value = if ($null -eq $secureBoot) { $labels.Unavailable } else { $secureBoot } }
    [pscustomobject]@{ Item = 'CPU'; Value = ($inventory.Processor.Name -join '; ') }
    [pscustomobject]@{ Item = 'GPU'; Value = ($inventory.Graphics.Name -join '; ') }
    [pscustomobject]@{ Item = $labels.Memory; Value = "$(($inventory.MemoryModules | Measure-Object Capacity -Sum).Sum / 1GB) GB / $(@($inventory.MemoryModules | Where-Object {-not $_.Error}).Count) DIMM / $(@($inventory.MemoryModules.ConfiguredClockSpeed | Sort-Object -Unique) -join ', ') MT/s" }
    [pscustomobject]@{ Item = $labels.Pnp; Value = @($inventory.PnpProblems | Where-Object { -not $_.Error }).Count }
    [pscustomobject]@{ Item = $labels.Events; Value = @($events | Where-Object { -not $_.Error }).Count }
)

$style = @'
<style>
body { font-family: Segoe UI, sans-serif; margin: 32px; color: #18212b; }
h1, h2 { color: #123b5d; }
table { border-collapse: collapse; width: 100%; margin-bottom: 24px; }
th, td { border: 1px solid #cbd5df; padding: 8px; text-align: left; vertical-align: top; }
th { background: #edf3f7; }
code { background: #f3f5f7; padding: 2px 4px; }
</style>
'@

$body = @(
    "<h1>$($labels.Title)</h1>"
    ($summaryRows | ConvertTo-Html -Fragment)
    "<h2>$($labels.Memory)</h2>"
    ($inventory.MemoryModules | Where-Object {-not $_.Error} | Select-Object BankLabel,DeviceLocator,Manufacturer,PartNumber,SerialNumber,@{Name='CapacityGB';Expression={[math]::Round($_.Capacity/1GB,2)}},Speed,ConfiguredClockSpeed,ConfiguredVoltage,MinVoltage,MaxVoltage,SMBIOSMemoryType,FormFactor,DataWidth,TotalWidth,InterleavePosition,PositionInRow | ConvertTo-Html -Fragment)
    "<h2>$($labels.Storage)</h2>"
    ($inventory.StorageReliability | ConvertTo-Html -Fragment)
    "<h2>$($labels.Volumes)</h2>"
    ($inventory.Volumes | ConvertTo-Html -Fragment)
    ($inventory.Partitions | ConvertTo-Html -Fragment)
    "<h2>$($labels.Security)</h2>"
    ($inventory.Tpm | ConvertTo-Html -Fragment)
    ($inventory.BitLockerVolumes | ConvertTo-Html -Fragment)
    ($inventory.DeviceGuard | ConvertTo-Html -Fragment)
    "<h2>$($labels.Drivers)</h2>"
    ($inventory.StorageControllers | ConvertTo-Html -Fragment)
    "<h2>$($labels.Pnp)</h2>"
    ($inventory.PnpProblems | ConvertTo-Html -Fragment)
    "<p>$($labels.Raw): <code>hardware.json</code>, <code>events.json</code></p>"
)

ConvertTo-Html -Title "WinPortableLab - $computerName" -Head $style -Body $body | Set-Content -LiteralPath $summaryPath -Encoding utf8

return $reportDirectory
