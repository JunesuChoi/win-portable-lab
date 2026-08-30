[CmdletBinding()]
param(
    [ValidateSet('gui','check','list','launch','launch-recommended','menu','validate')]
    [string]$Action = 'gui',
    [ValidateSet('quick','standard','deep','storage','gpu','memory','all')]
    [string]$Profile = 'quick',
    [string[]]$ToolId,
    [switch]$AcknowledgeRisk,
    [switch]$InstallMissing,
    [ValidateSet('ko','en','auto')]
    [string]$Language = 'auto',
    [switch]$NoElevation,
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
        $InstallMissing = [bool]$payload.InstallMissing
        $Language = [string]$payload.Language
    }
    catch { throw "Invalid elevation payload: $($_.Exception.Message)" }
}

function Test-WplCurrentAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$Language = Resolve-WplLanguage -Root $Root -Requested $Language
if (-not $NoElevation -and -not (Test-WplCurrentAdministrator)) {
    $payload = [ordered]@{
        Action=$Action;Profile=$Profile;ToolId=@($ToolId);AcknowledgeRisk=[bool]$AcknowledgeRisk
        InstallMissing=[bool]$InstallMissing;Language=$Language
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

function Get-WplUserToolPathMap {
    # Cached for one analysis pass; Reset-WplToolIndex clears it so an edited
    # override file is picked up by the explicit refresh.
    if ($null -eq $script:WplUserToolPaths) {
        $map = @{}
        $path = Join-Path $Root 'config\user-tool-paths.json'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                foreach ($entry in @(Read-JsonArray $path)) {
                    $id = [string]$entry.id
                    $declared = [string]$entry.path
                    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($declared)) { continue }
                    if ($entry.PSObject.Properties.Name -contains 'enabled' -and $entry.enabled -eq $false) { continue }
                    $map[$id] = $declared
                }
            }
            catch { }
        }
        $script:WplUserToolPaths = $map
    }
    return $script:WplUserToolPaths
}

function Get-WplUserToolPath([string]$LauncherId) {
    if ([string]::IsNullOrWhiteSpace($LauncherId)) { return $null }
    $map = Get-WplUserToolPathMap
    if (-not $map.ContainsKey($LauncherId)) { return $null }
    $declared = [Environment]::ExpandEnvironmentVariables($map[$LauncherId])
    if (-not [IO.Path]::IsPathRooted($declared)) { $declared = Join-Path $Root $declared }
    if (-not (Test-Path -LiteralPath $declared -PathType Leaf)) { return $null }
    if ([IO.Path]::GetExtension($declared) -ine '.exe') { return $null }
    return Get-Item -LiteralPath $declared
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
    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $items = @()
    for ($index = 0; $index -lt $document.Count; $index++) { $items += $document[$index] }
    return $items
}

