# OCCT detailed usage

Loads CPU, memory, power delivery and graphics together while watching for errors. Where Prime95 concentrates on calculation stability, OCCT exposes problems that appear under combined load and power draw. It is the heaviest tool in this project.

Launch id is `occt`, risk is very high load.

## Before starting

1. Prepare HWiNFO to watch CPU temperature, VRM temperature, the 12V rail and power draw.
2. Close all unsaved work.
3. Check the power supply's capacity and age. An ageing unit may trip its protection during this test.
4. Confirm case airflow is not obstructed.

## Test types

| Type | Load target | Recommended for |
|---|---|---|
| CPU | CPU computation | Core stability |
| Memory | Memory regions | Supporting RAM validation |
| 3D Standard | GPU | Graphics load in isolation |
| 3D Adaptive | GPU with varying load | Response to power transients |
| Power | CPU and GPU at maximum together | Power delivery limits. The most dangerous |

The `Power` test pushes the power supply to its limit. Do not run it if the unit's condition is in doubt; the system can shut off instantly.

## Key settings

| Setting | Meaning | Recommendation |
|---|---|---|
| Test Mode | Dataset size and load pattern | Start with the default |
| Instruction Set | AVX, AVX2, SSE selection | AVX2 at most for real-world criteria |
| Duration | Test length | Start short and extend |
| Error Behavior | Action on error | Set to stop on error |
| Monitoring thresholds | Temperature ceiling | Set below the model's official limit |

OCCT can stop automatically when a configured temperature is exceeded. Always set this value; it is the only safeguard during an unattended run.

## Pass criteria

| Goal | Recommended duration | Pass condition |
|---|---|---|
| Quick screening | 10 minutes of CPU | Zero errors |
| Baseline validation | 30 minutes CPU plus 30 minutes Memory | Zero errors |
| Production stability | 60 minutes each | Zero errors, stable temperature |
| Power limit check | 10 minutes of Power | Zero errors, no reboot |

OCCT displays detected errors on screen and records them in its log. A single error is a failure.

## Stop immediately when

- CPU or GPU temperature approaches the model's official limit.
- The 12V rail leaves its specified range.
- The system shuts off abruptly, which signals a power delivery problem.
- An error is displayed.
- A WHEA error is written to the event log.

An abrupt shutdown means a power supply or power circuitry problem. In that case stop repeating load tests and inspect the power path first.

## Relationship to other tools

OCCT is strong at combined load and power validation. Prime95 is better for calculation stability alone, and TestMem5 for precise memory error detection. Confirming each axis with Prime95 and TestMem5 before running OCCT makes it easier to isolate a cause.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id occt -AcknowledgeRisk -Language en
```

