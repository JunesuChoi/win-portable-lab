# Pester 5 and newer run each Describe block in an isolated scope, so shared
# helpers must be registered where every block can see them. BeforeAll covers
# Pester 5/6 while the direct invocation keeps the bundled Pester 3.4 working.
$script:WplTestSetup = {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:root 'src\WinPortableLab.Core.psm1') -Force
    Import-Module (Join-Path $script:root 'src\WinPortableLab.Process.psm1') -Force

    function Assert-WplTest {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw $Message }
    }

    function Get-WplTestData {
        # Windows PowerShell 5.1 can return a JSON top-level array as one nested
        # array object. Enumerating explicitly gives both runtimes the same shape.
        $catalogDocument = Read-WplJson -Path (Join-Path $script:root 'catalog\tools.json')
        $launcherDocument = Read-WplJson -Path (Join-Path $script:root 'config\tool-launchers.json')
        $catalog = @(foreach ($item in $catalogDocument) { $item })
        $launchers = @(foreach ($item in $launcherDocument) { $item })
        $packages = @(Get-WplPackageDefinitions -Root $script:root)
        $profiles = @(Get-ChildItem -LiteralPath (Join-Path $script:root 'profiles') -Filter '*.json' -File | ForEach-Object { Read-WplJson -Path $_.FullName })
        [pscustomobject]@{Catalog=$catalog;Launchers=$launchers;Packages=$packages;Profiles=$profiles}
    }
}

# Dot-source so the helpers land in the file scope that Pester 3.4 executes from.
. $script:WplTestSetup
# Pester 3.4 rejects a file-scope BeforeAll, so register it only on Pester 5+,
# which is where the per-Describe scope isolation actually requires it.
$script:WplPesterMajor = 0
try { $script:WplPesterMajor = [int](Get-Module Pester | Select-Object -First 1).Version.Major } catch { }
if ($script:WplPesterMajor -ge 5) { BeforeAll $script:WplTestSetup }


Describe 'Package and catalog definitions' {
    It 'keeps identifiers unique without relying on a brittle fixed package count' {
        $data = Get-WplTestData
        Assert-WplTest ($data.Catalog.Count -gt 0) 'The tool catalog is empty.'
        Assert-WplTest (@($data.Catalog.id | Sort-Object -Unique).Count -eq $data.Catalog.Count) 'Catalog ids are not unique.'
        Assert-WplTest (@($data.Packages.packageId | Sort-Object -Unique).Count -eq $data.Packages.Count) 'Package ids are not unique.'
    }

    It 'pins every package archive to SHA-256' {
        $data = Get-WplTestData
        $invalid = @($data.Packages | Where-Object { [string]$_.source.sha256 -notmatch '^[A-Fa-f0-9]{64}$' })
        Assert-WplTest ($invalid.Count -eq 0) "Packages without a valid SHA-256: $($invalid.packageId -join ', ')"
    }

    It 'describes every package and launcher in the catalog' {
        $data = Get-WplTestData
        $unknownPackages = @($data.Packages | Where-Object { $_.catalogId -notin @($data.Catalog.id) })
        $unknownLaunchers = @($data.Launchers | Where-Object { $_.catalogId -notin @($data.Catalog.id) })
        Assert-WplTest ($unknownPackages.Count -eq 0) "Packages reference unknown catalog ids: $($unknownPackages.packageId -join ', ')"
        Assert-WplTest ($unknownLaunchers.Count -eq 0) "Launchers reference unknown catalog ids: $($unknownLaunchers.id -join ', ')"
    }

    It 'has a package and launcher relationship for every catalog entry' {
        $data = Get-WplTestData
        $withoutPackage = @($data.Catalog | Where-Object { $_.id -notin @($data.Packages.catalogId) })
        $withoutLauncher = @($data.Catalog | Where-Object { $_.id -notin @($data.Launchers.catalogId) })
        Assert-WplTest ($withoutPackage.Count -eq 0) "Catalog entries without package definitions: $($withoutPackage.id -join ', ')"
        Assert-WplTest ($withoutLauncher.Count -eq 0) "Catalog entries without launchers: $($withoutLauncher.id -join ', ')"
    }

    It 'marks load and write risks explicitly' {
        $data = Get-WplTestData
        $occt = @($data.Packages | Where-Object packageId -eq 'occt') | Select-Object -First 1
        $diskspd = @($data.Packages | Where-Object packageId -eq 'diskspd') | Select-Object -First 1
        Assert-WplTest ($null -ne $occt -and $occt.risk.highLoad -eq $true) 'OCCT must remain explicitly high-load.'
        Assert-WplTest ($null -ne $diskspd -and $diskspd.risk.writesData -eq $true) 'DiskSpd must remain explicitly write-capable.'
    }
}

