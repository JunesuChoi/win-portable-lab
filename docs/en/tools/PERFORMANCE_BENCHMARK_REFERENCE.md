# Performance benchmark quick reference

These tools are not stability verdicts. Compare a performance baseline with the same version, power plan and similar ambient temperature. Keep HWiNFO sensors open; stop immediately for an error, freeze, WHEA event or excessive temperature.

## AIDA64 Extreme

Register `aida64.exe` from an official portable trial or licensed copy. Record Cache & Memory Benchmark Read/Write/Copy/Latency, but never use one number as proof of memory-overclock stability. Validate separately with TM5, HCI MemTest or y-cruncher.

## Cinebench 2024

Register `Cinebench.exe` from Maxon. Run CPU Multi Core once first; run the GPU test only after the driver and thermal baseline are known good. Do not compare 2024 scores directly with R23.

## 3DMark

Use only the official Steam, Epic or licensed standalone install. Register `3DMark.exe` and select the default test appropriate for the system. Keep Storage Benchmark separate from ordinary GPU comparison. Save the result and stop for artifacts, a driver reset or WHEA.

## Blender Benchmark

Register `benchmark-launcher.exe` from the official Open Data Benchmark Client. Online submission is optional. CPU/GPU rendering is sustained maximum load, so avoid battery mode and heat-trapping environments.

## Registering a user path

Use **Add/edit tool path** in the GUI and choose one executable. The project neither downloads nor bundles commercial/store tools. A registered executable can run elevated, so verify its official source and signature yourself.