function Find-LauncherExecutable([object]$Launcher) {
    # User-declared paths take precedence, matching Resolve-WplExecutable.
    $override = Get-WplUserToolPath ([string]$Launcher.id)
    if ($override) { return $override }
    if (-not $Launcher.pattern) { return $null }
    $toolsRoot = Join-Path $Root 'tools'
    return Get-WplToolFileIndex |
        Where-Object {
            $relative = $_.FullName.Substring($toolsRoot.Length).TrimStart('\')
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
        $launchableState = [bool]$exe -and -not $discoveryOnly
        $programs += [ordered]@{
            id = $launcher.id
            catalogId = $launcher.catalogId
            state = $candidates[$candidateId].state
            reason = [ordered]@{ko=(Get-WplText -Key $candidates[$candidateId].reasonKey -Language 'ko');en=(Get-WplText -Key $candidates[$candidateId].reasonKey -Language 'en')}
            risk = $launcher.risk
            launchMode = $launcher.launchMode
            installed = $installed
            launchable = $launchableState
            executable = if ($exe) { $exe.FullName } else { $null }
            arguments = @($launcher.arguments)
            command = if ($launchableState) { ".\WinPortableLab.ps1 -Action launch -ToolId $($launcher.id)$(if($requiresRisk){' -AcknowledgeRisk'}) -Language auto" } else { $null }
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

function Invoke-IntegratedCheck([string]$SelectedProfile) {
    Write-Host (Get-WplText -Key IntegratedCheckStart -Language $Language) -ForegroundColor Cyan
    $reportDirectory = & (Join-Path $Root 'scripts\Invoke-Inventory.ps1') -OutputRoot (Join-Path $Root 'reports') -Language $Language
    $recommendationDirectory = & (Join-Path $Root 'scripts\New-SystemRecommendation.ps1') -Root $Root -Language $Language
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

function Open-ToolIds([string[]]$Ids,[switch]$RiskAccepted,[string]$UseLanguage = $Language,[switch]$ContinueOnError) {
    $results = [Collections.Generic.List[object]]::new()
    foreach ($id in @($Ids | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        try {
            & (Join-Path $Root 'scripts\Open-PortableTool.ps1') -Root $Root -Id $id -AcknowledgeRisk:$RiskAccepted -Language $UseLanguage
            $results.Add([pscustomobject]@{id=$id;success=$true;error=$null})
        }
        catch {
            $results.Add([pscustomobject]@{id=$id;success=$false;error=$_.Exception.Message})
            if (-not $ContinueOnError) { throw }
        }
    }
    return @($results)
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
          <Expander x:Name="MoreExpander" Foreground="{DynamicResource InkSubtle}" Background="Transparent" BorderBrush="Transparent" BorderThickness="0" Padding="2,4" Margin="0,4,0,0" FontSize="12">
            <StackPanel Margin="0,7,0,0"><Button x:Name="GithubButton" Style="{StaticResource NavButton}"/><Button x:Name="ValidateButton" Style="{StaticResource NavButton}"/></StackPanel>
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
    $names = @('BadgeText','BrandText','DescriptionText','LanguageButton','SnapshotText','SystemSectionText','AdminText','QuickButton','AllButton','StorageButton','MemoryButton','GpuButton','RecordsSectionText','ManageSectionText','RefreshButton','SafeLaunchButton','ReportsButton','LatestResultButton','MoreExpander','GithubButton','ValidateButton','SidebarScroll','RecommendationSectionText','SearchBox','SearchHintText','FilterAllButton','FilterReadyButton','FilterMissingButton','FilterRiskButton','ProgramGrid','ReasonHeaderText','SelectedToolText','ReasonText','DetailScroll','StatusDot','AnalysisProgressBar','StatusText','GuideButton','ToolGuideButton','LaunchButton','OsText','CpuText','GpuText','MemoryText','OsCardButton','CpuCardButton','GpuCardButton','MemoryCardButton')
    $ui = @{}
    foreach ($name in $names) { $ui[$name] = $window.FindName($name) }

    $script:GuiLanguage = $Language
    $script:GuiPlan = $null
    $script:GuiPlanPath = $null
    $script:GuiRecommendationDirectory = $null
    $script:GuiJob = $null
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
    $script:GuiCurrentFilter = 'all'
    $script:GuiSnapshotCapturedAt = $null
    $script:GuiIsAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
        $visible = @($script:GuiPlan.programs | Where-Object {
            $matchesQuery = -not $query -or $_.displayName -like "*$query*" -or $_.id -like "*$query*"
            $matchesState = switch ($filter) {
                'ready' { [bool]$_.launchable }
                'missing' { -not [bool]$_.installed }
                'risky' { [string]$_.risk -notmatch '^read-only' }
                default { $true }
            }
            $matchesQuery -and $matchesState
        })
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
        $ui.LaunchButton.IsEnabled = -not ($script:GuiJob -and $script:GuiJob.State -in @('NotStarted','Running'))
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
        $ui.DetailScroll.ScrollToTop()
        $ui.ProgramGrid.ScrollIntoView($selected)
    }

    function Set-GuiSnapshotText {
        if($script:GuiSnapshotCapturedAt){
            $stamp=$script:GuiSnapshotCapturedAt.ToString('yyyy-MM-dd HH:mm')
            $profileKey=switch($script:GuiCurrentProfile){'quick'{'GuiProfileQuick'}'storage'{'GuiProfileStorage'}'memory'{'GuiProfileMemory'}'gpu'{'GuiProfileGpu'}'all'{'GuiProfileAll'}default{'GuiProfileStandard'}}
            $profileName=Get-WplText -Key $profileKey -Language $script:GuiLanguage
            $ui.SnapshotText.Text=Get-WplText -Key GuiSnapshotAt -Language $script:GuiLanguage -ArgumentList @($stamp,$profileName)
        }else{
            $ui.SnapshotText.Text=Get-WplText -Key GuiSnapshotPending -Language $script:GuiLanguage
        }
    }

    function Update-GuiFilterButtons {
        foreach($button in @($ui.FilterAllButton,$ui.FilterReadyButton,$ui.FilterMissingButton,$ui.FilterRiskButton)){
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
            $card.Child = $stack
            $advicePanel.Children.Add($card) | Out-Null
        }

        [void]$detailWindow.ShowDialog()
    }

    function Set-GuiAnalysisControls([bool]$Enabled) {
        foreach ($button in @($ui.QuickButton,$ui.AllButton,$ui.StorageButton,$ui.MemoryButton,$ui.GpuButton,$ui.RefreshButton)) { $button.IsEnabled = $Enabled }
        $ui.AnalysisProgressBar.Visibility = if ($Enabled) { [Windows.Visibility]::Collapsed } else { [Windows.Visibility]::Visible }
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
        $ui.AllButton.Content = Get-WplText -Key GuiAll -Language $code
        $ui.StorageButton.Content = Get-WplText -Key GuiStorage -Language $code
        $ui.MemoryButton.Content = Get-WplText -Key GuiMemory -Language $code
        $ui.GpuButton.Content = Get-WplText -Key GuiGpu -Language $code
        $ui.RefreshButton.Content = Get-WplText -Key GuiRefreshSystem -Language $code
        $ui.SafeLaunchButton.Content = Get-WplText -Key GuiSafeLaunch -Language $code
        $ui.ReportsButton.Content = Get-WplText -Key GuiReports -Language $code
        $ui.LatestResultButton.Content = Get-WplText -Key GuiLatestResult -Language $code
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

    if($os){$ui.OsText.Text = "$($os.Caption)`nBuild $($os.BuildNumber)"}else{$ui.OsText.Text = "Windows`nDetection unavailable"}
    if($cpu){
        $platform = @("$($board.Manufacturer) $($board.Product)".Trim(),$(if($bios){"BIOS $($bios.SMBIOSBIOSVersion)"}else{$null})) | Where-Object {$_}
        $compactBoard=if($board){[string]$board.Product}else{''}
        $compactBios=if($bios){"BIOS $($bios.SMBIOSBIOSVersion)"}else{''}
        $ui.CpuText.Text = "$($cpu.Name)`n$((@($compactBoard,$compactBios)|Where-Object{$_}) -join ' · ')"
    }else{$ui.CpuText.Text = 'Detection unavailable'}
    $ui.GpuText.Text = if($gpu.Count){@($gpu | ForEach-Object Name) -join [Environment]::NewLine}else{'Detection unavailable'}
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
    }else{$ui.MemoryText.Text = "Detection unavailable`n$(Get-WplText -Key GuiStorageDevices -Language $script:GuiLanguage -ArgumentList @($diskCount))"}

    # Detail payloads for the clickable hardware cards. Collected once with the
    # snapshot so opening a card never re-queries CIM.
    $script:GuiHardwareDetail = @{}
    $script:GuiHardwareAdvice = @{}

    function Add-DetailLine([Collections.Generic.List[string]]$Target,[string]$Label,$Value) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        $Target.Add(('{0}: {1}' -f $Label,$text.Trim()))
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
        Add-DetailLine $osDetail 'Edition' $os.Caption
        Add-DetailLine $osDetail 'Version' $os.Version
        Add-DetailLine $osDetail 'Build' $os.BuildNumber
        Add-DetailLine $osDetail 'Architecture' $os.OSArchitecture
        $installed = ConvertTo-LocalDate $os.InstallDate
        if ($installed) { Add-DetailLine $osDetail 'Installed' $installed.ToString('yyyy-MM-dd') }
        $booted = ConvertTo-LocalDate $os.LastBootUpTime
        if ($booted) { Add-DetailLine $osDetail 'Last boot' $booted.ToString('yyyy-MM-dd HH:mm') }
        Add-DetailLine $osDetail 'System drive' $os.SystemDrive
        Add-DetailLine $osDetail 'Windows directory' $os.WindowsDirectory
        Add-DetailLine $osDetail 'Locale' $os.Locale
    }
    if ($system) {
        Add-DetailLine $osDetail 'Computer' $system.Manufacturer
        Add-DetailLine $osDetail 'Model' $system.Model
        Add-DetailLine $osDetail 'System type' $system.SystemType
        Add-DetailLine $osDetail 'Hypervisor present' $system.HypervisorPresent
    }
    $script:GuiHardwareDetail['os'] = $osDetail

    # CPU and mainboard
    $cpuDetail = [Collections.Generic.List[string]]::new()
    if ($cpu) {
        Add-DetailLine $cpuDetail 'Processor' $cpu.Name
        Add-DetailLine $cpuDetail 'Vendor' $cpu.Manufacturer
        Add-DetailLine $cpuDetail 'Cores' $cpu.NumberOfCores
        Add-DetailLine $cpuDetail 'Logical processors' $cpu.NumberOfLogicalProcessors
        Add-DetailLine $cpuDetail 'Base clock (MHz)' $cpu.MaxClockSpeed
        Add-DetailLine $cpuDetail 'Socket' $cpu.SocketDesignation
        Add-DetailLine $cpuDetail 'Virtualization firmware' $cpu.VirtualizationFirmwareEnabled
    }
    if ($board) {
        Add-DetailLine $cpuDetail 'Mainboard vendor' $board.Manufacturer
        Add-DetailLine $cpuDetail 'Mainboard model' $board.Product
        Add-DetailLine $cpuDetail 'Mainboard revision' $board.Version
    }
    if ($bios) {
        Add-DetailLine $cpuDetail 'BIOS version' $bios.SMBIOSBIOSVersion
        Add-DetailLine $cpuDetail 'BIOS vendor' $bios.Manufacturer
        $biosDate = ConvertTo-LocalDate $bios.ReleaseDate
        if ($biosDate) { Add-DetailLine $cpuDetail 'BIOS release' $biosDate.ToString('yyyy-MM-dd') }
    }
    $script:GuiHardwareDetail['cpu'] = $cpuDetail

    # GPU
    $gpuDetail = [Collections.Generic.List[string]]::new()
    foreach ($adapter in $gpu) {
        Add-DetailLine $gpuDetail 'Adapter' $adapter.Name
        Add-DetailLine $gpuDetail '  Vendor' $adapter.AdapterCompatibility
        Add-DetailLine $gpuDetail '  Driver version' $adapter.DriverVersion
        $driverDate = ConvertTo-LocalDate $adapter.DriverDate
        if ($driverDate) { Add-DetailLine $gpuDetail '  Driver date' $driverDate.ToString('yyyy-MM-dd') }
        Add-DetailLine $gpuDetail '  Video mode' $adapter.VideoModeDescription
        if ($adapter.AdapterRAM -and [int64]$adapter.AdapterRAM -gt 0) {
            Add-DetailLine $gpuDetail '  Reported VRAM' ("{0} MB" -f [math]::Round([int64]$adapter.AdapterRAM / 1MB,0))
        }
    }
    $script:GuiHardwareDetail['gpu'] = $gpuDetail

    # Memory and storage
    $memoryDetail = [Collections.Generic.List[string]]::new()
    if ($script:GuiMemoryGb) { Add-DetailLine $memoryDetail 'Total' ("{0} GB" -f $script:GuiMemoryGb) }
    foreach ($module in $memoryModules) {
        $memoryDetail.Add(('Slot {0} [{1}]' -f $module.DeviceLocator,$module.BankLabel))
        Add-DetailLine $memoryDetail '  Capacity' ("{0} GB" -f [math]::Round($module.Capacity / 1GB,0))
        Add-DetailLine $memoryDetail '  Vendor' $module.Manufacturer
        Add-DetailLine $memoryDetail '  Part number' $module.PartNumber
        Add-DetailLine $memoryDetail '  Configured' ("{0} MT/s" -f $module.ConfiguredClockSpeed)
        Add-DetailLine $memoryDetail '  Rated' ("{0} MT/s" -f $module.Speed)
        Add-DetailLine $memoryDetail '  Voltage' ("{0} mV" -f $module.ConfiguredVoltage)
    }
    foreach ($disk in $disks) {
        $memoryDetail.Add(('Disk {0}' -f ([string]$disk.Model).Trim()))
        Add-DetailLine $memoryDetail '  Interface' $disk.InterfaceType
        if ($disk.Size) { Add-DetailLine $memoryDetail '  Size' ("{0} GB" -f [math]::Round([int64]$disk.Size / 1GB,1)) }
        Add-DetailLine $memoryDetail '  Firmware' $disk.FirmwareRevision
        Add-DetailLine $memoryDetail '  Status' $disk.Status
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
        $readyCount = @($script:GuiPlan.programs | Where-Object { $_.installed -and $_.launchable }).Count
        $totalCount = @($script:GuiPlan.programs).Count
        $statusKey = if ($readyCount -eq $totalCount) { 'GuiCheckComplete' } else { 'GuiCheckPartial' }
        $arguments = if ($statusKey -eq 'GuiCheckComplete') { @($totalCount) } else { @($readyCount,$totalCount) }
        $ui.StatusText.Text = Get-WplText -Key $statusKey -Language $script:GuiLanguage -ArgumentList $arguments
    }

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(750)
    $timer.Add_Tick({
        if (-not $script:GuiJob) { return }
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
                $output = @(& (Join-Path $ProjectRoot 'WinPortableLab.ps1') -Action check -Profile $SelectedProfile -Language $SelectedLanguage -NoElevation 2>&1)
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
    foreach($filterButton in @($ui.FilterAllButton,$ui.FilterReadyButton,$ui.FilterMissingButton,$ui.FilterRiskButton)){
        $filterButton.Add_Click({param($sender,$eventArgs);$script:GuiCurrentFilter=[string]$sender.Tag;Update-GuiFilterButtons;Update-GuiProgramPresentation})
    }
    $ui.QuickButton.Add_Click({ Set-GuiProfileFromSnapshot 'quick' })
    $ui.AllButton.Add_Click({ Set-GuiProfileFromSnapshot 'all' })
    $ui.StorageButton.Add_Click({ Set-GuiProfileFromSnapshot 'storage' })
    $ui.MemoryButton.Add_Click({ Set-GuiProfileFromSnapshot 'memory' })
    $ui.GpuButton.Add_Click({ Set-GuiProfileFromSnapshot 'gpu' })
    $ui.RefreshButton.Add_Click({ Start-GuiAnalysis $script:GuiCurrentProfile })
    $ui.OsCardButton.Add_Click({ Show-GuiHardwareDetail 'os' (Get-WplText -Key GuiDetailTitleOs -Language $script:GuiLanguage) })
    $ui.CpuCardButton.Add_Click({ Show-GuiHardwareDetail 'cpu' (Get-WplText -Key GuiDetailTitleCpu -Language $script:GuiLanguage) })
    $ui.GpuCardButton.Add_Click({ Show-GuiHardwareDetail 'gpu' (Get-WplText -Key GuiDetailTitleGpu -Language $script:GuiLanguage) })
    $ui.MemoryCardButton.Add_Click({ Show-GuiHardwareDetail 'memory' (Get-WplText -Key GuiDetailTitleMemory -Language $script:GuiLanguage) })
    $ui.LanguageButton.Add_Click({ $script:GuiLanguage = if ($script:GuiLanguage -eq 'ko') { 'en' } else { 'ko' }; Set-GuiText })
    $ui.LaunchButton.Add_Click({
        $selected = $ui.ProgramGrid.SelectedItem
        if (-not $selected) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiSelectTool -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        if (-not $selected.launchable) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNotLaunchable -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        $riskAccepted = $false
        if ([string]$selected.risk -notmatch '^read-only') {
            $message = Get-WplText -Key GuiRiskConfirm -Language $script:GuiLanguage -ArgumentList @($selected.riskText)
            $answer = [System.Windows.MessageBox]::Show($message,$window.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
            $riskAccepted = $true
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
            $sessionArguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Root "{1}" -LauncherId {2} -Start -AcceptRisk' -f $sessionScript,$Root,[string]$selected.id
            $sessionWindowStyle = if([string]$selected.launchMode -in @('cli','cli-help')){'Normal'}else{'Hidden'}
            if($sessionWindowStyle -eq 'Normal'){$sessionArguments += ' -PauseOnExit'}
            $launchSignal=$null
            if($sessionWindowStyle -eq 'Hidden'){
                $launchSignal=Join-Path $Root ('logs\launch-signal-{0}.json' -f [guid]::NewGuid().ToString('N'))
                $sessionArguments += ' -LaunchSignalPath "{0}"' -f $launchSignal
            }
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
        $safe = @($script:GuiPlan.programs | Where-Object { $_.state -eq 'recommended-now' -and $_.risk -eq 'read-only' -and $_.launchMode -eq 'gui' -and $_.launchable } | Select-Object -ExpandProperty id)
        if (-not $safe.Count) { [System.Windows.MessageBox]::Show((Get-WplText -Key NoSafeLaunch -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        $message = Get-WplText -Key GuiSafeLaunchConfirm -Language $script:GuiLanguage -ArgumentList @($safe.Count,($safe -join "`n"))
        $answer = [System.Windows.MessageBox]::Show($message,$window.Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Information)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $ui.SafeLaunchButton.IsEnabled = $false
        Set-GuiStatusTone 'busy'
        $ui.StatusText.Text = Get-WplText -Key GuiSafeLaunchRunning -Language $script:GuiLanguage -ArgumentList @($safe.Count)
        try {
            $results = @(Open-ToolIds -Ids $safe -UseLanguage $script:GuiLanguage -ContinueOnError)
            $failed = @($results | Where-Object { -not $_.success })
            try {
                [ordered]@{createdAt=(Get-Date).ToString('o');requested=@($safe);results=$results} |
                    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root 'logs\safe-launch-latest.json') -Encoding utf8
            }
            catch { }
            if ($failed.Count) {
                Set-GuiStatusTone 'busy'
                $ui.StatusText.Text = Get-WplText -Key GuiSafeLaunchPartial -Language $script:GuiLanguage -ArgumentList @(($results.Count-$failed.Count),$failed.Count)
                $details = @($failed | ForEach-Object { "- $($_.id): $($_.error)" }) -join [Environment]::NewLine
                [System.Windows.MessageBox]::Show($ui.StatusText.Text + [Environment]::NewLine + [Environment]::NewLine + $details,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Warning) | Out-Null
            }
            else {
                Set-GuiStatusTone 'ok'
                $ui.StatusText.Text = Get-WplText -Key GuiSafeLaunchCompleted -Language $script:GuiLanguage -ArgumentList @($results.Count)
            }
        }
        catch {
            Set-GuiStatusTone 'fail'
            $ui.StatusText.Text = Get-WplText -Key GuiLaunchFailed -Language $script:GuiLanguage -ArgumentList @($_.Exception.Message)
            [System.Windows.MessageBox]::Show($_.Exception.Message,$window.Title,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        }
        finally {
            $ui.SafeLaunchButton.IsEnabled = $true
        }
    })
    $ui.GuideButton.Add_Click({
        if (-not $script:GuiRecommendationDirectory) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoPlan -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        Open-WplTextDocument (Join-Path $script:GuiRecommendationDirectory "recommended-programs.$($script:GuiLanguage).md")
    })
    $ui.ReportsButton.Add_Click({ Start-Process explorer.exe -ArgumentList @((Join-Path $Root 'reports')) })
    $ui.ToolGuideButton.Add_Click({
        $selected = $ui.ProgramGrid.SelectedItem
        if (-not $selected) { [System.Windows.MessageBox]::Show((Get-WplText -Key GuiSelectTool -Language $script:GuiLanguage),$window.Title) | Out-Null; return }
        $documentName = Get-WplToolGuideName ([string]$selected.catalogId)
        $quickReference = Join-Path $Root ('docs\{0}\QUICK_USE.md' -f $script:GuiLanguage)
        $detailed = if ($documentName) { Join-Path $Root ('docs\{0}\tools\{1}.md' -f $script:GuiLanguage,$documentName) } else { $null }
        try {
            if ($detailed -and (Test-Path -LiteralPath $detailed -PathType Leaf)) { Open-WplTextDocument $detailed; return }
            [System.Windows.MessageBox]::Show((Get-WplText -Key GuiNoToolGuide -Language $script:GuiLanguage -ArgumentList @([string]$selected.displayName)),$window.Title) | Out-Null
            Open-WplTextDocument $quickReference
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
    $window.Add_Loaded({
        if ($script:GuiInitialAnalysisStarted) { return }
        $script:GuiInitialAnalysisStarted = $true
        Start-GuiAnalysis $Profile
    })
    $window.Add_Closed({
        $timer.Stop()
        if ($script:GuiJob -and $script:GuiJob.State -in @('NotStarted','Running')) { Stop-Job -Job $script:GuiJob -ErrorAction SilentlyContinue }
        if ($script:GuiJob) { Remove-Job -Job $script:GuiJob -Force -ErrorAction SilentlyContinue }
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
    Open-ToolIds -Ids $ToolId -RiskAccepted:$AcknowledgeRisk
    return
}

$result = Invoke-IntegratedCheck -SelectedProfile $Profile
if ($Action -in @('check','list')) {
    Show-ProgramPlan $result.Connection
    return $result
}

if ($Action -eq 'launch-recommended') {
    $safe = @($result.Connection.Plan.programs | Where-Object { $_.state -eq 'recommended-now' -and $_.risk -eq 'read-only' -and $_.launchMode -eq 'gui' -and $_.launchable } | Select-Object -ExpandProperty id)
    if (-not $safe.Count) { Write-Host (Get-WplText -Key NoSafeLaunch -Language $Language) -ForegroundColor Yellow; return }
    Open-ToolIds -Ids $safe
    return
}

Show-ProgramPlan $result.Connection
while ($true) {
    Write-Host ''
    $choice = Read-Host (Get-WplText -Key MenuPrompt -Language $Language)
    switch ($choice) {
        '1' { Show-ProgramPlan $result.Connection }
        '2' {
            $safe = @($result.Connection.Plan.programs | Where-Object { $_.state -eq 'recommended-now' -and $_.risk -eq 'read-only' -and $_.launchMode -eq 'gui' -and $_.launchable } | Select-Object -ExpandProperty id)
            if ($safe.Count) { Open-ToolIds -Ids $safe } else { Write-Host (Get-WplText -Key NoSafeLaunch -Language $Language) -ForegroundColor Yellow }
        }
        '3' { $selectedId = Read-Host (Get-WplText -Key EnterToolId -Language $Language); if ($selectedId) { Open-ToolIds -Ids @($selectedId) -RiskAccepted:$AcknowledgeRisk } }
        '4' { Start-Process explorer.exe -ArgumentList @($result.ReportDirectory) }
        '5' { Open-WplTextDocument (Join-Path $result.RecommendationDirectory "recommended-programs.$Language.md") }
        '0' { break }
        default { continue }
    }
    if ($choice -eq '0') { break }
}
