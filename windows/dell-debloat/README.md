# Dell-Debloat

One PowerShell script that **detects, removes and blocks** the Dell background software that shows up on a Dell PC, even after a clean Windows 11 install from Microsoft's own USB media.

It targets the Dell agents (SupportAssist, Connected Service Delivery, TechHub, Core Services, Client Management and similar). It does **not** touch BIOS, firmware, audio, panel, chipset or network drivers, Dell Command Update, or Windows Update itself.

## Why this exists

A clean Windows install on a Dell can still end up running Dell agents such as Dell TechHub, Dell Connected Service Delivery, SupportAssist PC Analytics and Dell Client Management Service. Removing the programs by hand worked, but some of them came back or left services behind.

On the PC this was built on (Dell Inspiron 16 Plus 7630, Windows 11 26H2), the evidence pointed to this chain:

1. The BIOS exposes a device called Dell Connected Service Delivery (`ACPI\DELL0033`).
2. Windows Update delivered a Dell "SoftwareComponent" driver for it (hardware ID `SWC\VID001&PID0001&DCSDSoftware`). The Windows Update history showed this in September 2026.
3. That component is what brings the Dell agents back. A second driver, `Root\DellInsDrv` (Dell Instrumentation), belongs to TechHub.

So the script removes the software and also blocks those two specific hardware IDs from installing again. Windows Update stays on and every other driver is untouched.

**Honest limits:** this chain is what the evidence on one PC showed. It is not proven for every Dell model, and it is not proven that the block stops everything. That is why there is a `-Verify` mode to run after the next Windows Update.

## What it does, in order

1. **Restore point** ("Before Dell-Debloat"). Skipped if you already made one in the last 3 hours.
2. **Block** the two Dell software-component hardware IDs through the Windows device-install deny list. It only blocks new installs and never disables a device that already works.
3. **Stop** the Dell watchdog services and processes (they otherwise re-install things while you uninstall).
4. **Uninstall** Dell programs through their own uninstallers (MSI), with retries if Windows Installer is busy.
5. **Remove** Dell Store apps, including the copy provisioned for new user accounts.
6. **Remove** leftover Dell services and scheduled tasks (exported first).
7. **Remove** only the two Dell software-component driver packages (exported first).
8. **Move** leftover Dell folders to a backup folder (not deleted).
9. **Check** the result and print PASS or FAIL per check.

## Use it

Open **Terminal (Admin)** (right-click Start). PowerShell 7 is fine, the script re-launches itself in Windows PowerShell 5.1 on purpose.

Preview first (changes nothing):

```powershell
powershell -ExecutionPolicy Bypass -File .\Dell-Debloat.ps1 -DryRun
```

Real run (shows the plan, then asks you to type YES):

```powershell
powershell -ExecutionPolicy Bypass -File .\Dell-Debloat.ps1
```

Check only (changes nothing). Run it after a restart and again after the next Windows Update:

```powershell
powershell -ExecutionPolicy Bypass -File .\Dell-Debloat.ps1 -Verify
```

Every run saves a full log to your Desktop (`Dell-Debloat_<mode>_<date>.txt`) and prints a short summary at the end.

### Fresh Windows install

Run it once right after installing Windows, ideally **before the first Windows Update**. If nothing Dell is installed yet, it still sets the block, so the Dell software drivers are refused when Windows Update offers them. Then run `-Verify` after the first round of updates.

### Switches

| Switch | Meaning |
|---|---|
| `-DryRun` | Show what would happen, change nothing |
| `-Verify` | Only run the PASS/FAIL checks |
| `-Unattended` | Do not ask for YES (for automation) |
| `-SkipRestorePoint` | Do not create a restore point |
| `-Force` | Run even if the PC does not report Dell as its maker |
| `-OutDir <folder>` | Where the log goes (default: Desktop) |

## What can be undone

| Change | Undo path |
|---|---|
| Everything, broadly | The restore point "Before Dell-Debloat" |
| Folders | Moved, not deleted, to `C:\ProgramData\DellDebloat-Backup\<date>\`. Move them back. |
| Services | Registry export saved there. `reg import` the `.reg` file, then restart. |
| Scheduled tasks | XML saved there. Re-create with `schtasks /create /xml`. |
| Driver packages | Exported there. `pnputil /add-driver <file>.inf /install` |
| Block list | Registry export saved there. Or delete the `DenyDeviceIDs` entries under `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions`. |
| **Uninstalled programs** | **Cannot be undone.** Reinstall from dell.com/support if you ever want them. |

When you are happy, delete the backup folder yourself to reclaim the space.

## Customise

The lists at the top of the script (the `CONFIG` section) control everything:

- `$AppRemove`: program names to remove (wildcards).
- `$KeepPattern`: anything matching is never touched (Dell Command Update, Power Manager, Display Manager and Peripheral Manager by default).
- `$SvcRemove`: exact service names to remove. Other Dell services are only **reported** as REVIEW and left alone.
- `$FolderRemove`: Dell folders to move to the backup.
- `$DriverInfRemove` and `$BlockHardwareIds`: the two driver packages and hardware IDs.

## Status

- Version 1.1. Syntax-checked with PowerShell's parser. Name-matching logic tested on sample names.
- Built from the output of read-only inventory scripts on a real Dell PC.
- **First live run (one Dell Inspiron 16 Plus 7630, Windows 11):** the program uninstall, service removal, block list and folder moves worked. Two driver packages did not delete in v1.0 because the removal order clashed with the block list (the uninstall step needs a device install, which the block forbids). v1.1 removes the device entries first and deletes the package without `/uninstall`. The v1.1 driver step has not been run live yet.
- Still unproven: whether Windows Update tries to bring the Dell software back. Run `-Verify` after the next Windows Update.
- Windows 11 only. Needs Administrator rights.

## Not covered

Dell programs that have no silent uninstaller are listed as `MANUAL` in the log. Remove them in Settings > Apps, then run the script again. Programs not on the remove list are shown as `REVIEW` and left alone.
