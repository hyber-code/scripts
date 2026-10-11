# Scoop auto-update

`Update-Scoop.ps1` keeps [Scoop](https://scoop.sh) and its apps up to date and cleans up after itself, **twice a month** (about every 15 days).

## What one run does

1. Works out the current slot: the 1st to 14th of the month is slot `YYYY-MM-01`, the 15th to the end is `YYYY-MM-15`.
2. If that slot already finished successfully, it exits straight away. So you can schedule it daily or at every logon and it only acts twice a month.
3. Otherwise it runs, with a log of the whole session:
   - `scoop update` (Scoop and buckets)
   - `scoop update --all` (all apps)
   - `scoop cleanup --all` (removes old versions)
   - `scoop cache rm *` (clears downloaded installers)
   - `scoop status`
4. Only if every step succeeded it records the slot, so a failed run is retried at the next start.

## Files and folders

Everything lives in `%USERPROFILE%\Scoop-AutoUpdate`:

| Item | Purpose |
|---|---|
| `Update-Scoop.ps1` | The script |
| `Logs\Scoop-Update-<date>.log` | One log per real run |
| `last-successful-slot.txt` | The last slot that finished, for example `2026-09-15` |

Scoop must be installed at `%USERPROFILE%\scoop` (the script uses its `scoop.cmd` shim).

## Run it

Once by hand:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Scoop-AutoUpdate\Update-Scoop.ps1"
```

To run it automatically, create a Windows Task Scheduler task that runs the same command daily or at logon. The slot check makes extra runs harmless. Exit code `0` means done or already done, `1` means a step failed (see the log).

## Notes

- `scoop cache rm *` also removes cached installers you may want for an offline reinstall.
- Nothing here is personal or machine specific. It only uses `%USERPROFILE%`.