Describe 'Launcher and profile relationships' {
    It 'turns a dirty diagnostic baseline into a real workload gate' {
        foreach ($risk in @('high-load','very-high-load','writes-test-file','fills-free-space-high-write','installer-changes-cpu-settings')) {
            Assert-WplTest (Test-WplBaselineBlockedRisk -RecommendationMode 'diagnostic-baseline-only' -Risk $risk) "Baseline mode did not block $risk."
        }
        Assert-WplTest (-not (Test-WplBaselineBlockedRisk -RecommendationMode 'diagnostic-baseline-only' -Risk 'read-only')) 'Read-only diagnosis was blocked with the workload.'
        Assert-WplTest (-not (Test-WplBaselineBlockedRisk -RecommendationMode 'conservative-baseline' -Risk 'high-load')) 'A clean baseline still blocks high-load guidance.'
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($gui -match 'Test-WplBaselineBlockedRisk') 'The connection plan does not call the tested workload gate.'
        Assert-WplTest ($gui.Contains("`$baselineWarning")) 'The connection plan ignores the baseline warning signal.'
        Assert-WplTest (-not $gui.Contains("state = if (`$baselineBlocked) { 'diagnostic-baseline-only' }")) 'Rows are still hard-blocked by the baseline gate.'
    }

    It 'enumerates every launcher through the shared array reader on both runtimes' {
        $launchers = @(Read-WplJsonArray -Path (Join-Path $root 'config\tool-launchers.json'))
        $data = Get-WplTestData
        Assert-WplTest ($launchers.Count -eq $data.Launchers.Count) "Read-WplJsonArray returned $($launchers.Count) launchers instead of $($data.Launchers.Count)."
        $collapsed = @($launchers | Where-Object { $_ -is [object[]] })
        Assert-WplTest ($collapsed.Count -eq 0) 'Read-WplJsonArray collapsed the JSON array into a nested object.'
        $withoutId = @($launchers | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.id) })
        Assert-WplTest ($withoutId.Count -eq 0) 'Read-WplJsonArray produced launcher entries without an id.'
    }

    It 'keeps launcher ids unique and executable patterns bounded' {
        $data = Get-WplTestData
        Assert-WplTest (@($data.Launchers.id | Sort-Object -Unique).Count -eq $data.Launchers.Count) 'Launcher ids are not unique.'
        $invalid = @($data.Launchers | Where-Object {
            $_.launchMode -ne 'external-boot' -and
            ([string]::IsNullOrWhiteSpace([string]$_.pattern) -or [IO.Path]::IsPathRooted([string]$_.pattern) -or [string]$_.pattern -match '(^|[\\/])\.\.([\\/]|$)')
        })
        Assert-WplTest ($invalid.Count -eq 0) "Invalid launcher patterns: $($invalid.id -join ', ')"
    }

    It 'maps every profile tool to a catalog entry and a launcher' {
        $data = Get-WplTestData
        $problems = @()
        foreach ($profile in $data.Profiles) {
            foreach ($toolId in @($profile.tools)) {
                if ($toolId -notin @($data.Catalog.id)) { $problems += "$($profile.id): unknown catalog id '$toolId'" }
                if ($toolId -notin @($data.Launchers.catalogId)) { $problems += "$($profile.id): no launcher for '$toolId'" }
            }
        }
        Assert-WplTest ($problems.Count -eq 0) ($problems -join '; ')
    }

    It 'does not silently make risky profiles confirmation-free' {
        $data = Get-WplTestData
        $unsafe = @()
        foreach ($profile in $data.Profiles) {
            $profileLaunchers = @($data.Launchers | Where-Object { $_.catalogId -in @($profile.tools) })
            $hasRisk = @($profileLaunchers | Where-Object { [string]$_.risk -notmatch '^read-only' }).Count -gt 0
            if ($hasRisk -and $profile.requiresConfirmation -ne $true) { $unsafe += $profile.id }
        }
        Assert-WplTest ($unsafe.Count -eq 0) "Risky profiles without confirmation: $($unsafe -join ', ')"
    }

    It 'accepts the Sysinternals licence prompt for every wired Sysinternals launcher' {
        # Without -accepteula these tools block on a modal EULA dialog and the
        # session never reaches a usable state.
        $data = Get-WplTestData
        $missing = @()
        foreach ($launcher in @($data.Launchers | Where-Object { $_.catalogId -eq 'sysinternals' })) {
            $arguments = @($launcher.arguments)
            if ($arguments -notcontains '-accepteula') { $missing += $launcher.id }
        }
        Assert-WplTest ($missing.Count -eq 0) "Sysinternals launchers missing -accepteula: $($missing -join ', ')"
    }

    It 'treats a help invocation that printed output as a completed session' {
        $session = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-WplToolSession.ps1') -Raw
        Assert-WplTest ($session -match 'helpSucceeded') 'Help-mode success is not evaluated.'
        Assert-WplTest ($session.Contains("launchMode -eq 'cli-help' -and ")) 'Help success is not scoped to help mode.'
        Assert-WplTest ($session.Contains('producedOutput')) 'Help success does not require real output.'
        Assert-WplTest ($session.Contains('if($helpSucceeded){0}')) 'A successful help run still exits non-zero.'
    }

    It 'lets a user-declared path override the bundled tools tree' {
        # Both resolvers must honour the override, otherwise the CLI and the GUI
        # would disagree about which executable a launcher points at.
        $core = Get-Content -LiteralPath (Join-Path $root 'src\WinPortableLab.Core.psm1') -Raw
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($core -match 'Get-WplToolOverride') 'The core resolver does not consult user-declared paths.'
        Assert-WplTest ($core -match 'user-tool-paths\.json') 'The override file location is not defined in the core module.'
        Assert-WplTest ($gui -match 'Get-WplUserToolPath') 'The GUI resolver does not consult user-declared paths.'
        Assert-WplTest ($gui -match 'WplUserToolPaths = \$null') 'The GUI override cache is not reset with the tool index.'
        # Only real .exe files may be accepted, and the editor must validate.
        $editor = Join-Path $root 'scripts\Set-WplToolPath.ps1'
        Assert-WplTest (Test-Path -LiteralPath $editor -PathType Leaf) 'The user path editor script is missing.'
        $editorSource = Get-Content -LiteralPath $editor -Raw
        foreach ($guard in @('UserPathNotFound','UserPathNotExe','UserPathUnknownId')) {
            Assert-WplTest ($editorSource -match $guard) "The editor does not guard against: $guard"
        }
        Assert-WplTest ($core -match "-ine '\.exe'") 'The core override does not reject non-executable paths.'
    }

    It 'keeps the override file out of version control' {
        $ignore = Get-Content -LiteralPath (Join-Path $root '.gitignore') -Raw
        Assert-WplTest ($ignore -match 'user-tool-paths\.json') 'The per-machine override file is not gitignored.'
    }

    It 'keeps discovery-only rows unlaunchable so the profile gate still holds' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match "available-in-profile") 'The discovery-only state is not defined.'
        Assert-WplTest ($source -match '\$discoveryOnly\s*=\s*\$candidates\[\$candidateId\]\.state -eq ''available-in-profile''') 'Discovery-only rows are not detected when building the plan.'
        Assert-WplTest ($source -match '\$launchableState\s*=\s*\[bool\]\$exe -and -not \$discoveryOnly') 'Discovery-only rows are still marked launchable.'
        Assert-WplTest ($source -match 'command = if \(\$launchableState\)') 'Discovery-only rows still emit a launch command.'
    }
}

