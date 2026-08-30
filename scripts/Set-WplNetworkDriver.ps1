[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('status','backup','restore','list')][string]$Action = 'status',
    [string]$BackupPath,
    [switch]$AcknowledgeRisk,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force

$Root = (Resolve-Path -LiteralPath $Root).Path
$driverStore = Join-Path $Root 'offline-packs\network-drivers'
$sdioRoot = Join-Path $Root 'tools\09-Driver-Detection-Maintenance\sdio'

function Get-NetworkAdapterInventory {
    # Win32_NetworkAdapter reports VPN TAP/TUN drivers as physical adapters, so
    # the bus prefix decides instead: only PCI, USB, and PCMCIA devices are real
    # NICs whose driver is worth exporting. A disconnected NIC still counts.
    $adapters = @()
    try {
        $adapters = @(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
            Where-Object { $_.PhysicalAdapter -and ([string]$_.PNPDeviceID -match '^(PCI|USB|PCMCIA)\\') })
    } catch { return @() }
    $signed = @{}
    try {
        foreach ($driver in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.DeviceClass -eq 'NET' })) {
            if ($driver.DeviceID) { $signed[[string]$driver.DeviceID] = $driver }
        }
    } catch { }
    foreach ($adapter in $adapters) {
        $driver = $null
        if ($adapter.PNPDeviceID -and $signed.ContainsKey([string]$adapter.PNPDeviceID)) { $driver = $signed[[string]$adapter.PNPDeviceID] }
        [pscustomobject]@{
            Name = [string]$adapter.Name
            Manufacturer = [string]$adapter.Manufacturer
            PnpDeviceId = [string]$adapter.PNPDeviceID
            NetConnectionStatus = [string]$adapter.NetConnectionStatus
            DriverVersion = if ($driver) { [string]$driver.DriverVersion } else { $null }
            DriverProvider = if ($driver) { [string]$driver.DriverProviderName } else { $null }
            InfName = if ($driver) { [string]$driver.InfName } else { $null }
            IsWireless = ([string]$adapter.Name -match '(?i)wi-?fi|wireless|wlan|802\.11')
        }
    }
}

function Get-SdioPackState {
    # SDIO ships indexes separately from the driver archives. Only the archives
    # make an offline install possible, so both are reported.
    $state = [pscustomobject]@{ Installed=$false; IndexCount=0; NetworkIndexes=@(); PackCount=0; NetworkPacks=@(); DriversPath=$null }
    if (-not (Test-Path -LiteralPath $sdioRoot -PathType Container)) { return $state }
    $state.Installed = $true
    $indexes = @(Get-ChildItem -LiteralPath $sdioRoot -Filter '*.bin' -File -Recurse -ErrorAction SilentlyContinue)
    $state.IndexCount = $indexes.Count
    $state.NetworkIndexes = @($indexes | Where-Object { $_.Name -match '(?i)_P_(LAN|WLAN|Net)' } | ForEach-Object { $_.Name })
    $driversDir = @(Get-ChildItem -LiteralPath $sdioRoot -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'drivers' } | Select-Object -First 1)
    if ($driversDir.Count) {
        $state.DriversPath = $driversDir[0].FullName
        $packs = @(Get-ChildItem -LiteralPath $driversDir[0].FullName -Filter '*.7z' -File -ErrorAction SilentlyContinue)
        $state.PackCount = $packs.Count
        $state.NetworkPacks = @($packs | Where-Object { $_.Name -match '(?i)(LAN|WLAN|Net)' } | ForEach-Object { $_.Name })
    }
    return $state
}

