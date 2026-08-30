# Installed portable tool snapshot

Snapshot date: 2026-08-30 (KST)

All package archives are gitignored. `scripts/Install-PortableTools.ps1` pins the SHA-256 values below, while each local version directory contains a more detailed `INSTALL-MANIFEST.json` with resolved URL, file size, executable hashes, Authenticode state and signer.

| Tool | Version | Source trust | Archive SHA-256 |
| --- | --- | --- | --- |
| AMD Cleanup Utility | 1.0.0.1 | official | `D05A5436...E71B744E` |
| NirSoft BatteryInfoView | 1.26 | official | `BE98EE43...10538AF7` |
| BlueScreenView | 1.55 | official | `DF57D4C9...5C821479` |
| CPU-Z | 3.01 | official | `8AE3B45D...ACE40827` |
| CrystalDiskInfo | 9.9.2 | official-project-mirror | `01ACB317...BD21C7DF` |
| CrystalDiskMark | 9.0.3 | official-project-mirror | `E0C1E76A...3C494B78` |
| Display Driver Uninstaller | 18.1.5.7 | official | `8C12B7D8...131FAAE9` |
| Microsoft DiskSpd | 2.2 | official | `496DF11E...13A5A6CE` |
| Driver Store Explorer | 1.0.26 | official-github-release | `89A5ED17...DA8E931F` |
| Fan Control | 275 | official-github-release | `369445D8...5AC7C030` |
| FullEventLogView | 1.81 | official | `DD67610F...B4BA1D95` |
| Glary Utilities Portable | 6.46 | official | `C6B04421...DC8DA301` |
| GPU-Z | 2.70.0 | official | `6CB0EF29...59979C29` |
| H2testw | 1.4 | official-publisher | `0D54B8BE...E2DAC187` |
| HCI MemTest (free) | 7.0 | official | `08960F44...8E4679E6` |
| HWiNFO | 8.52.6060 | vendor-listed-mirror | `0CE80064...B059F1ED` |
| Intel XTU Legacy | 7.14.2.93 | official-installer-not-portable | `C8F39BDD...FFFC2925` |
| Intel XTU Ultra | 10.0.1.188 | official-installer-not-portable | `0118C89C...E5F1C7ED` |
| LatencyMon | 7.40 | official | `D4E47287...8C6D17AF` |
| Memtest86+ | 8.10 | official | `7E6C5162...5EB26C29` |
| Naraeon Dirty Test | 1.0.0.0 | author-site-http-signed-and-hash-pinned | `3A94CF05...B33ED311` |
| OCCT | 17.0.18 | official | `FE25337C...30F1A716` |
| Prime95 | 30.19b20 | official | `D9475F2F...A8756BCA` |
| AMD Ryzen Master | 3.1.1.5502 | official-installer-not-portable | `8F3F687C...BF105749` |
| Snappy Driver Installer Origin | 830 | official | `7BB0CECA...E3692819` |
| smartmontools | 7.5 | official-project-mirror | `896337FC...E6104C70` |
| Sysinternals Suite | snapshot-2026-08-29 | official-rolling | `EC1C2258...356DE169` |
| TestMem5 | 0.13.1 | official | `05FFB5BB...50128C12` |
| TrafficMonitor Lite | 1.86 | official-github-release | `D9774A64...89CC1145` |
| USBDeview | 3.10 | official | `7EB383F7...893C161B` |
| ValiDrive | 1.0.1 | official | `99620686...72FA4F29` |
| Ventoy | 1.1.17 | official | `D250E97A...659DBAEB` |
| WizTree Portable | 4.30 | official | `8367F467...45FD7B5E` |
| y-cruncher | 0.8.7.9547b | official | `3BE696C1...163A4F87` |
| ZenTimings | 1.39 | official-github-release-with-published-sha256 | `2B350F44...6A7BDFDF` |

The shortened hashes here are for human scanning; the installer and local manifests contain the full 64 hexadecimal characters. The Sysinternals URL is rolling, so updating the suite intentionally requires reviewing and replacing its pinned hash.

## Execution state

- No GUI benchmark, stress test, driver cleanup, fan change or storage workload was started during setup.
- Safe smoke checks only: `smartctl --version` and `diskspd -?`.
- DDU and smartmontools installers were extracted with 7-Zip rather than executed.
- HWiNFO64/ARM64 commercial use requires the appropriate HWiNFO license.
- Intel XTU and AMD Ryzen Master are carried installers, not portable applications. They require an explicit local installation and are never auto-installed.
- No dirty, fill, capacity or integrity workload was executed while acquiring Naraeon Dirty Test, H2testw or ValiDrive.
