[CmdletBinding()]
param(
    [ValidateSet('gui','check','list','launch','launch-recommended','menu','validate')]
    [string]$Action = 'gui',
    [ValidateSet('quick','standard','deep','storage','gpu','memory','all')]
    [string]$Profile = 'quick',
    [string[]]$ToolId,
    [switch]$AcknowledgeRisk,
    [switch]$AcknowledgeManualTemperatureMonitoring,
    [switch]$InstallMissing,
    [ValidateSet('ko','en','auto')]
    [string]$Language = 'auto',
    [switch]$NoElevation,
    [switch]$FastRecommendation,
    [string]$ElevationPayload
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'scripts\WinPortableLab.Localization.ps1')

if ($ElevationPayload) {
    try {
        $payloadJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ElevationPayload))
        $payload = $payloadJson | ConvertFrom-Json
        $Action = [string]$payload.Action
        $Profile = [string]$payload.Profile
        $ToolId = @($payload.ToolId)
        $AcknowledgeRisk = [bool]$payload.AcknowledgeRisk
        $AcknowledgeManualTemperatureMonitoring = [bool]$payload.AcknowledgeManualTemperatureMonitoring
        $InstallMissing = [bool]$payload.InstallMissing
        $FastRecommendation = [bool]$payload.FastRecommendation
        $Language = [string]$payload.Language
    }
    catch { throw "Invalid elevation payload: $($_.Exception.Message)" }
}

function Test-WplCurrentAdministrator {
    # One implementation lives in WinPortableLab.Core.psm1; this wrapper exists
    # only because elevation runs before the module import below.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$Language = Resolve-WplLanguage -Root $Root -Requested $Language
if (-not $NoElevation -and -not (Test-WplCurrentAdministrator)) {
    $payload = [ordered]@{
        Action=$Action;Profile=$Profile;ToolId=@($ToolId);AcknowledgeRisk=[bool]$AcknowledgeRisk
        AcknowledgeManualTemperatureMonitoring=[bool]$AcknowledgeManualTemperatureMonitoring
        InstallMissing=[bool]$InstallMissing;FastRecommendation=[bool]$FastRecommendation;Language=$Language
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress -Depth 4)))
    $hostExecutable = (Get-Process -Id $PID).Path
    $elevationArguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -ElevationPayload {1}' -f $PSCommandPath,$encoded
    Write-Host (Get-WplText -Key ElevationRequest -Language $Language) -ForegroundColor Cyan
    try {
        $elevated = Start-Process -FilePath $hostExecutable -ArgumentList $elevationArguments -Verb RunAs -Wait -PassThru
        exit $elevated.ExitCode
    }
    catch {
        Write-Error (Get-WplText -Key ElevationCancelled -Language $Language)
        exit 1223
    }
}

# One recursive walk of tools\ feeds every launcher and manifest lookup below.
# Scanning per candidate meant 19+ full tree walks for a single analysis pass.
$script:WplToolFileIndex = $null
$script:WplManifestIdIndex = $null
$script:WplUserToolPaths = $null

# Output directories are not tracked in git, so the console creates them on the
# first run from a fresh clone before anything tries to write a report or log.
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
# Process helpers own argument encoding, so the GUI never hand-builds a command line.
Import-Module (Join-Path $Root 'src\WinPortableLab.Process.psm1') -Force
[void](Initialize-WplRuntimeDirectory -Root $Root)

# Override reading and executable resolution live in WinPortableLab.Core.psm1.
# The GUI used to reimplement both, and the copies had already drifted: this one
# indexed every file type while the module filtered to *.exe, and the two sliced
# the relative path from different roots. Delegate so one policy governs both.
function Get-WplUserToolPath([string]$LauncherId) {
    return Get-WplToolOverride -Root $Root -LauncherId ([string]$LauncherId)
}

function Get-WplToolFileIndex {
    if ($null -eq $script:WplToolFileIndex) {
        $toolsRoot = Join-Path $Root 'tools'
        $script:WplToolFileIndex = @(Get-ChildItem -LiteralPath $toolsRoot -File -Recurse -ErrorAction SilentlyContinue)
    }
    return $script:WplToolFileIndex
}

function Get-WplManifestIdIndex {
    if ($null -eq $script:WplManifestIdIndex) {
        $index = @{}
        foreach ($file in Get-WplToolFileIndex) {
            if ($file.Name -ne 'INSTALL-MANIFEST.json') { continue }
            try { $id = [string](Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json).id } catch { continue }
            if ($id) { $index[$id] = $true }
        }
        $script:WplManifestIdIndex = $index
    }
    return $script:WplManifestIdIndex
}

function Reset-WplToolIndex {
    $script:WplToolFileIndex = $null
    $script:WplManifestIdIndex = $null
    $script:WplUserToolPaths = $null
}

function Read-JsonArray([string]$Path) {
    # Delegates to the module so PS 5.1 array normalisation has one implementation.
    return @(Read-WplJsonArray -Path $Path)
}

