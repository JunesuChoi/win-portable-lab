# Macrorit Partition Expert - Detailed Guide

A free portable tool for creating, deleting, formatting and resizing partitions. It was chosen over MiniTool because the free tier performs resize and non-system MBR/GPT conversion with no paywalled apply step.

Run ID: `macrorit-partition-expert`. Risk: partition write (top tier).

## Golden rule

**Verify the target disk twice.** Partition work is hard to undo; applying to the wrong disk destroys data.

1. Back up important data to a different physical disk first.
2. On multi-disk machines, confirm the target by disk number and capacity, cross-checked against Windows Disk Management (diskmgmt.msc).
3. This project only opens the program window. The operator always selects and applies work manually.

## Free tier coverage

| Operation | Free |
|---|---|
| Create, delete, format partitions | Yes |
| Resize, move, extend | Yes |
| MBR/GPT conversion (non-system disks) | Yes |
| System-disk MBR to GPT, OS migration | Paid (out of scope) |

## Recommended procedure

1. Run as administrator; otherwise the disk list looks empty.
2. Confirm the target disk in the disk selector.
3. Stage the operations; writes start only when Commit/Apply is pressed.
4. Re-read the pending operation list and confirm targets before applying.
5. Never close the program or cut power during apply.
6. Verify the result in Windows Disk Management afterwards.

## Never do

Do not resize the system partition on a battery-only laptop. Do not format data disks without a backup.

## Related tools

Simple removable-media formatting belongs to SD Memory Card Formatter. Advanced repair and bad-sector work belongs to DiskGenius. Re-check disk health with CrystalDiskInfo after partition work.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id macrorit-partition-expert -AcknowledgeRisk -Language en
```