Describe 'Elevation and detailed inventory contract' {
    It 'offers an explicit standard-user escape hatch' {
        Assert-WplTest ((Get-Command (Join-Path $root 'WinPortableLab.ps1')).Parameters.Keys -contains 'NoElevation') 'WinPortableLab.ps1 lacks -NoElevation.'
        Assert-WplTest ((Get-Command (Join-Path $root 'scripts\Start-WinPortableLab.ps1')).Parameters.Keys -contains 'NoElevation') 'Start-WinPortableLab.ps1 lacks -NoElevation.'
    }

    It 'keeps detailed inventory collections in the report source' {
        $source = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-Inventory.ps1') -Raw
        foreach ($name in @('StorageReliability','Volumes','Partitions','Tpm','BitLockerVolumes','DeviceGuard','SignedDrivers','HotFixes','PowerPlan')) {
            Assert-WplTest ($source -match [regex]::Escape($name)) "Inventory section '$name' is missing."
        }
    }

    It 'uses a bounded recommendation inventory without removing full reporting' {
        $inventoryCommand = Get-Command (Join-Path $root 'scripts\Invoke-Inventory.ps1')
        Assert-WplTest ($inventoryCommand.Parameters.Keys -contains 'CollectionProfile') 'Inventory cannot select a recommendation collection profile.'
        $source = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-Inventory.ps1') -Raw
        Assert-WplTest ($source -match "ValidateSet\('quick','full'\)") 'Inventory profile validation is missing.'
        Assert-WplTest ($source -match '\$fullCollection\s*=\s*\$CollectionProfile -eq ''full''') 'Inventory does not preserve an explicit full-report branch.'
        Assert-WplTest ($source -match 'ProviderName=''Microsoft-Windows-WHEA-Logger''') 'Quick recommendations no longer collect WHEA stability signals.'
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($gui -match '-NoElevation -FastRecommendation') 'GUI analysis does not request the bounded recommendation inventory.'
        Assert-WplTest ($gui -match '\$collectionProfile = if\(\$FastRecommendation\)\{''quick''\}else\{''full''\}') 'Console and GUI inventory profile routing is not explicit.'
    }

    It 'builds recommendations from the captured inventory snapshot' {
        $fixture = Join-Path $TestDrive 'captured-inventory'
        $output = Join-Path $TestDrive 'recommendations'
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        [ordered]@{
            Processor=@([ordered]@{Name='Fixture CPU';Manufacturer='GenuineIntel';NumberOfCores=8;NumberOfLogicalProcessors=16})
            ComputerSystem=@([ordered]@{Manufacturer='Fixture Vendor';Model='Fixture Model'})
            OperatingSystem=@([ordered]@{Caption='Fixture Windows';Version='10.0';BuildNumber='99999';OSArchitecture='64-bit'})
            BaseBoard=@([ordered]@{Manufacturer='Fixture Board';Product='Fixture Z';Version='1.0'})
            Bios=@([ordered]@{SMBIOSBIOSVersion='FIXTURE-1';ReleaseDate='2026-01-01'})
            MemoryModules=@([ordered]@{Capacity=17179869184;ConfiguredClockSpeed=3200;Speed=3200;PartNumber='FIXTURE-DIMM'})
            Graphics=@([ordered]@{Name='Fixture GPU';DriverVersion='1.2.3';DriverDate='2026-01-01'})
            DiskDrives=@([ordered]@{Model='Fixture SSD';InterfaceType='NVMe';Size=1073741824000;FirmwareRevision='F1'})
            Batteries=@()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixture 'hardware.json') -Encoding utf8
        '[{"ProviderName":"Microsoft-Windows-WHEA-Logger","Id":1}]' | Set-Content -LiteralPath (Join-Path $fixture 'events.json') -Encoding utf8
        $created = & (Join-Path $root 'scripts\New-SystemRecommendation.ps1') -Root $root -OutputRoot $output -InventoryDirectory $fixture -Language en
        $settings = Read-WplJson -Path (Join-Path $created 'recommended-settings.json')
        Assert-WplTest ($settings.detected.cpu.name -eq 'Fixture CPU') 'Recommendation ignored the supplied inventory snapshot.'
        Assert-WplTest ($settings.detected.healthSignals.recommendationMode -eq 'diagnostic-baseline-only') 'Recommendation ignored the supplied event snapshot.'
        $source = Get-Content -LiteralPath (Join-Path $root 'scripts\New-SystemRecommendation.ps1') -Raw
        Assert-WplTest ($source -match 'if \(\$inventorySnapshot\)[\s\S]+?else \{[\s\S]+?Read-CimSafe') 'Standalone CIM fallback is not isolated from snapshot reuse.'
    }
}

