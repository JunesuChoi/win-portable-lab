# Snappy Driver Installer Origin (SDIO) detailed usage

Scans installed drivers and finds what is missing or outdated. Its defining strength is working offline once driver packs have been fetched in advance. Reach for it when Device Manager still shows unknown devices after a reinstall.

Launch id is `sdio`, risk is system changing with a reboot.

## The governing principle

**Keep scanning and installing apart.** Scanning is read-only and safe; installing replaces drivers and is awkward to undo.

1. Create a system restore point before installing. Leaving the tool's restore-point option enabled is the safer default.
2. On notebooks, avoid overwriting vendor drivers with generic ones. Brightness control, external outputs and power management can break.
3. Do not update graphics drivers here; installing the vendor's official driver directly is more reliable.

## Preparing driver packs

The program alone has no drivers to install. Packs must be fetched separately.

| Approach | Size | Suits |
|---|---|---|
| Full driver pack set | Tens of GB | Offline field work across many machines |
| Selected packs only | A few GB | Resolving one specific device |
| Index only, install online | Small | Environments with internet access |

This project does not bundle driver packs; they are very large and change often. Fetch them from inside the tool when needed.

## Reading the display

| Indicator | Meaning |
|---|---|
| Green | Current driver is up to date or appropriate |
| Blue | A newer driver exists |
| Yellow | Recommended but worth judging carefully |
| Red | Driver missing or faulty |
| Expert mode | Choose individual driver versions manually |

Red entries are the real problems. Blue often needs no action; replacing a working driver with the newest one is a common source of new faults.

## Recommended procedure

1. Run as administrator.
2. Fetch driver packs or the index.
3. Review the scan result only. Nothing has changed on the system yet.
4. Select just the missing drivers shown in red.
5. Confirm the restore-point option, then install.
6. After rebooting, confirm the problem markers cleared in Device Manager.

## Never use this

The package includes `SDIO_auto.bat`, which installs drivers in bulk without confirmation. This project forbids automatic execution, so that batch file is not used. Drivers replaced without knowing what changed make a fault impossible to trace.

## Relationship to other tools

DriverStore Explorer handles duplicate packages in the driver store. DDU handles complete graphics driver removal. To judge whether a driver causes a performance problem, gather evidence with LatencyMon first. Keeping SDIO to the role of "finding and filling missing drivers" is the safer use.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id sdio -AcknowledgeRisk -Language en
```

