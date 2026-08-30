# Network driver backup and offline install

LAN and Wi-Fi drivers are a different class of problem. A missing graphics driver leaves you with an ugly desktop; a missing network driver removes the only way to fetch the graphics driver. That is why a portable toolkit has to solve this one first.

Expand `More` in the console sidebar to reach `Network drivers`.

| Action | What it does | Changes the system | Needs admin |
|---|---|---|---|
| Check status | Lists real LAN/Wi-Fi cards, SDIO pack readiness, and stored backup count | No | No |
| Back up now | Exports this PC's network drivers to the USB | No (read only) | Yes |
| List backups | Shows the backups stored on the USB | No | No |
| Install selected backup | Adds a backup to this PC's driver store | Yes | Yes |
| SDIO offline install | Launches the driver-pack based installer | Yes | Yes |

## Do this while you still can

**Back up while the network still works.** Sitting in front of a PC with no LAN, you have no options left.

1. Plug in the USB and start the console.
2. Open `Network drivers` and press `Back up now`.
3. A folder appears at `offline-packs\network-drivers\{COMPUTERNAME}-{timestamp}` holding the INF packages and `NETWORK-DRIVER-MANIFEST.json`.

The manifest records adapter names, driver providers, versions, INF names, and the Windows build, so there is no guessing later about which machine a backup came from.

A backup is reusable on the same model. Different motherboards will not match, so collecting one per model you service regularly is the practical approach.

## Recovering a PC with no network

1. Plug in the USB and start the console. Approve the elevation prompt.
2. Press `Check status` to confirm the LAN/Wi-Fi card is detected at all. If no device appears, this may be hardware or a BIOS setting rather than a driver.
3. Pick the backup matching this model in `List backups`.
4. Press `Install selected backup`. Internally this runs `pnputil /add-driver /install`.
5. Reboot if Windows asks for it.

The install action changes the system. It requires explicit confirmation in the dialog, and `-AcknowledgeRisk` on the command line.

## Preparing SDIO driver packs for offline use

SDIO ships the program and the driver packs separately. This repository carries the program and the indexes only, and indexes alone cannot install anything offline. That is what a driver pack count of 0 in `Check status` means.

The packs are distributed over BitTorrent only and the full set runs to tens of gigabytes, so they are not bundled here. Selecting just the network families keeps it to a few gigabytes.

1. On a PC that still has internet, run `tools\09-Driver-Detection-Maintenance\sdio\830\SDIO_x64_R830.exe`.
2. In the driver pack download screen, select only the network packs: the entries containing `_LAN_`, `_WLAN-WiFi_`, or `_Net_`.
3. When the download finishes, `.7z` files appear in `sdio\830\drivers`.
4. Keep that folder on the USB as-is. From then on the install works without internet.

Driver packs and backup folders are covered by `.gitignore`, so they stay on the USB and never reach the repository.

## Situations you will hit

**Zero adapters reported.** This screen counts only real cards on the PCI, USB, or PCMCIA buses; virtual TAP/TUN adapters created by VPN clients are excluded. If the real count is zero, check Device Manager for an unknown device.

**A backup will not install on another PC.** An INF is bound to hardware IDs, so a different chipset is rejected. SDIO packs or the vendor driver are the answer there.

**It is a laptop.** Downloading the wireless driver from the vendor support page ahead of time is the most reliable option. Generic drivers can differ in power management and antenna configuration.

## Command line

```powershell
.\scripts\Set-WplNetworkDriver.ps1 -Root . -Action status
.\scripts\Set-WplNetworkDriver.ps1 -Root . -Action backup
.\scripts\Set-WplNetworkDriver.ps1 -Root . -Action list
.\scripts\Set-WplNetworkDriver.ps1 -Root . -Action restore -BackupPath '.\offline-packs\network-drivers\PC-20260830-101500' -AcknowledgeRisk
```

`backup` and `restore` require administrator rights. Use `-Language ko` or `-Language en` to pin the output language.

## Where to get a one-pack

Reviving a PC with no LAN needs a pack that already contains the network driver. This project does not bundle the packs themselves because of their size and distribution terms; it points you at the source so you can fetch one while you still have internet and keep it on the USB. The `Get a network one-pack` button in the `Network drivers` window opens the same list and can copy each address.

| Tool | Size | Character | When it fits |
|---|---|---|---|
| 3DP Net | About 120 MB | Official Korean distribution, self-extracting | First choice for most cases where only LAN needs to come back |
| SDIO network packs | A few GB for network only | Program already ships on this USB | When one tool should handle LAN and everything after it |
| DrvCeo universal network edition | A few hundred MB | Chinese interface, antivirus false positives reported | Last resort on awkward machines the other two cannot detect |

### 3DP Net

Address: `https://www.3dpchip.com/3dpchip/3dp/net_down_en.php`

Detects the network card model and installs the wired or wireless driver offline. It is the lightest of the three and ships Korean guidance. Once the link is up, continue with 3DP Chip or SDIO for the remaining drivers.

The download page offers two builds. Windows 7 and newer take the current version; XP and Vista take the legacy one. For the Windows 11 machines this project targets, use the current version.

Some mirrors found through search bundle adware installers. Download only from the official page above.

### SDIO network packs

Address: `https://www.snappy-driver-installer.org/`

The program itself already ships in this repository, so only the packs need downloading; there is no need to fetch a separate application. Follow the `Preparing SDIO driver packs for offline use` steps above.

The full collection exceeds 60 GB, but selecting only the `_LAN_` and `_WLAN-WiFi_` families finishes in a few GB.

### DrvCeo universal network edition

Address: `https://www.sysceo.com/software-softwarei-id-245.html`

SysCeo's all-in-one driver tool. It is distributed as a universal network-card edition plus a separate no-install build, and it also carries USB and storage controller drivers, which helps on machines where the NIC is not detected at all.

The interface is Chinese, and its driver-injection approach is reported to trigger antivirus false positives. Treat it as the entry needing the most judgement; if either of the first two tools solves the problem, there is no reason to reach for this one.

### After downloading

The downloaded file can live in any folder on the USB. For a standalone executable such as 3DP Net, keeping it under `tools\09-Driver-Detection-Maintenance` makes it easier to find later. You can also register it through the user tool path feature so the console launches it directly.
