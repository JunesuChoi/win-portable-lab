# WizTree detailed usage

Shows quickly where disk space went. It reads the NTFS master file table directly, so it finishes far faster than walking folders one by one. In this project it is used to judge whether free space is sufficient before a write test.

Launch id is `wiztree`, read-only. Direct MFT access requires administrator rights.

## Purpose in this project

H2testw and the Naraeon Dirty Test fill free space. Before running them, confirm:

1. The target drive's actual free space matches expectations.
2. Whether large temporary files remain that can be removed.
3. Whether a previous test left its test files behind.

## Reading the display

| Element | Meaning |
|---|---|
| Tree list | Folders sorted largest first |
| Size bar | Share relative to the parent folder |
| Treemap | File size expressed as rectangle area |
| Allocated column | Space actually allocated on disk |
| Files column | Number of files below |

Real file size and allocated size can differ; many small files allocate more. For free-space decisions, allocated size is the figure that matters.

## Procedure

1. Choose the drive at the top and press `Scan`.
2. Review the largest folders in sorted order.
3. Use the `File View` tab for totals by file type.
4. Export the list to CSV if a record is needed.

## Notes

WizTree can delete files. This project uses it only to inspect space and never automates deletion. Removing large files from system folders at random can damage Windows. If you are not certain something is safe to delete, leave it.

Free for non-commercial use; business use requires a licence.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id wiztree -Language en
```

