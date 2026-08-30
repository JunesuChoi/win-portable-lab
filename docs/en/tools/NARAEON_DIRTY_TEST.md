# Naraeon Dirty Test detailed usage

Fills an SSD's free space while recording write speed. Catalogue figures only describe the early window while the SLC cache holds; this tool shows how far real speed falls once that cache is exhausted. Use it to produce evidence for speed collapse during large copies.

Launch id is `naraeon-dirty-test`, risk is a high-write test that fills all free space.

## Confirm before running

This test consumes SSD endurance (TBW) and fills free space completely.

1. Confirm no important data is on the target drive. Re-check the drive letter even when a backup exists.
2. Never run it on the operating-system drive; Windows becomes unstable when space runs out.
3. Check SMART status and temperature with CrystalDiskInfo first. Do not run it on a drive already in a warning state.
4. Record the expected write volume, which equals the free space available.

## Reading the graph

Read the shape of the result graph, not the peak figure.

| Graph shape | Meaning |
|---|---|
| High start then gentle decline | Normal. Direct TLC/QLC write speed after cache exhaustion |
| Sharp stepped drop | A cache policy transition. Normal if characteristic of the model |
| Extreme drop at one point with no recovery | Caution. Possible controller or NAND problem |
| Heavy sawtooth oscillation | Caution. Suspect thermal throttling |
| Sections near zero | A problem. I/O stalls are occurring |

Reading it alongside temperature matters, because a slowdown caused by heat must be told apart from NAND characteristics. Record temperature during the run with HWiNFO or CrystalDiskInfo.

## Pass criteria

| Item | Healthy |
|---|---|
| Minimum speed after cache | Holds around the model's rated direct-write speed |
| I/O stall sections | None |
| Temperature during the run | Below the throttling threshold |
| SMART afterwards | No growth in reallocated sectors or media errors |
| Event log | No disk or controller errors |

Do not skip re-reading SMART afterwards. Some problems only surface right after a heavy write load.

## Stop immediately when

- Drive temperature approaches the vendor limit.
- Speed falls near zero and does not recover.
- The device disappears from the list or re-enumerates.
- A disk error is written to the event log.
- A SMART warning appears.

## Cleanup afterwards

Delete the files the test created to recover space. Checking with WizTree confirms no test files remain. Then re-read SMART with CrystalDiskInfo.

## Relationship to other tools

If only a performance baseline is needed, CrystalDiskMark is far shorter and safer. For fake capacity or data integrity, H2testw fits the purpose. Reach for the dirty test only when sustained write behaviour is the question.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id naraeon-dirty-test -AcknowledgeRisk -Language en
```