Describe 'GUI snapshot and launcher behavior contract' {
    It 'keeps colour literals confined to the token definitions' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $lines = @($source -split "`n")
        $offenders = @()
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($line -notmatch '#[0-9A-Fa-f]{6}') { continue }
            # Only the SolidColorBrush token block and pure white may carry a literal.
            if ($line -match 'SolidColorBrush x:Key=') { continue }
            if ($line -match '#FFFFFF') { continue }
            $offenders += ('line {0}: {1}' -f ($index + 1),$line.Trim())
        }
        Assert-WplTest ($offenders.Count -eq 0) "Colour literals outside the token block: $($offenders -join ' | ')"
    }

    It 'does not reintroduce the retired neon palette' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $retired = @('#28D7F2','#42E8F5','#7DEBFA','#56F2C2','#F5A623','#FF5D6C','#081018','#0D6674','#A64F18')
        $found = @($retired | Where-Object { $source -match [regex]::Escape($_) })
        Assert-WplTest ($found.Count -eq 0) "Retired neon colours are back: $($found -join ', ')"
    }

    It 'signals risk through the row accent rather than a filled row background' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match 'riskTier') 'The risk tier property is missing.'
        foreach ($tier in @('safe','caution','danger')) {
            Assert-WplTest ($source -match ("Binding riskTier\}"" Value=""$tier")) "No row accent trigger for the $tier tier."
        }
        Assert-WplTest ($source -match 'Set-GuiStatusTone') 'Status colours are not resolved through the shared helper.'
    }

    It 'splits the status column into a state badge and a readiness label' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match 'DataGridTemplateColumn Header="STATUS"') 'The status column is not templated.'
        Assert-WplTest ($source -match 'SortMemberPath="displayStatus"') 'The templated status column lost its sort key.'
        Assert-WplTest ($source -match 'Text="\{Binding stateText\}"') 'The state badge does not bind stateText.'
        Assert-WplTest ($source -match 'Text="\{Binding readyText\}"') 'The readiness label does not bind readyText.'
        # displayStatus must survive because search and sorting still read it.
        Assert-WplTest ($source -match 'NotePropertyName displayStatus') 'displayStatus is no longer produced.'
    }

    It 'reuses the current snapshot when a profile button is clicked' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        foreach ($button in @('Quick','All','Storage','Memory','Gpu')) {
            Assert-WplTest ($source -match ('\$ui\.{0}Button\.Add_Click\(\{{ Set-GuiProfileFromSnapshot' -f $button)) "$button triggers a new inventory instead of snapshot reuse."
        }
    }

    It 'reruns inventory only through the explicit refresh button after initial load' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match '\$ui\.RefreshButton\.Add_Click\(\{ Start-GuiAnalysis') 'Refresh is not wired to analysis.'
        Assert-WplTest ([regex]::Matches($source,'\.Add_Click\(\{ Start-GuiAnalysis').Count -eq 1) 'More than one button directly reruns inventory.'
    }

    It 'starts tools from their executable directory and preserves no-argument compatibility' {
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $session = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-WplToolSession.ps1') -Raw
        $processModule = Get-Content -LiteralPath (Join-Path $root 'src\WinPortableLab.Process.psm1') -Raw
        Assert-WplTest ($session -match '-WorkingDirectory \(Split-Path \$executable\.FullName\)') 'Tool working directory is not set to its executable directory.'
        Assert-WplTest ($session -match 'Start-WplProcess[\s\S]+-ArgumentList \$launcherArguments') 'Session launch does not use the cross-version process wrapper.'
        Assert-WplTest ($processModule -match 'if \(\$ArgumentList\.Count -gt 0\)[\s\S]+\$parameters\.ArgumentList = ConvertTo-WplWindowsCommandLine') 'Empty ArgumentList is not guarded in the cross-version process wrapper.'
        Assert-WplTest ($gui -match "launchMode -in @\('cli','cli-help'\)") 'CLI launch modes are not distinguished.'
    }

    It 'passes quoted script paths as one native command line' {
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $session = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-WplToolSession.ps1') -Raw
        # The session command line must be produced by the shared encoder. Building
        # it with -f interpolation let an unquoted launcher id smuggle extra
        # parameters into an elevated powershell.exe invocation.
        Assert-WplTest ($gui -match '\$sessionArguments = ConvertTo-WplWindowsCommandLine -ArgumentList') 'Session command line is not produced by the shared argument encoder.'
        Assert-WplTest ($gui -notmatch '(?m)^\s*\$sessionArguments\s*=\s*''-NoLogo') 'Session command line is still hand-built from a format string.'
        Assert-WplTest ($gui -notmatch '\-LauncherId \{2\}') 'The launcher id is still interpolated into the command line unquoted.'
        Assert-WplTest ($gui -match 'WinPortableLab\.Process\.psm1') 'The GUI does not import the process module that owns argument encoding.'
        Assert-WplTest ($session -match '\$launchers = @\(foreach \(\$item in \$launcherDocument\) \{ \$item \}\)') 'PS 5.1 JSON array normalization is missing.'
    }

    It 'selects one safe recommendation instead of batch-launching tools' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $start = $source.IndexOf('$ui.SafeLaunchButton.Add_Click')
        $end = $source.IndexOf('$ui.GuideButton.Add_Click',$start)
        Assert-WplTest ($start -ge 0 -and $end -gt $start) 'Could not isolate the guided recommendation handler.'
        $handler = $source.Substring($start,$end-$start)
        Assert-WplTest ($handler -match "GuiCurrentFilter='recommended'") 'The guided action does not return to the recommendation view.'
        Assert-WplTest ($handler -match 'ProgramGrid.SelectedItem=\$next') 'The guided action does not select one next item.'
        Assert-WplTest ($handler -notmatch 'Open-ToolIds|Start-Process') 'The guided action still starts one or more tools automatically.'
    }

    It 'applies each list filter to the pipeline item rather than the filter name' {
        # The inline switch used `$_`, which inside a switch body is the switch
        # input string, so 'recommended', 'missing' and 'risky' all matched every
        # row. Verified against the live GUI before this predicate was extracted.
        $catalogOnly = [pscustomobject]@{id='ventoy';displayName='Ventoy';state='catalog-only';risk='system-changing';installed=$true;launchable=$true}
        $recommended = [pscustomobject]@{id='cpuz';displayName='CPU-Z Portable';state='recommended-now';risk='read-only';installed=$true;launchable=$true}
        $missing = [pscustomobject]@{id='occt';displayName='OCCT';state='guided-test';risk='very-high-load';installed=$false;launchable=$false}
        Assert-WplTest (Test-WplProgramVisible -Program $recommended -Filter 'recommended') 'A recommended row was hidden by the recommended filter.'
        Assert-WplTest (-not (Test-WplProgramVisible -Program $catalogOnly -Filter 'recommended')) 'The recommended filter still shows catalogue-only rows.'
        Assert-WplTest (Test-WplProgramVisible -Program $catalogOnly -Filter 'all') 'The all filter hid a catalogue row.'
        Assert-WplTest (Test-WplProgramVisible -Program $recommended -Filter 'ready') 'The ready filter hid a launchable row.'
        Assert-WplTest (-not (Test-WplProgramVisible -Program $missing -Filter 'ready')) 'The ready filter shows an unlaunchable row.'
        Assert-WplTest (Test-WplProgramVisible -Program $missing -Filter 'missing') 'The missing filter hid an unacquired row.'
        Assert-WplTest (-not (Test-WplProgramVisible -Program $recommended -Filter 'missing')) 'The missing filter shows an acquired row.'
        Assert-WplTest (Test-WplProgramVisible -Program $missing -Filter 'risky') 'The risk filter hid a high-load row.'
        Assert-WplTest (-not (Test-WplProgramVisible -Program $recommended -Filter 'risky')) 'The risk filter shows a read-only row.'
        Assert-WplTest (Test-WplProgramVisible -Program $recommended -Filter 'all' -Query 'cpu') 'A matching search query hid its row.'
        Assert-WplTest (-not (Test-WplProgramVisible -Program $recommended -Filter 'all' -Query 'ventoy')) 'A non-matching search query still shows the row.'
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($gui -match 'Test-WplProgramVisible -Program \$_ -Filter \$filter -Query \$query') 'The GUI list does not use the tested visibility predicate.'
        Assert-WplTest ($gui -notmatch "'ready' \{ \[bool\]\\\$_\.launchable \}") 'The untestable inline filter switch is back in the GUI.'
    }

    It 'requires a truthful manual-temperature acknowledgement for high load' {
        $session = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-WplToolSession.ps1') -Raw
        $cli = Get-Content -LiteralPath (Join-Path $root 'scripts\Open-PortableTool.ps1') -Raw
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($session -match 'AcknowledgeManualTemperatureMonitoring') 'The supervised launcher has no temperature-monitoring acknowledgement.'
        Assert-WplTest ($session -match "temperatureMonitoringMode") 'The session journal does not record the monitoring mode.'
        Assert-WplTest ($cli -match 'ManualTemperatureMonitoringRequired') 'Direct CLI launch bypasses the high-load monitoring gate.'
        Assert-WplTest ($gui -match "sessionTokens.Add\('-AcknowledgeManualTemperatureMonitoring'\)") 'The GUI does not pass its explicit high-load acknowledgement to the session.'
        $conditions = Read-WplJson -Path (Join-Path $root 'config\stop-conditions.json')
        Assert-WplTest (-not ($conditions.PSObject.Properties.Name -contains 'maximumCpuTemperatureC')) 'The config still advertises an unused automatic CPU temperature stop.'
    }

    It 'tracks a launcher process family instead of only its bootstrap PID' {
        # A tool that exits its bootstrap and leaves a worker behind used to look
        # like a completed session, so this starts that exact shape for real.
        $hostExecutable = (Get-Process -Id $PID).Path
        $before = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId,CreationDate)
        $startedAt = Get-Date
        $bootstrap = Start-Process -FilePath $hostExecutable -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoLogo','-NoProfile','-Command',
            "Start-Process -FilePath '$hostExecutable' -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-Command','Start-Sleep -Seconds 25') | Out-Null")
        try {
            $deadline = (Get-Date).AddSeconds(20)
            $related = @()
            $alive = @()
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 400
                $related = @(Get-WplRelatedProcessIds -RootProcessId $bootstrap.Id -ExecutablePath $hostExecutable -StartedAfter $startedAt -ExcludedProcesses $before)
                # Waiting on $related alone can exit while it still holds only the
                # bootstrap PID, which then dies and leaves nothing alive to check.
                # The assertion is about a surviving worker, so wait for one.
                $alive = @($related | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
                $bootstrap.Refresh()
                if ($bootstrap.HasExited -and $alive.Count) { break }
            }
            Assert-WplTest ($bootstrap.HasExited) 'The fixture bootstrap did not exit, so the surrogate case was not exercised.'
            Assert-WplTest ($related.Count -ge 1) 'A surviving worker process was lost once its bootstrap exited.'
            Assert-WplTest ($alive.Count -ge 1) 'The resolver reported only dead processes for a running worker.'
            Stop-WplRelatedProcesses -ProcessIds $related
            Start-Sleep -Milliseconds 800
            $remaining = @($related | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            Assert-WplTest ($remaining.Count -eq 0) "Stop-WplRelatedProcesses left $($remaining.Count) process(es) running."
        }
        finally {
            Stop-Process -Id $bootstrap.Id -Force -ErrorAction SilentlyContinue
        }
        $session = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-WplToolSession.ps1') -Raw
        Assert-WplTest ($session -match 'Get-WplRelatedProcessIds') 'The session supervisor does not refresh the related process family.'
        Assert-WplTest ($session -match 'Stop-WplRelatedProcesses') 'Cancellation and timeout still stop only the bootstrap process.'
        Assert-WplTest ($session -match 'surrogateProcessObserved') 'The session journal does not record a surrogate worker.'
    }

    It 'opens hardware detail from every summary card' {
        # Each card must be an invokable button wired to its own detail section,
        # otherwise a click silently does nothing.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        foreach ($card in @('OsCardButton','CpuCardButton','GpuCardButton','MemoryCardButton')) {
            Assert-WplTest ($source -match ('x:Name="{0}"' -f $card)) "The $card element is missing from the XAML."
            Assert-WplTest ($source -match ('\$ui\.{0}\.Add_Click' -f $card)) "The $card element has no click handler."
            Assert-WplTest ($source -match ('''{0}''' -f $card)) "The $card element is not resolved by name."
        }
        foreach ($section in @('os','cpu','gpu','memory')) {
            Assert-WplTest ($source -match ("GuiHardwareDetail\['{0}'\]" -f $section)) "No detail payload is built for the $section section."
        }
        Assert-WplTest ($source -match 'function Show-GuiHardwareDetail') 'The detail window function is missing.'
    }

    It 'advises firmware and driver updates without claiming a newer release exists' {
        # The console has no vendor catalogue, so advisories must only prompt a
        # check and must never auto-download anything.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match 'function Set-GuiUpdateAdvice') 'The update advisory builder is missing.'
        Assert-WplTest ($source -match 'function Get-WplVendorSupportUrl') 'The vendor link resolver is missing.'
        Assert-WplTest ($source -match 'AdviceBiosAge') 'No BIOS age advisory text is used.'
        Assert-WplTest ($source -match 'AdviceGpuDriverAge') 'No graphics driver age advisory text is used.'
        # Vendor destinations must be official https endpoints.
        $urls = @([regex]::Matches($source,"return '(https?://[^']+)'") | ForEach-Object { $_.Groups[1].Value })
        Assert-WplTest ($urls.Count -ge 6) "Too few vendor support links are defined: $($urls.Count)"
        $insecure = @($urls | Where-Object { $_ -notmatch '^https://' })
        Assert-WplTest ($insecure.Count -eq 0) "Vendor links must use https: $($insecure -join ', ')"
        # A link is opened only from an explicit click, never during analysis.
        Assert-WplTest ($source -match 'GuiOpenVendorPage') 'The vendor page button text is missing.'
    }

    It 'queries the vendor for a real latest version where an endpoint exists' {
        # NVIDIA is the only vendor with a stable public query, so the online
        # check must be limited to it and must never run during analysis.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match 'function Get-WplNvidiaLatestDriver') 'The NVIDIA lookup function is missing.'
        Assert-WplTest ($source -match 'function Compare-WplDriverVersion') 'The driver version comparison is missing.'
        Assert-WplTest ($source -match 'GuiCheckLatestDriver') 'The online check button text is missing.'
        Assert-WplTest ($source -match "Vendor -match '\(\?i\)nvidia'") 'The online check is not restricted to the supported vendor.'
        # The lookup runs from a click handler, not from Set-GuiUpdateAdvice.
        $adviceStart = $source.IndexOf('function Set-GuiUpdateAdvice')
        $adviceEnd = $source.IndexOf('function Show-GuiHardwareDetail')
        Assert-WplTest ($adviceStart -ge 0 -and $adviceEnd -gt $adviceStart) 'Could not isolate the advisory builder.'
        $adviceBody = $source.Substring($adviceStart,$adviceEnd - $adviceStart)
        Assert-WplTest (-not ($adviceBody -match 'Get-WplNvidiaLatestDriver')) 'Analysis must not perform a network lookup.'
        # Every reported state must have wording, including failure.
        foreach ($key in @('GuiLatestAvailable','GuiLatestCurrent','GuiLatestAhead','GuiLatestUnknown','GuiCheckLatestFailed')) {
            Assert-WplTest ($source -match $key) "Missing online-check wording: $key"
        }
    }

    It 'always offers a vendor destination even when the age threshold is not met' {
        # A recent release date is not proof of being current, so the advisory
        # entry is emitted regardless and severity carries the urgency.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match "'none'") 'There is no non-urgent advisory severity.'
        foreach ($key in @('AdviceBiosRecent','AdviceGpuDriverRecent','AdviceBiosCheckHeading','AdviceGpuCheckHeading')) {
            Assert-WplTest ($source -match $key) "Missing non-urgent advisory wording: $key"
        }
    }

    It 'constructs WPF thickness values with a supported overload' {
        # Windows.Thickness accepts one or four values; two arguments throws at
        # runtime and only surfaces when the dialog is actually opened.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $bad = @([regex]::Matches($source,'New-Object Windows\.Thickness ([0-9]+,[0-9]+)(?![0-9,])') | ForEach-Object { $_.Value })
        Assert-WplTest ($bad.Count -eq 0) "Thickness needs one or four values: $($bad -join ' | ')"
    }

    It 'wires task, list, detail, and scrolling surfaces explicitly' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        foreach ($pattern in @('x:Name="SidebarScroll"','ScrollViewer\.VerticalScrollBarVisibility="Auto"','x:Name="DetailScroll"','Add_PreviewMouseWheel','x:Name="SelectedToolText"','x:Name="FilterAllButton"','x:Name="SnapshotText"')) {
            Assert-WplTest ($source -match $pattern) "GUI contract missing: $pattern"
        }
    }

    It 'declares every named element the code resolves from the XAML' {
        # A restyle that deletes a TextBlock but leaves its $ui lookup behind only
        # fails at runtime, so compare the lookup table against the markup.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $listMatch = [regex]::Match($source,'\$names = @\(([^)]*)\)')
        Assert-WplTest ($listMatch.Success) 'The GUI element name list could not be located.'
        $declared = @([regex]::Matches($listMatch.Groups[1].Value,"'([A-Za-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value })
        Assert-WplTest ($declared.Count -gt 0) 'The GUI element name list is empty.'
        $inMarkup = @([regex]::Matches($source,'x:Name="([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
        $orphaned = @($declared | Where-Object { $_ -notin $inMarkup })
        Assert-WplTest ($orphaned.Count -eq 0) "Named elements resolved in code but absent from the XAML: $($orphaned -join ', ')"
    }
}

Describe 'KO and EN localization contract' {
    It 'pairs every detailed tool guide across KO and EN' {
        $guideNames = @('TESTMEM5','HCI_MEMTEST','LATENCYMON','BATTERYINFOVIEW','WIZTREE','VENTOY','PRIME95','OCCT','NARAEON_DIRTY_TEST','H2TESTW','DDU','SDIO','SD_CARD_FORMATTER','GLARY_UTILITIES')
        $missing = @()
        foreach ($name in $guideNames) {
            foreach ($code in @('ko','en')) {
                $path = Join-Path $root ('docs\{0}\tools\{1}.md' -f $code,$name)
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing += "$code/$name" }
            }
        }
        Assert-WplTest ($missing.Count -eq 0) "Missing tool guides: $($missing -join ', ')"
        foreach ($code in @('ko','en')) {
            $quick = Join-Path $root ('docs\{0}\QUICK_USE.md' -f $code)
            Assert-WplTest (Test-Path -LiteralPath $quick -PathType Leaf) "Missing quick reference: $code"
        }
    }

    It 'maps every guide-backed catalog id to an existing document' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $matched = [regex]::Matches($source,"'(?<id>[a-z0-9-]+)'\s*\{\s*'(?<doc>[A-Z0-9_]+)'\s*\}")
        $data = Get-WplTestData
        $broken = @()
        foreach ($entry in $matched) {
            $id = $entry.Groups['id'].Value
            $doc = $entry.Groups['doc'].Value
            if ($id -notin @($data.Catalog.id)) { continue }
            foreach ($code in @('ko','en')) {
                $path = Join-Path $root ('docs\{0}\tools\{1}.md' -f $code,$doc)
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $broken += "$id -> $code/$doc" }
            }
        }
        Assert-WplTest ($broken.Count -eq 0) "Guide mapping points at missing documents: $($broken -join ', ')"
    }

    It 'contains paired non-empty KO and EN text for every localization key' {
        $source = Get-Content -LiteralPath (Join-Path $root 'scripts\WinPortableLab.Localization.ps1') -Raw
        $declared = @([regex]::Matches($source,'(?m)^\s*([A-Za-z][A-Za-z0-9]*)=@\{') | ForEach-Object { $_.Groups[1].Value })
        $paired = @([regex]::Matches($source,'(?m)^\s*([A-Za-z][A-Za-z0-9]*)=@\{ko=(.+);en=(.+)\}\s*$'))
        Assert-WplTest ($declared.Count -gt 0) 'No localization keys were detected.'
        Assert-WplTest ($paired.Count -eq $declared.Count) 'One or more localization keys lack a KO/EN value on the canonical entry line.'
        foreach ($entry in $paired) {
            Assert-WplTest (-not [string]::IsNullOrWhiteSpace($entry.Groups[2].Value)) "$($entry.Groups[1].Value) has empty KO text."
            Assert-WplTest (-not [string]::IsNullOrWhiteSpace($entry.Groups[3].Value)) "$($entry.Groups[1].Value) has empty EN text."
            $koArgs = @([regex]::Matches($entry.Groups[2].Value,'\{\d+\}') | ForEach-Object Value | Sort-Object -Unique)
            $enArgs = @([regex]::Matches($entry.Groups[3].Value,'\{\d+\}') | ForEach-Object Value | Sort-Object -Unique)
            Assert-WplTest (($koArgs -join ',') -eq ($enArgs -join ',')) "$($entry.Groups[1].Value) has mismatched KO/EN format placeholders."
        }
    }

    It 'defines every literal Get-WplText key used by production scripts' {
        $localization = Get-Content -LiteralPath (Join-Path $root 'scripts\WinPortableLab.Localization.ps1') -Raw
        $defined = @([regex]::Matches($localization,'(?m)^\s*([A-Za-z][A-Za-z0-9]*)=@\{') | ForEach-Object { $_.Groups[1].Value })
        $production = @((Join-Path $root 'WinPortableLab.ps1')) + @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File | Where-Object Name -ne 'WinPortableLab.Localization.ps1' | ForEach-Object FullName) + @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Include '*.ps1','*.psm1' -File -Recurse | ForEach-Object FullName)
        $missing = @()
        foreach ($path in $production) {
            $source = Get-Content -LiteralPath $path -Raw
            foreach ($match in [regex]::Matches($source,'Get-WplText\s+-Key\s+([A-Za-z][A-Za-z0-9]*)')) {
                if ($match.Groups[1].Value -notin $defined) { $missing += "$([IO.Path]::GetFileName($path)):$($match.Groups[1].Value)" }
            }
        }
        Assert-WplTest ($missing.Count -eq 0) "Undefined localization keys: $($missing -join ', ')"
    }
}

