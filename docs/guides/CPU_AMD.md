# AMD CPU inspection and stability guide

AMD tuning behavior differs by processor family, socket, chipset, BIOS and cooling. WinPortableLab records and guides settings but does not apply PBO, Curve Optimizer, Curve Shaper, voltage or frequency automatically.

## Identification

- Full Ryzen/Threadripper model
- Socket and motherboard chipset
- BIOS and AGESA version
- CCD and core count
- Current PBO, Curve Optimizer, Curve Shaper and manual OC state
- Memory profile, FCLK/UCLK/MCLK where exposed
- Cooling, idle baseline and WHEA history

AMD currently provides different Ryzen Master downloads for Ryzen 5000 and later, Ryzen 3000-4000, and Ryzen 2000 and earlier. Feature availability must be detected, not assumed.

Source: https://www.amd.com/en/products/software/ryzen-master.html

## Platform routing

| Platform group | Typical platform | Tuning route | Validation emphasis |
| --- | --- | --- | --- |
| Ryzen 2000 and earlier | AM4, early Zen/Zen+ | Legacy Ryzen Master or BIOS only when supported | All-core load, memory/fabric separation and cold boot |
| Ryzen 3000/4000 | AM4, Zen 2 desktop/APU | Matching legacy Ryzen Master branch; PBO availability varies | Per-CCD behavior, fabric/memory and boost transitions |
| Ryzen 5000 | AM4, Zen 3 | Current Ryzen Master support includes Curve Optimizer on eligible desktop parts | Per-core CO errors, low-load boost and memory/fabric |
| Ryzen 7000/8000 | AM5, Zen 4 desktop/APU | Ryzen Master 3.x, PBO/CO where supported, DDR5 EXPO | DDR5 training, iGPU where present, thermal target behavior |
| Ryzen 9000 | AM5, Zen 5 | Current Ryzen Master; Curve Shaper only on applicable processors | Temperature/frequency bands, per-core CO and DDR5 |
| Threadripper/TR PRO | TRX/WRX platforms | Exact platform documentation only | NUMA/CCD topology, memory channels and workstation workload |
| Notebook/OEM APU | Vendor-controlled platform | Inspection only unless OEM explicitly supports tuning | Shared power/thermal budget and OEM driver/firmware |

## AM4 Zen 2/Zen 3 procedure

1. Load CPU and memory defaults.
2. Establish stock single-thread, mixed-thread and memory baselines.
3. Keep memory and fabric at defaults while diagnosing CPU stability.
4. For an eligible Ryzen 5000 system, test Curve Optimizer changes per core when possible rather than assuming one all-core offset fits every core.
5. Validate both sustained load and light/idle boost transitions.
6. Restore CPU defaults before changing memory frequency, fabric or timings.

## AM5 Zen 4/Zen 5 procedure

1. Update BIOS only through the board/system vendor and record the resulting AGESA version.
2. Allow the first DDR5 memory training to complete; do not power-cycle merely because the first boot is slow.
3. Establish a JEDEC memory baseline before enabling EXPO.
4. Validate PBO/CO independently from EXPO.
5. For Ryzen 9000, use Curve Shaper only if Ryzen Master exposes it for the processor; do not copy another CPU's temperature/frequency-band values.
6. Include cold boot, sleep/resume and idle-to-boost transitions in the final validation.

AMD documents Curve Optimizer as a voltage/frequency curve shift and notes that larger negative offsets increase the magnitude of the voltage reduction. Availability varies by CPU.

Sources:

- https://docs.amd.com/r/en-US/68886-ryzen-master-user-guide/Curve-Optimizer
- https://docs.amd.com/r/en-US/68886-ryzen-master-user-guide/What-s-New-in-Ryzen-Master-3.1.0

## X3D processors

Treat X3D parts as a separate route even within the same generation.

- Use only controls explicitly exposed by the current BIOS/Ryzen Master for that exact part.
- Do not reuse fixed-voltage or all-core settings from a non-X3D processor.
- Prefer default boost behavior, PBO/CO controls when supported, and evidence-driven validation.
- Include gaming-like burst loads and idle transitions, not only an all-core torture test.

## Test ladder

1. Stock CPU and JEDEC memory baseline
2. Short calculation smoke test
3. Per-core or core-cycling workload when CO is in use
4. Mixed all-core workload
5. Memory/fabric workload
6. Idle, sleep/resume and boost-transition observation
7. Extended validation using the exact intended daily profile

## Failure interpretation

| Evidence | First response |
| --- | --- |
| Worker/calculation error | Revert the last CPU tuning change |
| WHEA processor/core event | Return CO/PBO/manual CPU tuning to defaults |
| Memory error with CPU stock | Investigate memory profile, controller and DIMM layout |
| Only idle/light-load crash | Suspect aggressive negative curve settings before adding voltage blindly |
| Only combined CPU+GPU APU failure | Separate shared power, cooling and memory variables |

AMD states that overclocking or undervolting outside published specifications can affect warranty and can cause damage or data loss. The toolkit must show this warning before tuning guidance.

Source: https://www.amd.com/en/products/processors/technologies/expo.html

