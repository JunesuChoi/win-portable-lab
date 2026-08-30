# System-specific recommendation files

Run:

```powershell
.\Start.cmd -Mode recommend -Language en
```

The generated values are conservative starting points, not a promise of stability and not an executable BIOS profile.

If recent seven-day WHEA or Kernel-Power 41 events are detected, `recommendationMode` becomes `diagnostic-baseline-only`. Treat that state as a stock-setting diagnosis route, not an overclock recommendation. All detection and file generation remain local; nothing is uploaded.

## Fixed baseline values

| Area | Initial value |
| --- | --- |
| CPU profile | Auto/Default, or Intel Default Settings on detected 13th/14th Gen Intel desktop routes |
| Manual CPU voltage | Unset / Auto |
| Fixed CPU ratio | Unset / Auto |
| AMD PBO | Auto |
| AMD Curve Optimizer | 0 |
| Memory | JEDEC/Auto first; XMP/EXPO Profile 1 only after the stock baseline |
| Sensor sampling | 1 second |
| Idle baseline | 10 minutes |
| CPU smoke / mixed / extended | 10 / 30 / 60 minutes |
| Memory smoke / varied patterns | 10 / 60 minutes |
| Bootable memory test | 4 passes |
| Cold boot validation | 3 cycles |
| Storage test | 1 GiB bounded test file, 3 runs; never a raw disk target |
| Allowed calculation, memory, or new WHEA errors | 0 |

Temperature limits are intentionally not guessed. Use the exact CPU/GPU limit for the detected model and stop on throttling, sensor failure, calculation error, WHEA, crash, reboot, BSOD, or corruption.

The JSON contains `applyAllowed: false`. Any future importer must reject this file as an automatic tuning profile.
