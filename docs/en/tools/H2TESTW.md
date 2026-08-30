# H2testw detailed usage

Writes a verifiable pattern into free space, reads it back and compares. It exposes fake USB sticks and SD cards whose declared capacity differs from reality, and confirms a device stores data intact. It is an integrity tool, not a speed measurement.

Launch id is `h2testw`, risk is a high-write test that fills all free space.

## Before starting

1. Confirm no important data is on the target drive.
2. A freshly formatted device gives the most accurate result; with existing files only the remaining space is tested.
3. For USB devices, connect directly to a rear port where possible. Going through a hub makes it hard to tell a connection fault from a device fault.
4. Estimate the duration. Depending on capacity and speed it can take hours.

## Settings

The program offers German and English. Select English at the top.

| Setting | Meaning | Recommendation |
|---|---|---|
| Select target | The drive to test | Double-check the drive letter |
| all available space | Test all remaining space | Recommended for an accurate verdict |
| only | Test a specified amount | When time is short |
| endless verify | Repeating verification | Chasing intermittent errors |

`Write + Verify` is the default action. Use `Verify` alone to re-check data already written.

## Reading the result

A verdict is printed when the test completes.

| Result | Meaning |
|---|---|
| `Test finished without errors` | Healthy. Capacity and integrity both confirmed |
| `The media is likely to be defective` | Faulty. Data corruption occurred |
| Written amount far below declared capacity | Fake capacity; the controller is lying about size |
| Errors concentrated from one point onward | Possible NAND defect in that region |

If even one byte is in error, do not keep important data on that device. A fake-capacity stick overwrites earlier data past a certain point, so copying appears to succeed while files corrupt later.

## Pass criteria

| Goal | Recommended setting | Pass condition |
|---|---|---|
| Accepting a new device | all available space | Zero bytes in error |
| Suspected fake capacity | all available space | Written amount matches declared capacity |
| Chasing intermittent errors | endless verify | Zero errors across repeats |
| Quick check when time is short | `only` with a partial size | Zero errors, though not a full guarantee |

## Cleanup afterwards

Delete the `.h2w` files the test created, or they keep occupying space. Keeping them allows a later `Verify` run, so retain them if re-verification is planned.

## Relationship to other tools

ValiDrive spot-checks declared capacity within minutes. Use ValiDrive for fast screening and H2testw for a definitive verdict. For performance questions CrystalDiskMark fits, and sustained SSD write behaviour belongs to the Naraeon Dirty Test.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id h2testw -AcknowledgeRisk -Language en
```

