# Mutagen sync setup and check

`Setup-Mutagen.ps1` installs [Mutagen](https://mutagen.io), sets up SSH access, creates two-way sync sessions between a Windows folder and one or more servers, and checks that they are healthy. One script, safe to run again at any time (it only does what is missing).

Mutagen two-way sync is a convenience, **not a backup**. A deleted file is deleted on both sides.

## What it does, in order

1. Installs the Windows OpenSSH client if missing (that one step needs an Administrator window).
2. Installs the pinned Mutagen version from the official GitHub release into `InstallDir` and adds it to your user PATH. The SHA-256 of the download is written to the log.
3. For each server: creates an SSH key if there is none, adds the SSH shortcut (Host alias) to your ssh config if the settings ask for one (the old file is copied first), and tests passwordless login. If the server does not accept the key yet, it prints a **step-by-step guide for the one manual step** (add the key to `authorized_keys`) and carries on. Run it again afterwards.
4. Starts the Mutagen daemon and registers it to start at every login.
5. Creates the sessions that do not exist yet. Existing sessions are never changed.
6. Checks everything (PASS or FAIL per line) and flushes each session.

## Settings file

Real addresses and usernames are kept out of the script. Copy the example and edit it:

```powershell
Copy-Item .\mutagen-config.example.psd1 .\mutagen-config.psd1
notepad .\mutagen-config.psd1
```

`mutagen-config.psd1` is listed in `.gitignore`. Do not publish it. Windows variables such as `%USERPROFILE%` are expanded, so the same file works on a new PC with a different username.

The file has three parts:

- `MutagenVersion` and `InstallDir`
- `Targets`: one per server (`SshHost`, `KeyFile`, optional `ConfigEntry` for an ssh alias, optional `Relay` to hand the key over through another server that already trusts this PC, and `KeyHelp` text shown in the manual step)
- `Sessions`: one per sync (`Name`, `Target`, `Mode`, `Local`, `Remote`, optional `Ignore` list)

## Use it

Set up and check (Terminal, ideally Administrator the first time so OpenSSH can be installed):

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-Mutagen.ps1
```

Check only (changes nothing except that it flushes sessions, which only delivers pending changes):

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-Mutagen.ps1 -CheckOnly
```

Preview what it would do:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-Mutagen.ps1 -DryRun
```

A full log is saved to your Desktop (`Mutagen-<mode>_<date>.txt`) with a short summary at the end. Exit code `0` means everything passed, `1` means something failed or a manual step is still needed.

## What the checks look at

- Mutagen installed at the wanted version, daemon answers, daemon registered to start at login
- Passwordless SSH to each server
- Per session: both ends connected, status "Watching for changes", no conflicts, no errors, no transition problems (a warning only, for example a file name Windows does not allow), and a successful flush

If a session reports conflicts, stop and resolve them by hand. Never force a resolution.

## Status

- Syntax-checked with PowerShell's parser. The session-status reader was tested on sample text in the format Mutagen 0.18 prints for `mutagen sync list`.
- **Not yet run against a live Mutagen and real servers at the time of writing.** Run `-DryRun` first.
- The Mutagen release is downloaded from `github.com/mutagen-io/mutagen`. The script logs the SHA-256 but does not compare it with a published value.
