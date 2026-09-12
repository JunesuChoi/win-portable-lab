# Native memory cleanup

OnePack implements all eight cleanup regions MemReduct exposes, through the same native API calls inside the console. It does not bundle or download a separate executable, and it performs one operator-selected cleanup rather than running in the background.

## What it does

`WinPortableLab.Memory.psm1` calls `NtSetSystemInformation` with `SystemMemoryListInformation` (class 80), `SystemFileCacheInformationEx` (class 81), `SystemCombinePhysicalMemoryInformation` (class 130) and `SystemRegistryReconciliationInformation` (class 155), plus Windows `SetSystemFileCacheSize`, `EmptyWorkingSet`, `CreateFile` and `FlushFileBuffers`. It captures a snapshot before and after the request and records success, failure and skipped status for every operation. The action is temporary; it does not alter any registry value or persistent setting.

Actual cleanup needs administrator rights and `SeProfileSingleProcessPrivilege` in the process token, which covers the working-set, memory-list and combined-memory regions. System file-cache cleanup also needs `SeIncreaseQuotaPrivilege`. A standard user can still view the summary and create a `-Report` plan.

## Areas and when to use them

| Area | Operation | When it fits |
|---|---|---|
| `WorkingSet` | Trims process working sets | Before a short diagnostic comparison when rereading application pages is acceptable |
| `SystemFileCache` | Flushes the file cache, then restores the previous minimum, maximum and flags | Cache-impact comparisons; part of the MemReduct default mask |
| `ModifiedFileCache` | Flushes the write cache of every mounted volume | When file-system writes should be forced to complete first |
| `ModifiedPageList` | Flushes modified pages waiting for disk write | Opt-in freeze region; only after writes have finished and a comparison is needed |
| `StandbyList` | Purges reusable standby cache pages | Opt-in freeze region; a one-off comparison where immediate available memory matters more than cache reuse |
| `LowPriorityStandbyList` | Purges only low-priority standby pages | A narrower comparison that should not touch the whole standby list |
| `RegistryCache` | Flushes pending registry hives to disk (Windows 8.1+) | Before a registry-heavy comparison; changes no registry value |
| `CombineMemoryLists` | Asks the kernel to combine its physical memory lists (Windows 10+) | Reduces physical-memory fragmentation; part of the MemReduct default mask |

The default `Combined` plan is the MemReduct default mask: `WorkingSet`, `SystemFileCache`, `ModifiedFileCache`, `LowPriorityStandbyList`, `RegistryCache` and `CombineMemoryLists`. Only `StandbyList` and `ModifiedPageList` - the two regions MemReduct also calls freezes - are left out, and `-AcknowledgeRisk` is required to execute them. `RegistryCache` and `CombineMemoryLists` report themselves as skipped instead of running on a Windows build that does not provide them. Add `-ProcessId` to target individual processes. If a protected process handle cannot be opened, that process is skipped and the count is included in the result instead of failing the whole request.

Every real run appends to `logs\memory-cleanup-stats.json`, which records the run count, the cumulative freed memory and the timestamp of the last cleanup - the same statistics MemReduct keeps in its configuration file.

## Automatic cleanup and resident monitoring

Automatic cleanup is opt-in. The `memoryAutoCleanup` block in `config\settings.json` stores the threshold, cooldown, check interval and target regions, and its defaults are the same 90 percent, 30 seconds and 30 seconds Mem Reduct uses for automatic reduction. Once usage crosses the threshold and the cooldown has elapsed, only the default plan runs. The standby list and the modified page list stay out of the automatic plan, so an unattended run never discards reclaimable pages without an acknowledgement.

Save the preference in the `Automatic cleanup and resident monitoring` area of the GUI, or run the same decision once from the console:

```powershell
.\WinPortableLab.ps1 -Action memory-auto -Report -Json -Language en
.\WinPortableLab.ps1 -Action memory-auto -Language en
```

`-Report` prints the decision only and performs no cleanup. Resident monitoring runs while the GUI window is open, and the notification-area icon offers open, clean now, toggle automatic cleanup and exit. Selecting `Register for Windows startup` starts the pack in the tray at logon. The registration is a single `HKCU` `Run` value, so it needs no administrator rights and the same screen removes it again. That value is the only permanent trace the pack leaves on a host, and removing it leaves nothing behind.

## What it does not do

