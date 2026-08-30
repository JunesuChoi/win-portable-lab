# BatteryInfoView detailed usage

Shows a notebook battery's real remaining capacity and how far it has worn. Windows only reports the remaining percentage, while this tool reports current full-charge capacity against the designed capacity plus the charge cycle count. Use it to judge when a battery needs replacing.

Launch id is `batteryinfoview`, read-only.

## Key fields

| Field | Meaning | How to read it |
|---|---|---|
| Designed Capacity | Capacity as manufactured | The reference value |
| Full Charged Capacity | Actual capacity at full charge today | Compare against designed capacity |
| Battery Wear Level | Wear percentage | Further from 100% means more ageing |
| Charge/Discharge Cycles | Number of cycles | Compare with the vendor's rated cycles |
| Voltage | Present voltage | Cell condition reference |
| Charge/Discharge Rate | Present charge or discharge rate | Real consumption in use |
| Power State | Charging, discharging, on AC | Current state |

## Wear interpretation

| Wear level | Meaning |
|---|---|
| 90% or above | Good |
| 80 to 90% | Normal ageing |
| 60 to 80% | Noticeably shorter runtime; consider replacement depending on use |
| Below 60% | Replacement recommended |

Read the cycle count alongside it. Many notebook batteries are rated for 300 to 500 cycles. Heavy wear at a low cycle count often points to high-temperature operation or being kept permanently at full charge.

## Procedure

1. Running on battery, with the AC adapter removed, exposes the discharge rate.
2. Read the fields and, if needed, save a report from the `File` menu.
3. When checking a used notebook, record wear level and cycle count together. Wear level alone cannot reveal a replaced battery.

## Notes

Some batteries do not report designed capacity or cycle count. Zero or blank values mean the battery firmware does not expose them, not a tool failure. Desktops have no battery to report.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id batteryinfoview -Language en
```