function Find-LauncherExecutable([object]$Launcher) {
    # Resolution policy (override precedence, *.exe filtering, pattern matching)
    # belongs to Resolve-WplExecutable. The cached index below only exists so a
    # single analysis pass does not walk tools\ once per candidate.
    $override = Get-WplUserToolPath ([string]$Launcher.id)
    if ($override) { return $override }
    if ([string]::IsNullOrWhiteSpace([string]$Launcher.pattern)) { return $null }
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    return Get-WplToolFileIndex |
        Where-Object { $_.Extension -ieq '.exe' } |
        Where-Object {
            $relative = $_.FullName.Substring($resolvedRoot.Length).TrimStart('\')
            $relative -like "*\$($Launcher.pattern)" -or $_.Name -like $Launcher.pattern
        } |
        Sort-Object LastWriteTime,FullName -Descending |
        Select-Object -First 1
}

function Test-CatalogPackageInstalled([string]$CatalogId) {
    return (Get-WplManifestIdIndex).ContainsKey($CatalogId)
}

function Add-Candidate([Collections.Specialized.OrderedDictionary]$Map,[string]$Id,[string]$State,[string]$ReasonKey) {
    if (-not $Map.Contains($Id)) {
        $Map.Add($Id,[ordered]@{state=$State;reasonKey=$ReasonKey})
    }
}

function New-ProgramConnectionPlan([string]$RecommendationDirectory,[string]$SelectedProfile) {
    $settingsPath = Join-Path $RecommendationDirectory 'recommended-settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $launchers = Read-JsonArray (Join-Path $Root 'config\tool-launchers.json')
    $candidates = [ordered]@{}

    Add-Candidate $candidates 'cpuz' 'recommended-now' 'RecIdentity'
    Add-Candidate $candidates 'hwinfo' 'recommended-now' 'RecSensors'
    Add-Candidate $candidates 'crystaldiskinfo' 'recommended-now' 'RecStorageHealth'
    Add-Candidate $candidates 'smartctl-scan' 'recommended-now' 'RecStorageHealth'
    Add-Candidate $candidates 'fulleventlogview' 'recommended-now' 'RecEvents'
    Add-Candidate $candidates 'trafficmonitor' 'recommended-now' 'RecTrafficMonitor'
    Add-Candidate $candidates 'sysinternals-tcpview' 'recommended-now' 'RecTcpView'
    if ($SelectedProfile -in @('deep','all')) {
        Add-Candidate $candidates 'sysinternals-process-monitor' 'guided-test' 'RecProcessMonitor'
    }
    if (@($settings.detected.graphics).Count -gt 0) { Add-Candidate $candidates 'gpuz' 'recommended-now' 'RecGpuIdentity' }

    if ($SelectedProfile -in @('standard','deep','memory','all')) {
        Add-Candidate $candidates 'prime95' 'guided-test' 'RecCpuStress'
        Add-Candidate $candidates 'y-cruncher' 'guided-test' 'RecMemoryStress'
    }
    if ($SelectedProfile -in @('standard','deep','storage','all')) {
        Add-Candidate $candidates 'crystaldiskmark' 'guided-test' 'RecStorageBaseline'
        Add-Candidate $candidates 'diskspd-help' 'guided-test' 'RecDiskSpd'
    }
    if ($SelectedProfile -in @('deep','memory','all')) {
        Add-Candidate $candidates 'occt' 'guided-test' 'RecOcct'
        Add-Candidate $candidates 'memtest86plus' 'external-boot' 'RecBootMemory'
    }
    if ($SelectedProfile -in @('standard','deep','memory','all')) {
        Add-Candidate $candidates 'testmem5' 'guided-test' 'RecTestMem5'
    }
    if ($SelectedProfile -in @('deep','memory','all')) {
        Add-Candidate $candidates 'hci-memtest' 'guided-test' 'RecHciMemtest'
        Add-Candidate $candidates 'ventoy' 'conditional-boot-media' 'RecVentoy'
    }
    if ($SelectedProfile -in @('storage','all')) {
        Add-Candidate $candidates 'wiztree' 'recommended-now' 'RecWizTree'
    }
    Add-Candidate $candidates 'latencymon' 'recommended-now' 'RecLatencyMon'
    if (@($settings.detected.battery).Count -gt 0) {
        Add-Candidate $candidates 'batteryinfoview' 'recommended-now' 'RecBatteryInfo'
    }
    if ($SelectedProfile -in @('storage','all')) {
        Add-Candidate $candidates 'naraeon-dirty-test' 'conditional-high-write' 'RecDirty'
        Add-Candidate $candidates 'h2testw' 'conditional-high-write' 'RecIntegrity'
        Add-Candidate $candidates 'validrive' 'conditional-usb-only' 'RecUsbCapacity'
    }
    if ($SelectedProfile -in @('gpu','all')) {
        Add-Candidate $candidates 'ddu' 'conditional-driver-recovery' 'RecDdu'
        $gpuNames = @($settings.detected.graphics | ForEach-Object { [string]$_.name }) -join '; '
        if ($gpuNames -match '(?i)AMD|Radeon') { Add-Candidate $candidates 'amd-cleanup-utility' 'conditional-driver-recovery' 'RecAmdCleanup' }
    }
    else {
        # Keep driver-recovery tools discoverable outside the GPU profile without
        # promoting them to a recommendation. Otherwise they look absent entirely.
        Add-Candidate $candidates 'ddu' 'available-in-profile' 'RecDdu'
        $gpuNames = @($settings.detected.graphics | ForEach-Object { [string]$_.name }) -join '; '
        if ($gpuNames -match '(?i)AMD|Radeon') { Add-Candidate $candidates 'amd-cleanup-utility' 'available-in-profile' 'RecAmdCleanup' }
    }

    $cpu = $settings.detected.cpu
    if ($cpu.vendor -eq 'AMD') { Add-Candidate $candidates 'zentimings' 'recommended-now' 'RecMemoryTimings' }
    if ($cpu.vendor -eq 'Intel' -and $cpu.unlockedSuffixDetected) {
        $xtuId = if ([string]$cpu.route -match 'ultra') { 'intel-xtu-ultra' } else { 'intel-xtu-legacy' }
        Add-Candidate $candidates $xtuId 'deferred-until-baseline-stable' 'RecIntelXtu'
    }
    elseif ($cpu.vendor -eq 'AMD') {
        Add-Candidate $candidates 'ryzen-master' 'deferred-until-baseline-stable' 'RecRyzenMaster'
    }
    if (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Minidump')) {
        Add-Candidate $candidates 'bluescreenview' 'conditional-if-dump-exists' 'RecCrash'
    }
    # Driver detection is only meaningful when Windows reports a device problem,
    # so it stays conditional rather than a default recommendation.
    if ($SelectedProfile -in @('gpu','all')) {
        Add-Candidate $candidates 'sdio' 'conditional-driver-recovery' 'RecSdio'
    }
    if ($SelectedProfile -in @('deep','all')) {
        Add-Candidate $candidates 'glary-utilities' 'guided-test' 'RecGlary'
    }

    # The default GUI view filters these rows out, but the All tools view must
    # expose every configured launcher so the console is also a complete tool
    # manager rather than a recommendation-only subset.
    foreach ($launcher in $launchers) {
        Add-Candidate $candidates ([string]$launcher.id) 'catalog-only' 'RecCatalogOnly'
    }

    $programs = @()
    foreach ($candidateId in $candidates.Keys) {
        $launcher = @($launchers | Where-Object { $_.id -eq $candidateId }) | Select-Object -First 1
        if (-not $launcher) { throw "Launcher configuration missing for '$candidateId'." }
        $exe = Find-LauncherExecutable $launcher
        $installed = [bool]$exe -or ($launcher.launchMode -eq 'external-boot' -and (Test-CatalogPackageInstalled $launcher.catalogId))
        $requiresRisk = [string]$launcher.risk -notmatch '^read-only'
        # 'available-in-profile' rows exist only so the tool stays visible. They must
        # not be launchable, or the profile gate around risky tools means nothing.
        $discoveryOnly = $candidates[$candidateId].state -eq 'available-in-profile'
        # A recent WHEA or Kernel-Power event makes stress/overclock paths
        # diagnostic-only. Keep them visible, but never present them as a next
        # launchable step until the baseline is clean.
        $baselineBlocked = Test-WplBaselineBlockedRisk -RecommendationMode ([string]$settings.detected.healthSignals.recommendationMode) -Risk ([string]$launcher.risk)
        $launchableState = [bool]$exe -and -not $discoveryOnly -and -not $baselineBlocked
        $state = if ($baselineBlocked) { 'diagnostic-baseline-only' } else { $candidates[$candidateId].state }
        $reasonKey = if ($baselineBlocked) { 'RecBaselineBlocked' } else { $candidates[$candidateId].reasonKey }
        $programs += [ordered]@{
            id = $launcher.id
            catalogId = $launcher.catalogId
            state = $state
            reason = [ordered]@{ko=(Get-WplText -Key $reasonKey -Language 'ko');en=(Get-WplText -Key $reasonKey -Language 'en')}
            risk = $launcher.risk
            launchMode = $launcher.launchMode
            installed = $installed
            launchable = $launchableState
            executable = if ($exe) { $exe.FullName } else { $null }
            arguments = @($launcher.arguments)
            command = if ($launchableState) { ".\WinPortableLab.ps1 -Action launch -ToolId $($launcher.id)$(if($requiresRisk){' -AcknowledgeRisk'})$(if([string]$launcher.risk -match '^(?:high-load|very-high-load)$'){' -AcknowledgeManualTemperatureMonitoring'}) -Language auto" } else { $null }
        }
    }

    $plan = [ordered]@{
        schemaVersion = '1.0.0'
        kind = 'WinPortableLab-recommended-program-connections'
        generatedAt = (Get-Date).ToString('o')
        profile = $SelectedProfile
        recommendationOnly = $true
        autoLaunchAllowed = $false
        detected = [ordered]@{cpu=$settings.detected.cpu;graphics=$settings.detected.graphics;storage=$settings.detected.storage;healthSignals=$settings.detected.healthSignals}
        programs = $programs
    }
    $jsonPath = Join-Path $RecommendationDirectory 'recommended-programs.json'
    $plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    foreach ($code in @('ko','en')) {
        $lines = @(
            "# $(Get-WplText -Key RecommendedPrograms -Language $code)",'',
            "> $(Get-WplText -Key RecommendationOnly -Language $code)",'',
            "## $(Get-WplText -Key DetectedSummary -Language $code)",'',
            "- CPU: $($settings.detected.cpu.name)",
            "- GPU: $(@($settings.detected.graphics.name) -join '; ')",
            "- Profile: $SelectedProfile",'',
            "## $(Get-WplText -Key ProgramConnections -Language $code)",'',
            '| ID | State | Installed | Risk | Reason | Command |',
            '|---|---|---:|---|---|---|'
        )
        foreach ($program in $programs) {
            $reason = [string]$program.reason.$code
            $command = if ($program.command) { "``$($program.command)``" } else { '-' }
            $lines += "| $($program.id) | $($program.state) | $($program.installed) | $($program.risk) | $reason | $command |"
        }
        $lines | Set-Content -LiteralPath (Join-Path $RecommendationDirectory "recommended-programs.$code.md") -Encoding utf8
    }
    return [pscustomobject]@{Directory=$RecommendationDirectory;JsonPath=$jsonPath;Plan=$plan}
}

function Invoke-IntegratedCheck([string]$SelectedProfile,[switch]$FastRecommendation) {
    Write-Host (Get-WplText -Key IntegratedCheckStart -Language $Language) -ForegroundColor Cyan
    # GUI recommendation analysis intentionally skips the full driver/security
    # report.  It still records every fact consumed by recommendations and the
    # stability gate; CLI checks retain the complete elevated inventory.
    $collectionProfile = if($FastRecommendation){'quick'}else{'full'}
    $reportDirectory = & (Join-Path $Root 'scripts\Invoke-Inventory.ps1') -OutputRoot (Join-Path $Root 'reports') -CollectionProfile $collectionProfile -Language $Language
    $recommendationDirectory = & (Join-Path $Root 'scripts\New-SystemRecommendation.ps1') -Root $Root -InventoryDirectory $reportDirectory -Language $Language
    $connection = New-ProgramConnectionPlan -RecommendationDirectory $recommendationDirectory -SelectedProfile $SelectedProfile

    if ($InstallMissing) {
        $missing = @($connection.Plan.programs | Where-Object { -not $_.installed } | Select-Object -ExpandProperty catalogId -Unique)
        if ($missing.Count) {
            Write-Host (Get-WplText -Key MissingPrograms -Language $Language -ArgumentList @($missing -join ', ')) -ForegroundColor Yellow
            & (Join-Path $Root 'scripts\Install-PortableTools.ps1') -Root $Root -Id ($missing -join ',') -IncludeHighLoad -Language $Language
            $downloadSucceeded = $?
            if (-not $downloadSucceeded) { throw 'Recommended program download failed.' }
            Reset-WplToolIndex
            $connection = New-ProgramConnectionPlan -RecommendationDirectory $recommendationDirectory -SelectedProfile $SelectedProfile
        }
    }

    Write-Host (Get-WplText -Key ReportCreated -Language $Language -ArgumentList @($reportDirectory)) -ForegroundColor Green
    Write-Host (Get-WplText -Key RecommendationCreated -Language $Language -ArgumentList @($recommendationDirectory)) -ForegroundColor Green
    Write-Host (Get-WplText -Key ProgramPlanCreated -Language $Language -ArgumentList @($connection.JsonPath)) -ForegroundColor Green
    return [pscustomobject]@{ReportDirectory=$reportDirectory;RecommendationDirectory=$recommendationDirectory;Connection=$connection}
}

function Show-ProgramPlan([object]$Connection) {
    $Connection.Plan.programs | Select-Object @{n=(Get-WplText -Key ProgramId -Language $Language);e={$_.id}},@{n=(Get-WplText -Key RecommendationState -Language $Language);e={$_.state}},@{n=(Get-WplText -Key Installed -Language $Language);e={$_.installed}},@{n=(Get-WplText -Key Launchable -Language $Language);e={$_.launchable}},@{n=(Get-WplText -Key Risk -Language $Language);e={$_.risk}},@{n=(Get-WplText -Key Reason -Language $Language);e={$_.reason.$Language}} | Format-Table -Wrap -AutoSize
}

function Open-ToolIds([string[]]$Ids,[switch]$RiskAccepted,[switch]$ManualTemperatureMonitoringAccepted,[string]$UseLanguage = $Language,[switch]$ContinueOnError) {
    $results = [Collections.Generic.List[object]]::new()
    foreach ($id in @($Ids | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        try {
            & (Join-Path $Root 'scripts\Open-PortableTool.ps1') -Root $Root -Id $id -AcknowledgeRisk:$RiskAccepted -AcknowledgeManualTemperatureMonitoring:$ManualTemperatureMonitoringAccepted -Language $UseLanguage
            $results.Add([pscustomobject]@{id=$id;success=$true;error=$null})
        }
        catch {
            $results.Add([pscustomobject]@{id=$id;success=$false;error=$_.Exception.Message})
            if (-not $ContinueOnError) { throw }
        }
    }
    return @($results)
}

function Get-WplSafeLaunchIds([object]$Plan) {
    # One definition of "safe to launch without a risk prompt": recommended now,
    # read-only, GUI-startable, and actually resolved on disk. It was written out
    # three times, so a change to one copy silently disagreed with the others.
    if (-not $Plan) { return @() }
    return @($Plan.programs |
        Where-Object { $_.state -eq 'recommended-now' -and $_.risk -eq 'read-only' -and $_.launchMode -eq 'gui' -and $_.launchable } |
        Select-Object -ExpandProperty id)
}

function Open-WplTextDocument([Parameter(Mandatory)][string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Document not found: $Path" }
    $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
    Start-Process -FilePath $notepad -ArgumentList @("`"$Path`"")
}

# Detailed per-tool guides exist for a subset of the catalog. Tools without one
# fall back to the quick reference rather than failing.
function Get-WplToolGuideName([string]$CatalogId) {
    switch ($CatalogId) {
        'testmem5' { 'TESTMEM5' }
        'hci-memtest' { 'HCI_MEMTEST' }
        'latencymon' { 'LATENCYMON' }
        'batteryinfoview' { 'BATTERYINFOVIEW' }
        'wiztree' { 'WIZTREE' }
        'ventoy' { 'VENTOY' }
        'prime95' { 'PRIME95' }
        'occt' { 'OCCT' }
        'naraeon-dirty-test' { 'NARAEON_DIRTY_TEST' }
        'h2testw' { 'H2TESTW' }
        'ddu' { 'DDU' }
        'sdio' { 'SDIO' }
        'sd-card-formatter' { 'SD_CARD_FORMATTER' }
        'glary-utilities' { 'GLARY_UTILITIES' }
        default { $null }
    }
}

function Show-WplGui {
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OnePack Portable Korea" Width="1200" Height="800" MinWidth="1040" MinHeight="700"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource Canvas}" Foreground="{DynamicResource Ink}" FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Ideal" UseLayoutRounding="True">
  <Window.Resources>
    <!-- Colour tokens. Every brush is defined once here and referenced elsewhere;
         a repository test fails if a colour literal appears outside this block. -->
    <SolidColorBrush x:Key="Canvas" Color="#0A0A0B"/>
    <SolidColorBrush x:Key="Surface1" Color="#0F1011"/>
    <SolidColorBrush x:Key="Surface2" Color="#141516"/>
    <SolidColorBrush x:Key="Surface3" Color="#18191A"/>
    <SolidColorBrush x:Key="Hairline" Color="#23252A"/>
    <SolidColorBrush x:Key="HairlineStrong" Color="#34343A"/>
    <SolidColorBrush x:Key="Ink" Color="#F7F8F8"/>
    <SolidColorBrush x:Key="InkMuted" Color="#D0D6E0"/>
    <SolidColorBrush x:Key="InkSubtle" Color="#8A8F98"/>
    <SolidColorBrush x:Key="InkTertiary" Color="#62666D"/>
    <SolidColorBrush x:Key="Accent" Color="#5E6AD2"/>
    <SolidColorBrush x:Key="AccentHover" Color="#828FFF"/>
    <!-- Diagnostic semantics. This project must signal risk, which the source brand does not need. -->
    <SolidColorBrush x:Key="Ok" Color="#27A644"/>
    <SolidColorBrush x:Key="Caution" Color="#B4823A"/>
    <SolidColorBrush x:Key="Danger" Color="#C2504B"/>
    <Style x:Key="NavButton" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource InkMuted}"/>
      <Setter Property="Background" Value="{DynamicResource Surface2}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Hairline}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource Surface3}"/>
          <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
          <Setter Property="BorderBrush" Value="{DynamicResource HairlineStrong}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="{DynamicResource Surface1}"/>
          <Setter Property="Foreground" Value="{DynamicResource InkTertiary}"/>
          <Setter Property="BorderBrush" Value="{DynamicResource Hairline}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="ActionButton" TargetType="Button" BasedOn="{StaticResource NavButton}">
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Background" Value="{DynamicResource Surface2}"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource HairlineStrong}"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
      <Setter Property="Background" Value="{DynamicResource Accent}"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource AccentHover}"/>
          <Setter Property="BorderBrush" Value="{DynamicResource AccentHover}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="{DynamicResource Surface1}"/>
          <Setter Property="Foreground" Value="{DynamicResource InkTertiary}"/>
          <Setter Property="BorderBrush" Value="{DynamicResource Hairline}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="FilterChip" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource InkSubtle}"/>
      <Setter Property="Background" Value="{DynamicResource Surface1}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Hairline}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="11,5"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
          <Setter Property="BorderBrush" Value="{DynamicResource HairlineStrong}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <!-- Hardware summary cards are buttons so a click can open full detail,
         while the template keeps them looking like flat panels. -->
    <Style x:Key="HardwareCard" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="VerticalContentAlignment" Value="Top"/>
      <Setter Property="Padding" Value="13,11"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="CardSurface" Background="{DynamicResource Surface1}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CardSurface" Property="Background" Value="{DynamicResource Surface2}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="{DynamicResource Canvas}"/>
      <Setter Property="Foreground" Value="{DynamicResource InkSubtle}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Hairline}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="Medium"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource InkMuted}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="3,0"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="{DynamicResource Surface3}"/>
          <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
          <Setter Property="BorderThickness" Value="0"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource HairlineStrong}"/>
      <Setter Property="Width" Value="10"/>
    </Style>
  </Window.Resources>
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="2,0,2,16">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Rectangle Width="3" Height="19" Fill="{DynamicResource Accent}" RadiusX="1.5" RadiusY="1.5" Margin="0,0,11,0"/>
        <TextBlock x:Name="BrandText" Foreground="{DynamicResource Ink}" FontSize="19" FontWeight="SemiBold" VerticalAlignment="Center">
          <TextBlock.ToolTip><ToolTip><TextBlock x:Name="DescriptionText" TextWrapping="Wrap" MaxWidth="420"/></ToolTip></TextBlock.ToolTip>
        </TextBlock>
        <TextBlock x:Name="BadgeText" Foreground="{DynamicResource InkTertiary}" FontSize="11" Margin="12,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock x:Name="SnapshotText" Foreground="{DynamicResource InkTertiary}" FontSize="11" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <Button x:Name="LanguageButton" Style="{StaticResource FilterChip}" Width="50" Margin="0"/>
      </StackPanel>
    </Grid>

    <Grid Grid.Row="1" Margin="0,0,0,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="1.1*"/><ColumnDefinition Width="1.8*"/><ColumnDefinition Width="1.6*"/><ColumnDefinition Width="1.1*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="OsCardButton" Grid.Column="0" Style="{StaticResource HardwareCard}">
        <StackPanel>
          <Grid>
            <TextBlock Text="OS" Foreground="{DynamicResource InkTertiary}" FontSize="10" FontWeight="Medium"/>
            <TextBlock Text="&#x2039;&#x203A;" Foreground="{DynamicResource InkTertiary}" FontSize="10" HorizontalAlignment="Right"/>
          </Grid>
          <TextBlock x:Name="OsText" Foreground="{DynamicResource InkMuted}" Margin="0,5,0,0" TextWrapping="Wrap" FontSize="11" LineHeight="16"/>
        </StackPanel>
      </Button>
      <Button x:Name="CpuCardButton" Grid.Column="1" Margin="10,0,0,0" Style="{StaticResource HardwareCard}">
        <StackPanel>
          <Grid>
            <TextBlock Text="CPU" Foreground="{DynamicResource InkTertiary}" FontSize="10" FontWeight="Medium"/>
            <TextBlock Text="&#x2039;&#x203A;" Foreground="{DynamicResource InkTertiary}" FontSize="10" HorizontalAlignment="Right"/>
          </Grid>
          <TextBlock x:Name="CpuText" Foreground="{DynamicResource InkMuted}" Margin="0,5,0,0" TextWrapping="Wrap" FontSize="11" LineHeight="16"/>
        </StackPanel>
      </Button>
      <Button x:Name="GpuCardButton" Grid.Column="2" Margin="10,0,0,0" Style="{StaticResource HardwareCard}">
        <StackPanel>
          <Grid>
            <TextBlock Text="GPU" Foreground="{DynamicResource InkTertiary}" FontSize="10" FontWeight="Medium"/>
            <TextBlock Text="&#x2039;&#x203A;" Foreground="{DynamicResource InkTertiary}" FontSize="10" HorizontalAlignment="Right"/>
          </Grid>
          <TextBlock x:Name="GpuText" Foreground="{DynamicResource InkMuted}" Margin="0,5,0,0" TextWrapping="Wrap" FontSize="11" LineHeight="16"/>
        </StackPanel>
      </Button>
      <Button x:Name="MemoryCardButton" Grid.Column="3" Margin="10,0,0,0" Style="{StaticResource HardwareCard}">
        <StackPanel>
          <Grid>
            <TextBlock Text="RAM / DISK" Foreground="{DynamicResource InkTertiary}" FontSize="10" FontWeight="Medium"/>
            <TextBlock Text="&#x2039;&#x203A;" Foreground="{DynamicResource InkTertiary}" FontSize="10" HorizontalAlignment="Right"/>
          </Grid>
          <TextBlock x:Name="MemoryText" Foreground="{DynamicResource InkMuted}" Margin="0,5,0,0" TextWrapping="Wrap" FontSize="11" LineHeight="16"/>
        </StackPanel>
      </Button>
    </Grid>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions><ColumnDefinition Width="194"/><ColumnDefinition Width="*"/><ColumnDefinition Width="310"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="{DynamicResource Surface1}" CornerRadius="8" Padding="11">
        <ScrollViewer x:Name="SidebarScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" PanningMode="VerticalOnly" IsDeferredScrollingEnabled="False" Padding="0,0,4,0">
        <StackPanel>
          <StackPanel Margin="2,0,4,9">
            <TextBlock x:Name="SystemSectionText" Foreground="{DynamicResource InkTertiary}" FontWeight="Medium" FontSize="10"/>
            <TextBlock x:Name="AdminText" Foreground="{DynamicResource InkSubtle}" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap"/>
          </StackPanel>
          <Button x:Name="QuickButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="StandardButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="DeepButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="StorageButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="MemoryButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="GpuButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="AllButton" Style="{StaticResource NavButton}"/>
          <Separator Background="{DynamicResource Hairline}" Margin="0,9,0,11" Height="1"/>
          <TextBlock x:Name="RecordsSectionText" Foreground="{DynamicResource InkTertiary}" FontWeight="Medium" FontSize="10" Margin="2,0,0,7"/>
          <Button x:Name="LatestResultButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="ReportsButton" Style="{StaticResource NavButton}"/>
          <Separator Background="{DynamicResource Hairline}" Margin="0,9,0,11" Height="1"/>
          <TextBlock x:Name="ManageSectionText" Foreground="{DynamicResource InkTertiary}" FontWeight="Medium" FontSize="10" Margin="2,0,0,7"/>
          <Button x:Name="RefreshButton" Style="{StaticResource NavButton}"/>
          <Button x:Name="BatchDownloadButton" Style="{StaticResource NavButton}"/>
          <Expander x:Name="MoreExpander" Foreground="{DynamicResource InkSubtle}" Background="Transparent" BorderBrush="Transparent" BorderThickness="0" Padding="2,4" Margin="0,4,0,0" FontSize="12">
            <StackPanel Margin="0,7,0,0"><Button x:Name="NetworkDriverButton" Style="{StaticResource NavButton}"/><Button x:Name="GithubButton" Style="{StaticResource NavButton}"/><Button x:Name="ValidateButton" Style="{StaticResource NavButton}"/></StackPanel>
          </Expander>
        </StackPanel>
        </ScrollViewer>
      </Border>

      <Border Grid.Column="1" Margin="14,0,0,0" Background="{DynamicResource Surface1}" CornerRadius="8" Padding="14">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="34"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock x:Name="RecommendationSectionText" Grid.Row="0" Foreground="{DynamicResource Ink}" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,11"/>
          <Grid Grid.Row="1" Margin="0,0,0,9">
            <TextBox x:Name="SearchBox" Background="{DynamicResource Canvas}" Foreground="{DynamicResource Ink}" BorderBrush="{DynamicResource Hairline}" BorderThickness="1" Padding="10,5" VerticalContentAlignment="Center" FontSize="12"/>
            <TextBlock x:Name="SearchHintText" Foreground="{DynamicResource InkTertiary}" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False" FontSize="12"/>
          </Grid>
          <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,10">
            <Button x:Name="FilterRecommendedButton" Tag="recommended" Style="{StaticResource FilterChip}"/>
            <Button x:Name="FilterAllButton" Tag="all" Style="{StaticResource FilterChip}"/>
            <Button x:Name="FilterReadyButton" Tag="ready" Style="{StaticResource FilterChip}"/>
            <Button x:Name="FilterMissingButton" Tag="missing" Style="{StaticResource FilterChip}"/>
            <Button x:Name="FilterRiskButton" Tag="risky" Style="{StaticResource FilterChip}"/>
          </StackPanel>
          <DataGrid x:Name="ProgramGrid" Grid.Row="3" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"
                    Background="Transparent" Foreground="{DynamicResource InkMuted}" BorderThickness="0" GridLinesVisibility="Horizontal"
                    HorizontalGridLinesBrush="{DynamicResource Hairline}" RowBackground="Transparent" AlternatingRowBackground="Transparent"
                    HeadersVisibility="Column" CanUserAddRows="False" CanUserSortColumns="True" ScrollViewer.VerticalScrollBarVisibility="Auto"
                    ScrollViewer.HorizontalScrollBarVisibility="Auto" ScrollViewer.CanContentScroll="True" ScrollViewer.PanningMode="VerticalOnly" RowHeight="32">
            <DataGrid.Columns>
              <DataGridTextColumn Header="PROGRAM" Binding="{Binding displayName}" Width="220" SortMemberPath="displayName"/>
              <DataGridTemplateColumn Header="STATUS" Width="190" SortMemberPath="displayStatus" CanUserSort="True">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                      <Border Background="{DynamicResource Surface3}" CornerRadius="4" Padding="7,2" VerticalAlignment="Center">
                        <TextBlock Text="{Binding stateText}" Foreground="{DynamicResource InkMuted}" FontSize="11"/>
                      </Border>
                      <TextBlock Text="{Binding readyText}" Foreground="{DynamicResource InkTertiary}" FontSize="11" Margin="7,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="RISK" Binding="{Binding riskText}" Width="*" SortMemberPath="riskText"/>
            </DataGrid.Columns>
            <DataGrid.RowStyle>
              <Style TargetType="DataGridRow">
                <Setter Property="Foreground" Value="{DynamicResource InkMuted}"/>
                <Setter Property="BorderThickness" Value="2,0,0,0"/>
                <Setter Property="BorderBrush" Value="Transparent"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding riskTier}" Value="safe"><Setter Property="BorderBrush" Value="{DynamicResource Ok}"/></DataTrigger>
                  <DataTrigger Binding="{Binding riskTier}" Value="caution"><Setter Property="BorderBrush" Value="{DynamicResource Caution}"/></DataTrigger>
                  <DataTrigger Binding="{Binding riskTier}" Value="danger"><Setter Property="BorderBrush" Value="{DynamicResource Danger}"/></DataTrigger>
                  <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource Surface2}"/></Trigger>
                  <Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{DynamicResource Surface3}"/><Setter Property="Foreground" Value="{DynamicResource Ink}"/></Trigger>
                </Style.Triggers>
              </Style>
            </DataGrid.RowStyle>
          </DataGrid>
        </Grid>
      </Border>

      <Border Grid.Column="2" Margin="14,0,0,0" Background="{DynamicResource Surface1}" CornerRadius="8" Padding="14">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <TextBlock x:Name="ReasonHeaderText" Foreground="{DynamicResource InkTertiary}" FontSize="10" FontWeight="Medium"/>
          <TextBlock x:Name="SelectedToolText" Grid.Row="1" Foreground="{DynamicResource Ink}" FontSize="15" FontWeight="SemiBold" Margin="0,7,0,11" TextWrapping="Wrap"/>
          <ScrollViewer x:Name="DetailScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" PanningMode="VerticalOnly" IsDeferredScrollingEnabled="False">
            <TextBlock x:Name="ReasonText" Foreground="{DynamicResource InkSubtle}" Margin="0,0,6,0" TextWrapping="Wrap" LineHeight="19" FontSize="12"/>
          </ScrollViewer>
          <Grid Grid.Row="3" Margin="0,12,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Button x:Name="GuideButton" Grid.Column="0" Style="{StaticResource ActionButton}" Margin="0" Padding="6,6" FontSize="11"/><Button x:Name="ToolGuideButton" Grid.Column="1" Style="{StaticResource ActionButton}" Margin="6,0,0,0" Padding="6,6" FontSize="11"/><Button x:Name="LaunchButton" Grid.Column="2" Style="{StaticResource PrimaryButton}" Margin="6,0,0,0" Padding="6,6" FontSize="11"/></Grid>
        </Grid>
      </Border>
    </Grid>

    <Border Grid.Row="3" Margin="0,14,0,0" Background="{DynamicResource Surface1}" CornerRadius="8" Padding="13,9">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="StatusDot" Width="7" Height="7" Fill="{DynamicResource Ok}" Margin="2,0,10,0"/>
          <ProgressBar x:Name="AnalysisProgressBar" Width="84" Height="3" IsIndeterminate="True" Visibility="Collapsed" Margin="0,0,10,0" Background="{DynamicResource Surface3}" Foreground="{DynamicResource Accent}" BorderThickness="0"/>
          <TextBlock x:Name="StatusText" Foreground="{DynamicResource InkSubtle}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" FontSize="12"/>
        </StackPanel>
        <Button x:Name="SafeLaunchButton" Grid.Column="1" Style="{StaticResource ActionButton}" Height="31" MinWidth="170" Padding="14,5" VerticalContentAlignment="Center" FontSize="12"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $names = @('BadgeText','BrandText','DescriptionText','LanguageButton','SnapshotText','SystemSectionText','AdminText','QuickButton','StandardButton','DeepButton','AllButton','StorageButton','MemoryButton','GpuButton','RecordsSectionText','ManageSectionText','RefreshButton','BatchDownloadButton','SafeLaunchButton','ReportsButton','LatestResultButton','MoreExpander','NetworkDriverButton','GithubButton','ValidateButton','SidebarScroll','RecommendationSectionText','SearchBox','SearchHintText','FilterRecommendedButton','FilterAllButton','FilterReadyButton','FilterMissingButton','FilterRiskButton','ProgramGrid','ReasonHeaderText','SelectedToolText','ReasonText','DetailScroll','StatusDot','AnalysisProgressBar','StatusText','GuideButton','ToolGuideButton','LaunchButton','OsText','CpuText','GpuText','MemoryText','OsCardButton','CpuCardButton','GpuCardButton','MemoryCardButton')
    $ui = @{}
    foreach ($name in $names) { $ui[$name] = $window.FindName($name) }

    $script:GuiLanguage = $Language
    $script:GuiPlan = $null
    $script:GuiPlanPath = $null
    $script:GuiRecommendationDirectory = $null
    $script:GuiJob = $null
    $script:GuiInstallers = $null
    $script:GuiInitialAnalysisStarted = $false
    $script:GuiJobStarted = $null
    $script:GuiMemoryGb = $null
    $script:GuiDiskCount = $null
    $script:GuiMemoryHardwareText = $null
    $script:GuiMemoryToolTip = $null
    # Populated with the hardware snapshot; a card clicked before then reports
    # that detail is not available yet instead of throwing.
    $script:GuiHardwareDetail = @{}
    $script:GuiUpdateAdvice = @()
    $script:GuiCurrentProfile = $Profile
    $script:GuiCurrentFilter = 'recommended'
    $script:GuiSnapshotCapturedAt = $null
    $script:GuiIsAdministrator = Test-WplCurrentAdministrator
    $script:GuiCatalogNames = @{}
    foreach ($catalogTool in @(Read-JsonArray (Join-Path $Root 'catalog\tools.json'))) { $script:GuiCatalogNames[[string]$catalogTool.id] = [string]$catalogTool.name }

    function Get-GuiStateText([string]$Value,[string]$Code) {
        $key = switch ($Value) {
            'recommended-now' { 'StateRecommendedNow' }
            'guided-test' { 'StateGuidedTest' }
            'conditional-high-write' { 'StateConditionalHighWrite' }
            'conditional-usb-only' { 'StateConditionalUsbOnly' }
            'conditional-driver-recovery' { 'StateConditionalDriverRecovery' }
            'conditional-if-dump-exists' { 'StateConditionalIfDumpExists' }
            'conditional-boot-media' { 'StateConditionalBootMedia' }
            'deferred-until-baseline-stable' { 'StateDeferredBaseline' }
            'external-boot' { 'StateExternalBoot' }
            'available-in-profile' { 'StateAvailableInProfile' }
            'catalog-only' { 'StateCatalogOnly' }
            'diagnostic-baseline-only' { 'StateDiagnosticBaselineOnly' }
            default { 'StateUnknown' }
        }
        return Get-WplText -Key $key -Language $Code
    }

    function Get-GuiRiskText([string]$Value,[string]$Code) {
        $key = switch ($Value) {
            'read-only' { 'RiskReadOnly' }
            'read-only-admin' { 'RiskReadOnlyAdmin' }
            'read-only-default' { 'RiskReadOnlyDefault' }
            'read-only-help' { 'RiskReadOnlyHelp' }
            'writes-test-file' { 'RiskWritesTestFile' }
            'high-load' { 'RiskHighLoad' }
            'very-high-load' { 'RiskVeryHighLoad' }
            'system-changing' { 'RiskSystemChanging' }
            'system-changing-optional' { 'RiskSystemChangingOptional' }
            'system-changing-reboot' { 'RiskSystemChangingReboot' }
            'installer-changes-cpu-settings' { 'RiskInstallerChangesCpuSettings' }
            'installer-changes-cpu-memory-settings' { 'RiskInstallerChangesCpuMemorySettings' }
            'reboot-external-boot' { 'RiskRebootExternalBoot' }
            'changes-cooling-settings' { 'RiskChangesCoolingSettings' }
            'fills-free-space-high-write' { 'RiskFillsFreeSpaceHighWrite' }
            'writes-spot-checks-usb' { 'RiskWritesSpotChecksUsb' }
            default { 'RiskUnknown' }
        }
        return Get-WplText -Key $key -Language $Code
    }

    function Get-GuiLaunchModeText([string]$Value,[string]$Code) {
        $key = switch ($Value) {
            'gui' { 'LaunchModeGui' }
            'installer' { 'LaunchModeInstaller' }
            'cli' { 'LaunchModeCli' }
            'cli-help' { 'LaunchModeCliHelp' }
            'external-boot' { 'LaunchModeExternalBoot' }
            default { 'ProgramUnavailable' }
        }
        return Get-WplText -Key $key -Language $Code
    }

    function Update-GuiProgramPresentation {
        if (-not $script:GuiPlan) { return }
        $code = $script:GuiLanguage
        $selectedId = if ($ui.ProgramGrid.SelectedItem) { [string]$ui.ProgramGrid.SelectedItem.id } else { $null }
        foreach ($program in @($script:GuiPlan.programs)) {
            $displayName = if ($script:GuiCatalogNames.ContainsKey([string]$program.catalogId)) { $script:GuiCatalogNames[[string]$program.catalogId] } else { [string]$program.id }
            if ($program.id -eq 'smartctl-scan') { $displayName = "$displayName SMART scan" }
            elseif ($program.id -eq 'intel-xtu-legacy') { $displayName = "$displayName 7.x" }
            elseif ($program.id -eq 'intel-xtu-ultra') { $displayName = "$displayName 10.x" }
            $readyText = if ($program.installed -and $program.launchable) { Get-WplText -Key ProgramReady -Language $code }
                elseif ($program.installed -and $program.launchMode -eq 'external-boot') { Get-WplText -Key ProgramBootReady -Language $code }
                elseif ($program.state -eq 'available-in-profile') { Get-WplText -Key ProgramProfileGated -Language $code }
                elseif ($program.installed) { Get-WplText -Key ProgramUnavailable -Language $code }
                else { Get-WplText -Key ProgramMissing -Language $code }
            $program | Add-Member -NotePropertyName displayName -NotePropertyValue $displayName -Force
            $program | Add-Member -NotePropertyName stateText -NotePropertyValue (Get-GuiStateText ([string]$program.state) $code) -Force
            $program | Add-Member -NotePropertyName readyText -NotePropertyValue $readyText -Force
            $program | Add-Member -NotePropertyName displayStatus -NotePropertyValue "$($program.stateText) · $readyText" -Force
            $program | Add-Member -NotePropertyName riskText -NotePropertyValue (Get-GuiRiskText ([string]$program.risk) $code) -Force
            # The row's left edge carries risk, so the grid no longer needs a coloured fill per state.
            $riskTier = if ([string]$program.risk -match '^read-only') { 'safe' }
                elseif ([string]$program.risk -match 'system-changing|reboot|installer') { 'danger' }
                else { 'caution' }
            $program | Add-Member -NotePropertyName riskTier -NotePropertyValue $riskTier -Force
            $program | Add-Member -NotePropertyName modeText -NotePropertyValue (Get-GuiLaunchModeText ([string]$program.launchMode) $code) -Force
        }
        $query = ([string]$ui.SearchBox.Text).Trim()
        $filter = $script:GuiCurrentFilter
        $visible = @($script:GuiPlan.programs | Where-Object { Test-WplProgramVisible -Program $_ -Filter $filter -Query $query })
        $ui.ProgramGrid.ItemsSource = $null
        $ui.ProgramGrid.ItemsSource = $visible
        $selection = if($selectedId){@($visible | Where-Object { $_.id -eq $selectedId }) | Select-Object -First 1}else{$null}
        if(-not $selection){$selection=@($visible | Where-Object state -eq 'recommended-now')|Select-Object -First 1}
        if(-not $selection){$selection=$visible|Select-Object -First 1}
        $ui.ProgramGrid.SelectedItem = $selection
        $ui.ProgramGrid.Items.Refresh()
    }

    function Set-GuiSelectionDetails {
        $selected = $ui.ProgramGrid.SelectedItem
        if (-not $selected) {
            $ui.SelectedToolText.Text = Get-WplText -Key GuiNoToolSelected -Language $script:GuiLanguage
            $ui.ReasonText.Text = Get-WplText -Key GuiSelectTool -Language $script:GuiLanguage
            $ui.LaunchButton.IsEnabled = $false
            return
        }
        $busy = $script:GuiJob -and $script:GuiJob.State -in @('NotStarted','Running')
        $code = $script:GuiLanguage
        $path = if ($selected.executable) { [string]$selected.executable } else { '-' }
        $reason = [string]$selected.reason.$code
        $ui.SelectedToolText.Text = [string]$selected.displayName
        $ui.ReasonText.Text = @(
            "$(Get-WplText -Key GuiDetailId -Language $code): $($selected.id)",
            "$(Get-WplText -Key GuiDetailState -Language $code): $($selected.stateText)",
            "$(Get-WplText -Key GuiDetailRisk -Language $code): $($selected.riskText)  |  $(Get-WplText -Key GuiDetailMode -Language $code): $($selected.modeText)",
            "$(Get-WplText -Key GuiDetailReady -Language $code): $($selected.readyText)",
            "$(Get-WplText -Key GuiDetailPath -Language $code): $path",
            '',
            $reason
        ) -join "`n"
        $primaryAction = if ($selected.launchable) { 'launch' } elseif (-not $selected.installed) { 'prepare' } else { 'guide' }
        $selected | Add-Member -NotePropertyName primaryAction -NotePropertyValue $primaryAction -Force
        $ui.LaunchButton.Content = Get-WplText -Key $(switch($primaryAction){'launch'{'GuiLaunchSelected'}'prepare'{'GuiPrepareSelected'}default{'GuiOpenRequiredGuide'}}) -Language $code
        $ui.LaunchButton.IsEnabled = -not $busy
        $ui.DetailScroll.ScrollToTop()
        $ui.ProgramGrid.ScrollIntoView($selected)
    }

    function Open-GuiToolGuide([object]$Selected) {
        if (-not $Selected) { throw (Get-WplText -Key GuiSelectTool -Language $script:GuiLanguage) }
        $documentName = Get-WplToolGuideName ([string]$Selected.catalogId)
        $quickReference = Join-Path $Root ('docs\{0}\QUICK_USE.md' -f $script:GuiLanguage)
        $detailed = if ($documentName) { Join-Path $Root ('docs\{0}\tools\{1}.md' -f $script:GuiLanguage,$documentName) } else { $null }
        if ($detailed -and (Test-Path -LiteralPath $detailed -PathType Leaf)) { Open-WplTextDocument $detailed; return }
        [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoToolGuide -Language $script:GuiLanguage -ArgumentList @([string]$Selected.displayName)),$window.Title) | Out-Null
        Open-WplTextDocument $quickReference
    }

    function Set-GuiPlanFromCurrentSnapshot {
        if (-not $script:GuiRecommendationDirectory) { return }
        Reset-WplToolIndex
        $connection = New-ProgramConnectionPlan -RecommendationDirectory $script:GuiRecommendationDirectory -SelectedProfile $script:GuiCurrentProfile
        Set-GuiPlan $connection.JsonPath
    }

    function Select-GuiExistingExecutable([object]$Selected) {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = Get-WplText -Key GuiChooseExecutable -Language $script:GuiLanguage -ArgumentList @([string]$Selected.displayName)
        $dialog.Filter = 'Executable files (*.exe)|*.exe'
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog($window) -ne $true) { return }
        & (Join-Path $Root 'scripts\Set-WplToolPath.ps1') -Root $Root -Action set -Id ([string]$Selected.id) -Path $dialog.FileName -Language $script:GuiLanguage | Out-Null
        Set-GuiPlanFromCurrentSnapshot
        Set-GuiStatusTone 'ok'
        $ui.StatusText.Text = Get-WplText -Key GuiPathRegistered -Language $script:GuiLanguage -ArgumentList @([string]$Selected.displayName)
    }

    function Prepare-GuiSelectedTool([object]$Selected) {
        $package = @(Get-WplPackageDefinitions -Root $Root | Where-Object { [string]$_.catalogId -eq [string]$Selected.catalogId }) | Select-Object -First 1
        if (-not $package) { Select-GuiExistingExecutable $Selected; return }
        $message = Get-WplText -Key GuiPrepareChoice -Language $script:GuiLanguage -ArgumentList @([string]$Selected.displayName)
        $answer = [System.Windows.MessageBox]::Show($message,$window.Title,[System.Windows.MessageBoxButton]::YesNoCancel,[System.Windows.MessageBoxImage]::Information)
        if ($answer -eq [System.Windows.MessageBoxResult]::Cancel) { return }
        if ($answer -eq [System.Windows.MessageBoxResult]::No) { Select-GuiExistingExecutable $Selected; return }
        $installerArguments = [Collections.Generic.List[string]]::new()
        $installerArguments.AddRange([string[]]@('-Id',[string]$Selected.catalogId))
        if ([bool]$package.risk.highLoad) { $installerArguments.Add('-IncludeHighLoad') }
        Start-WplGuiInstaller ([string]$Selected.displayName) $installerArguments.ToArray()
    }

    function Set-GuiSnapshotText {
        if($script:GuiSnapshotCapturedAt){
            $stamp=$script:GuiSnapshotCapturedAt.ToString('yyyy-MM-dd HH:mm')
            $profileKey=switch($script:GuiCurrentProfile){'quick'{'GuiProfileQuick'}'standard'{'GuiProfileStandard'}'deep'{'GuiProfileDeep'}'storage'{'GuiProfileStorage'}'memory'{'GuiProfileMemory'}'gpu'{'GuiProfileGpu'}'all'{'GuiProfileAll'}default{'GuiProfileStandard'}}
            $profileName=Get-WplText -Key $profileKey -Language $script:GuiLanguage
            $ui.SnapshotText.Text=Get-WplText -Key GuiSnapshotAt -Language $script:GuiLanguage -ArgumentList @($stamp,$profileName)
        }else{
            $ui.SnapshotText.Text=Get-WplText -Key GuiSnapshotPending -Language $script:GuiLanguage
        }
    }

    function Update-GuiFilterButtons {
        foreach($button in @($ui.FilterRecommendedButton,$ui.FilterAllButton,$ui.FilterReadyButton,$ui.FilterMissingButton,$ui.FilterRiskButton)){
            $active=[string]$button.Tag -eq $script:GuiCurrentFilter
            $button.Background=$window.TryFindResource($(if($active){'Surface3'}else{'Surface1'}))
            $button.BorderBrush=$window.TryFindResource($(if($active){'HairlineStrong'}else{'Hairline'}))
            $button.Foreground=$window.TryFindResource($(if($active){'Ink'}else{'InkSubtle'}))
        }
    }

    function Move-GuiScroll([System.Windows.Controls.ScrollViewer]$Viewer,[int]$Delta) {
        if(-not $Viewer){return}
        $lines=[math]::Max(1,[int][System.Windows.SystemParameters]::WheelScrollLines)
        for($i=0;$i-lt$lines;$i++){
            if($Delta-lt0){$Viewer.LineDown()}else{$Viewer.LineUp()}
        }
    }

    # Optional online lookup for the one vendor that publishes a stable query
    # endpoint. Never called during analysis; only from an explicit button so a
    # field machine without internet is unaffected.
    function Get-WplNvidiaLatestDriver([string]$AdapterName) {
        $result = [pscustomobject]@{ Success=$false; Version=$null; Released=$null; Url=$null; Error=$null }
        try {
            $series = Invoke-RestMethod -Uri 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=2' -TimeoutSec 12 -ErrorAction Stop
            $seriesList = @($series.LookupValueSearch.LookupValues.LookupValue)
            # Match the widest series name that appears in the adapter string.
            $normalized = ($AdapterName -replace 'NVIDIA','').Trim()
            $candidate = $null
            foreach ($entry in $seriesList) {
                $name = [string]$entry.Name
                if ($name -match '\(Notebook') { continue }
                $token = ($name -replace 'GeForce ','') -replace ' Series',''
                if ($token -and $normalized -match [regex]::Escape($token.Split(' ')[0])) {
                    if (-not $candidate -or $token.Length -gt $candidate.Token.Length) {
                        $candidate = [pscustomobject]@{ Psid=[string]$entry.Value; Token=$token }
                    }
                }
            }
            if (-not $candidate) { $result.Error = 'series-not-matched'; return $result }
            $products = Invoke-RestMethod -Uri ('https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3&ParentID={0}' -f $candidate.Psid) -TimeoutSec 12 -ErrorAction Stop
            $productList = @($products.LookupValueSearch.LookupValues.LookupValue)
            $best = $null
            foreach ($product in $productList) {
                $productName = ([string]$product.Name -replace 'NVIDIA ','').Trim()
                if ($normalized -like ('*' + $productName + '*')) {
                    if (-not $best -or $productName.Length -gt $best.Name.Length) {
                        $best = [pscustomobject]@{ Pfid=[string]$product.Value; Name=$productName }
                    }
                }
            }
            if (-not $best) { $result.Error = 'product-not-matched'; return $result }
            $osId = if ([Environment]::OSVersion.Version.Build -ge 22000) { '135' } else { '57' }
            $languageCode = if ($script:GuiLanguage -eq 'ko') { '1042' } else { '1033' }
            $lookup = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid={0}&pfid={1}&osID={2}&languageCode={3}&isWHQL=1&dch=1&numberOfResults=1'
            $response = Invoke-RestMethod -Uri ($lookup -f $candidate.Psid,$best.Pfid,$osId,$languageCode) -TimeoutSec 15 -ErrorAction Stop
            $info = @($response.IDS)[0].downloadInfo
            if (-not $info) { $result.Error = 'no-driver-returned'; return $result }
            $result.Success = $true
            $result.Version = [string]$info.Version
            $result.Released = [string]$info.ReleaseDateTime
            $result.Url = [string]$info.DetailsURL
        }
        catch { $result.Error = $_.Exception.Message }
        return $result
    }

    # Compares two dotted driver versions numerically so 616.56 sorts above 99.9.
    function Compare-WplDriverVersion([string]$Installed,[string]$Latest) {
        $parse = {
            param($value)
            $digits = @(($value -split '[^0-9]+') | Where-Object { $_ })
            if (-not $digits.Count) { return $null }
            # NVIDIA reports the installed driver as 32.0.15.6636 style, where the
            # marketing version is the trailing five digits.
            if ($digits.Count -ge 4) {
                $tail = ($digits[-2] + $digits[-1])
                if ($tail.Length -ge 5) { $tail = $tail.Substring($tail.Length - 5) }
                return [double]($tail.Insert($tail.Length - 2,'.'))
            }
            return [double]($digits -join '.')
        }
        try {
            $installedValue = & $parse $Installed
            $latestValue = & $parse $Latest
            if ($null -eq $installedValue -or $null -eq $latestValue) { return $null }
            if ($latestValue -gt $installedValue) { return 'outdated' }
            if ($latestValue -lt $installedValue) { return 'newer-than-published' }
            return 'current'
        }
        catch { return $null }
    }

    # Model-specific BIOS search. Vendors do not expose a stable query API, so
    # the operator is taken to a pre-filled search rather than a guessed
    # download URL that would rot. Returns \$null when the model is unknown.
    function Get-WplBiosSearchUrl([string]$Vendor,[string]$Model) {
        $needle = ([string]$Vendor).ToLowerInvariant()
        $model = ([string]$Model).Trim()
        if ([string]::IsNullOrWhiteSpace($model)) { return $null }
        $encoded = [uri]::EscapeDataString($model)
        if ($needle -match 'micro-star|msi') { return 'https://www.msi.com/search/' + $encoded }
        if ($needle -match 'asus|asustek') { return 'https://www.asus.com/support/download-center/?keyword=' + $encoded }
        if ($needle -match 'gigabyte') { return 'https://www.gigabyte.com/Search?kw=' + $encoded }
        if ($needle -match 'asrock') { return 'https://www.asrock.com/support/index.asp?cat=BIOS&keyword=' + $encoded }
        if ($needle -match 'biostar') { return 'https://www.biostar.com.tw/app/en/search.php?keyword=' + $encoded }
        if ($needle -match 'dell|alienware') { return 'https://www.dell.com/support/search/en-us#q=' + $encoded }
        if ($needle -match 'hewlett|hp ') { return 'https://support.hp.com/us-en/search?q=' + $encoded }
        if ($needle -match 'lenovo') { return 'https://support.lenovo.com/us/en/search?query=' + $encoded }
        if ($needle -match 'acer') { return 'https://www.acer.com/us-en/search#t=DownloadsTab&q=' + $encoded }
        if ($needle -match 'samsung') { return 'https://www.samsung.com/us/search/searchMain/?listType=g&searchTerm=' + $encoded }
        if ($needle -match 'intel') { return 'https://www.intel.com/content/www/us/en/search.html?ws=text#q=' + $encoded }
        return $null
    }

    # Vendor support pages for firmware and graphics drivers. Only official
    # first-party destinations are listed; nothing is downloaded automatically.
    function Get-WplVendorSupportUrl([string]$Kind,[string]$Vendor) {
        $needle = ([string]$Vendor).ToLowerInvariant()
        if ($Kind -eq 'gpu') {
            if ($needle -match 'nvidia') { return 'https://www.nvidia.com/Download/index.aspx' }
            if ($needle -match 'amd|ati|radeon') { return 'https://www.amd.com/en/support' }
            if ($needle -match 'intel') { return 'https://www.intel.com/content/www/us/en/download-center/home.html' }
            return $null
        }
        if ($needle -match 'micro-star|msi') { return 'https://www.msi.com/support' }
        if ($needle -match 'asus|asustek') { return 'https://www.asus.com/support/' }
        if ($needle -match 'gigabyte') { return 'https://www.gigabyte.com/Support' }
        if ($needle -match 'asrock') { return 'https://www.asrock.com/support/index.asp' }
        if ($needle -match 'biostar') { return 'https://www.biostar.com.tw/app/en/support/download.php' }
        if ($needle -match 'dell|alienware') { return 'https://www.dell.com/support/home' }
        if ($needle -match 'hewlett|hp ') { return 'https://support.hp.com/us-en/drivers' }
        if ($needle -match 'lenovo') { return 'https://support.lenovo.com/us/en/' }
        if ($needle -match 'acer') { return 'https://www.acer.com/us-en/support' }
        if ($needle -match 'samsung') { return 'https://www.samsung.com/us/support/downloads/' }
        if ($needle -match 'intel') { return 'https://www.intel.com/content/www/us/en/support.html' }
        return $null
    }

    # An advisory is a prompt to check the vendor page, never a claim that a
    # newer release exists. This tool cannot see vendor catalogues offline.
    function Set-GuiUpdateAdvice($Bios,$Board,$Graphics) {
        $advice = [Collections.Generic.List[object]]::new()
        $now = Get-Date

        $biosDate = ConvertTo-LocalDate $Bios.ReleaseDate
        if ($biosDate) {
            $ageMonths = [math]::Round(($now - $biosDate).TotalDays / 30.44,0)
            $vendor = if ($Board) { [string]$Board.Manufacturer } else { [string]$Bios.Manufacturer }
            $supportUrl = Get-WplVendorSupportUrl 'bios' $vendor
            if ($supportUrl) {
                # As with drivers, a recent release date is not proof of being
                # current, so the vendor destination is always offered.
                $severity = if ($ageMonths -ge 36) { 'caution' } elseif ($ageMonths -ge 18) { 'info' } else { 'none' }
                $detail = if ($severity -eq 'none') {
                        Get-WplText -Key AdviceBiosRecent -Language $script:GuiLanguage -ArgumentList @([string]$Bios.SMBIOSBIOSVersion,$biosDate.ToString('yyyy-MM-dd'),$ageMonths)
                    } else {
                        Get-WplText -Key AdviceBiosAge -Language $script:GuiLanguage -ArgumentList @([string]$Bios.SMBIOSBIOSVersion,$biosDate.ToString('yyyy-MM-dd'),$ageMonths)
                    }
                $advice.Add([pscustomobject]@{
                    Kind = 'bios'
                    Severity = $severity
                    Subject = (@($vendor,[string]$Board.Product) | Where-Object { $_ }) -join ' '
                    Detail = $detail
                    Url = $supportUrl
                    Vendor = $vendor
                    InstalledVersion = [string]$Bios.SMBIOSBIOSVersion
                    SearchUrl = Get-WplBiosSearchUrl $vendor ([string]$Board.Product)
                    Model = [string]$Board.Product
                })
            }
        }

        foreach ($adapter in @($Graphics)) {
            $driverDate = ConvertTo-LocalDate $adapter.DriverDate
            $vendor = [string]$adapter.AdapterCompatibility
            $supportUrl = Get-WplVendorSupportUrl 'gpu' $vendor
            $canQuery = $vendor -match '(?i)nvidia'
            $ageMonths = if ($driverDate) { [math]::Round(($now - $driverDate).TotalDays / 30.44,0) } else { $null }
            # A recent driver date does not mean the driver is current, so an entry
            # is emitted whenever a vendor destination exists. Severity conveys
            # whether age alone already warrants attention.
            $severity = if ($null -ne $ageMonths -and $ageMonths -ge 24) { 'caution' }
                elseif ($null -ne $ageMonths -and $ageMonths -ge 12) { 'info' }
                else { 'none' }
            if (-not $supportUrl -and -not $canQuery) { continue }
            $detail = if ($null -eq $ageMonths) {
                    Get-WplText -Key AdviceGpuDriverUnknownDate -Language $script:GuiLanguage -ArgumentList @([string]$adapter.DriverVersion)
                }
                elseif ($severity -eq 'none') {
                    Get-WplText -Key AdviceGpuDriverRecent -Language $script:GuiLanguage -ArgumentList @([string]$adapter.DriverVersion,$driverDate.ToString('yyyy-MM-dd'),$ageMonths)
                }
                else {
                    Get-WplText -Key AdviceGpuDriverAge -Language $script:GuiLanguage -ArgumentList @([string]$adapter.DriverVersion,$driverDate.ToString('yyyy-MM-dd'),$ageMonths)
                }
            $advice.Add([pscustomobject]@{
                Kind = 'gpu'
                Severity = $severity
                Subject = [string]$adapter.Name
                Detail = $detail
                Url = $supportUrl
                Vendor = $vendor
                InstalledVersion = [string]$adapter.DriverVersion
            })
        }

        $script:GuiUpdateAdvice = $advice
    }

    # Detail window for one hardware card. Read-only text plus any vendor links
    # that apply to the card's subject.
    function Show-GuiHardwareDetail([string]$Section,[string]$Title) {
        $lines = if ($script:GuiHardwareDetail -and $script:GuiHardwareDetail.ContainsKey($Section)) { @($script:GuiHardwareDetail[$Section]) } else { @() }
        if (-not $lines.Count) {
            [System.Windows.MessageBox]::Show((Get-WplText -Key GuiDetailUnavailable -Language $script:GuiLanguage),$window.Title) | Out-Null
            return
        }
        $relevant = @($script:GuiUpdateAdvice | Where-Object {
            ($Section -eq 'cpu' -and $_.Kind -eq 'bios') -or ($Section -eq 'gpu' -and $_.Kind -eq 'gpu')
        })

        [xml]$detailXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" Height="620" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Segoe UI" SizeToContent="Manual">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="DetailTitle" Grid.Row="0" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,12"/>
    <Border x:Name="DetailSurface" Grid.Row="1" CornerRadius="8" Padding="12">
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
        <TextBlock x:Name="DetailBody" TextWrapping="NoWrap" FontFamily="Consolas" FontSize="12" LineHeight="18"/>
      </ScrollViewer>
    </Border>
    <StackPanel x:Name="AdvicePanel" Grid.Row="2" Margin="0,12,0,0"/>
    <Button x:Name="DetailCloseButton" Grid.Row="3" Height="30" MinWidth="110" HorizontalAlignment="Right" Margin="0,12,0,0"/>
  </Grid>
</Window>
'@
        $detailWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $detailXaml))
        $detailWindow.Owner = $window
        $detailWindow.Title = $Title
        $detailWindow.Background = $window.TryFindResource('Canvas')
        $detailWindow.Foreground = $window.TryFindResource('Ink')
        $body = $detailWindow.FindName('DetailBody')
        $body.Foreground = $window.TryFindResource('InkMuted')
        $body.Text = ($lines -join [Environment]::NewLine)
        $titleBlock = $detailWindow.FindName('DetailTitle')
        $titleBlock.Text = $Title
        $titleBlock.Foreground = $window.TryFindResource('Ink')
        $detailWindow.FindName('DetailSurface').Background = $window.TryFindResource('Surface1')
        $close = $detailWindow.FindName('DetailCloseButton')
        $close.Content = Get-WplText -Key GuiDetailClose -Language $script:GuiLanguage
        $close.Style = $window.TryFindResource('ActionButton')
        $close.Add_Click({ $detailWindow.Close() })

        $advicePanel = $detailWindow.FindName('AdvicePanel')
        foreach ($item in $relevant) {
            $card = New-Object Windows.Controls.Border
            $card.Background = $window.TryFindResource('Surface2')
            $card.CornerRadius = New-Object Windows.CornerRadius 8
            $card.Padding = New-Object Windows.Thickness 12
            $card.Margin = New-Object Windows.Thickness 0,0,0,8
            $card.BorderThickness = New-Object Windows.Thickness 2,0,0,0
            $card.BorderBrush = $window.TryFindResource($(switch ($item.Severity) { 'caution' { 'Caution' } 'info' { 'Accent' } default { 'Hairline' } }))
            $stack = New-Object Windows.Controls.StackPanel
            $heading = New-Object Windows.Controls.TextBlock
            $headingKey = if ($item.Severity -eq 'none') {
                    if ($item.Kind -eq 'bios') { 'AdviceBiosCheckHeading' } else { 'AdviceGpuCheckHeading' }
                } else {
                    if ($item.Kind -eq 'bios') { 'AdviceBiosHeading' } else { 'AdviceGpuHeading' }
                }
            $heading.Text = Get-WplText -Key $headingKey -Language $script:GuiLanguage
            $heading.FontWeight = 'SemiBold'
            $heading.FontSize = 12
            $heading.Foreground = $window.TryFindResource('Ink')
            $stack.Children.Add($heading) | Out-Null
            $detailText = New-Object Windows.Controls.TextBlock
            $detailText.Text = $item.Subject + [Environment]::NewLine + $item.Detail
            $detailText.TextWrapping = 'Wrap'
            $detailText.FontSize = 11
            $detailText.LineHeight = 17
            $detailText.Margin = New-Object Windows.Thickness 0,4,0,0
            $detailText.Foreground = $window.TryFindResource('InkSubtle')
            $stack.Children.Add($detailText) | Out-Null
            if ($item.Url) {
                $linkButton = New-Object Windows.Controls.Button
                $linkButton.Content = Get-WplText -Key GuiOpenVendorPage -Language $script:GuiLanguage
                $linkButton.Style = $window.TryFindResource('ActionButton')
                $linkButton.HorizontalAlignment = 'Left'
                $linkButton.Margin = New-Object Windows.Thickness 0,8,0,0
                $linkButton.Padding = New-Object Windows.Thickness 10,4,10,4
                $linkButton.FontSize = 11
                $linkButton.Tag = $item.Url
                $linkButton.ToolTip = $item.Url
                $linkButton.Add_Click({
                    param($sender,$eventArgs)
                    try { Start-Process ([string]$sender.Tag) }
                    catch { [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null }
                })
                $stack.Children.Add($linkButton) | Out-Null
            }
            # Only NVIDIA publishes a stable version query, so the online check
            # button appears for that vendor alone. It runs on click, not during
            # analysis, and reports failure plainly instead of guessing.
            if ($item.Kind -eq 'gpu' -and $item.Vendor -match '(?i)nvidia') {
                $checkButton = New-Object Windows.Controls.Button
                $checkButton.Content = Get-WplText -Key GuiCheckLatestDriver -Language $script:GuiLanguage
                $checkButton.Style = $window.TryFindResource('PrimaryButton')
                $checkButton.HorizontalAlignment = 'Left'
                $checkButton.Margin = New-Object Windows.Thickness 0,8,0,0
                $checkButton.Padding = New-Object Windows.Thickness 10,4,10,4
                $checkButton.FontSize = 11
                $resultText = New-Object Windows.Controls.TextBlock
                $resultText.TextWrapping = 'Wrap'
                $resultText.FontSize = 11
                $resultText.LineHeight = 17
                $resultText.Margin = New-Object Windows.Thickness 0,6,0,0
                $resultText.Visibility = 'Collapsed'
                $checkButton.Add_Click({
                    param($sender,$eventArgs)
                    $sender.IsEnabled = $false
                    $resultText.Visibility = 'Visible'
                    $resultText.Foreground = $window.TryFindResource('InkSubtle')
                    $resultText.Text = Get-WplText -Key GuiCheckingLatest -Language $script:GuiLanguage
                    $detailWindow.Dispatcher.Invoke([action]{},'Render')
                    $lookup = Get-WplNvidiaLatestDriver ([string]$item.Subject)
                    if (-not $lookup.Success) {
                        $resultText.Foreground = $window.TryFindResource('Caution')
                        $resultText.Text = Get-WplText -Key GuiCheckLatestFailed -Language $script:GuiLanguage -ArgumentList @([string]$lookup.Error)
                        $sender.IsEnabled = $true
                        return
                    }
                    $verdict = Compare-WplDriverVersion ([string]$item.InstalledVersion) ([string]$lookup.Version)
                    switch ($verdict) {
                        'outdated' {
                            $resultText.Foreground = $window.TryFindResource('Caution')
                            $resultText.Text = Get-WplText -Key GuiLatestAvailable -Language $script:GuiLanguage -ArgumentList @([string]$lookup.Version,[string]$lookup.Released)
                        }
                        'current' {
                            $resultText.Foreground = $window.TryFindResource('Ok')
                            $resultText.Text = Get-WplText -Key GuiLatestCurrent -Language $script:GuiLanguage -ArgumentList @([string]$lookup.Version)
                        }
                        'newer-than-published' {
                            $resultText.Foreground = $window.TryFindResource('InkSubtle')
                            $resultText.Text = Get-WplText -Key GuiLatestAhead -Language $script:GuiLanguage -ArgumentList @([string]$lookup.Version)
                        }
                        default {
                            $resultText.Foreground = $window.TryFindResource('InkSubtle')
                            $resultText.Text = Get-WplText -Key GuiLatestUnknown -Language $script:GuiLanguage -ArgumentList @([string]$lookup.Version,[string]$lookup.Released)
                        }
                    }
                    if ($lookup.Url) { $sender.Tag = [string]$lookup.Url; $sender.ToolTip = [string]$lookup.Url }
                    $sender.IsEnabled = $true
                })
                $stack.Children.Add($checkButton) | Out-Null
                $stack.Children.Add($resultText) | Out-Null
            }
            # BIOS has no queryable endpoint, so the operator is handed a
            # model-filtered search plus the exact version string to compare.
            if ($item.Kind -eq 'bios' -and $item.SearchUrl) {
                $searchButton = New-Object Windows.Controls.Button
                $searchButton.Content = Get-WplText -Key GuiSearchBios -Language $script:GuiLanguage
                $searchButton.Style = $window.TryFindResource('PrimaryButton')
                $searchButton.HorizontalAlignment = 'Left'
                $searchButton.Margin = New-Object Windows.Thickness 0,8,0,0
                $searchButton.Padding = New-Object Windows.Thickness 10,4,10,4
                $searchButton.FontSize = 11
                $searchButton.Tag = [string]$item.SearchUrl
                $searchButton.ToolTip = [string]$item.SearchUrl
                $searchButton.Add_Click({
                    param($sender,$eventArgs)
                    try { Start-Process ([string]$sender.Tag) }
                    catch { [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null }
                })
                $stack.Children.Add($searchButton) | Out-Null
                $steps = New-Object Windows.Controls.TextBlock
                $steps.Text = Get-WplText -Key GuiBiosManualSteps -Language $script:GuiLanguage -ArgumentList @([string]$item.Model,[string]$item.InstalledVersion)
                $steps.TextWrapping = 'Wrap'
                $steps.FontSize = 11
                $steps.LineHeight = 17
                $steps.Margin = New-Object Windows.Thickness 0,6,0,0
                $steps.Foreground = $window.TryFindResource('InkSubtle')
                $stack.Children.Add($steps) | Out-Null
            }
            $card.Child = $stack
            $advicePanel.Children.Add($card) | Out-Null
        }

        [void]$detailWindow.ShowDialog()
    }

    function Set-GuiAnalysisControls([bool]$Enabled) {
        foreach ($button in @($ui.QuickButton,$ui.StandardButton,$ui.DeepButton,$ui.AllButton,$ui.StorageButton,$ui.MemoryButton,$ui.GpuButton,$ui.RefreshButton,$ui.BatchDownloadButton)) { $button.IsEnabled = $Enabled }
        $ui.AnalysisProgressBar.Visibility = if ($Enabled) { [Windows.Visibility]::Collapsed } else { [Windows.Visibility]::Visible }
    }

    # Installations run out of process so the UI stays responsive, and the same
    # watcher refreshes the program list from the cached recommendation
    # snapshot the moment an installer exits - no full re-analysis needed.
    function Start-WplGuiInstaller([string]$DisplayName,[string[]]$InstallerArguments) {
        if (-not $script:GuiInstallers) { $script:GuiInstallers = [Collections.Generic.List[object]]::new() }
        $tokens = [Collections.Generic.List[string]]::new()
        $tokens.AddRange([string[]]@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'scripts\Install-PortableTools.ps1'),'-Root',$Root,'-Language',$script:GuiLanguage))
        $tokens.AddRange($InstallerArguments)
        $logDirectory = Join-Path $Root 'logs'
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $stdoutLog = Join-Path $logDirectory 'tool-install-latest.out.log'
        $stderrLog = Join-Path $logDirectory 'tool-install-latest.err.log'
        $process = Start-Process powershell.exe -ArgumentList (ConvertTo-WplWindowsCommandLine -ArgumentList $tokens.ToArray()) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
        $script:GuiInstallers.Add([pscustomobject]@{Process=$process;DisplayName=$DisplayName})
        Set-GuiStatusTone 'busy'
        $ui.StatusText.Text = Get-WplText -Key GuiDownloadStarted -Language $script:GuiLanguage -ArgumentList @($DisplayName)
        $timer.Start()
    }

    function Update-WplGuiInstallers {
        if (-not $script:GuiInstallers -or $script:GuiInstallers.Count -eq 0) { return $false }
        foreach ($installer in $script:GuiInstallers) { $installer.Process.Refresh() }
        $finished = @($script:GuiInstallers | Where-Object { $_.Process.HasExited })
        foreach ($installer in $finished) { [void]$script:GuiInstallers.Remove($installer) }
        if ($finished.Count) {
            $names = (@($finished | ForEach-Object { $_.DisplayName }) -join ', ')
            $failed = @($finished | Where-Object { $_.Process.ExitCode -ne 0 })
            Reset-WplToolIndex
            if ($failed.Count) {
                Set-GuiStatusTone 'fail'
                $ui.StatusText.Text = Get-WplText -Key GuiDownloadFailed -Language $script:GuiLanguage -ArgumentList @($names)
            }
            else {
                try { Set-GuiPlanFromCurrentSnapshot } catch { }
                Set-GuiStatusTone 'ok'
                $ui.StatusText.Text = Get-WplText -Key GuiDownloadCompleted -Language $script:GuiLanguage -ArgumentList @($names)
            }
        }
        return ($script:GuiInstallers.Count -gt 0)
    }

    # Runs the network driver helper out of process so an elevation prompt can be
    # requested for the two actions that touch the driver store, and so console
    # output is captured verbatim instead of being reformatted by the GUI.
    function Invoke-GuiNetworkDriverAction([string]$Action,[string]$BackupPath,[switch]$AcknowledgeRisk) {
        $helper = Join-Path $Root 'scripts\Set-WplNetworkDriver.ps1'
        $logDirectory = Join-Path $Root 'logs'
        if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
        $logPath = Join-Path $logDirectory ('network-driver-{0}.log' -f $Action)
        if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue }
        $quote = { param($value) "'" + ([string]$value -replace "'","''") + "'" }
        $inner = [Text.StringBuilder]::new()
        [void]$inner.Append('[Console]::OutputEncoding=[Text.Encoding]::UTF8; & ')
        [void]$inner.Append((& $quote $helper))
        [void]$inner.Append(' -Root ').Append((& $quote $Root))
        [void]$inner.Append(' -Action ').Append($Action)
        [void]$inner.Append(' -Language ').Append($script:GuiLanguage)
        if ($BackupPath) { [void]$inner.Append(' -BackupPath ').Append((& $quote $BackupPath)) }
        if ($AcknowledgeRisk) { [void]$inner.Append(' -AcknowledgeRisk') }
        [void]$inner.Append(' *>&1 | Out-File -LiteralPath ').Append((& $quote $logPath)).Append(' -Encoding utf8')
        $start = @{
            FilePath = 'powershell.exe'
            ArgumentList = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-Command',$inner.ToString())
            WindowStyle = 'Hidden'
            Wait = $true
            PassThru = $true
        }
        # status and list only read, so they never provoke a UAC prompt.
        if (-not $script:GuiIsAdministrator -and $Action -in @('backup','restore')) { $start.Verb = 'RunAs' }
        $process = Start-Process @start
        $output = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -Encoding utf8 } else { '' }
        [pscustomobject]@{ ExitCode = [int]$process.ExitCode; Output = [string]$output; LogPath = $logPath }
    }

    function Get-GuiNetworkDriverBackups {
        $store = Join-Path $Root 'offline-packs\network-drivers'
        if (-not (Test-Path -LiteralPath $store -PathType Container)) { return @() }
        return @(Get-ChildItem -LiteralPath $store -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    }

    # Network one-pack sources. Every entry is a landing page rather than a direct
    # file, because these projects rotate build numbers and a pinned binary URL
    # rots within months. Nothing is downloaded automatically.
    function Get-WplNetworkPackSources {
        @(
            [pscustomobject]@{
                Id = '3dp-net'
                Name = '3DP Net'
                Url = 'https://www.3dpchip.com/3dpchip/3dp/net_down_en.php'
                NoteKey = 'GuiNetPack3dpNote'
                DescriptionKey = 'GuiNetPack3dpDesc'
                ReputationKey = 'GuiNetPack3dpReputation'
                Bundled = $false
            }
            [pscustomobject]@{
                Id = 'sdio-net'
                Name = 'Snappy Driver Installer Origin'
                Url = 'https://www.snappy-driver-installer.org/'
                NoteKey = 'GuiNetPackSdioNote'
                DescriptionKey = 'GuiNetPackSdioDesc'
                ReputationKey = 'GuiNetPackSdioReputation'
                Bundled = $true
            }
            [pscustomobject]@{
                Id = 'drvceo-net'
                Name = 'DrvCeo'
                Url = 'https://www.sysceo.com/software-softwarei-id-245.html'
                NoteKey = 'GuiNetPackDrvceoNote'
                DescriptionKey = 'GuiNetPackDrvceoDesc'
                ReputationKey = 'GuiNetPackDrvceoReputation'
                Bundled = $false
            }
        )
    }

    # One card per source: what it is, what it costs to download, and the caveat
    # that decides whether it suits the machine in front of you.
    function Show-GuiNetworkPackSources {
        [xml]$packXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="700" Height="640" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Segoe UI" SizeToContent="Manual">
  <Grid Margin="18">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="PackTitle" Grid.Row="0" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
    <TextBlock x:Name="PackIntro" Grid.Row="1" FontSize="11" LineHeight="17" TextWrapping="Wrap" Margin="0,8,0,0"/>
    <ScrollViewer x:Name="PackScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" PanningMode="VerticalOnly" Margin="0,12,0,0">
      <StackPanel x:Name="PackList" Margin="0,0,6,0"/>
    </ScrollViewer>
    <Button x:Name="PackCloseButton" Grid.Row="3" Height="30" MinWidth="110" HorizontalAlignment="Right" Margin="0,12,0,0"/>
  </Grid>
</Window>
'@
        $packWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $packXaml))
        $packWindow.Owner = $window
        $packWindow.Background = $window.TryFindResource('Canvas')
        $packWindow.Foreground = $window.TryFindResource('Ink')
        $packWindow.Title = Get-WplText -Key GuiNetDriverOnePackTitle -Language $script:GuiLanguage
        $packTitle = $packWindow.FindName('PackTitle')
        $packTitle.Text = $packWindow.Title
        $packTitle.Foreground = $window.TryFindResource('Ink')
        $packIntro = $packWindow.FindName('PackIntro')
        $packIntro.Text = Get-WplText -Key GuiNetDriverOnePackIntro -Language $script:GuiLanguage
        $packIntro.Foreground = $window.TryFindResource('InkSubtle')
        $packScroll = $packWindow.FindName('PackScroll')
        $packScroll.Add_PreviewMouseWheel({param($sender,$eventArgs);Move-GuiScroll $sender $eventArgs.Delta;$eventArgs.Handled=$true})
        $packClose = $packWindow.FindName('PackCloseButton')
        $packClose.Content = Get-WplText -Key GuiDetailClose -Language $script:GuiLanguage
        $packClose.Style = $window.TryFindResource('ActionButton')
        $packClose.Add_Click({ $packWindow.Close() })
        $packList = $packWindow.FindName('PackList')

        foreach ($source in @(Get-WplNetworkPackSources)) {
            $card = New-Object Windows.Controls.Border
            $card.Background = $window.TryFindResource('Surface1')
            $card.CornerRadius = New-Object Windows.CornerRadius 8
            $card.Padding = New-Object Windows.Thickness 14
            $card.Margin = New-Object Windows.Thickness 0,0,0,10
            $card.BorderThickness = New-Object Windows.Thickness 2,0,0,0
            $card.BorderBrush = $window.TryFindResource($(if ($source.Bundled) { 'Ok' } else { 'Hairline' }))
            $stack = New-Object Windows.Controls.StackPanel

            $heading = New-Object Windows.Controls.TextBlock
            $heading.Text = if ($source.Bundled) { '{0} - {1}' -f $source.Name,(Get-WplText -Key GuiNetPackBundled -Language $script:GuiLanguage) } else { [string]$source.Name }
            $heading.FontWeight = 'SemiBold'
            $heading.FontSize = 13
            $heading.TextWrapping = 'Wrap'
            $heading.Foreground = $window.TryFindResource('Ink')
            $stack.Children.Add($heading) | Out-Null

            $note = New-Object Windows.Controls.TextBlock
            $note.Text = Get-WplText -Key ([string]$source.NoteKey) -Language $script:GuiLanguage
            $note.FontSize = 10
            $note.TextWrapping = 'Wrap'
            $note.Margin = New-Object Windows.Thickness 0,4,0,0
            $note.Foreground = $window.TryFindResource('InkTertiary')
            $stack.Children.Add($note) | Out-Null

            $description = New-Object Windows.Controls.TextBlock
            $description.Text = Get-WplText -Key ([string]$source.DescriptionKey) -Language $script:GuiLanguage
            $description.FontSize = 11
            $description.LineHeight = 17
            $description.TextWrapping = 'Wrap'
            $description.Margin = New-Object Windows.Thickness 0,7,0,0
            $description.Foreground = $window.TryFindResource('InkSubtle')
            $stack.Children.Add($description) | Out-Null

            # Reputation is reported as-is, including where communities disagree.
            # Presenting only the favourable half would mislead the operator.
            if ($source.ReputationKey) {
                $reputationHeading = New-Object Windows.Controls.TextBlock
                $reputationHeading.Text = Get-WplText -Key GuiNetPackReputation -Language $script:GuiLanguage
                $reputationHeading.FontSize = 10
                $reputationHeading.FontWeight = 'Medium'
                $reputationHeading.Margin = New-Object Windows.Thickness 0,9,0,0
                $reputationHeading.Foreground = $window.TryFindResource('InkTertiary')
                $stack.Children.Add($reputationHeading) | Out-Null
                $reputationText = New-Object Windows.Controls.TextBlock
                $reputationText.Text = Get-WplText -Key ([string]$source.ReputationKey) -Language $script:GuiLanguage
                $reputationText.FontSize = 11
                $reputationText.LineHeight = 17
                $reputationText.TextWrapping = 'Wrap'
                $reputationText.Margin = New-Object Windows.Thickness 0,4,0,0
                $reputationText.Foreground = $window.TryFindResource('InkSubtle')
                $stack.Children.Add($reputationText) | Out-Null
            }

            $addressText = New-Object Windows.Controls.TextBlock
            $addressText.Text = [string]$source.Url
            $addressText.FontFamily = New-Object Windows.Media.FontFamily 'Consolas'
            $addressText.FontSize = 10
            $addressText.TextWrapping = 'Wrap'
            $addressText.Margin = New-Object Windows.Thickness 0,7,0,0
            $addressText.Foreground = $window.TryFindResource('InkTertiary')
            $stack.Children.Add($addressText) | Out-Null

            $buttonRow = New-Object Windows.Controls.StackPanel
            $buttonRow.Orientation = 'Horizontal'
            $buttonRow.Margin = New-Object Windows.Thickness 0,9,0,0
            $openButton = New-Object Windows.Controls.Button
            $openButton.Content = Get-WplText -Key GuiNetDriverOnePackOpen -Language $script:GuiLanguage
            $openButton.Style = $window.TryFindResource('PrimaryButton')
            $openButton.Padding = New-Object Windows.Thickness 12,5,12,5
            $openButton.FontSize = 11
            $openButton.Tag = [string]$source.Url
            $openButton.ToolTip = [string]$source.Url
            $openButton.Add_Click({
                param($sender,$eventArgs)
                try { Start-Process ([string]$sender.Tag) }
                catch { [System.Windows.MessageBox]::Show($_.Exception.Message,$packWindow.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null }
            })
            $buttonRow.Children.Add($openButton) | Out-Null
            $copyButton = New-Object Windows.Controls.Button
            $copyButton.Content = Get-WplText -Key GuiNetDriverOnePackCopy -Language $script:GuiLanguage
            $copyButton.Style = $window.TryFindResource('ActionButton')
            $copyButton.Padding = New-Object Windows.Thickness 12,5,12,5
            $copyButton.FontSize = 11
            $copyButton.Margin = New-Object Windows.Thickness 8,0,0,0
            $copyButton.Tag = [string]$source.Url
            $copyButton.Add_Click({
                param($sender,$eventArgs)
                try {
                    [Windows.Clipboard]::SetText([string]$sender.Tag)
                    $ui.StatusText.Text = Get-WplText -Key GuiNetDriverOnePackCopied -Language $script:GuiLanguage -ArgumentList @([string]$sender.Tag)
                }
                catch { [System.Windows.MessageBox]::Show($_.Exception.Message,$packWindow.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null }
            })
            $buttonRow.Children.Add($copyButton) | Out-Null
            $stack.Children.Add($buttonRow) | Out-Null

            $card.Child = $stack
            $packList.Children.Add($card) | Out-Null
        }

        # The real hazard with these tools is a tampered mirror rather than the
        # tool itself, so the source warning and the responsibility notice close
        # the list instead of hiding in one card.
        foreach ($noticeKey in @('GuiNetPackOfficialOnly','GuiNetPackUserResponsibility')) {
            $notice = New-Object Windows.Controls.Border
            $notice.Background = $window.TryFindResource('Surface2')
            $notice.CornerRadius = New-Object Windows.CornerRadius 8
            $notice.Padding = New-Object Windows.Thickness 14
            $notice.Margin = New-Object Windows.Thickness 0,0,0,10
            $notice.BorderThickness = New-Object Windows.Thickness 2,0,0,0
            $notice.BorderBrush = $window.TryFindResource($(if ($noticeKey -eq 'GuiNetPackOfficialOnly') { 'Caution' } else { 'Hairline' }))
            $noticeText = New-Object Windows.Controls.TextBlock
            $noticeText.Text = Get-WplText -Key $noticeKey -Language $script:GuiLanguage
            $noticeText.FontSize = 11
            $noticeText.LineHeight = 17
            $noticeText.TextWrapping = 'Wrap'
            $noticeText.Foreground = $window.TryFindResource('InkSubtle')
            $notice.Child = $noticeText
            $packList.Children.Add($notice) | Out-Null
        }

        [void]$packWindow.ShowDialog()
    }

    # Network drivers are the one class of driver whose absence blocks fetching
    # every other driver, so they get a dedicated surface rather than living
    # inside the generic recommendation list.
    function Show-GuiNetworkDriver {
        [xml]$netXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="660" Height="620" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Segoe UI" SizeToContent="Manual">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="NetTitle" Grid.Row="0" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
    <TextBlock x:Name="NetIntro" Grid.Row="1" FontSize="11" LineHeight="17" TextWrapping="Wrap" Margin="0,8,0,0"/>
    <WrapPanel x:Name="NetActions" Grid.Row="2" Margin="0,12,0,0"/>
    <Grid Grid.Row="3" Margin="0,2,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="NetBackupLabel" Grid.Column="0" FontSize="11" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <ComboBox x:Name="NetBackupCombo" Grid.Column="1" Height="26" FontSize="11" VerticalContentAlignment="Center"/>
      <Button x:Name="NetRestoreButton" Grid.Column="2" Height="26" MinWidth="140" Margin="8,0,0,0" FontSize="11"/>
    </Grid>
    <Border x:Name="NetOutputSurface" Grid.Row="4" CornerRadius="8" Padding="12" Margin="0,12,0,0">
      <ScrollViewer x:Name="NetOutputScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" PanningMode="VerticalOnly">
        <TextBlock x:Name="NetOutputBody" TextWrapping="NoWrap" FontFamily="Consolas" FontSize="11" LineHeight="17"/>
      </ScrollViewer>
    </Border>
    <Button x:Name="NetCloseButton" Grid.Row="5" Height="30" MinWidth="110" HorizontalAlignment="Right" Margin="0,12,0,0"/>
  </Grid>
</Window>
'@
        $netWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $netXaml))
        $netWindow.Owner = $window
        $netWindow.Background = $window.TryFindResource('Canvas')
        $netWindow.Foreground = $window.TryFindResource('Ink')
        $netWindow.Title = Get-WplText -Key GuiNetDriverTitle -Language $script:GuiLanguage
        $netTitle = $netWindow.FindName('NetTitle')
        $netTitle.Text = $netWindow.Title
        $netTitle.Foreground = $window.TryFindResource('Ink')
        $netIntro = $netWindow.FindName('NetIntro')
        $netIntro.Text = Get-WplText -Key GuiNetDriverIntro -Language $script:GuiLanguage
        $netIntro.Foreground = $window.TryFindResource('InkSubtle')
        $netWindow.FindName('NetOutputSurface').Background = $window.TryFindResource('Surface1')
        $netBody = $netWindow.FindName('NetOutputBody')
        $netBody.Foreground = $window.TryFindResource('InkMuted')
        $netScroll = $netWindow.FindName('NetOutputScroll')
        $netScroll.Add_PreviewMouseWheel({param($sender,$eventArgs);Move-GuiScroll $sender $eventArgs.Delta;$eventArgs.Handled=$true})
        $netClose = $netWindow.FindName('NetCloseButton')
        $netClose.Content = Get-WplText -Key GuiDetailClose -Language $script:GuiLanguage
        $netClose.Style = $window.TryFindResource('ActionButton')
        $netClose.Add_Click({ $netWindow.Close() })
        $netBackupLabel = $netWindow.FindName('NetBackupLabel')
        $netBackupLabel.Text = Get-WplText -Key GuiNetDriverBackupLabel -Language $script:GuiLanguage
        $netBackupLabel.Foreground = $window.TryFindResource('InkTertiary')
        $netCombo = $netWindow.FindName('NetBackupCombo')
        $netActions = $netWindow.FindName('NetActions')

        $refreshBackups = {
            $previous = [string]$netCombo.SelectedItem
            $netCombo.Items.Clear()
            foreach ($directory in @(Get-GuiNetworkDriverBackups)) { [void]$netCombo.Items.Add($directory.Name) }
            if ($netCombo.Items.Count -gt 0) {
                $netCombo.SelectedIndex = if ($previous -and $netCombo.Items.Contains($previous)) { $netCombo.Items.IndexOf($previous) } else { 0 }
            }
        }
        $runAction = {
            param([string]$ActionName,[string]$SelectedBackupPath,[bool]$RiskAccepted)
            $netBody.Foreground = $window.TryFindResource('InkSubtle')
            $netBody.Text = Get-WplText -Key GuiNetDriverRunning -Language $script:GuiLanguage -ArgumentList @($ActionName)
            $netWindow.Dispatcher.Invoke([action]{},'Render')
            try {
                $result = Invoke-GuiNetworkDriverAction -Action $ActionName -BackupPath $SelectedBackupPath -AcknowledgeRisk:$RiskAccepted
                $netBody.Foreground = $window.TryFindResource($(if ($result.ExitCode -eq 0) { 'InkMuted' } else { 'Caution' }))
                $netBody.Text = if ([string]::IsNullOrWhiteSpace([string]$result.Output)) { [string]$result.LogPath } else { ([string]$result.Output).TrimEnd() }
                $netScroll.ScrollToTop()
            }
            catch {
                $netBody.Foreground = $window.TryFindResource('Caution')
                $netBody.Text = Get-WplText -Key GuiNetDriverActionFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
            }
            & $refreshBackups
        }
        $addAction = {
            param([string]$TextKey,[scriptblock]$Handler,[bool]$Primary)
            $actionButton = New-Object Windows.Controls.Button
            $actionButton.Content = Get-WplText -Key $TextKey -Language $script:GuiLanguage
            $actionButton.Style = $window.TryFindResource($(if ($Primary) { 'PrimaryButton' } else { 'ActionButton' }))
            $actionButton.Margin = New-Object Windows.Thickness 0,0,8,8
            $actionButton.Padding = New-Object Windows.Thickness 12,5,12,5
            $actionButton.FontSize = 11
            $actionButton.Add_Click($Handler)
            $netActions.Children.Add($actionButton) | Out-Null
        }

        & $addAction 'GuiNetDriverStatusAction' { & $runAction 'status' '' $false } $false
        & $addAction 'GuiNetDriverBackupAction' {
            $answer = [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNetDriverBackupConfirm -Language $script:GuiLanguage),$netWindow.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Information)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
            & $runAction 'backup' '' $false
        } $true
        & $addAction 'GuiNetDriverListAction' { & $runAction 'list' '' $false } $false
        & $addAction 'GuiNetDriverOnePackAction' {
            try { Show-GuiNetworkPackSources }
            catch {
                $netBody.Foreground = $window.TryFindResource('Caution')
                $netBody.Text = Get-WplText -Key GuiNetDriverActionFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
            }
        } $false
        & $addAction 'GuiNetDriverSdioAction' {
            $sdioRows = @()
            if ($script:GuiPlan) { $sdioRows = @($script:GuiPlan.programs | Where-Object { [string]$_.catalogId -eq 'sdio' }) }
            if (-not $sdioRows.Count -or -not $sdioRows[0].launchable) {
                [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNetDriverSdioMissing -Language $script:GuiLanguage),$netWindow.Title) | Out-Null
                return
            }
            $confirm = Get-WplText -Key GuiRiskConfirm -Language $script:GuiLanguage -ArgumentList @([string]$sdioRows[0].riskText)
            $answer = [System.Windows.MessageBox]::Show($confirm,$netWindow.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
            try {
                [void](Open-ToolIds -Ids @([string]$sdioRows[0].id) -RiskAccepted -UseLanguage $script:GuiLanguage)
                $netBody.Foreground = $window.TryFindResource('InkMuted')
                $netBody.Text = Get-WplText -Key GuiLaunchStarted -Language $script:GuiLanguage -ArgumentList @([string]$sdioRows[0].id)
            }
            catch {
                $netBody.Foreground = $window.TryFindResource('Caution')
                $netBody.Text = Get-WplText -Key GuiNetDriverActionFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
            }
        } $false
        & $addAction 'GuiNetDriverGuideAction' {
            try { Open-WplTextDocument (Join-Path $Root ('docs\{0}\NETWORK_DRIVERS.md' -f $script:GuiLanguage)) }
            catch {
                $netBody.Foreground = $window.TryFindResource('Caution')
                $netBody.Text = Get-WplText -Key GuiNetDriverActionFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
            }
        } $false

        $netRestore = $netWindow.FindName('NetRestoreButton')
        $netRestore.Content = Get-WplText -Key GuiNetDriverRestoreAction -Language $script:GuiLanguage
        $netRestore.Style = $window.TryFindResource('ActionButton')
        $netRestore.Add_Click({
            $selectedBackup = [string]$netCombo.SelectedItem
            if ([string]::IsNullOrWhiteSpace($selectedBackup)) {
                [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNetDriverNoBackupSelected -Language $script:GuiLanguage),$netWindow.Title) | Out-Null
                return
            }
            $message = Get-WplText -Key GuiNetDriverRestoreConfirm -Language $script:GuiLanguage -ArgumentList @($selectedBackup)
            $answer = [System.Windows.MessageBox]::Show($message,$netWindow.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
            & $runAction 'restore' (Join-Path (Join-Path $Root 'offline-packs\network-drivers') $selectedBackup) $true
        })

        & $refreshBackups
        # The first status pass runs after the window is up. Calling it inline
        # blocked on a hidden child process before ShowDialog, so the dialog only
        # appeared once the probe finished.
        $netWindow.Add_ContentRendered({ & $runAction 'status' '' $false })
        [void]$netWindow.ShowDialog()
    }

    # Status colours resolve from the window's colour tokens so the palette stays
    # defined in one place instead of being repeated at every call site.
    function Set-GuiStatusTone([string]$Tone) {
        $key = switch ($Tone) { 'ok' { 'Ok' } 'busy' { 'Caution' } 'fail' { 'Danger' } default { 'InkSubtle' } }
        $brush = $window.TryFindResource($key)
        if ($brush) { $ui.StatusDot.Fill = $brush }
    }

    function Set-GuiText {
        $code = $script:GuiLanguage
        $window.Title = Get-WplText -Key GuiBrand -Language $code
        $ui.BadgeText.Text = Get-WplText -Key GuiBadge -Language $code
        $ui.BrandText.Text = Get-WplText -Key GuiBrand -Language $code
        $ui.DescriptionText.Text = Get-WplText -Key GuiDescription -Language $code
        $ui.LanguageButton.Content = Get-WplText -Key GuiLanguage -Language $code
        $ui.SystemSectionText.Text = Get-WplText -Key GuiSystem -Language $code
        $ui.RecordsSectionText.Text = Get-WplText -Key GuiRecordsSection -Language $code
        $ui.ManageSectionText.Text = Get-WplText -Key GuiManageSection -Language $code
        $ui.MoreExpander.Header = Get-WplText -Key GuiMore -Language $code
        $ui.RecommendationSectionText.Text = Get-WplText -Key GuiRecommended -Language $code
        $ui.QuickButton.Content = Get-WplText -Key GuiQuick -Language $code
        $ui.StandardButton.Content = Get-WplText -Key GuiStandard -Language $code
        $ui.DeepButton.Content = Get-WplText -Key GuiDeep -Language $code
        $ui.AllButton.Content = Get-WplText -Key GuiAll -Language $code
        $ui.StorageButton.Content = Get-WplText -Key GuiStorage -Language $code
        $ui.MemoryButton.Content = Get-WplText -Key GuiMemory -Language $code
        $ui.GpuButton.Content = Get-WplText -Key GuiGpu -Language $code
        $ui.RefreshButton.Content = Get-WplText -Key GuiRefreshSystem -Language $code
        $ui.BatchDownloadButton.Content = Get-WplText -Key GuiBatchDownload -Language $code
        $ui.SafeLaunchButton.Content = Get-WplText -Key GuiSafeLaunch -Language $code
        $ui.ReportsButton.Content = Get-WplText -Key GuiReports -Language $code
        $ui.LatestResultButton.Content = Get-WplText -Key GuiLatestResult -Language $code
        $ui.NetworkDriverButton.Content = Get-WplText -Key GuiNetworkDriver -Language $code
        $ui.GithubButton.Content = Get-WplText -Key GuiGithub -Language $code
        $ui.ValidateButton.Content = Get-WplText -Key GuiValidate -Language $code
        $ui.GuideButton.Content = Get-WplText -Key GuiOpenGuide -Language $code
        $ui.ToolGuideButton.Content = Get-WplText -Key GuiOpenToolGuide -Language $code
        $ui.LaunchButton.Content = Get-WplText -Key GuiLaunchSelected -Language $code
        $ui.ReasonHeaderText.Text = Get-WplText -Key GuiSelectedReason -Language $code
        $ui.ProgramGrid.Columns[0].Header = Get-WplText -Key GuiProgramName -Language $code
        $ui.ProgramGrid.Columns[1].Header = Get-WplText -Key RecommendationState -Language $code
        $ui.ProgramGrid.Columns[2].Header = Get-WplText -Key Risk -Language $code
        $ui.SearchBox.ToolTip = Get-WplText -Key GuiSearchHint -Language $code
        $ui.SearchHintText.Text = Get-WplText -Key GuiSearchPlaceholder -Language $code
        $ui.FilterRecommendedButton.Content = Get-WplText -Key GuiFilterRecommended -Language $code
        $ui.FilterAllButton.Content = Get-WplText -Key GuiFilterAll -Language $code
        $ui.FilterReadyButton.Content = Get-WplText -Key GuiFilterReady -Language $code
        $ui.FilterMissingButton.Content = Get-WplText -Key GuiFilterMissing -Language $code
        $ui.FilterRiskButton.Content = Get-WplText -Key GuiFilterRisk -Language $code
        $adminValue = Get-WplText -Key $(if($script:GuiIsAdministrator){'GuiAdminElevated'}else{'GuiAdminStandard'}) -Language $code
        if (-not $script:GuiIsAdministrator) { $adminValue = "$adminValue · $(Get-WplText -Key GuiAdminLimited -Language $code)" }
        $ui.AdminText.Text = "$(Get-WplText -Key GuiAdminStatus -Language $code): $adminValue"
        if ($script:GuiMemoryHardwareText -and $null -ne $script:GuiDiskCount) {
            $ui.MemoryText.Text = "$($script:GuiMemoryHardwareText)`n$(Get-WplText -Key GuiStorageDevices -Language $code -ArgumentList @($script:GuiDiskCount))"
            $ui.MemoryText.ToolTip = $script:GuiMemoryToolTip
        }
        Set-GuiSnapshotText
        Update-GuiFilterButtons
        Update-GuiProgramPresentation
        if (-not $script:GuiJob -and -not $script:GuiPlan) { $ui.StatusText.Text = Get-WplText -Key GuiReady -Language $code }
        Set-GuiSelectionDetails
    }

    $quickDetectionErrors = [Collections.Generic.List[string]]::new()
    function Get-GuiCim([string]$ClassName,[switch]$All) {
        try {
            $items = @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop)
            if($All){return $items}
            return $items | Select-Object -First 1
        }
        catch {
            $quickDetectionErrors.Add("$ClassName`: $($_.Exception.Message)")
            if($All){return @()}
            return $null
        }
    }

    $os = Get-GuiCim 'Win32_OperatingSystem'
    $cpu = Get-GuiCim 'Win32_Processor'
    $gpu = @(Get-GuiCim 'Win32_VideoController' -All)
    $system = Get-GuiCim 'Win32_ComputerSystem'
    $board = Get-GuiCim 'Win32_BaseBoard'
    $bios = Get-GuiCim 'Win32_BIOS'
    $memoryModules = @(Get-GuiCim 'Win32_PhysicalMemory' -All)
    $disks = @(Get-GuiCim 'Win32_DiskDrive' -All)
    $diskCount = $disks.Count

    if($os){$ui.OsText.Text = "$($os.Caption)`n$(Get-WplText -Key DetailBuild -Language $script:GuiLanguage) $($os.BuildNumber)"}else{$ui.OsText.Text = "Windows`n$(Get-WplText -Key GuiDetectionUnavailable -Language $script:GuiLanguage)"}
    if($cpu){
        $platform = @("$($board.Manufacturer) $($board.Product)".Trim(),$(if($bios){"BIOS $($bios.SMBIOSBIOSVersion)"}else{$null})) | Where-Object {$_}
        $compactBoard=if($board){[string]$board.Product}else{''}
        $compactBios=if($bios){"BIOS $($bios.SMBIOSBIOSVersion)"}else{''}
        $ui.CpuText.Text = "$($cpu.Name)`n$((@($compactBoard,$compactBios)|Where-Object{$_}) -join ' · ')"
    }else{$ui.CpuText.Text = Get-WplText -Key GuiDetectionUnavailable -Language $script:GuiLanguage}
    $ui.GpuText.Text = if($gpu.Count){@($gpu | ForEach-Object Name) -join [Environment]::NewLine}else{Get-WplText -Key GuiDetectionUnavailable -Language $script:GuiLanguage}
    $ui.OsText.ToolTip=$ui.OsText.Text
    $ui.CpuText.ToolTip=$ui.CpuText.Text
    $ui.GpuText.ToolTip=$ui.GpuText.Text

    if($system -or $memoryModules.Count){
        $script:GuiMemoryGb = [math]::Round($system.TotalPhysicalMemory / 1GB,0)
        if(-not $script:GuiMemoryGb -and $memoryModules.Count){$script:GuiMemoryGb=[math]::Round((($memoryModules|Measure-Object Capacity -Sum).Sum)/1GB,0)}
        $script:GuiDiskCount = $diskCount
        $memoryTypeCode = $memoryModules | Select-Object -ExpandProperty SMBIOSMemoryType -Unique | Select-Object -First 1
        $memoryType = switch ($(if($null -eq $memoryTypeCode){0}else{[int]$memoryTypeCode})) { 20 {'DDR'} 21 {'DDR2'} 24 {'DDR3'} 26 {'DDR4'} 34 {'DDR5'} 35 {'LPDDR5'} default {'DDR'} }
        $memoryClocks = @($memoryModules.ConfiguredClockSpeed | Where-Object {$_} | Sort-Object -Unique)
        $memoryClockText = if($memoryClocks.Count){$memoryClocks -join '/'}else{'-'}
        $moduleCount = $memoryModules.Count
        $moduleSizes = @($memoryModules | ForEach-Object {"$([math]::Round($_.Capacity / 1GB,0))GB"})
        $script:GuiMemoryHardwareText = "$($script:GuiMemoryGb) GB · $memoryType · $moduleCount DIMM`n$memoryClockText MT/s · $($moduleSizes -join ' + ')"
        $script:GuiMemoryToolTip = @($memoryModules | ForEach-Object {
            "$($_.DeviceLocator) [$($_.BankLabel)]: $([math]::Round($_.Capacity/1GB,0)) GB · $($_.Manufacturer) $(([string]$_.PartNumber).Trim()) · $($_.ConfiguredClockSpeed) MT/s · $($_.ConfiguredVoltage) mV · S/N $($_.SerialNumber)"
        }) -join [Environment]::NewLine
        $ui.MemoryText.Text = "$($script:GuiMemoryHardwareText)`n$(Get-WplText -Key GuiStorageDevices -Language $script:GuiLanguage -ArgumentList @($diskCount))"
        $ui.MemoryText.ToolTip = $script:GuiMemoryToolTip
    }else{$ui.MemoryText.Text = "$(Get-WplText -Key GuiDetectionUnavailable -Language $script:GuiLanguage)`n$(Get-WplText -Key GuiStorageDevices -Language $script:GuiLanguage -ArgumentList @($diskCount))"}

    # Detail payloads for the clickable hardware cards. Collected once with the
    # snapshot so opening a card never re-queries CIM.
    $script:GuiHardwareDetail = @{}
    $script:GuiHardwareAdvice = @{}

    function Add-DetailLine([Collections.Generic.List[string]]$Target,[string]$Label,$Value) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        $Target.Add(('{0}: {1}' -f $Label,$text.Trim()))
    }

    function Get-GuiDetailLabel([string]$Key) {
        return Get-WplText -Key $Key -Language $script:GuiLanguage
    }

    function ConvertTo-LocalDate($Value) {
        if ($null -eq $Value) { return $null }
        if ($Value -is [datetime]) { return $Value }
        try { return [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value) } catch { }
        try { return [datetime]::Parse([string]$Value) } catch { }
        return $null
    }

    # OS
    $osDetail = [Collections.Generic.List[string]]::new()
    if ($os) {
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailEdition') $os.Caption
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailVersion') $os.Version
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailBuild') $os.BuildNumber
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailArchitecture') $os.OSArchitecture
        $installed = ConvertTo-LocalDate $os.InstallDate
        if ($installed) { Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailInstalled') $installed.ToString('yyyy-MM-dd') }
        $booted = ConvertTo-LocalDate $os.LastBootUpTime
        if ($booted) { Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailLastBoot') $booted.ToString('yyyy-MM-dd HH:mm') }
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailSystemDrive') $os.SystemDrive
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailWindowsDirectory') $os.WindowsDirectory
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailLocale') $os.Locale
    }
    if ($system) {
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailComputer') $system.Manufacturer
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailModel') $system.Model
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailSystemType') $system.SystemType
        Add-DetailLine $osDetail (Get-GuiDetailLabel 'DetailHypervisor') $system.HypervisorPresent
    }
    $script:GuiHardwareDetail['os'] = $osDetail

    # CPU and mainboard
    $cpuDetail = [Collections.Generic.List[string]]::new()
    if ($cpu) {
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailProcessor') $cpu.Name
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailVendor') $cpu.Manufacturer
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailCores') $cpu.NumberOfCores
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailLogicalProcessors') $cpu.NumberOfLogicalProcessors
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailBaseClock') $cpu.MaxClockSpeed
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailSocket') $cpu.SocketDesignation
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailVirtualization') $cpu.VirtualizationFirmwareEnabled
    }
    if ($board) {
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailMainboardVendor') $board.Manufacturer
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailMainboardModel') $board.Product
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailMainboardRevision') $board.Version
    }
    if ($bios) {
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailBiosVersion') $bios.SMBIOSBIOSVersion
        Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailBiosVendor') $bios.Manufacturer
        $biosDate = ConvertTo-LocalDate $bios.ReleaseDate
        if ($biosDate) { Add-DetailLine $cpuDetail (Get-GuiDetailLabel 'DetailBiosRelease') $biosDate.ToString('yyyy-MM-dd') }
    }
    $script:GuiHardwareDetail['cpu'] = $cpuDetail

    # GPU
    $gpuDetail = [Collections.Generic.List[string]]::new()
    foreach ($adapter in $gpu) {
        Add-DetailLine $gpuDetail (Get-GuiDetailLabel 'DetailAdapter') $adapter.Name
        Add-DetailLine $gpuDetail ('  ' + (Get-GuiDetailLabel 'DetailVendor')) $adapter.AdapterCompatibility
        Add-DetailLine $gpuDetail ('  ' + (Get-GuiDetailLabel 'DetailDriverVersion')) $adapter.DriverVersion
        $driverDate = ConvertTo-LocalDate $adapter.DriverDate
        if ($driverDate) { Add-DetailLine $gpuDetail ('  ' + (Get-GuiDetailLabel 'DetailDriverDate')) $driverDate.ToString('yyyy-MM-dd') }
        Add-DetailLine $gpuDetail ('  ' + (Get-GuiDetailLabel 'DetailVideoMode')) $adapter.VideoModeDescription
        if ($adapter.AdapterRAM -and [int64]$adapter.AdapterRAM -gt 0) {
            Add-DetailLine $gpuDetail ('  ' + (Get-GuiDetailLabel 'DetailReportedVram')) ("{0} MB" -f [math]::Round([int64]$adapter.AdapterRAM / 1MB,0))
        }
    }
    $script:GuiHardwareDetail['gpu'] = $gpuDetail

    # Memory and storage
    $memoryDetail = [Collections.Generic.List[string]]::new()
    if ($script:GuiMemoryGb) { Add-DetailLine $memoryDetail (Get-GuiDetailLabel 'DetailTotal') ("{0} GB" -f $script:GuiMemoryGb) }
    foreach ($module in $memoryModules) {
        $memoryDetail.Add(('{0} {1} [{2}]' -f (Get-GuiDetailLabel 'DetailSlot'),$module.DeviceLocator,$module.BankLabel))
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailCapacity')) ("{0} GB" -f [math]::Round($module.Capacity / 1GB,0))
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailVendor')) $module.Manufacturer
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailPartNumber')) $module.PartNumber
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailConfigured')) ("{0} MT/s" -f $module.ConfiguredClockSpeed)
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailRated')) ("{0} MT/s" -f $module.Speed)
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailVoltage')) ("{0} mV" -f $module.ConfiguredVoltage)
    }
    foreach ($disk in $disks) {
        $memoryDetail.Add(('{0} {1}' -f (Get-GuiDetailLabel 'DetailDisk'),([string]$disk.Model).Trim()))
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailInterface')) $disk.InterfaceType
        if ($disk.Size) { Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailSize')) ("{0} GB" -f [math]::Round([int64]$disk.Size / 1GB,1)) }
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailFirmware')) $disk.FirmwareRevision
        Add-DetailLine $memoryDetail ('  ' + (Get-GuiDetailLabel 'DetailStatus')) $disk.Status
    }
    $script:GuiHardwareDetail['memory'] = $memoryDetail

    Set-GuiUpdateAdvice -Bios $bios -Board $board -Graphics $gpu

    $quickLogPath = Join-Path $Root 'logs\gui-hardware-latest.log'
    New-Item -ItemType Directory -Path (Split-Path -Parent $quickLogPath) -Force | Out-Null
    if($quickDetectionErrors.Count){$quickDetectionErrors | Set-Content -LiteralPath $quickLogPath -Encoding utf8}
    elseif(Test-Path -LiteralPath $quickLogPath){Remove-Item -LiteralPath $quickLogPath -Force -ErrorAction SilentlyContinue}

    function Set-GuiPlan([string]$Path) {
        $script:GuiPlanPath = $Path
        $script:GuiRecommendationDirectory = Split-Path -Parent $Path
        $script:GuiPlan = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $script:GuiCurrentProfile = [string]$script:GuiPlan.profile
        $settingsPath=Join-Path $script:GuiRecommendationDirectory 'recommended-settings.json'
        if(Test-Path -LiteralPath $settingsPath){
            try{$settings=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json;$script:GuiSnapshotCapturedAt=[datetime]$settings.generatedAt}catch{}
        }
        Set-GuiSnapshotText
        Update-GuiProgramPresentation
        $ui.GuideButton.IsEnabled = $true
        $ui.SafeLaunchButton.IsEnabled = $true
        $ui.LaunchButton.IsEnabled = $false
        Set-GuiSelectionDetails
        Set-GuiStatusTone 'ok'
        $recommendedPrograms = @($script:GuiPlan.programs | Where-Object { $_.state -ne 'catalog-only' })
        $readyCount = @($recommendedPrograms | Where-Object { $_.installed -and $_.launchable }).Count
        $totalCount = $recommendedPrograms.Count
        $statusKey = if ($readyCount -eq $totalCount) { 'GuiCheckComplete' } else { 'GuiCheckPartial' }
        $arguments = if ($statusKey -eq 'GuiCheckComplete') { @($totalCount) } else { @($readyCount,$totalCount) }
        $ui.StatusText.Text = Get-WplText -Key $statusKey -Language $script:GuiLanguage -ArgumentList $arguments
    }

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(750)
    $timer.Add_Tick({
        $installerActive = Update-WplGuiInstallers
        if (-not $script:GuiJob) {
            # Installers share the analysis timer; stop it only when neither is active.
            if (-not $installerActive) { $timer.Stop() }
            return
        }
        if ($script:GuiJob.State -notin @('Completed','Failed','Stopped')) {
            $newReport = Get-ChildItem -LiteralPath (Join-Path $Root 'reports') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $script:GuiJobStarted.AddSeconds(-2) } | Select-Object -First 1
            $newSettings = Get-ChildItem -LiteralPath (Join-Path $Root 'recommendations') -Filter 'recommended-settings.json' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $script:GuiJobStarted.AddSeconds(-2) } | Select-Object -First 1
            $progressKey = if ($newSettings) { 'GuiProgressConnection' } elseif ($newReport) { 'GuiProgressRecommendation' } else { 'GuiProgressInventory' }
            $ui.StatusText.Text = Get-WplText -Key $progressKey -Language $script:GuiLanguage
            return
        }
        $timer.Stop()
        Set-GuiAnalysisControls $true
        $state = $script:GuiJob.State
        $reason = if ($script:GuiJob.ChildJobs.Count -and $script:GuiJob.ChildJobs[0].JobStateInfo.Reason) {
            [string]$script:GuiJob.ChildJobs[0].JobStateInfo.Reason.Message
        }
        else { '' }
        $jobErrors = @()
        Receive-Job -Job $script:GuiJob -ErrorAction SilentlyContinue -ErrorVariable +jobErrors | Out-Null
        if (-not $reason -and $jobErrors.Count) { $reason = [string]$jobErrors[-1].Exception.Message }
        Remove-Job -Job $script:GuiJob -ErrorAction SilentlyContinue
        $script:GuiJob = $null
        if ($state -eq 'Completed') {
            $latest = Get-ChildItem -LiteralPath (Join-Path $Root 'recommendations') -Filter 'recommended-programs.json' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $script:GuiJobStarted.AddSeconds(-2) } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($latest) { Set-GuiPlan $latest.FullName; return }
            $reason = 'No recommendation output was created.'
        }
        if(-not $reason){
            $analysisLog=Join-Path $Root 'logs\gui-analysis-latest.log'
            if(Test-Path -LiteralPath $analysisLog){
                # The last log line is often blank or a bare exit code, which produced
                # useless messages like "exit code .". Prefer the last line with content.
                $logLines=@(Get-Content -LiteralPath $analysisLog -Tail 40 -ErrorAction SilentlyContinue |
                    ForEach-Object {[string]$_} |
                    Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
                if($logLines.Count){$reason=$logLines[-1].Trim()}
            }
        }
        if([string]::IsNullOrWhiteSpace([string]$reason)){
            $reason=Get-WplText -Key GuiCheckFailedNoDetail -Language $script:GuiLanguage -ArgumentList @((Join-Path $Root 'logs\gui-analysis-latest.log'))
        }
        Set-GuiStatusTone 'fail'
        $ui.StatusText.Text = Get-WplText -Key GuiCheckFailed -Language $script:GuiLanguage -ArgumentList @($reason)
    })

    function Start-GuiAnalysis([string]$SelectedProfile) {
        if ($script:GuiJob -and $script:GuiJob.State -in @('NotStarted','Running')) {
            $ui.StatusText.Text = Get-WplText -Key GuiJobBusy -Language $script:GuiLanguage
            return
        }
        $script:GuiJobStarted = Get-Date
        Set-GuiStatusTone 'busy'
        $ui.StatusText.Text = Get-WplText -Key GuiProgressInventory -Language $script:GuiLanguage
        Reset-WplToolIndex
        Set-GuiAnalysisControls $false
        $ui.GuideButton.IsEnabled = $false
        $ui.SafeLaunchButton.IsEnabled = $false
        $ui.LaunchButton.IsEnabled = $false
        $modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules;$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
        $analysisLog = Join-Path $Root 'logs\gui-analysis-latest.log'
        New-Item -ItemType Directory -Path (Split-Path -Parent $analysisLog) -Force | Out-Null
        $script:GuiJob = Start-Job -ScriptBlock {
            param($ProjectRoot,$SelectedProfile,$SelectedLanguage,$WindowsModulePath,$AnalysisLog)
            $env:PSModulePath = $WindowsModulePath
            try {
                $output = @(& (Join-Path $ProjectRoot 'WinPortableLab.ps1') -Action check -Profile $SelectedProfile -Language $SelectedLanguage -NoElevation -FastRecommendation 2>&1)
                $checkSucceeded = $?
                $output | Out-String | Set-Content -LiteralPath $AnalysisLog -Encoding utf8
                if (-not $checkSucceeded) {
                    $detail = @($output | ForEach-Object {[string]$_} | Where-Object {$_}) -join [Environment]::NewLine
                    throw $(if($detail){$detail}else{'Integrated check returned an unsuccessful status.'})
                }
            }
            catch {
                $detail = $_ | Out-String
                $detail | Add-Content -LiteralPath $AnalysisLog -Encoding utf8
                throw $_.Exception.Message
            }
        } -ArgumentList $Root,$SelectedProfile,$script:GuiLanguage,$modulePath,$analysisLog
        $timer.Start()
    }

    function Set-GuiProfileFromSnapshot([string]$SelectedProfile) {
        if ($script:GuiJob -and $script:GuiJob.State -in @('NotStarted','Running')) {
            $ui.StatusText.Text = Get-WplText -Key GuiJobBusy -Language $script:GuiLanguage
            return
        }
        $settingsPath = if($script:GuiRecommendationDirectory){Join-Path $script:GuiRecommendationDirectory 'recommended-settings.json'}else{$null}
        if (-not $settingsPath -or -not (Test-Path -LiteralPath $settingsPath)) {
            Start-GuiAnalysis $SelectedProfile
            return
        }
        try {
            Set-GuiStatusTone 'busy'
            $ui.StatusText.Text = Get-WplText -Key GuiReusingSnapshot -Language $script:GuiLanguage
            $connection = New-ProgramConnectionPlan -RecommendationDirectory $script:GuiRecommendationDirectory -SelectedProfile $SelectedProfile
            Set-GuiPlan $connection.JsonPath
        }
        catch {
            Set-GuiStatusTone 'fail'
            $ui.StatusText.Text = Get-WplText -Key GuiCheckFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
        }
    }

    $ui.ProgramGrid.Add_SelectionChanged({
        Set-GuiSelectionDetails
    })
    $ui.SidebarScroll.Add_PreviewMouseWheel({param($sender,$eventArgs);Move-GuiScroll $sender $eventArgs.Delta;$eventArgs.Handled=$true})
    $ui.DetailScroll.Add_PreviewMouseWheel({param($sender,$eventArgs);Move-GuiScroll $sender $eventArgs.Delta;$eventArgs.Handled=$true})
    $ui.SearchBox.Add_TextChanged({$ui.SearchHintText.Visibility=if([string]::IsNullOrEmpty($ui.SearchBox.Text)){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed};Update-GuiProgramPresentation})
    foreach($filterButton in @($ui.FilterRecommendedButton,$ui.FilterAllButton,$ui.FilterReadyButton,$ui.FilterMissingButton,$ui.FilterRiskButton)){
        $filterButton.Add_Click({param($sender,$eventArgs);$script:GuiCurrentFilter=[string]$sender.Tag;Update-GuiFilterButtons;Update-GuiProgramPresentation})
    }
    $ui.QuickButton.Add_Click({ Set-GuiProfileFromSnapshot 'quick' })
    $ui.StandardButton.Add_Click({ Set-GuiProfileFromSnapshot 'standard' })
    $ui.DeepButton.Add_Click({ Set-GuiProfileFromSnapshot 'deep' })
    $ui.AllButton.Add_Click({ Set-GuiProfileFromSnapshot 'all' })
    $ui.StorageButton.Add_Click({ Set-GuiProfileFromSnapshot 'storage' })
    $ui.MemoryButton.Add_Click({ Set-GuiProfileFromSnapshot 'memory' })
    $ui.GpuButton.Add_Click({ Set-GuiProfileFromSnapshot 'gpu' })
    $ui.RefreshButton.Add_Click({ Start-GuiAnalysis $script:GuiCurrentProfile })
    $ui.BatchDownloadButton.Add_Click({
        if ($script:GuiInstallers -and $script:GuiInstallers.Count) {
            $ui.StatusText.Text = Get-WplText -Key GuiBatchInProgress -Language $script:GuiLanguage
            return
        }
        if (-not $script:GuiPlan) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoPlan -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        $packageCatalogIds = @(Get-WplPackageDefinitions -Root $Root | ForEach-Object { [string]$_.catalogId })
        $missing = @($script:GuiPlan.programs |
            Where-Object { -not $_.installed -and $_.catalogId -and $packageCatalogIds -contains [string]$_.catalogId } |
            Select-Object -ExpandProperty catalogId -Unique)
        if (-not $missing.Count) {
            Set-GuiStatusTone 'ok'
            $ui.StatusText.Text = Get-WplText -Key GuiBatchDownloadNothing -Language $script:GuiLanguage
            return
        }
        Start-WplGuiInstaller (Get-WplText -Key GuiBatchDownloadName -Language $script:GuiLanguage) ([string[]]@('-Id',($missing -join ','),'-IncludeHighLoad'))
    })
    $ui.OsCardButton.Add_Click({ Show-GuiHardwareDetail 'os' (Get-WplText -Key GuiDetailTitleOs -Language $script:GuiLanguage) })
    $ui.CpuCardButton.Add_Click({ Show-GuiHardwareDetail 'cpu' (Get-WplText -Key GuiDetailTitleCpu -Language $script:GuiLanguage) })
    $ui.GpuCardButton.Add_Click({ Show-GuiHardwareDetail 'gpu' (Get-WplText -Key GuiDetailTitleGpu -Language $script:GuiLanguage) })
    $ui.MemoryCardButton.Add_Click({ Show-GuiHardwareDetail 'memory' (Get-WplText -Key GuiDetailTitleMemory -Language $script:GuiLanguage) })
    $ui.LanguageButton.Add_Click({ $script:GuiLanguage = if ($script:GuiLanguage -eq 'ko') { 'en' } else { 'ko' }; Set-GuiText })
    $ui.LaunchButton.Add_Click({
        $selected = $ui.ProgramGrid.SelectedItem
        if (-not $selected) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiSelectTool -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        if ([string]$selected.primaryAction -eq 'prepare') {
            try { Prepare-GuiSelectedTool $selected }
            catch { [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null }
            return
        }
        if ([string]$selected.primaryAction -eq 'guide' -or -not $selected.launchable) {
            try { Open-GuiToolGuide $selected }
            catch { [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null }
            return
        }
        # An overridden launcher runs a binary the bundled tree does not own, so
        # it is confirmed even when the catalog risk tier is read-only.
        $selectedTrust = Get-WplToolOverrideTrust -Root $Root -LauncherId ([string]$selected.id)
        if ($selectedTrust -and -not $selectedTrust.IsTrusted) {
            $overrideMessage = Get-WplText -Key GuiOverrideConfirm -Language $script:GuiLanguage -ArgumentList @([string]$selected.id,$selectedTrust.Path,$selectedTrust.InsideToolsRoot,$selectedTrust.SignatureStatus)
            $overrideAnswer = [System.Windows.MessageBox]::Show($overrideMessage,$window.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
            if ($overrideAnswer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }
        $riskAccepted = $false
        $manualTemperatureAccepted = $false
        if ([string]$selected.risk -notmatch '^read-only') {
            $highLoad = [string]$selected.risk -match '^(?:high-load|very-high-load)$'
            $messageKey = if($highLoad){'GuiHighLoadConfirm'}else{'GuiRiskConfirm'}
            $message = Get-WplText -Key $messageKey -Language $script:GuiLanguage -ArgumentList @($selected.riskText)
            $answer = [System.Windows.MessageBox]::Show($message,$window.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
            $riskAccepted = $true
            $manualTemperatureAccepted = $highLoad
        }
        $preview = @(
            (Get-WplText -Key GuiLaunchPreview -Language $script:GuiLanguage),
            '',
            "$(Get-WplText -Key GuiDetailName -Language $script:GuiLanguage): $($selected.displayName)",
            "$(Get-WplText -Key GuiDetailRisk -Language $script:GuiLanguage): $($selected.riskText)",
            "$(Get-WplText -Key GuiDetailMode -Language $script:GuiLanguage): $($selected.modeText)",
            "$(Get-WplText -Key GuiDetailPath -Language $script:GuiLanguage): $($selected.executable)",
            '',
            (Get-WplText -Key GuiLaunchSessionPolicy -Language $script:GuiLanguage)
        ) -join [Environment]::NewLine
        $previewAnswer = [System.Windows.MessageBox]::Show($preview,$window.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Information)
        if ($previewAnswer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        try {
            Set-GuiStatusTone 'busy'
            $ui.StatusText.Text = Get-WplText -Key GuiLaunching -Language $script:GuiLanguage -ArgumentList @([string]$selected.id)
            $sessionScript = Join-Path $Root 'scripts\Start-WplToolSession.ps1'
            $sessionWindowStyle = if([string]$selected.launchMode -in @('cli','cli-help')){'Normal'}else{'Hidden'}
            # Every value is encoded with the shared CommandLineToArgvW encoder.
            # Interpolating the launcher id unquoted let a hand-edited id smuggle
            # extra parameters into an elevated powershell.exe invocation.
            $sessionTokens = [Collections.Generic.List[string]]::new()
            $sessionTokens.AddRange([string[]]@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$sessionScript,'-Root',$Root,'-LauncherId',[string]$selected.id,'-Start','-AcceptRisk'))
            if($manualTemperatureAccepted){$sessionTokens.Add('-AcknowledgeManualTemperatureMonitoring')}
            if($sessionWindowStyle -eq 'Normal'){$sessionTokens.Add('-PauseOnExit')}
            $launchSignal=$null
            if($sessionWindowStyle -eq 'Hidden'){
                $launchSignal=Join-Path $Root ('logs\launch-signal-{0}.json' -f [guid]::NewGuid().ToString('N'))
                $sessionTokens.AddRange([string[]]@('-LaunchSignalPath',$launchSignal))
            }
            $sessionArguments = ConvertTo-WplWindowsCommandLine -ArgumentList $sessionTokens.ToArray()
            $sessionStart=@{FilePath='powershell.exe';ArgumentList=$sessionArguments;WindowStyle=$sessionWindowStyle;PassThru=$true}
            if(-not $script:GuiIsAdministrator){$sessionStart.Verb='RunAs'}
            $sessionHost=Start-Process @sessionStart
            if($launchSignal){
                $deadline=(Get-Date).AddSeconds(8)
                while(-not (Test-Path -LiteralPath $launchSignal) -and -not $sessionHost.HasExited -and (Get-Date)-lt $deadline){Start-Sleep -Milliseconds 100;$sessionHost.Refresh()}
                if(Test-Path -LiteralPath $launchSignal){
                    $signal=Get-Content -LiteralPath $launchSignal -Raw|ConvertFrom-Json
                    Remove-Item -LiteralPath $launchSignal -Force -ErrorAction SilentlyContinue
                    if(-not $signal.success){throw [string]$signal.message}
                }
                elseif($sessionHost.HasExited){throw "Launcher session exited with code $($sessionHost.ExitCode)."}
                else{throw 'The launcher did not confirm process startup within 8 seconds.'}
            }
            Set-GuiStatusTone 'ok'
            $ui.StatusText.Text = Get-WplText -Key GuiLaunchStarted -Language $script:GuiLanguage -ArgumentList @([string]$selected.id)
        }
        catch {
            Set-GuiStatusTone 'fail'
            $ui.StatusText.Text = Get-WplText -Key GuiLaunchFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
            [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })
    $ui.SafeLaunchButton.Add_Click({
        if (-not $script:GuiPlan) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoPlan -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        $safe = @(Get-WplSafeLaunchIds $script:GuiPlan)
        if (-not $safe.Count) { [System.Windows.MessageBox]::Show((Get-WplText -Key NoSafeLaunch -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        # Guided selection replaces the old batch launcher. One click now chooses
        # one next step and never opens a wall of diagnostic windows.
        $nextId = if($ui.ProgramGrid.SelectedItem -and [string]$ui.ProgramGrid.SelectedItem.id -in $safe){
            $currentIndex=[array]::IndexOf([object[]]$safe,[string]$ui.ProgramGrid.SelectedItem.id)
            $safe[($currentIndex + 1) % $safe.Count]
        }else{$safe[0]}
        $script:GuiCurrentFilter='recommended'
        Update-GuiFilterButtons
        Update-GuiProgramPresentation
        $next = @($ui.ProgramGrid.ItemsSource | Where-Object { [string]$_.id -eq [string]$nextId }) | Select-Object -First 1
        if($next){$ui.ProgramGrid.SelectedItem=$next;$ui.ProgramGrid.ScrollIntoView($next);Set-GuiSelectionDetails}
        Set-GuiStatusTone 'ok'
        $ui.StatusText.Text = Get-WplText -Key GuiNextRecommendationSelected -Language $script:GuiLanguage -ArgumentList @([string]$next.displayName)
    })
    $ui.GuideButton.Add_Click({
        if (-not $script:GuiRecommendationDirectory) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoPlan -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        Open-WplTextDocument (Join-Path $script:GuiRecommendationDirectory "recommended-programs.$($script:GuiLanguage).md")
    })
    $ui.ReportsButton.Add_Click({ Start-Process explorer.exe -ArgumentList @((Join-Path $Root 'reports')) })
    $ui.ToolGuideButton.Add_Click({
        $selected = $ui.ProgramGrid.SelectedItem
        if (-not $selected) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiSelectTool -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        try {
            Open-GuiToolGuide $selected
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })
    $ui.LatestResultButton.Add_Click({
        $latest = @(
            Get-ChildItem -LiteralPath (Join-Path $Root 'reports') -File -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath (Join-Path $Root 'recommendations') -File -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath (Join-Path $Root 'sessions') -Filter 'session.json' -File -Recurse -ErrorAction SilentlyContinue
        ) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { Start-Process explorer.exe -ArgumentList @('/select,',$latest.FullName) }
        else { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoResults -Language $script:GuiLanguage),$window.Title) | Out-Null }
    })
    $ui.GithubButton.Add_Click({
        $remote = (& git -C $Root remote get-url origin 2>$null | Select-Object -First 1)
        if ($remote -and $remote -match 'github\.com') {
            if ($remote -match '^git@github\.com:(.+)$') { $remote = "https://github.com/$($Matches[1])" }
            Start-Process ([string]$remote -replace '\.git$','')
        }
        else {
            [System.Windows.MessageBox]::Show((Get-WplText -Key GuiGithubMissing -Language $script:GuiLanguage),$window.Title) | Out-Null
            Open-WplTextDocument (Join-Path $Root 'README.md')
        }
    })
    $ui.ValidateButton.Add_Click({
        $arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'WinPortableLab.ps1'),'-Action','validate','-Language',$script:GuiLanguage)
        Start-Process powershell.exe -ArgumentList $arguments
        $ui.StatusText.Text = Get-WplText -Key GuiValidationStarted -Language $script:GuiLanguage
    })
    $ui.NetworkDriverButton.Add_Click({
        try { Show-GuiNetworkDriver }
        catch {
            Set-GuiStatusTone 'fail'
            $ui.StatusText.Text = Get-WplText -Key GuiNetDriverActionFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
        }
    })
    $window.Add_Loaded({
        if ($script:GuiInitialAnalysisStarted) { return }
        $script:GuiInitialAnalysisStarted = $true
        Start-GuiAnalysis $Profile
    })
    $window.Add_Closed({
        $timer.Stop()
        if ($script:GuiJob -and $script:GuiJob.State -in @('NotStarted','Running')) { Stop-Job -Job $script:GuiJob -ErrorAction SilentlyContinue }
        if ($script:GuiJob) { Remove-Job -Job $script:GuiJob -Force -ErrorAction SilentlyContinue }
        if ($script:GuiInstallers) {
            foreach ($installer in $script:GuiInstallers) {
                $installer.Process.Refresh()
                if (-not $installer.Process.HasExited) { Stop-Process -Id $installer.Process.Id -Force -ErrorAction SilentlyContinue }
            }
        }
    })

    $ui.GuideButton.IsEnabled = $false
    $ui.SafeLaunchButton.IsEnabled = $false
    $ui.LaunchButton.IsEnabled = $false
    Set-GuiText
    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    $dispatcherHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
        param($sender,$eventArgs)
        try {
            $message = [string]$eventArgs.Exception.Message
            [ordered]@{
                createdAt=(Get-Date).ToString('o')
                type=$eventArgs.Exception.GetType().FullName
                message=$message
                stackTrace=[string]$eventArgs.Exception.StackTrace
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Root 'logs\gui-unhandled-latest.json') -Encoding utf8
            Set-GuiStatusTone 'fail'
            $ui.StatusText.Text = Get-WplText -Key GuiUnexpectedError -Language $script:GuiLanguage -ArgumentList @($message)
            [System.Windows.MessageBox]::Show($ui.StatusText.Text,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
            $eventArgs.Handled = $true
        }
        catch {
            $eventArgs.Handled = $false
        }
    }
    $dispatcher.add_UnhandledException($dispatcherHandler)
    try { [void]$window.ShowDialog() }
    finally { $dispatcher.remove_UnhandledException($dispatcherHandler) }
}

if ($Action -eq 'gui') {
    Show-WplGui
    return
}

if ($Action -eq 'validate') {
    & (Join-Path $Root 'scripts\Test-Repository.ps1') -Root $Root -Language $Language
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & (Join-Path $Root 'scripts\Test-InstalledTools.ps1') -Root $Root -Language $Language
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $latestConnection = Get-ChildItem -LiteralPath (Join-Path $Root 'recommendations') -Filter 'recommended-programs.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestConnection) { & (Join-Path $Root 'scripts\Test-ProgramConnections.ps1') -Root $Root -Path $latestConnection.FullName -Language $Language }
    exit $LASTEXITCODE
}

if ($Action -eq 'launch') {
    if (-not $ToolId) { throw 'ToolId is required for Action=launch.' }
    Open-ToolIds -Ids $ToolId -RiskAccepted:$AcknowledgeRisk -ManualTemperatureMonitoringAccepted:$AcknowledgeManualTemperatureMonitoring
    return
}

$result = Invoke-IntegratedCheck -SelectedProfile $Profile -FastRecommendation:$FastRecommendation
if ($Action -in @('check','list')) {
    Show-ProgramPlan $result.Connection
    return $result
}

if ($Action -eq 'launch-recommended') {
    $safe = @(Get-WplSafeLaunchIds $result.Connection.Plan)
    if (-not $safe.Count) { Write-Host (Get-WplText -Key NoSafeLaunch -Language $Language) -ForegroundColor Yellow; return }
    Write-Host (Get-WplText -Key BulkLaunchDisabled -Language $Language -ArgumentList @($safe -join ', ')) -ForegroundColor Yellow
    return
}

Show-ProgramPlan $result.Connection
while ($true) {
    Write-Host ''
    $choice = Read-Host (Get-WplText -Key MenuPrompt -Language $Language)
    switch ($choice) {
        '1' { Show-ProgramPlan $result.Connection }
        '2' {
            $safe = @(Get-WplSafeLaunchIds $result.Connection.Plan)
            if ($safe.Count) { Write-Host (Get-WplText -Key BulkLaunchDisabled -Language $Language -ArgumentList @($safe -join ', ')) -ForegroundColor Yellow } else { Write-Host (Get-WplText -Key NoSafeLaunch -Language $Language) -ForegroundColor Yellow }
        }
        '3' { $selectedId = Read-Host (Get-WplText -Key EnterToolId -Language $Language); if ($selectedId) { Open-ToolIds -Ids @($selectedId) -RiskAccepted:$AcknowledgeRisk -ManualTemperatureMonitoringAccepted:$AcknowledgeManualTemperatureMonitoring } }
        '4' { Start-Process explorer.exe -ArgumentList @($result.ReportDirectory) }
        '5' { Open-WplTextDocument (Join-Path $result.RecommendationDirectory "recommended-programs.$Language.md") }
        '0' { break }
        default { continue }
    }
    if ($choice -eq '0') { break }
}
