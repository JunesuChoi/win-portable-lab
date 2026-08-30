# Quick tool reference

What each tool observes, when to reach for it, and what a healthy result looks like. Option-level detail lives in the per-tool documents under `docs/en/tools/`.

Select a tool in the GUI list, or open it with the command below. The command only opens the program window; it never starts a test automatically.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id <toolId> -Language en
```

## System information and monitoring

| Tool | What it shows | When to use | Healthy result |
|---|---|---|---|
| CPU-Z (`cpuz`) | CPU, mainboard and memory configuration | Confirming configuration at the start | Model and memory clock match expectations |
| GPU-Z (`gpuz`) | GPU model, driver and sensors | Starting a graphics investigation | Driver version and PCIe link width look correct |
| HWiNFO (`hwinfo`) | Temperature, clocks, voltage, throttling | Continuous watch during any load test | Below thermal limits, no throttling |
| BatteryInfoView (`batteryinfoview`) | Wear against design capacity, cycle count | Notebook field checks | Wear proportional to age |
| FanControl (`fancontrol`) | Fan curve configuration | Tuning noise and cooling | Temperature stays in a stable band |

## Storage health and testing

| Tool | What it shows | When to use | Healthy result |
|---|---|---|---|
| CrystalDiskInfo (`crystaldiskinfo`) | SMART status, temperature, endurance | Before and after every write test | Status `Good`, no growth in reallocated sectors |
| smartctl (`smartctl-scan`) | Raw SMART values and self-test log | When exact figures are needed | Media errors and error log entries at zero |
| WizTree (`wiztree`) | Disk space distribution | Judging free space before a write test | Enough headroom for the planned test |
| CrystalDiskMark (`crystaldiskmark`) | Sequential and random baseline | Suspected performance loss | Small deviation from rated specification |
| DiskSpd (`diskspd-help`) | Bounded repeatable I/O load | When a reproducible measurement is required | No latency spikes |
| Naraeon Dirty Test (`naraeon-dirty-test`) | Sustained write after SLC cache | Speed collapse during large copies | Post-cache speed does not fall apart |
| H2testw (`h2testw`) | Full free-space write and read integrity | Suspected fake capacity or corruption | Zero bytes in error |
| ValiDrive (`validrive`) | USB declared-capacity spot check | Fast USB authenticity check | Every probed region responds |

## CPU and memory stability

| Tool | What it shows | When to use | Healthy result |
|---|---|---|---|
| Prime95 (`prime95`) | CPU calculation stability | Validating a CPU overclock | Zero worker and hardware errors |
| y-cruncher (`y-cruncher`) | Calculation errors on the memory path | Combined CPU and RAM validation | Result validation passes |
| TestMem5 (`testmem5`) | RAM overclock sub-timing errors | Validating a memory overclock | Zero errors through the full cycle |
| HCI MemTest (`hci-memtest`) | Coverage-based RAM errors | Extra confidence after TM5 passes | Zero errors, coverage accumulating |
| OCCT (`occt`) | Combined load and error detection | Overall power and thermal check | Zero errors, no voltage droop |
| MemTest86+ (`memtest86plus`) | RAM tested outside Windows | Excluding operating-system influence | Zero errors across all passes |
| Ventoy (`ventoy`) | Bootable USB creation | Preparing MemTest86+ media | The USB device boots |

## Driver and system diagnostics

| Tool | What it shows | When to use | Healthy result |
|---|---|---|---|
| FullEventLogView (`fulleventlogview`) | WHEA, disk and power events | Tracing an unexplained fault | No related error events |
| BlueScreenView (`bluescreenview`) | Minidump summary | After a blue screen | No recent dumps |
| LatencyMon (`latencymon`) | DPC and ISR latency | Audio dropouts, micro stutter | Maximum DPC latency stays low |
| TCPView (`sysinternals-tcpview`) | Per-process network connections | Checking suspicious traffic | No unknown remote endpoints |
| Process Explorer (`sysinternals-process-explorer`) | Process detail and handles | Tracing resource consumption | No abnormal consumer |
| Process Monitor (`sysinternals-process-monitor`) | File and registry access tracing | Tracing access failures | No repeating failures |
| DriverStore Explorer (`driverstoreexplorer`) | Driver store cleanup | Removing driver leftovers | Duplicate packages cleared |
| USBDeview (`usbdeview`) | USB device history | USB detection problems | Target device enumerates |
| DDU (`ddu`) | Complete graphics driver removal | Only on vendor change or failed removal | Clean install succeeds after reboot |
| SDIO (`sdio`) | Missing or outdated driver scan | Unknown devices after a reinstall | No problem markers in Device Manager |
| Glary Utilities (`glary-utilities`) | Startup, disk and system overview | First pass at slow-boot causes | No unnecessary startup entries |

## Risk labels

- Read-only: changes nothing. Safe to launch immediately.
- High load: significant heat and power draw. Requires sensor watch and stop conditions.
- Writes: consumes storage endurance. Back up first.
- System changing: alters drivers or device configuration. Requires a recovery plan.

Risky tools prompt for confirmation in the GUI and require `-AcknowledgeRisk` on the command line.

Already own a program? Point the console at it with [your own tool paths](USER_TOOL_PATHS.md).

## Per-tool guides

Option-level detail and pass criteria live in the documents below. Selecting a tool in the GUI and pressing `Selected tool guide` opens the same file.

| Tool | Document |
|---|---|
| Prime95 | [PRIME95.md](tools/PRIME95.md) |
| OCCT | [OCCT.md](tools/OCCT.md) |
| TestMem5 | [TESTMEM5.md](tools/TESTMEM5.md) |
| HCI MemTest | [HCI_MEMTEST.md](tools/HCI_MEMTEST.md) |
| Naraeon Dirty Test | [NARAEON_DIRTY_TEST.md](tools/NARAEON_DIRTY_TEST.md) |
| H2testw | [H2TESTW.md](tools/H2TESTW.md) |
| WizTree | [WIZTREE.md](tools/WIZTREE.md) |
| DDU | [DDU.md](tools/DDU.md) |
| LatencyMon | [LATENCYMON.md](tools/LATENCYMON.md) |
| BatteryInfoView | [BATTERYINFOVIEW.md](tools/BATTERYINFOVIEW.md) |
| Ventoy | [VENTOY.md](tools/VENTOY.md) |
| SDIO | [SDIO.md](tools/SDIO.md) |
| Glary Utilities | [GLARY_UTILITIES.md](tools/GLARY_UTILITIES.md) |
