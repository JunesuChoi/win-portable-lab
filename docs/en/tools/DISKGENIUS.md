# DiskGenius - Detailed Guide

An advanced secondary tool: partition management plus MBR/GPT repair, bad-sector scanning and disk cloning. The free edition covers inspection and partition work; saving recovered files is paid. Powerful tools leave room for mistakes, so treat this as the advanced option only.

Run ID: `diskgenius`. Risk: partition write (top tier).

## Golden rule

**Separate inspection from repair.** Scanning is read-only; recovery, restore and partition-table edits write to the disk.

1. Never use redistributed PartitionGuru portable builds; this project records only the vendor-signed official ZIP.
2. Back up or clone the target disk before any repair or restore.
3. Confirm the target disk number before accepting any automatic repair proposal.

## Key features

| Feature | Use | Free edition |
|---|---|---|
| Create, delete, format, resize | General partition management | Yes |
| Bad-sector verify | Precise defect diagnosis ahead of SMART counters | Yes (repair attempts are paid) |
| MBR/GPT repair | Unbootable or corrupted partition tables | Yes, mind save limits |
| Disk/partition cloning | Migration before replacement | Partially free |
| File recovery save | Restoring deleted files | Paid |

## Recommended procedure (bad-sector scan)

1. Run as administrator.
2. Select the target disk in the left list.
3. Start Bad Sectors - Verify Now; this is a read-only scan.
4. All Normal means healthy. Growing Damaged or Critical counts mean stop trusting that disk with backups.

## Never do

Do not repeat recovery attempts on a disk with rising reallocated sectors or abnormal noise; each attempt erases more of what remains. Prioritize backup and cloning first.

## Related tools

Everyday partition work belongs to Macrorit Partition Expert. Track health trends with CrystalDiskInfo and smartmontools. Investigate post-operation event-log anomalies with FullEventLogView.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id diskgenius -AcknowledgeRisk -Language en
```
