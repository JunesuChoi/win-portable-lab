# LatencyMon detailed usage

Measures whether a driver spends so long in the kernel that it disrupts real-time processing. Use it when temperatures and clocks look fine but audio drops out, frame delivery is uneven, or the mouse stalls momentarily. HWiNFO sensor logging cannot see this.

Launch id is `latencymon`. It is read-only but requires administrator rights.

## How the measurement works

- An ISR is an interrupt service routine, the code that handles a hardware interrupt immediately.
- A DPC is a deferred procedure call, which finishes the work the ISR postponed.
- When either holds the processor too long, audio buffers run dry and frame delivery slips. LatencyMon measures how long each driver holds it.

## How to run

1. Reproduce the normal environment. The cause only shows with the usual programs running.
2. Run LatencyMon as administrator.
3. Start monitoring with the play button.
4. Measure for at least ten minutes. If the symptom is intermittent, run long enough for it to occur at least once.

## Reading the tabs

| Tab | What it shows | Key point |
|---|---|---|
| Main | Overall verdict | States in plain language whether the system suits real-time audio |
| Stats | Maximum DPC/ISR latency and interrupt counts | Read maximum and average together |
| Drivers | Per-driver execution time | Sort by `Highest execution` and read the top entries |
| Processes | Hard page faults per process | Reveals a specific program as the cause |
| Stacks | Kernel stack samples | For deeper analysis |

## Interpretation

| Maximum DPC/ISR latency | Meaning |
|---|---|
| Under 500 microseconds | Good. No problem for real-time audio |
| 500 to 1000 microseconds | Caution. Dropouts possible at low buffer settings |
| 1000 to 4000 microseconds | Problematic. The responsible driver must be found |
| Above 4000 microseconds | Severe. Symptoms will be noticeable |

Driver file names at the top of the Drivers tab are the candidates. Common ones behave as follows.

| File | Responsibility | Action |
|---|---|---|
| `ndis.sys` | Networking | Update LAN/Wi-Fi drivers, disable adapter power saving |
| `nvlddmkm.sys` | NVIDIA graphics | Update, or clean install after DDU |
| `amdkmdag.sys` | AMD graphics | Same as above |
| `storport.sys` | Storage | Update chipset/NVMe drivers, check SMART |
| `ACPI.sys` | Power management | Update BIOS, review C-State settings |
| `dxgkrnl.sys` | Graphics kernel | Review together with the graphics driver |
| `wdf01000.sys` | Driver framework | Trace the underlying device driver |

## Improvement order

1. Update the device driver behind the top entry to the current official release.
2. If graphics is responsible, remove it completely with DDU and clean install.
3. If networking is responsible, disable power-saving features in the adapter properties.
4. If power management is responsible, update the BIOS and review aggressive power settings.
5. Re-measure under the same conditions and confirm the figure dropped.

Change one thing at a time and re-measure. Changing several at once hides which one helped.

## Notes

The measurement is read-only but observes at kernel level, so administrator rights are required. The Home Edition is free for personal use; business use requires a licence.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id latencymon -Language en
```

