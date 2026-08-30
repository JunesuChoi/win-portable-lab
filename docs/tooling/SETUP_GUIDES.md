# Third-party tool setup guides

Run the following command to create a traced directory for every catalog entry:

```powershell
.\scripts\Start-WinPortableLab.ps1 -Mode tools
```

To prepare selected tools and open their official pages:

```powershell
.\scripts\Setup-Tools.ps1 -Root . -Id diskspd,hwinfo,ddu -OpenSourcePages
```

The setup helper creates `SOURCE.json` provenance records. The separate installer downloads pinned portable releases, verifies known vendor checksums, records SHA-256/signatures, and extracts archives without starting any utility:

```powershell
.\scripts\Install-PortableTools.ps1 -Root . -IncludeHighLoad
.\scripts\Test-InstalledTools.ps1 -Root .
```

Current sources include direct vendor downloads, official GitHub/SourceForge projects, and SAC for HWiNFO; SAC is explicitly listed by HWiNFO as a mirror. Every installed version receives `INSTALL-MANIFEST.json`.

## TrafficMonitor

1. Use the official `zhongyang219/TrafficMonitor` release archive and retain its license files.
2. WinPortableLab uses the x64 Lite build for portable taskbar monitoring of upload/download throughput plus CPU, memory, GPU and disk load.
3. Open `trafficmonitor` from the System or Network route. Its working directory remains the extracted program folder so skins, plugins and configuration resolve correctly.
4. Treat the Anti-996 license as a redistribution restriction: the current offline-pack policy does not redistribute this archive.

TrafficMonitor is a live observer, not the source of the saved diagnostic baseline. Use WinPortableLab's refresh button to capture a new system snapshot after a hardware or driver change.

## ZenTimings and detailed memory data

WinPortableLab always records WMI/CIM DIMM slots, capacity, vendor, part/serial number, rated and configured speed, voltage, form factor and data width in `hardware.json` and `summary.html`. The dashboard memory card exposes the most useful summary and a per-slot tooltip.

ZenTimings v1.39 is additionally available on AMD Ryzen systems for applied memory timings that standard Windows CIM cannot expose. It is intentionally skipped on Intel systems and requires administrator rights. RAMSPDToolkit was reviewed but not integrated because its driver-backed SMBus/SPD write capabilities exceed this toolkit's read-only default; Mem Reduct was also excluded because clearing memory changes the state being diagnosed.

## Microsoft DiskSpd

1. Open https://github.com/microsoft/diskspd/releases.
2. Download the current official release ZIP.
3. Keep the license file with the binary.
4. Place the appropriate AMD64 executable under `tools/03-Storage-Benchmark-Dirty-Integrity/diskspd/`.
5. Run only file-target profiles supplied by this project.

Raw physical-disk and partition write targets are outside the supported policy. The default adapter will create a bounded temporary file, record estimated writes, run the workload and remove only that known file.

## smartmontools

1. Open https://www.smartmontools.org/ and select the official Windows package.
2. Record the package version and source.
3. Place the approved portable files under `tools/02-Storage-Health-SMART/smartmontools/`, or record the installed path when using the installer.
4. Prefer `smartctl` JSON output when supported.

The adapter will read health data by default. Device self-tests and any write-affecting operation require a separate policy review.

## Prime95

1. Open https://www.mersenne.org/download/.
2. Review and accept the GIMPS license.
3. Download the Windows 64-bit archive and verify the published checksum.
4. Extract it under `tools/04-CPU-Memory-Stability/prime95/`.
5. Read the included `stress.txt` and `readme.txt` for that exact version.

The project does not redistribute Prime95. Future automation must generate a dedicated temporary configuration and must not silently join PrimeNet.

## y-cruncher

1. Open https://www.numberworld.org/y-cruncher/.
2. Download the Windows release directly from the author.
3. Review the license and included command-line manual.
4. Extract it under `tools/04-CPU-Memory-Stability/y-cruncher/`.
5. Preserve `Command Lines.txt` with the binary because syntax and profiles may vary by release.

## MemTest86+

1. Open https://www.memtest.org/.
2. Download the current Windows USB installer or boot image.
3. Verify the published checksum.
4. Use a dedicated disposable USB device for the boot image.

Do not write the MemTest86+ image onto the drive containing WinPortableLab. Imaging a USB device overwrites its existing partition layout. Confirm Secure Boot requirements and the selected target disk before writing anything.

## OCCT

1. Open https://www.ocbase.com/occt.
2. Select a license suitable for personal, professional or enterprise use.
3. Install or place the approved build separately.
4. Record the executable path in the future local machine configuration.

Structured CLI automation and JSON/CSV reports require the appropriate OCCT tier. The project does not attempt to automate the Personal GUI.

## HWiNFO

1. Open https://www.hwinfo.com/download/.
2. Choose the portable package.
3. Confirm that the intended use complies with the non-commercial or paid license.
4. Extract it under `tools/01-System-Info-Monitoring/hwinfo/` only when that use is licensed.

HWiNFO is the single full sensor-monitoring baseline. The dashboard does not automate its shared-memory interface because non-Pro availability is time-limited and commercial use requires the appropriate license. Keep HWiNFO visible during load testing and apply the guide's manual temperature stop thresholds.

## DDU

1. Download the current release from the Wagnardsoft release forum.
2. Verify the SHA-256 published beside the portable/self-extracting link.
3. Extract the self-extracting package without launching DDU.
4. Follow `docs/guides/GPU_DDU.md` and never launch DDU from a benchmark profile.

DDU must run from a local disk. When WinPortableLab itself is on a USB drive, copy the approved DDU folder to a temporary local directory before use and remove only that known copy afterward.

## Intel XTU and AMD Ryzen Master

These are installed, platform-specific tuning applications rather than portable binaries.

- Intel XTU: https://www.intel.com/content/www/us/en/download/17881/intel-extreme-tuning-utility-intel-xtu.html
- AMD Ryzen Master: https://www.amd.com/en/products/software/ryzen-master.html

WinPortableLab will detect and open the correct installed application after checking the CPU/platform route. It will not install a mismatched XTU branch or apply tuning values automatically.
