# Prime95 detailed usage

Tests CPU calculation stability. Use it after changing an overclock or voltage to see whether calculation errors appear. It generates a great deal of heat, so never run it without watching temperatures.

Launch id is `prime95`, risk is high load.

## Before starting

1. Open HWiNFO first to watch CPU package temperature, per-core temperatures, VRM temperature and power.
2. Look up the official maximum temperature for that exact CPU model. This value differs per model and is never assumed automatically.
3. Close unsaved work.

## The startup choice

On launch it asks whether to join the GIMPS prime-search project. Always choose `Just Stress Testing`. Entering account details makes it fetch work over the network. This project uses it for testing only.

## Test types

| Type | Character | Recommended for |
|---|---|---|
| Smallest FFTs | Loops inside cache. Maximum heat, minimal memory involvement | CPU core and voltage in isolation |
| Small FFTs | Similar but slightly wider | Standard core stability check |
| Large FFTs | Loads the memory controller too | CPU and RAM combined |
| Blend | Uses substantial memory, mixed workload | General validation, the default recommendation |
| Custom | Explicit FFT range and memory amount | Reproducing a specific range |

## About AVX

Recent versions use AVX and AVX-512 instructions. On CPUs where AVX-512 is active, the heat produced never occurs in real workloads. Split the approach by purpose.

- To judge real-world stability, disable AVX-512 in the CPU settings under `Options` before testing.
- To see worst-case headroom, enable it and test briefly. Stop immediately if temperature reaches the limit.

Record the two cases separately so a thermal failure with AVX-512 enabled is not misread as calculation instability.

## Pass criteria

| Goal | Recommended duration | Pass condition |
|---|---|---|
| Quick screening | 10 minutes of Small FFTs | Zero errors, no stopped worker |
| Baseline validation | 30 minutes of Blend | Zero errors |
| Production stability | 60 minutes or more of Blend | Zero errors, stable temperature |

Text such as `FATAL ERROR` or `rounding was` in a worker window is a failure. A single stopped worker counts as a failure. Results are written to `results.txt` in the program folder.

## Stop immediately when

- CPU temperature approaches the model's official limit.
- A worker reports an error or stops.
- The system hangs or reboots.
- A WHEA error is written to the event log.
- VRM temperature rises sharply.

## Relationship to other tools

Prime95 specialises in CPU calculation stability. TestMem5 and HCI MemTest find memory errors better. Use OCCT for power delivery and combined load. The three do not replace one another.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id prime95 -AcknowledgeRisk -Language en
```

