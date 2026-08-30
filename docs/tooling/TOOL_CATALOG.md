# Tool catalog policy

The machine-readable catalog is `catalog/tools.json`. Third-party executables are stored only in gitignored local directories; they are never committed as repository content.

## Distribution modes

| Mode | Meaning |
| --- | --- |
| `bundled` | Redistribution reviewed; binary and notices may be shipped |
| `download-on-demand` | Retrieve from the official source and verify before execution |
| `extract-from-official-installer` | Extract command-line files without running the vendor installer |
| `user-supplied` | Operator places the tool under `tools/<purpose-folder>/<id>/` |
| `installer-carried-not-portable` | Carry the official installer, but never claim portability or install automatically |
| `launch-only` | Detect and open an installed or separately licensed application |

## Initial decisions

- HWiNFO is the single full sensor-monitoring baseline; overlapping full sensor-monitoring utilities are not retained.
- DiskSpd is the preferred automatable storage workload because it supports CLI/XML results and has an MIT-licensed official repository.
- DDU is guided manual operation. The current release must be obtained from Wagnardsoft, extracted to a local disk, and used with the replacement driver ready.
- OCCT structured CLI automation is reserved for a correctly licensed edition.
- HWiNFO is downloaded from the vendor-listed SAC mirror; 64/ARM64 commercial use still requires a paid license.
- Prime95 and y-cruncher are downloaded for this local toolkit but remain uncommitted and must be used under their supplied terms.
- CPU-Z, GPU-Z, CrystalDiskInfo and CrystalDiskMark use their portable/standalone editions.
- Intel XTU and AMD Ryzen Master are carried installers. WinPortableLab does not install them or set voltage or frequency automatically.
- Naraeon Dirty Test covers broad-space sustained-write behavior; H2testw covers full free-space write/read verification; ValiDrive covers quick USB declared-capacity spot checks.

## Source references

- DiskSpd: https://github.com/microsoft/diskspd
- MemTest86+: https://github.com/memtest86plus/memtest86plus
- Prime95: https://www.mersenne.org/download/
- DDU: https://www.wagnardsoft.com/display-driver-uninstaller-ddu
- OCCT: https://www.ocbase.com/occt
- HWiNFO: https://www.hwinfo.com/download/
