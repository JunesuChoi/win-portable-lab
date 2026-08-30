# Ventoy detailed usage

Lets you copy ISO files onto one USB device and pick which to boot. In this project it prepares the media for checks that must run outside Windows, such as MemTest86+.

Launch id is `ventoy`, risk is system changing. It erases the USB device, so it is never launched automatically.

## The critical warning

Installing Ventoy completely erases the target USB device. Before running it, confirm:

1. The listed device is the intended USB, checked twice by drive letter and capacity.
2. No external hard disk or backup drive is selected.
3. Nothing on the USB needs keeping.

Choosing the wrong device is hard to recover from. Do not press `Install` before confirming.

## Installation steps

1. Connect the USB device. 8 GB or larger is recommended.
2. Run Ventoy2Disk as administrator.
3. Select the target USB in the `Device` list and re-check it by capacity.
4. Set the partition style under `Option` if needed; the default works in most cases.
5. Press `Install`. Two warnings appear and both must be confirmed.
6. Once complete, copy ISO files directly onto the partition that was created.

## Key options

| Option | Meaning | Recommendation |
|---|---|---|
| Partition Style MBR | Broad compatibility including legacy BIOS | Suits field work across many machines |
| Partition Style GPT | Modern UEFI-only layout | When only recent machines are involved |
| Secure Boot Support | Allows booting where Secure Boot is enabled | Enable to avoid turning Secure Boot off |
| Preserve space | Leaves space at the end | Unnecessary outside special cases |

For field diagnostics across many machines, MBR together with Secure Boot support gives the widest compatibility.

## Preparing MemTest86+ media

1. Install Ventoy as above.
2. Copy the ISO from `tools/04-CPU-Memory-Stability/memtest86plus` onto the USB device.
3. Boot the target PC from USB, changing the boot order if necessary.
4. Choose MemTest86+ from the Ventoy menu.

If Secure Boot is enabled and blocks booting, reinstall with Secure Boot support or temporarily disable Secure Boot on that machine. Restore the original setting when the check is finished.

## Notes

Licensed GPL-3.0, which carries a source-availability obligation on redistribution. This project does not include it in the offline pack.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id ventoy -AcknowledgeRisk -Language en
```

