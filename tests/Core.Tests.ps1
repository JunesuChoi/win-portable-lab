# Pester 5 and newer run each Describe block in an isolated scope, so shared
# helpers must be registered where every block can see them. BeforeAll covers
# Pester 5/6 while the direct invocation keeps the bundled Pester 3.4 working.
$script:WplTestSetup = {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:root 'src\WinPortableLab.Core.psm1') -Force

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
        Assert-WplTest ($gui -match '\$sessionArguments = ''-NoLogo .+ -File "\{0\}" -Root "\{1\}"') 'Session command line does not quote script/root paths.'
        Assert-WplTest ($gui -notmatch '\$sessionScript = ''"\{0\}"''') 'Script path is still stored as a literal quoted array element.'
        Assert-WplTest ($session -match '\$launchers = @\(foreach \(\$item in \$launcherDocument\) \{ \$item \}\)') 'PS 5.1 JSON array normalization is missing.'
    }

    It 'isolates every safe batch launch failure from the WPF dispatcher' {
        $source = Get-Content -LiteralPath (Join-Path $root 'WinPortableLab.ps1') -Raw
        Assert-WplTest ($source -match 'function Open-ToolIds[\s\S]+?foreach[\s\S]+?try[\s\S]+?catch[\s\S]+?if \(-not \$ContinueOnError\) \{ throw \}') 'Open-ToolIds does not isolate each item when ContinueOnError is set.'
        Assert-WplTest ($source -match 'Open-ToolIds -Ids \$safe -UseLanguage \$script:GuiLanguage -ContinueOnError') 'Safe launch does not request per-tool error continuation.'
        Assert-WplTest ($source -match 'logs\\safe-launch-latest\.json') 'Safe launch result logging is missing.'
        Assert-WplTest ($source -match 'finally \{\s*\$ui\.SafeLaunchButton\.IsEnabled = \$true') 'Safe launch button is not restored in finally.'
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
        $guideNames = @('TESTMEM5','HCI_MEMTEST','LATENCYMON','BATTERYINFOVIEW','WIZTREE','VENTOY','PRIME95','OCCT','NARAEON_DIRTY_TEST','H2TESTW','DDU','SDIO','GLARY_UTILITIES')
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
