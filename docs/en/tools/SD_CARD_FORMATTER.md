# SD Memory Card Formatter detailed usage

This is the SD Association's official formatter for SD, SDHC and SDXC cards. It erases the selected card. It is a **recovery or reinitialisation task**, not a diagnostic tool, so inspect the problem with read-only tools first.

The launch id is `sd-card-formatter` and the risk is `formats-removable-media`.

## Before use

1. Copy any required card data to another device. Recovery after formatting is not guaranteed.
2. Recheck the reader and target SD card. Do not select another removable disk.
3. First inspect PC storage errors and card-reader connectivity with CrystalDiskInfo and Event Viewer.
4. For full-size SD cards, make sure the physical write-protect tab is unlocked.

## Safe procedure

1. Start the tool and review the official EULA in the installer window.
2. In `Select Card`, match the target by both capacity and drive letter.
3. Use Quick format for normal reuse. Consider Overwrite format only when checking a logical card issue; it writes the entire card and takes much longer.
4. Confirm the drive letter and capacity once more before starting.
5. After completion, confirm that Windows mounts the card. For important media, verify separately with H2testw or ValiDrive.

## Cautions

- This tool is for SD cards. Do not use it for SSDs, USB flash drives, or a system drive.
- Formatting does not repair physical card failure, fake capacity, or a faulty card reader.
- The program is installer-based. Formatting is never automated by this project.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id sd-card-formatter -AcknowledgeRisk -Language en
```
