# SSD dirty, sustained-write and integrity tests

Each storage test has a different purpose. Back up important data and confirm the target drive letter, free space, SMART health and temperature before writing. These tests consume flash endurance and are never started automatically.

| Purpose | Tool | Recommended use |
|---|---|---|
| Health, endurance and temperature | CrystalDiskInfo, smartmontools | Before and after every write test |
| Short performance baseline | CrystalDiskMark | Begin with a small test size |
| Bounded repeatable workload | Microsoft DiskSpd | Target an ordinary file with explicit size and duration limits |
| Sustained write after SLC cache and dirty-state behavior | Naraeon Dirty Test | Use a backed-up test volume and capture a sufficiently complete utilization graph |
| Full free-space write/read integrity | H2testw | Prefer an empty or freshly formatted test volume |
| Quick fake-capacity check for USB storage | GRC ValiDrive | Spot-check USB mass storage; confirm fully with H2testw when needed |

## Safe sequence

1. Record model, firmware, connection type and drive letter.
2. Check warnings, temperature and media errors with CrystalDiskInfo or `smartctl`.
3. Confirm that no important data remains and record the estimated write amount.
4. Start with a short baseline; run Naraeon or H2testw only when the question requires it.
5. Stop on excessive temperature rise, I/O error, device reconnect, or disk/controller events.
6. Capture SMART and Windows System events again after the test.

For Naraeon Dirty Test, evaluate post-SLC-cache throughput, graph variability and low-speed regions instead of quoting peak speed alone. Do not casually fill an operating-system or data-bearing volume.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id naraeon-dirty-test -AcknowledgeRisk -Language en
.\scripts\Open-PortableTool.ps1 -Root . -Id h2testw -AcknowledgeRisk -Language en
.\scripts\Open-PortableTool.ps1 -Root . -Id validrive -AcknowledgeRisk -Language en
```

These commands open the tool UI only; they do not start a test automatically.
