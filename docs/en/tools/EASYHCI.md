# EasyHCI operating guide

A Korean launcher that automates the free HCI MemTest. MemTest itself has no command line, no log and no multithreading, so an operator normally has to start several instances by hand and work out the allocation for each. EasyHCI does that arithmetic and the repetition for you.

The execution id is `easyhci` and the risk class is high load. The actual load comes from the memtest.exe processes it starts.

## Before you start

memtest.exe is not bundled with this pack. HCI MemTest is proprietary freeware owned by HCI Design, and redistributing it or embedding it in another program needs the author's permission.

1. Download the free edition from [hcidesign.com/memtest](https://hcidesign.com/memtest/).
2. Put `memtest.exe` next to EasyHCI, or anywhere in this pack's tools tree.

The launcher searches in this order and, when it finds nothing, shows a dialog listing every location it tried.

| Order | Location |
|---|---|
| 1 | The path written in `Resources\memtest_path.txt` |
| 2 | `Resources\memtest.exe` |
| 3 | The folder holding EasyHCI.exe |
| 4 | Up to six parent levels, looking for `hci-memtest\memtest.exe` |
| 5 | At each level, `tools` subfolders whose names contain `hci` or `memtest` |

Step 5 means that if you downloaded this pack's HCI MemTest entry, no configuration is needed.

## Running a test

1. Set the target coverage on the `설정` (Settings) tab. Leaving it at the default works.
2. Start the test from the `테스트` (Test) tab.
3. Watch progress there. Runs are long, so overnight is the usual choice.

At start it asks whether to close unnecessary processes. The free edition only tests unallocated memory, so closing other programs widens the tested range. Processes to keep are listed in `Resources\Process_Exceptions.ini`.

## What it automates

| Item | Behaviour |
|---|---|
| Allocation per instance | Probes the largest allocation that fits free memory and CPU thread count |
| Instance count | Starts one per logical core |
| Coverage aggregation | Collects progress across every window |
| Screenshots | Saves captures on the interval you choose |
| Sound alerts | Distinguishes success from error by sound |
| Logging | Writes `EasyHCI_Log.txt` when the run ends |
| Final action | Optionally shuts down, sleeps or closes after completion |

## Reading the result

- `Coverage`: cumulative progress. 100 percent is one full pass; longer runs stack up to 200, 400 percent and beyond.
- `Errors`: must be zero. A single error means the overclock is not stable.
- Memory usage should stay above 95 percent during the run for the result to be worth trusting.

## Cautions

- It runs with administrator rights, which HCI MemTest needs for large allocations.
- A long passing run can still fail in daily use, usually because memory runs hotter in games once GPU heat rises. Consider spot cooling when running high voltage.
- HCI MemTest alone is not enough. Pair it with [TESTMEM5](TESTMEM5.md) or Prime95.
- The limits of the free edition are documented in [HCI_MEMTEST](HCI_MEMTEST.md).

## About this fork

- Upstream: [Manbocoon/EasyHCI](https://github.com/Manbocoon/EasyHCI) (MIT, © 2022 kbum08)
- Fork: [JunesuChoi/EasyHCI](https://github.com/JunesuChoi/EasyHCI)
- Upstream bundles memtest.exe and embeds it in the executable, extracting it on first run. This fork does not.