- It does not write registry values or system settings such as `ClearPageFileAtShutdown`, `LargeSystemCache` or `DisablePagingExecutive`. Flushing the registry cache writes no value; it only lowers pending hives to disk.
- It is not a memory-leak diagnostic tool. Leaks require per-process tracing and observation over time.
- It is not a stability test. Use TestMem5, OCCT and the other dedicated tools for RAM, CPU and GPU validation.
- It does not resize the page file or change prefetch, services or power plans.

Cleanup is temporary cache reclamation. Windows may reread data from storage when it is needed again, so the first launch after cleanup can be slower. There is no setting to restore and no reboot is required.

## Command line

Create a plan without administrator rights:

```powershell
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Report -Language en
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Report -Json -Language en
```

Run the default combined operation from an elevated PowerShell after acknowledging the risk:

```powershell
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area Combined -AcknowledgeRisk -Language en
```

Working-set-only cleanup does not require the risk acknowledgement:

```powershell
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet -Language en
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet -ProcessId 1234,5678 -Language en
```

`-Json` prints the snapshots, delta, per-area results and the running statistics as JSON. Every request is also written to `logs\memory-cleanup-<timestamp>.json`. Since the action makes no persistent system change, there is no restore command.

## Comparison with MemReduct

| Capability | This feature | Relationship to MemReduct |
|---|---|---|
| Working-set cleanup | Supported (`WorkingSet`) | Same `MemoryEmptyWorkingSets` command MemReduct issues for `REDUCT_WORKINGSET` |
| Modified page list | Supported (`ModifiedPageList`) | Same command value 3 MemReduct issues for `REDUCT_MODIFIEDLIST` |
| Standby lists | Supported (`StandbyList`, `LowPriorityStandbyList`) | Same command values 4 and 5 MemReduct issues for `REDUCT_STANDBYLIST` and `REDUCT_STANDBYPRIORITY0LIST` |
| System file cache | Supported (`SystemFileCache`) | Same flush MemReduct requests with `SystemFileCacheInformationEx`; this implementation reads the current limits first and restores them |
| Volume write cache | Supported (`ModifiedFileCache`) | Same volume-cache flush as `REDUCT_MODIFIEDFILECACHE`, reached through the documented `CreateFile`/`FlushFileBuffers` pair instead of the mount-manager IOCTL |
| Registry cache | Supported (`RegistryCache`) | Same `SystemRegistryReconciliationInformation` call as `REDUCT_REGISTRYCACHE`, with the same Windows 8.1 gate |
| Combined memory lists | Supported (`CombineMemoryLists`) | Same `SystemCombinePhysicalMemoryInformation` call as `REDUCT_COMBINEMEMORYLISTS`, with the same Windows 10 gate |
| Cleanup statistics | Supported (`logs\memory-cleanup-stats.json`) | Same run count, cumulative freed memory and last-cleanup timestamp MemReduct keeps |
| Individual processes | Supported (`EmptyWorkingSet`, `-ProcessId`) | Adds a focused complement to the whole-system operation |
| Automatic cleanup | Supported (`memory-auto`, 90 percent threshold, 30-second cooldown) | Same defaults as Mem Reduct automatic reduction, limited to the default plan |
| Resident monitoring and tray icon | Supported (`-StartMinimized`, notification-area menu) | Stays resident like Mem Reduct and keeps watching after the window is closed |
| Windows startup registration | Supported (`scripts\Set-WplStartup.ps1`, one HKCU Run value) | Starts in the tray at logon, needs no administrator rights and removes cleanly |
| Global hotkeys | Intentionally excluded | The tray menu offers the same actions without installing a keyboard hook in a resident process |
| Registry value and system-settings changes | Scope unchanged | `ClearPageFileAtShutdown`, `LargeSystemCache` and `DisablePagingExecutive` are still never written; the only exception is the startup value above |
| Default mask | `Combined` equals `REDUCT_MASK_DEFAULT` | The same six regions run by default; the two freezes stay opt-in |
| Third-party executable | Intentionally excluded | No MemReduct binary is bundled or downloaded; Win32/NT APIs are called directly |
| Modal confirmation dialog | Intentionally excluded | The GUI uses an inline risk acknowledgement and inline result text |

`NtSetSystemInformation` is an internal API that is not declared in the Windows SDK, so behavior can vary by Windows version. Each status and snapshot is recorded, and a failure is not replaced with a speculative registry or system-setting change. The declaration and file-cache flush semantics were checked against [Microsoft Learn's NtSetSystemInformation](https://learn.microsoft.com/en-us/windows/win32/sysinfo/ntsetsysteminformation) and [SetSystemFileCacheSize](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setsystemfilecachesize).
