# Registering your own tool paths

If you already own a program, register its path instead of downloading it again. A registered path **takes precedence** over the bundled `tools/` search.

Settings live in `config/user-tool-paths.json`. That file is specific to one machine and is not committed to the repository.

## Register

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action set -Id hwinfo -Path "D:\Portable\HWiNFO64.exe"
```

`-Id` is the launcher id. List the available ids with:

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -List
```

## Review

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action list
```

| State | Meaning |
|---|---|
| `active` | Applied normally |
| `missing-file` | Nothing at that location; falls back to the bundled search |
| `not-an-executable` | Not a `.exe` |
| `disabled` | Temporarily off via `enabled: false` |

## Remove

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action remove -Id hwinfo
```

Removing an entry restores the bundled `tools/` search for that launcher.

## Validate every entry

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action verify
```

Checks the launcher id and file existence for every registered entry. It exits non-zero on a problem, so it fits into a pre-flight script.

## Path forms

- Absolute paths are recommended.
- A relative path resolves against the project folder.
- Environment variables work, for example `%ProgramFiles%\CPUID\CPU-Z\cpuz.exe`.

## Safety rules

Registration checks the following and saves nothing if any check fails.

1. The launcher id exists in the catalog.
2. The file is actually present.
3. The extension is `.exe`.

The Authenticode signature state is recorded alongside the entry. An unsigned file can still be registered, but the observed state is written to the file.

If a registered path later disappears, that tool falls back to the bundled search automatically. A diagnostic run is never interrupted by a stale entry.

## Notes

Risk tiers come from the catalog. Changing a path does not change a tool's risk tier or its confirmation flow. Repointing DDU, for example, still treats it as a system-changing tool that requires acknowledgement.

After changing a path, press `Refresh system information` in the GUI to pick it up.

