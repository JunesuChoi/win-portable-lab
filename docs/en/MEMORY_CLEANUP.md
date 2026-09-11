# Native memory cleanup

OnePack includes the core Windows memory-list cleanup that users commonly reach for in MemReduct, implemented with native API calls inside the console. It does not bundle or download a separate executable, and it performs one operator-selected cleanup rather than running in the background.

## What it does

`WinPortableLab.Memory.psm1` calls `NtSetSystemInformation` with `SystemMemoryListInformation` (information class 80), plus Windows `EmptyWorkingSet` and `SetSystemFileCacheSize`. It captures a snapshot before and after the request and records success, failure and skipped status for every operation. The action is temporary; it does not alter the registry or persistent settings.

Actual cleanup needs administrator rights and `SeProfileSingleProcessPrivilege` in the process token. System file-cache cleanup also needs `SeIncreaseQuotaPrivilege`. A standard user can still view the summary and create a `-Report` plan.

## Areas and when to use them

| Area | Operation | When it fits |
|---|---|---|
| `WorkingSet` | Trims process working sets | Before a short diagnostic comparison when rereading application pages is acceptable |
| `SystemWorkingSet` | Trims the Windows system working set | When comparing an unusually large system working set |
| `ModifiedPageList` | Flushes modified pages waiting for disk write | Only after writes have finished and a comparison is needed |
| `StandbyList` | Purges reusable standby cache pages | A one-off comparison where immediate available memory matters more than cache reuse |
| `LowPriorityStandbyList` | Purges only low-priority standby pages | A narrower comparison that should not touch the whole standby list |
| `SystemFileCache` | Flushes the file cache, then restores the previous minimum, maximum and flags | Excluded by default; select explicitly only when file-cache impact is part of the comparison |

The default `Combined` plan contains `WorkingSet`, `SystemWorkingSet`, `ModifiedPageList`, `StandbyList` and `LowPriorityStandbyList`. It excludes the system file cache. `-AcknowledgeRisk` is required to execute standby, modified-list or file-cache operations. Add `-ProcessId` to target individual processes. If a protected process handle cannot be opened, that process is skipped and the count is included in the result instead of failing the whole request.

## What it does not do

- It does not write registry or system settings such as `ClearPageFileAtShutdown`, `LargeSystemCache` or `DisablePagingExecutive`.
- It does not run automatically, at boot, on a threshold, or through a scheduled task.
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
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet,SystemWorkingSet -Language en
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet -ProcessId 1234,5678 -Language en
```

`-Json` prints the snapshots, delta and per-area results as JSON. Every request is also written to `logs\memory-cleanup-<timestamp>.json`. Since the action makes no persistent system change, there is no restore command.

## Comparison with MemReduct

| Capability | This feature | Relationship to MemReduct |
|---|---|---|
| Working-set cleanup | Supported (`WorkingSet`, `SystemWorkingSet`) | Uses the same Windows memory-list working-set command as the core MemReduct operation |
| Modified page list | Supported (`ModifiedPageList`) | Same command value 3 used for the modified list |
| Standby lists | Supported (`StandbyList`, `LowPriorityStandbyList`) | Same command values 4 and 5 for standby and low-priority standby |
| System file cache | Supported when explicitly selected; excluded by default | Flushes with `SetSystemFileCacheSize(-1,-1,0)`, then restores the values and flags read before the call |
| Individual processes | Supported (`EmptyWorkingSet`, `-ProcessId`) | Adds a focused complement to the whole-system operation |
| Automatic or scheduled cleanup | Intentionally excluded | Project rule: no automatic execution or scheduled tasks |
| Registry cache and registry settings | Intentionally excluded | Project rule: no settings changes and no registry writes |
| Third-party executable | Intentionally excluded | No MemReduct binary is bundled or downloaded; Win32/NT APIs are called directly |
| Modal confirmation dialog | Intentionally excluded | The GUI uses an inline risk acknowledgement and inline result text |

`NtSetSystemInformation` is an internal API that is not declared in the Windows SDK, so behavior can vary by Windows version. Each status and snapshot is recorded, and a failure is not replaced with a speculative registry or system-setting change. The declaration and file-cache flush semantics were checked against [Microsoft Learn's NtSetSystemInformation](https://learn.microsoft.com/en-us/windows/win32/sysinfo/ntsetsysteminformation) and [SetSystemFileCacheSize](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setsystemfilecachesize).
