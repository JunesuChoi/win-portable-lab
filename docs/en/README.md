# WinPortableLab English guide

## Commands

```powershell
.\Start.cmd -Mode inventory -Language en
.\Start.cmd -Mode recommend -Language en
.\Start.cmd -Mode validate -Language en
.\Start.cmd -Mode launch -Language en
.\Start.cmd -Mode smart -Language en
.\WinPortableLab.ps1 -Action check -Profile quick -Language en
.\WinPortableLab.ps1 -Action menu -Profile all -Language en
```

The integrated `WinPortableLab.ps1` checks system information and recent error signals, then creates settings guidance plus `recommended-programs.json` containing resolved executable paths.

Running `WinPortableLab.ps1` without arguments opens the persistent **ONEPACK PORTABLE KOREA** WPF dashboard. It remains open after analysis and provides profile scans, selected-tool launch, safe recommended launch, reports and GitHub project access as buttons.

Quick, All, Storage, Memory and GPU reuse the completed system snapshot and rebuild only the recommended-program list. Use **Refresh system information** only after hardware, driver or Windows state changes. The memory card shows capacity, DDR generation, DIMM count, operating rate and each module size; hover it for slot, vendor, part number, voltage and serial details.

The default launch requests administrator privileges through Windows UAC. Once approved, the report includes storage reliability, volumes and partitions, TPM, BitLocker protection status, Device Guard, signed drivers, device problems, recent hotfixes, page files and the active power plan. BitLocker recovery keys are never collected. Use `-NoElevation` only for an intentionally limited standard-user report.

```powershell
.\WinPortableLab.ps1 -Action list -Profile storage -Language en
.\WinPortableLab.ps1 -Action launch -ToolId hwinfo -Language en
.\WinPortableLab.ps1 -Action launch-recommended -Profile quick -Language en
.\WinPortableLab.ps1 -Action launch -ToolId prime95 -AcknowledgeRisk -Language en
```

`launch-recommended` opens read-only GUI tools only. Prime95, OCCT, storage writes, DDU and XTU/Ryzen Master installers are excluded from automatic safe launch.

The recommendation command reads Windows CIM hardware information and writes a JSON recommendation plus Korean and English Markdown files. It never applies firmware or tuning settings.

## Updates, offline packs, and supervised launches

~~~powershell
.\scripts\Test-ToolUpdates.ps1 -Root .
.\scripts\Test-ToolUpdates.ps1 -Root . -Online
.\scripts\New-OfflinePack.ps1 -Root . -IncludeRedistributableArchives
.\scripts\Start-WplToolSession.ps1 -Root . -LauncherId occt
.\scripts\Start-WplToolSession.ps1 -Root . -LauncherId occt -Start -AcceptRisk
.\scripts\Test-ToolLaunchers.ps1 -Root . -SmokeReadOnlyGui -Language en
~~~

Supervised launches are recorded under sessions and enforce the default 30-minute timeout, a minimum-free-memory threshold, and cancellation requests. GUI tools use the executable directory as their working directory so adjacent DLL and configuration files resolve correctly. CLI tools run in a visible console, save `console-output.txt`, and remain open for review when started from the dashboard. Use HWiNFO alone for the sensor baseline and load-temperature monitoring. HWiNFO shared-memory integration is not used as an automatic stop condition because its availability depends on licensing and run-time limits.

TrafficMonitor Lite observes network throughput and CPU, RAM, GPU and disk use in the taskbar. ZenTimings is recommended only on AMD Ryzen and requires administrator rights to inspect applied memory timings. On Intel systems, use CPU-Z, HWiNFO and the detailed DIMM report instead.

The hardware cards query OS, CPU, board, BIOS, GPU, memory and disks independently. A failed CIM class no longer clears every card; individual failures are written to `logs/gui-hardware-latest.log`, while full recommendation failures are recorded in `logs/gui-analysis-latest.log`. A tool launch is shown as successful only after the supervisor confirms the target PID. When the dashboard is not elevated, the launch supervisor requests UAC before starting the selected tool.

PowerShell sources use UTF-8 with BOM for consistent rendering in Windows PowerShell 5.1 and PowerShell 7. Validation rejects malformed UTF-8, replacement characters, common mojibake sequences and non-ASCII PowerShell files without a BOM. The dashboard uses three task, recommendation-list and selected-tool panes with snapshot freshness, search/filter chips, automatic first selection and fixed launch actions.

## Guides

- [System-specific recommendation guide](SETTING_GUIDE.md)
- [Intel CPU](../guides/CPU_INTEL.md)
- [AMD CPU](../guides/CPU_AMD.md)
- [GPU and DDU](../guides/GPU_DDU.md)
- [RAM overclocking](../guides/RAM_OVERCLOCK.md)
- [SSD dirty, sustained-write and integrity tests](SSD_DIRTY_TEST.md)
- [Safety policy](../SAFETY_POLICY.md)
- [Tool setup](../tooling/SETUP_GUIDES.md)
