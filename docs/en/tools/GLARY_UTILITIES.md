# Glary Utilities Portable detailed usage

A maintenance suite that shows startup entries, disk usage and system information on one surface. In this project it is used **for read-only inspection only**. The cleanup and deletion features can destroy diagnostic evidence and are out of scope.

Launch id is `glary-utilities`, risk is system changing.

## Features used here

| Feature | Purpose | Character |
|---|---|---|
| Startup Manager | Review what runs at boot | Read, then optionally disable |
| Disk Analysis | Disk usage distribution | Read-only |
| System Information | Hardware and OS summary | Read-only |
| Process Manager | Review running processes | Read-only |

Startup Manager helps when boot is slow. It lists fewer entries than Autoruns, which also makes it easier to read. Use Autoruns when precise tracing is required.

## Features not used

The package also ships the following, which conflict with this project's principles.

| Feature | Why it is avoided |
|---|---|
| Registry Cleaner | Benefit is unproven and the change is hard to undo |
| 1-Click Maintenance | Applies many changes at once, making them untraceable |
| Disk Cleaner | Can delete the logs and dumps that diagnosis depends on |
| Tracks Eraser | Deletes activity records and obstructs root-cause work |
| File Shredder | Unrecoverable deletion |
| Boot Defrag | Loads a kernel driver (`BootDefragDriver.sys`) |
| Uninstaller | Removing programs exceeds an inspection remit |
| Registry Defrag | Rewrites the registry during reboot |

Disk Cleaner and Tracks Eraser deserve particular care. This project treats event logs and minidumps as diagnostic evidence, and those features can erase exactly that. **Running a cleaner before inspection makes the cause unfindable.**

## Cautions when running

1. Do not press the 1-Click Maintenance button on the first screen; it runs several cleanup actions together.
2. Open only the individual features you need from the Advanced Tools tab.
3. The free edition shows paid-upgrade prompts and some features may be limited.
4. Despite being portable, some features load services or drivers, so a completely trace-free run is not guaranteed.

## Licence

Free for personal use; business use requires a licence. This project does not include it in the offline pack.

## Relationship to other tools

Sysinternals Autoruns is more precise for startup analysis, Process Explorer for process detail, and WizTree for disk space. Glary's advantage is convenience when skimming several areas at once, so use it for an initial overview and hand precise analysis to the dedicated tools.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id glary-utilities -AcknowledgeRisk -Language en
```

