# Storage tool detailed guide

Before any write test, recheck disk number, drive letter, and backup status. Never write-test a volume containing irreplaceable data.

## AS SSD Benchmark · ATTO Disk Benchmark · HD Tune Pro

Register the executable from an official copy through **Add/edit tool path**; the project does not download these automatically. AS SSD and ATTO create test-file I/O, so never use them on a recovery target, evidence drive, or a nearly-full volume. With HD Tune Pro, start with **Info, Health and read-only Error Scan**. Run Write Benchmark, Erase or Extra Tests only after independently confirming the target disk and backup.

## smartmontools (smartmontools)

Read the full SMART/NVMe log. If reallocated/pending sectors, media/data-integrity errors, or critical warnings are non-zero or increasing, back up and use the vendor diagnostic before benchmarking.

## CrystalDiskInfo (crystaldiskinfo)

Record model, firmware, temperature, and health. Confirm caution/bad status, unusual heat, or rapidly rising NAND writes with the vendor tool. AAM/APM and firmware commands are outside this workflow.

## DiskSpd (diskspd)

Use file targets only. Example: diskspd.exe -c4G -d60 -r -w30 -t2 -o4 -b1M test.dat. c=file size, d=seconds, r=random, w=write percentage, t/o=threads and queue depth, b=block size. Raw disk or partition writes are forbidden.

## CrystalDiskMark (crystaldiskmark)

Confirm drive letter, size, and passes. Start at 1 GiB × 3; use 16–32 GiB × 3 for cache/sustained-write checks. SEQ1M is sequential throughput and RND4K Q1T1 is a responsiveness reference.

## ValiDrive (validrive)

This is a quick screen for USB/SD advertised capacity. A pass is not full certification; confirm suspicious media empty with complete H2testw write-and-verify.

Stop on SMART warnings, I/O errors, WHEA, or disconnects and record model, firmware, temperature, and transport with the result.