Describe 'Network driver recovery contract' {
    It 'gates driver-store writes behind an explicit acknowledgement and elevation' {
        $source = Get-Content -LiteralPath (Join-Path $root 'scripts\Set-WplNetworkDriver.ps1') -Raw
        $restoreBlock = [regex]::Match($source,"(?s)'restore'\s*\{.*")
        Assert-WplTest ($restoreBlock.Success) 'The restore action block could not be located.'
        Assert-WplTest ($restoreBlock.Value -match 'if \(-not \$AcknowledgeRisk\) \{ throw') 'Restore does not refuse to run without -AcknowledgeRisk.'
        Assert-WplTest ($restoreBlock.Value -match 'Test-WplAdministrator') 'Restore does not require administrator rights.'
        $backupBlock = [regex]::Match($source,"(?s)'backup'\s*\{.*?(?='list'\s*\{)")
        Assert-WplTest ($backupBlock.Success) 'The backup action block could not be located.'
        Assert-WplTest ($backupBlock.Value -match 'Test-WplAdministrator') 'Backup does not require administrator rights.'
        Assert-WplTest ($source -notmatch "pnputil.exe /add-driver .*\n.*'backup'") 'Backup must not install drivers.'
    }

    It 'counts only bus-attached adapters so VPN tunnels are not mistaken for hardware' {
        # Win32_NetworkAdapter marks TAP/TUN drivers as PhysicalAdapter, which
        # previously produced ten adapters on a machine that has two real NICs.
        $source = Get-Content -LiteralPath (Join-Path $root 'scripts\Set-WplNetworkDriver.ps1') -Raw
        Assert-WplTest ($source -match "PNPDeviceID -match '\^\(PCI\|USB\|PCMCIA\)") 'The adapter filter no longer restricts to physical buses.'
    }

    It 'keeps exported driver backups out of version control' {
        $ignore = Get-Content -LiteralPath (Join-Path $root '.gitignore') -Raw
        Assert-WplTest ($ignore -match '(?m)^offline-packs/') 'offline-packs is not ignored, so driver exports could be committed.'
    }

    It 'requests elevation only for the two write-capable actions' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match "Action -in @\('backup','restore'\)") 'The GUI no longer scopes the elevation request to backup and restore.'
        Assert-WplTest ($source -match 'x:Name="NetworkDriverButton"') 'The network driver entry point is missing from the sidebar.'
        Assert-WplTest ($source -match 'x:Name="NetBackupCombo"') 'The backup selector is missing from the network driver window.'
    }

    It 'documents the offline workflow in both languages' {
        foreach ($code in @('ko','en')) {
            $path = Join-Path $root ('docs\{0}\NETWORK_DRIVERS.md' -f $code)
            Assert-WplTest (Test-Path -LiteralPath $path -PathType Leaf) "Missing network driver guide: $code"
            $text = Get-Content -LiteralPath $path -Raw
            Assert-WplTest ($text -match 'pnputil') "$code guide does not state the restore mechanism."
            Assert-WplTest ($text -match 'SDIO') "$code guide does not cover the SDIO offline pack workflow."
        }
    }

    It 'points the BIOS check at a model-filtered vendor search rather than a guessed download link' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $function = [regex]::Match($source,'(?s)function Get-WplBiosSearchUrl.*?\n    \}')
        Assert-WplTest ($function.Success) 'Get-WplBiosSearchUrl could not be located.'
        Assert-WplTest ($function.Value -match 'EscapeDataString') 'The model is not URL-encoded before being placed in a query.'
        Assert-WplTest ($function.Value -notmatch '\.(zip|exe|cab)') 'A direct firmware file link was introduced; only search pages are allowed.'
        foreach ($vendor in @('msi','asus','gigabyte','asrock','lenovo','dell')) {
            Assert-WplTest ($function.Value -match $vendor) "No BIOS search destination for $vendor."
        }
        Assert-WplTest ($source -match 'GuiBiosManualSteps') 'The manual BIOS comparison steps are not shown.'
    }

    It 'offers a network one-pack route for every source it names' {
        # A pinned binary URL rots within months, so each entry must be a landing
        # page. A direct .exe here would silently break in the field.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $function = [regex]::Match($source,'(?s)function Get-WplNetworkPackSources.*?\n    \}')
        Assert-WplTest ($function.Success) 'Get-WplNetworkPackSources could not be located.'
        $urls = @([regex]::Matches($function.Value,"Url = '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        Assert-WplTest ($urls.Count -ge 3) "Expected at least three one-pack sources; found $($urls.Count)."
        foreach ($url in $urls) {
            Assert-WplTest ($url -match '^https://') "One-pack source is not HTTPS: $url"
            Assert-WplTest ($url -notmatch '\.(exe|7z|zip)$') "One-pack source pins a binary that will rot: $url"
        }
        foreach ($key in @('GuiNetPack3dpDesc','GuiNetPackSdioDesc','GuiNetPackDrvceoDesc')) {
            Assert-WplTest ($source -match $key) "Missing description binding: $key"
        }
        Assert-WplTest ($source -match 'GuiNetDriverOnePackAction') 'The one-pack action is not wired into the network driver window.'
    }

    It 'runs the first status probe after the window is rendered' {
        # Calling the probe inline blocked on a hidden child process before
        # ShowDialog, so the dialog stayed invisible until the probe finished.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $function = [regex]::Match($source,'(?s)function Show-GuiNetworkDriver.*?\[void\]\$netWindow\.ShowDialog\(\)')
        Assert-WplTest ($function.Success) 'Show-GuiNetworkDriver could not be located.'
        Assert-WplTest ($function.Value -match 'Add_ContentRendered') 'The initial status probe is not deferred to ContentRendered.'
        $inline = [regex]::Match($function.Value,"(?m)^\s*& \`$runAction 'status' '' \`$false\s*$")
        Assert-WplTest (-not $inline.Success) 'A blocking inline status probe was reintroduced before ShowDialog.'
    }

    It 'documents every one-pack source in both languages' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $function = [regex]::Match($source,'(?s)function Get-WplNetworkPackSources.*?\n    \}')
        $urls = @([regex]::Matches($function.Value,"Url = '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        foreach ($code in @('ko','en')) {
            $text = Get-Content -LiteralPath (Join-Path $root ('docs\{0}\NETWORK_DRIVERS.md' -f $code)) -Raw
            foreach ($url in $urls) {
                Assert-WplTest ($text -match [regex]::Escape($url)) "$code guide does not document the source $url"
            }
        }
    }

    It 'reports split community reputation instead of only the favourable half' {
        # A source is kept or dropped on evidence, so the card must carry both
        # sides where communities disagree, plus the responsibility notice.
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        $function = [regex]::Match($source,'(?s)function Get-WplNetworkPackSources.*?\n    \}')
        Assert-WplTest ($function.Success) 'Get-WplNetworkPackSources could not be located.'
        $reputationKeys = @([regex]::Matches($function.Value,"ReputationKey = '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $urls = @([regex]::Matches($function.Value,"Url = '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        Assert-WplTest ($reputationKeys.Count -eq $urls.Count) 'Every one-pack source must declare a reputation entry.'
        $localization = Get-Content -LiteralPath (Join-Path $root 'scripts\WinPortableLab.Localization.ps1') -Raw
        foreach ($key in $reputationKeys) {
            Assert-WplTest ($localization -match ('(?m)^\s*' + [regex]::Escape($key) + '=@\{')) "Undefined reputation key: $key"
        }
        foreach ($key in @('GuiNetPackOfficialOnly','GuiNetPackUserResponsibility')) {
            Assert-WplTest ($source -match $key) "The one-pack window does not show $key."
        }
        # The contested entry must name both the favourable and the critical view.
        $drvceo = [regex]::Match($localization,'(?m)^\s*GuiNetPackDrvceoReputation=@\{.*$')
        Assert-WplTest ($drvceo.Success) 'GuiNetPackDrvceoReputation is missing.'
        Assert-WplTest ($drvceo.Value -match '(?i)PUP') 'The DrvCeo reputation omits the PUP classification.'
        Assert-WplTest ($drvceo.Value -match '(?i)reddit') 'The DrvCeo reputation omits the critical community view.'
    }

    It 'documents the split reputation and responsibility notice in both languages' {
        foreach ($code in @('ko','en')) {
            # Windows PowerShell 5.1 decodes -Raw with the ANSI code page, which
            # mangles Hangul before the match. Read UTF-8 explicitly on both hosts.
            $text = Get-Content -LiteralPath (Join-Path $root ('docs\{0}\NETWORK_DRIVERS.md' -f $code)) -Raw -Encoding utf8
            Assert-WplTest ($text -match '(?i)PUP') "$code guide omits the PUP classification for automatic driver installers."
            # The KO guide names Reddit in Hangul, so both spellings are accepted.
            Assert-WplTest ($text -match '(?i)reddit' -or $text -match '\ub808\ub527') "$code guide omits the critical community view."
            Assert-WplTest ($text -match '(?i)sysceo\.com') "$code guide does not pin the official DrvCeo source."
        }
    }

    It 'keeps the advertised test count in step with the suite' {
        # A README that claims a stale number is a small lie that survives for
        # months, so the count is asserted against the actual test total.
        $readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw -Encoding utf8
        $suite = Get-Content -LiteralPath (Join-Path $root 'tests\Core.Tests.ps1') -Raw -Encoding utf8
        $actual = @([regex]::Matches($suite,'(?m)^\s{4}It\s')).Count
        Assert-WplTest ($actual -gt 0) 'No It blocks were detected in the suite.'
        $claimed = @([regex]::Matches($readme,'(?:(\d+)\s*tests|\ud14c\uc2a4\ud2b8\s*(\d+)\uac1c)') | ForEach-Object {
            if ($_.Groups[1].Success) { [int]$_.Groups[1].Value } else { [int]$_.Groups[2].Value }
        })
        Assert-WplTest ($claimed.Count -gt 0) 'The README does not state a test count in either language.'
        $wrong = @($claimed | Where-Object { $_ -ne $actual } | Sort-Object -Unique)
        Assert-WplTest ($wrong.Count -eq 0) "README claims test count $($wrong -join ', ') but the suite has $actual."
    }

    It 'creates runtime directories instead of tracking empty placeholders' {
        # Empty .gitkeep files existed only to hold the tree open in git. The
        # console creates these directories on first run, so a fresh clone must
        # not depend on tracked placeholders.
        $module = Get-Content -LiteralPath (Join-Path $root 'src\WinPortableLab.Core.psm1') -Raw
        Assert-WplTest ($module -match 'function Initialize-WplRuntimeDirectory') 'Initialize-WplRuntimeDirectory is missing.'
        Assert-WplTest ($module -match 'Export-ModuleMember[^\r\n]*Initialize-WplRuntimeDirectory') 'Initialize-WplRuntimeDirectory is not exported.'
        $function = [regex]::Match($module,'(?s)function Initialize-WplRuntimeDirectory.*?\n\}')
        Assert-WplTest ($function.Success) 'Initialize-WplRuntimeDirectory body could not be located.'
        foreach ($directory in @('tools','reports','recommendations','sessions','logs')) {
            Assert-WplTest ($function.Value -match "'$directory'") "Runtime directory not created on demand: $directory"
        }
        # Both entry points must prepare the tree before writing anything.
        foreach ($entry in @('WinPortableLab.ps1','scripts\Test-Repository.ps1')) {
            $source = Get-Content -LiteralPath (Join-Path $root $entry) -Raw
            Assert-WplTest ($source -match 'Initialize-WplRuntimeDirectory') "$entry does not create the runtime directories."
        }
    }

    It 'tracks no empty placeholder files and keeps the tools documentation' {
        $tracked = @(& git -C $root ls-files)
        Assert-WplTest ($tracked.Count -gt 0) 'git ls-files returned nothing.'
        $placeholders = @($tracked | Where-Object { $_ -match '(^|/)\.gitkeep$' })
        Assert-WplTest ($placeholders.Count -eq 0) "Tracked placeholder files reappeared: $($placeholders -join ', ')"
        # The per-folder purpose documents are real bilingual content, not
        # placeholders, so they must survive the cleanup.
        $toolDocs = @($tracked | Where-Object { $_ -match '^tools/\d{2}-[^/]+/README\.md$' })
        Assert-WplTest ($toolDocs.Count -eq 9) "Expected 9 tools folder guides; found $($toolDocs.Count)."
    }
}

Describe 'Elevated launch integrity contract' {
    It 'requires acknowledgement before a user-declared path backs a launcher' {
        # config/user-tool-paths.json is per-machine, unsigned, and lives on the
        # removable medium. Without this gate a read-only tool repointed by that
        # file would start elevated with no prompt at all.
        $module = Get-Content -LiteralPath (Join-Path $root 'src\WinPortableLab.Core.psm1') -Raw
        Assert-WplTest ($module -match 'function Get-WplToolOverrideTrust') 'Get-WplToolOverrideTrust is missing.'
        Assert-WplTest ($module -match 'Export-ModuleMember[^\r\n]*Get-WplToolOverrideTrust') 'Get-WplToolOverrideTrust is not exported.'
        $trust = [regex]::Match($module,'(?s)function Get-WplToolOverrideTrust.*?\n\}')
        Assert-WplTest ($trust.Success) 'Get-WplToolOverrideTrust body could not be located.'
        Assert-WplTest ($trust.Value -match 'InsideToolsRoot') 'The trust record does not report tools-root containment.'
        Assert-WplTest ($trust.Value -match 'Get-AuthenticodeSignature') 'The trust record does not inspect the signature.'
        # Containment decides trust; the signature is reported but not required.
        # Many bundled diagnostics ship unsigned, so requiring a signature would
        # prompt on nearly every legitimate override and train operators to click
        # through the warning.
        Assert-WplTest ($trust.Value -match 'IsTrusted = \$insideTools') 'Trust must be decided by tools-root containment alone.'
        Assert-WplTest ($trust.Value -notmatch "IsTrusted = \(\`$insideTools -and") 'A signature requirement was reintroduced into the trust decision.'
        $cli = Get-Content -LiteralPath (Join-Path $root 'scripts\Open-PortableTool.ps1') -Raw
        Assert-WplTest ($cli -match 'UntrustedOverrideBlocked') 'The CLI launcher does not gate an untrusted override.'
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest (@([regex]::Matches($gui,'GuiOverrideConfirm')).Count -ge 1) 'The individual GUI launch path must confirm an untrusted override.'
    }

    It 'refuses an unpinned or mismatched download instead of skipping the check' {
        # The comparison used to be conditional on the manifest declaring a hash,
        # so a definition without sha256 downloaded and extracted unverified.
        $installer = Get-Content -LiteralPath (Join-Path $root 'scripts\Install-PortableTools.ps1') -Raw
        Assert-WplTest ($installer -notmatch '\$package\.source\.sha256 -and \$hash -ne') 'The hash check is still skipped when no pin is declared.'
        Assert-WplTest ($installer -match "expected -notmatch '\^\[0-9a-fA-F\]\{64\}\$'") 'The installer does not require a 64-hex pin.'
        $verify = [regex]::Match($installer,'(?s)\$expected = \[string\]\$package\.source\.sha256.*?\n    \}')
        Assert-WplTest ($verify.Success) 'The verification block could not be located.'
        Assert-WplTest ($verify.Value -match 'Remove-Item') 'A rejected archive is left on disk for a later unverified run.'
    }

    It 'keeps executable resolution and the safe-launch rule in one place' {
        # The GUI used to reimplement override reading and pattern matching, and
        # the copies had drifted on both file-type filtering and the path root.
        $gui = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($gui -notmatch 'function Get-WplUserToolPathMap') 'The duplicated override reader is back.'
        Assert-WplTest ($gui -match 'function Get-WplUserToolPath[^\r\n]*\r?\n[^}]*Get-WplToolOverride -Root') 'The GUI override lookup no longer delegates to the module.'
        Assert-WplTest ($gui -match 'function Get-WplSafeLaunchIds') 'The safe-launch rule is not centralised.'
        # Count the launchMode clause: it is unique to the safe-launch rule.
        $copies = @([regex]::Matches($gui,"launchMode -eq 'gui' -and")).Count
        Assert-WplTest ($copies -eq 1) "The safe-launch predicate is written $copies times; it must exist once."
        $inventory = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-Inventory.ps1') -Raw
        $pnp = @([regex]::Matches($inventory,'\$inventory\.PnpProblems \| ConvertTo-Html')).Count
        Assert-WplTest ($pnp -eq 1) "The PnP table is rendered $pnp times in the report; it must render once."
    }
}
