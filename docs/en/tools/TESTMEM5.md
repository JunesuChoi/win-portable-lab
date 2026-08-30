# TestMem5 (TM5) detailed usage

Finds the errors that appear when RAM overclock sub-timings are wrong, and finds them quickly. It is common for a system to pass y-cruncher and Prime95 yet fail TM5. The reverse also holds: passing TM5 does not prove complete stability.

Launch id is `testmem5`, risk is high load, and administrator rights are required.

## Before starting

1. Open HWiNFO first so memory, VRM and CPU temperatures are visible.
2. Close unsaved work. A memory error can terminate programs abnormally.
3. Prepare an antivirus exclusion. TM5 uses low-level memory access and is frequently flagged; if it is quarantined it will not run at all.

## Choosing a profile

TM5 0.13.1 ships the profiles inside its `bin` folder, so nothing extra needs downloading.

| Profile file | Character | Recommended for |
|---|---|---|
| `Extreme @ anta777.cfg` | Standard validation, the common reference | Default first choice |
| `Absolut @ anta777.cfg` | Harder than Extreme | Extra pass after Extreme succeeds |
| `DDR5 Intel @ anta777.cfg` | DDR5 Intel platforms | DDR5 with Intel |
| `DDR5 Ryzen3D @ anta777.cfg` | DDR5 Ryzen X3D | DDR5 with X3D |
| `Heavy @ anta777.cfg` | Heavy patterns | Chasing pattern-specific errors |
| `Super Light 2 @ anta777.cfg` | Very short check | Quick screening while changing values |
| `1usmus v3 @ 1usmus.cfg` | Classic early-Ryzen profile | Older Ryzen |
| `Default @ serj.cfg` | Author default | Reference only |

Prefer a platform-specific profile when one exists. On DDR4, `Extreme @ anta777.cfg` is the default.

## Applying a profile

Skipping this order means testing with the previous profile.

1. Run TM5 as administrator.
2. Select the profile and press `Load config & exit`. The program closes.
3. Run TM5 as administrator again.
4. Confirm the profile name shown at the top of the main window. Choosing Extreme displays `Extreme1 / anta777`.
5. Start the run.

## Reading the display

- `Cycle`: one full pass. An Extreme cycle usually takes 20 to 40 minutes depending on system speed and capacity.
- `Test`: the current pattern number. Repeated failures at the same number help narrow down the responsible timing.
- `Errors`: must stay at zero. Anything above zero means the setting is unstable.
- `Coverage`: how much memory has been exercised.

## Pass criteria

| Goal | Recommended run | Pass condition |
|---|---|---|
| Quick screening while tuning | One Super Light 2 cycle | Zero errors |
| Baseline validation | One Extreme cycle | Zero errors |
| Production stability | Three or more Extreme cycles | Zero errors throughout |
| Final confirmation | One additional Absolut cycle | Zero errors |

A single error is a failure. Raise voltage, relax timings or lower the clock, then restart the test from the beginning.

## Stop immediately when

- Memory or VRM temperature approaches the vendor limit.
- An error appears. Continuing adds no information and only risks data corruption.
- The system hangs or reboots. That also counts as unstable.
- A WHEA error is written to the event log.

## Relationship to other tools

TM5 specialises in memory error detection. Use Prime95 for CPU core stability, OCCT for combined load, and MemTest86+ to remove operating-system influence. Accumulating coverage with HCI MemTest after TM5 passes raises confidence further.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id testmem5 -AcknowledgeRisk -Language en
```

