# HCI MemTest detailed usage

Validates memory by accumulating a coverage percentage. Where TM5 is strong at catching errors quickly, HCI MemTest builds confidence by running long and accumulating coverage.

Launch id is `hci-memtest`, risk is high load.

## Free edition limits

This project includes the free edition only; the paid editions cannot be redistributed. The free edition has these constraints.

| Aspect | Free | Paid Pro |
|---|---|---|
| Test target | Only RAM Windows has not allocated | Automatic distribution across available RAM |
| Multithreading | None; several instances started manually | Native multithreading |
| Command line automation | None | Available |
| Log file | None | Error log saved |

Because there is no automation or log output, results from this tool are not captured into the session record the way other tools are. Read the result on screen and keep a screenshot if evidence is needed.

## How to run

1. Close as many programs as possible. The free edition only tests unallocated memory, so other programs holding memory shrink the tested range.
2. Divide total memory minus the operating-system share by the number of instances. On a 64 GB system with 8 logical cores, dividing roughly 56 GB by 8 gives about 7000 MB per instance.
3. Start one instance per logical core and enter the calculated size in each window.
4. Press `Start Testing` in every window.

Leaving the field empty or using `All unused RAM` lets the first instance claim everything, leaving the rest without a proper allocation. Specifying the size explicitly is safer.

## Reading the display

- `Coverage`: test progress. 100% is one full pass; continued running accumulates to 200%, 400% and beyond.
- `Errors`: must stay at zero.

## Pass criteria

| Goal | Recommended coverage | Pass condition |
|---|---|---|
| Quick check | 400% | Zero errors |
| General use | 1000% | Zero errors |
| Always-on system | 5000% or more | Zero errors throughout |
| Integrity-critical work | 10000% | Zero errors throughout |

Higher coverage targets take proportionally longer; 5000% usually needs an overnight run. A single window showing one or more errors fails the whole test.

## Stop immediately when

- Any window reports one or more errors.
- Memory or CPU temperature approaches its limit.
- The system hangs or reboots.
- A WHEA error is written to the event log.

## Relationship to other tools

Screening with TM5 first and then running HCI MemTest long on the surviving settings is the efficient order. TM5 catches errors fast; HCI MemTest spends time finding what was missed. To remove operating-system influence entirely, boot-test with MemTest86+.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id hci-memtest -AcknowledgeRisk -Language en
```