switch ($Action) {
    'status' {
        $adapters = @(Get-NetworkAdapterInventory)
        $sdio = Get-SdioPackState
        $backups = @()
        if (Test-Path -LiteralPath $driverStore -PathType Container) {
            $backups = @(Get-ChildItem -LiteralPath $driverStore -Directory -ErrorAction SilentlyContinue)
        }
        Write-Host (Get-WplText -Key NetDriverAdapters -Language $Language -ArgumentList @($adapters.Count)) -ForegroundColor Cyan
        $adapters | Select-Object Name,DriverProvider,DriverVersion,IsWireless,InfName | Format-Table -AutoSize
        Write-Host (Get-WplText -Key NetDriverSdioState -Language $Language -ArgumentList @($sdio.Installed,$sdio.IndexCount,$sdio.PackCount)) -ForegroundColor Cyan
        if ($sdio.NetworkIndexes.Count) { Write-Host ('  indexes: ' + ($sdio.NetworkIndexes -join ', ')) -ForegroundColor DarkGray }
        if ($sdio.NetworkPacks.Count) { Write-Host ('  packs: ' + ($sdio.NetworkPacks -join ', ')) -ForegroundColor DarkGray }
        if ($sdio.Installed -and $sdio.PackCount -eq 0) {
            Write-Host (Get-WplText -Key NetDriverPacksMissing -Language $Language -ArgumentList @($sdio.DriversPath)) -ForegroundColor Yellow
        }
        Write-Host (Get-WplText -Key NetDriverBackupCount -Language $Language -ArgumentList @($backups.Count,$driverStore)) -ForegroundColor Cyan
        $readyOffline = ($sdio.PackCount -gt 0) -or ($backups.Count -gt 0)
        Write-Host (Get-WplText -Key $(if ($readyOffline) { 'NetDriverOfflineReady' } else { 'NetDriverOfflineNotReady' }) -Language $Language) -ForegroundColor $(if ($readyOffline) { 'Green' } else { 'Yellow' })
        return
    }
    'backup' {
        # Exports the current machine's network drivers so the same model can be
        # repaired later without internet. Read-only against the live system.
        if (-not (Test-WplAdministrator)) { throw (Get-WplText -Key NetDriverNeedsAdmin -Language $Language) }
        $adapters = @(Get-NetworkAdapterInventory)
        if (-not $adapters.Count) { throw (Get-WplText -Key NetDriverNoAdapters -Language $Language) }
        $stamp = '{0}-{1}' -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd-HHmmss')
        $target = if ($BackupPath) { $BackupPath } else { Join-Path $driverStore $stamp }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $exported = 0
        $failures = @()
        foreach ($adapter in $adapters) {
            if (-not $adapter.InfName) { $failures += ('{0}: no INF recorded' -f $adapter.Name); continue }
            $destination = Join-Path $target ($adapter.InfName -replace '[^A-Za-z0-9._-]','_')
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            $output = & pnputil.exe /export-driver $adapter.InfName $destination 2>&1
            if ($LASTEXITCODE -eq 0) { $exported++ }
            else { $failures += ('{0}: {1}' -f $adapter.Name,(($output | Out-String).Trim())) }
        }
        $manifest = [ordered]@{
            schemaVersion = 1
            computer = $env:COMPUTERNAME
            createdAt = (Get-Date).ToString('o')
            windowsBuild = [string](Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
            adapters = @($adapters | ForEach-Object { [ordered]@{ name=$_.Name; provider=$_.DriverProvider; version=$_.DriverVersion; inf=$_.InfName; wireless=$_.IsWireless; pnpDeviceId=$_.PnpDeviceId } })
            exportedInfCount = $exported
            failures = @($failures)
        }
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $target 'NETWORK-DRIVER-MANIFEST.json') -Encoding utf8
        Write-Host (Get-WplText -Key NetDriverBackupDone -Language $Language -ArgumentList @($exported,$adapters.Count,$target)) -ForegroundColor Green
        if ($failures.Count) { $failures | ForEach-Object { Write-Warning $_ } }
        return
    }
    'list' {
        if (-not (Test-Path -LiteralPath $driverStore -PathType Container)) {
            Write-Host (Get-WplText -Key NetDriverNoBackups -Language $Language -ArgumentList @($driverStore)) -ForegroundColor Yellow
            return
        }
        $rows = foreach ($dir in @(Get-ChildItem -LiteralPath $driverStore -Directory | Sort-Object Name -Descending)) {
            $manifestPath = Join-Path $dir.FullName 'NETWORK-DRIVER-MANIFEST.json'
            $manifest = if (Test-Path -LiteralPath $manifestPath) { Read-WplJson -Path $manifestPath } else { $null }
            [pscustomobject]@{
                Backup = $dir.Name
                Computer = if ($manifest) { [string]$manifest.computer } else { 'unknown' }
                Build = if ($manifest) { [string]$manifest.windowsBuild } else { '' }
                Adapters = if ($manifest) { @($manifest.adapters).Count } else { 0 }
                ExportedInf = if ($manifest) { [int]$manifest.exportedInfCount } else { 0 }
            }
        }
        if (-not @($rows).Count) { Write-Host (Get-WplText -Key NetDriverNoBackups -Language $Language -ArgumentList @($driverStore)) -ForegroundColor Yellow; return }
        $rows | Format-Table -AutoSize
        return
    }
    'restore' {
        # Installing a driver changes the system, so it is gated behind an
        # explicit acknowledgement like every other write-capable action here.
        if (-not $AcknowledgeRisk) { throw (Get-WplText -Key NetDriverRestoreNeedsRisk -Language $Language) }
        if (-not (Test-WplAdministrator)) { throw (Get-WplText -Key NetDriverNeedsAdmin -Language $Language) }
        if (-not $BackupPath) { throw (Get-WplText -Key NetDriverRestoreNeedsPath -Language $Language) }
        if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) { throw (Get-WplText -Key NetDriverRestoreBadPath -Language $Language -ArgumentList @($BackupPath)) }
        $infFiles = @(Get-ChildItem -LiteralPath $BackupPath -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
        if (-not $infFiles.Count) { throw (Get-WplText -Key NetDriverRestoreNoInf -Language $Language -ArgumentList @($BackupPath)) }
        $added = 0
        $failures = @()
        foreach ($inf in $infFiles) {
            $output = & pnputil.exe /add-driver $inf.FullName /install 2>&1
            if ($LASTEXITCODE -eq 0) { $added++ } else { $failures += ('{0}: {1}' -f $inf.Name,(($output | Out-String).Trim())) }
        }
        Write-Host (Get-WplText -Key NetDriverRestoreDone -Language $Language -ArgumentList @($added,$infFiles.Count)) -ForegroundColor Green
        if ($failures.Count) { $failures | ForEach-Object { Write-Warning $_ } }
        return
    }
}
