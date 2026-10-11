<#
.SYNOPSIS
  Setup-Mutagen.ps1 : install Mutagen, set up SSH, create the sync sessions and check them. One script.

.DESCRIPTION
  Reads a small settings file (mutagen-config.psd1, next to this script) that lists the servers and
  sync sessions, then does everything in order:
    1. Installs the OpenSSH client if it is missing (needs an Administrator window for that one step).
    2. Installs Mutagen (pinned version from the settings file) and puts it on your PATH.
    3. Creates an SSH key for each server if there is none, and tests passwordless login.
       If a server does not accept the key yet, the script prints a step-by-step guide for the one
       manual step (adding the key) and carries on with the other servers. Re-run it afterwards.
    4. Adds the SSH shortcut (Host alias) to your ssh config where the settings file asks for one.
    5. Starts the Mutagen helper (daemon) and makes it start at every login.
    6. Creates the sync sessions that do not exist yet. Existing sessions are left alone.
    7. Checks everything and prints PASS or FAIL per check, then flushes each session.

  Safe to run again at any time: it only does what is missing.

  Modes:
    -CheckOnly  change nothing, only run the checks (also flushes sessions, which only pushes pending changes)
    -DryRun     show what would be done, change nothing

  Your real IP addresses, usernames and folders live only in mutagen-config.psd1. Copy
  mutagen-config.example.psd1 to mutagen-config.psd1 and edit it. Never publish the real one.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Setup-Mutagen.ps1
  powershell -ExecutionPolicy Bypass -File .\Setup-Mutagen.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'mutagen-config.psd1'),
  [switch]$CheckOnly,
  [switch]$DryRun,
  [string]$OutDir = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$mode    = if ($CheckOnly) { 'Check' } elseif ($DryRun) { 'DryRun' } else { 'Setup' }
$LogFile = Join-Path $OutDir "Mutagen-${mode}_$stamp.txt"
$Count   = @{ Done = 0; Failed = 0; Planned = 0; Pass = 0; Fail = 0; Warn = 0 }
$Manual  = New-Object System.Collections.Generic.List[string]
$ReadyTargets = @{}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Log([string]$msg, [string]$color = 'Gray') {
  $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $msg
  Write-Host $line -ForegroundColor $color
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}
function Head([string]$t) { Log ''; Log "==================== $t ====================" 'Cyan' }
function Expand([string]$s) { if ($null -eq $s) { return $null }; return [Environment]::ExpandEnvironmentVariables($s) }
function Do-Step([string]$What, [scriptblock]$Action) {
  if ($DryRun -or $CheckOnly) { if ($DryRun) { $Count.Planned++; Log "WOULD   $What" 'Cyan' }; return $true }
  try { $null = & $Action; $Count.Done++; Log "DONE    $What" 'Green'; return $true }
  catch { $Count.Failed++; Log "FAILED  $What : $($_.Exception.Message)" 'Red'; return $false }
}
function Check([bool]$ok, [string]$pass, [string]$fail, [bool]$warnOnly = $false) {
  if ($ok) { $Count.Pass++; Log "PASS    $pass" 'Green' }
  elseif ($warnOnly) { $Count.Warn++; Log "WARN    $fail" 'Yellow' }
  else { $Count.Fail++; Log "FAIL    $fail" 'Red' }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Log "Setup-Mutagen  mode=$mode  started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ------------------------------------------------------------------ settings file
Head '0. Settings file'
if (-not (Test-Path -LiteralPath $ConfigPath)) {
  Log "Settings file not found: $ConfigPath" 'Red'
  Log 'Step by step:'
  Log '  1. In the same folder as this script, copy mutagen-config.example.psd1 to mutagen-config.psd1'
  Log '  2. Open mutagen-config.psd1 in Notepad and replace the example values with yours'
  Log '  3. Run this script again'
  exit 2
}
$cfg = Import-PowerShellDataFile -Path $ConfigPath
$WantVer    = [string]$cfg.MutagenVersion
$InstallDir = Expand $cfg.InstallDir
Log "Settings : $ConfigPath"
Log "Mutagen  : version $WantVer into $InstallDir"
Log ("Servers  : {0}    Sessions: {1}" -f @($cfg.Targets).Count, @($cfg.Sessions).Count)

# ------------------------------------------------------------------ helpers
function Find-Mutagen {
  $c = Get-Command mutagen -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $p = Join-Path $InstallDir 'mutagen.exe'
  if (Test-Path -LiteralPath $p) { return $p }
  return $null
}
function Get-MutagenVersion([string]$exe) {
  try { $v = (& $exe version 2>&1 | Out-String); if ($v -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] } } catch {}
  return $null
}
function Get-SessionBlocks([string]$exe) {
  $txt = & $exe sync list 2>&1 | Out-String
  $blocks = @{}; $cur = $null
  foreach ($line in ($txt -split "`r?`n")) {
    if ($line -match '^Name:\s*(.+?)\s*$') { $cur = $Matches[1]; $blocks[$cur] = New-Object System.Collections.Generic.List[string]; continue }
    if ($line -match '^-{10,}') { $cur = $null; continue }
    if ($cur) { $blocks[$cur].Add($line) }
  }
  return $blocks
}
function Test-Ssh($target, [string]$key) {
  $sshArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=accept-new')
  if ($key -and (Test-Path -LiteralPath $key) -and -not $target.ConfigEntry) { $sshArgs += @('-i', $key) }
  $out = & ssh.exe @sshArgs $target.SshHost 'echo ok' 2>&1 | Out-String
  return ($LASTEXITCODE -eq 0 -and $out -match 'ok')
}

# ================================================================= 1. OpenSSH client
Head '1. OpenSSH client'
if (Get-Command ssh.exe -ErrorAction SilentlyContinue) { Log 'OpenSSH client present.' 'Green' }
elseif ($CheckOnly) { Check $false '' 'OpenSSH client (ssh.exe) is missing' }
else {
  if ($isAdmin -or $DryRun) {
    Do-Step 'Install the Windows OpenSSH client' { Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' -ErrorAction Stop | Out-Null } | Out-Null
  } else {
    $Manual.Add('Install the OpenSSH client: Settings > System > Optional features > View features > search "OpenSSH Client" > Add. Or run this script from an Administrator window.')
    Log 'OpenSSH client is missing and this window is not Administrator.' 'Yellow'
    Log '  Step by step: Settings > System > Optional features > View features > type OpenSSH Client > tick it > Next > Add.'
    Log '  Then open a NEW PowerShell window and run this script again.'
  }
}

# ================================================================= 2. Mutagen install
Head '2. Mutagen'
$mutagen = Find-Mutagen
$have = if ($mutagen) { Get-MutagenVersion $mutagen } else { $null }
if ($have -and $have -ge [version]$WantVer) { Log "Mutagen $have found at $mutagen (wanted $WantVer or newer)." 'Green' }
elseif ($CheckOnly) { Check $false '' ("Mutagen missing or older than $WantVer (found: {0})" -f $(if ($have) { $have } else { 'none' })) }
else {
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
  $url  = "https://github.com/mutagen-io/mutagen/releases/download/v$WantVer/mutagen_windows_${arch}_v$WantVer.zip"
  $zip  = Join-Path $env:TEMP "mutagen_$WantVer.zip"
  Do-Step "Download Mutagen $WantVer ($arch) from the official GitHub release" {
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Log ("          SHA-256 of the download: {0}" -f (Get-FileHash -Path $zip -Algorithm SHA256).Hash)
  } | Out-Null
  Do-Step "Unpack Mutagen into $InstallDir" {
    if ($mutagen) { & $mutagen daemon stop 2>&1 | Out-Null }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
  } | Out-Null
  Do-Step 'Add the Mutagen folder to your PATH (your user only)' {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $InstallDir) {
      [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $InstallDir), 'User')
    }
    if (($env:Path -split ';') -notcontains $InstallDir) { $env:Path = $env:Path + ';' + $InstallDir }
  } | Out-Null
  $mutagen = Find-Mutagen
}
if (-not $mutagen -and -not $DryRun) {
  Log 'Mutagen is not available, so the rest cannot run. Fix the error above and run again.' 'Red'
  if ($Manual.Count -gt 0) { $Manual | ForEach-Object { Log "MANUAL STEP: $_" 'Yellow' } }
  exit 1
}

# ================================================================= 3. SSH keys per server
Head '3. SSH keys and passwordless login'
foreach ($t in @($cfg.Targets)) {
  $key = Expand $t.KeyFile
  if (-not (Test-Path -LiteralPath $key)) {
    Do-Step "Create SSH key for '$($t.Name)' at $key" {
      New-Item -ItemType Directory -Force -Path (Split-Path $key) | Out-Null
      & ssh-keygen.exe -t ed25519 -f $key -N '""' -C ("mutagen-{0}-{1}" -f $t.Name, $env:COMPUTERNAME) | Out-Null
      if (-not (Test-Path -LiteralPath $key)) { throw 'ssh-keygen did not create the key' }
    } | Out-Null
  } else { Log "Key for '$($t.Name)' exists: $key" }

  # ssh config shortcut (Host alias), written before the login test so the alias works
  if ($t.ConfigEntry) {
    $ce = $t.ConfigEntry
    $cfgFile = Join-Path $env:USERPROFILE '.ssh\config'
    $existing = if (Test-Path -LiteralPath $cfgFile) { Get-Content -LiteralPath $cfgFile -Raw } else { '' }
    if ($existing -match ("(?m)^\s*Host\s+" + [regex]::Escape($ce.Alias) + "\s*$")) { Log "ssh config already has 'Host $($ce.Alias)'. Left as it is." }
    else {
      Do-Step "Add 'Host $($ce.Alias)' to $cfgFile (copy of the old file saved first)" {
        New-Item -ItemType Directory -Force -Path (Split-Path $cfgFile) | Out-Null
        if (Test-Path -LiteralPath $cfgFile) { Copy-Item -LiteralPath $cfgFile -Destination "$cfgFile.bak-$stamp" -Force }
        $block = "`r`nHost {0}`r`n    HostName {1}`r`n    User {2}`r`n    IdentityFile {3}`r`n    IdentitiesOnly yes`r`n" -f $ce.Alias, $ce.HostName, $ce.User, $key
        Add-Content -LiteralPath $cfgFile -Value $block -Encoding ASCII
      } | Out-Null
    }
  }

  if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) { continue }
  if (Test-Path -LiteralPath $key) {
    if (Test-Ssh $t $key) { $ReadyTargets[$t.Name] = $true; Log "Passwordless login works for '$($t.Name)'." 'Green'; continue }
  }
  if ($CheckOnly) { continue }

  # try the optional relay through another server that already trusts this PC
  if ($t.Relay -and (Test-Path -LiteralPath "$key.pub")) {
    $r = $t.Relay
    Log "Login to '$($t.Name)' not accepted yet. Trying to hand the key over through $($r.Via) ..."
    $pub = Get-Content -LiteralPath "$key.pub" -Raw
    $inner = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $mid = "ssh -i $($r.ViaKey) $($r.User)@$($r.Host) '$inner'"
    if (-not $DryRun) {
      $pub | & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $r.Via $mid 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0 -and (Test-Ssh $t $key)) { $ReadyTargets[$t.Name] = $true; Log "Key handed over. Login to '$($t.Name)' works." 'Green'; continue }
    } else { Log "WOULD   hand the key to '$($t.Name)' through $($r.Via)" 'Cyan'; continue }
  }
  if ($DryRun) { continue }

  # the one manual step, explained step by step
  $pubText = if (Test-Path -LiteralPath "$key.pub") { (Get-Content -LiteralPath "$key.pub" -Raw).Trim() } else { '(key file missing)' }
  $Manual.Add("Add this PC's key to '$($t.Name)' (see the steps in the log), then run this script again.")
  Log ''
  Log "MANUAL STEP for '$($t.Name)': the server does not accept this PC's key yet." 'Yellow'
  Log '  What  : add the public key below as a NEW LINE in the file authorized_keys on that server.'
  if ($t.KeyHelp) { Log ('  Where : ' + $t.KeyHelp) }
  else { Log '  Where : log in to the server (web console or an existing key), open the file ~/.ssh/authorized_keys of the user in the Address.' }
  Log '  How   : 1) copy the whole line below   2) paste it on a new line at the end of that file   3) save   4) run this script again'
  Log "  Key   : $pubText"
  Log ''
}

# ================================================================= 4. Daemon + autostart
Head '4. Mutagen helper (daemon) and start at login'
if ($mutagen) {
  Do-Step 'Start the Mutagen daemon' { & $mutagen daemon start 2>&1 | Out-Null } | Out-Null
  $runKey = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
  $hasRun = $false
  if ($runKey) { foreach ($p in $runKey.PSObject.Properties) { if ("$($p.Value)" -match 'mutagen') { $hasRun = $true } } }
  if ($hasRun) { Log 'Start at login is already registered.' 'Green' }
  else { Do-Step 'Register the daemon to start at every login (mutagen daemon register)' { & $mutagen daemon register 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" } } | Out-Null }
}

# ================================================================= 5. Sessions
Head '5. Sync sessions'
if ($mutagen) { $blocks = Get-SessionBlocks $mutagen } else { $blocks = @{} }
foreach ($s in @($cfg.Sessions)) {
  $local = Expand $s.Local
  if ($blocks.ContainsKey($s.Name)) { Log "Session '$($s.Name)' already exists. Left as it is." 'Green'; continue }
  if ($s.Target -and -not $ReadyTargets[$s.Target] -and -not $DryRun -and -not $CheckOnly) {
    Log "Session '$($s.Name)' skipped: server '$($s.Target)' is not ready yet (see the manual step above)." 'Yellow'; continue
  }
  if ($CheckOnly) { continue }
  Do-Step "Create the local folder $local" { New-Item -ItemType Directory -Force -Path $local | Out-Null } | Out-Null
  $mode2 = if ($s.Mode) { $s.Mode } else { 'two-way-safe' }
  Do-Step "Create session '$($s.Name)' ($mode2): $local <-> $($s.Remote)" {
    $a = @('sync','create',"--name=$($s.Name)","--sync-mode=$mode2")
    foreach ($ig in @($s.Ignore)) { if ($ig) { $a += "--ignore=$ig" } }
    $a += @($local, $s.Remote)
    $o = & $mutagen @a 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $o.Trim() }
  } | Out-Null
}

# ================================================================= 6. Checks
Head '6. Checks'
$mutagen = Find-Mutagen
if (-not $mutagen) { Check $false '' 'Mutagen is not installed' }
else {
  $ver = Get-MutagenVersion $mutagen
  Check ($ver -and $ver -ge [version]$WantVer) "Mutagen $ver installed ($mutagen)" "Mutagen version is $ver, wanted $WantVer or newer"
  $listOk = $true
  try { & $mutagen sync list 2>&1 | Out-Null; $listOk = ($LASTEXITCODE -eq 0) } catch { $listOk = $false }
  Check $listOk 'Mutagen daemon answers' 'Mutagen daemon does not answer. Try: mutagen daemon start'
  $runKey = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
  $hasRun = $false
  if ($runKey) { foreach ($p in $runKey.PSObject.Properties) { if ("$($p.Value)" -match 'mutagen') { $hasRun = $true } } }
  Check $hasRun 'Daemon is registered to start at login' 'Daemon is not registered to start at login. Run: mutagen daemon register'

  foreach ($t in @($cfg.Targets)) {
    $key = Expand $t.KeyFile
    $ok = (Get-Command ssh.exe -ErrorAction SilentlyContinue) -and (Test-Ssh $t $key)
    Check ([bool]$ok) "Passwordless login works: $($t.Name)" "Passwordless login does NOT work: $($t.Name)"
  }

  $blocks = Get-SessionBlocks $mutagen
  foreach ($s in @($cfg.Sessions)) {
    $n = $s.Name
    if (-not $blocks.ContainsKey($n)) { Check $false '' "Session '$n' does not exist"; continue }
    $b = @($blocks[$n])
    $conn = @($b | Where-Object { $_ -match 'Connection state:' })
    Check ($conn.Count -ge 2 -and @($conn | Where-Object { $_ -notmatch 'state:\s*Connected\s*$' }).Count -eq 0) "'$n': both ends connected" "'$n': an end is not connected"
    $status = ($b | Where-Object { $_ -match '^Status:' } | Select-Object -First 1)
    Check ($status -match 'Watching for changes') "'$n': watching for changes" ("'$n': status is: " + $status)
    Check (@($b | Where-Object { $_ -match '^\s*Conflicts:' }).Count -eq 0) "'$n': no conflicts" "'$n': conflicts reported. Stop and resolve them by hand. Do not force a resolution."
    Check (@($b | Where-Object { $_ -match '^\s*Last error:' }).Count -eq 0) "'$n': no errors" "'$n': an error is reported (run: mutagen sync list)"
    Check (@($b | Where-Object { $_ -match 'problems?:' -and $_ -notmatch ':\s*0\s*$' }).Count -eq 0) "'$n': no transition problems" "'$n': transition problems reported (a file name that Windows does not allow is harmless)" $true
    $f = & $mutagen sync flush $n 2>&1 | Out-String
    Check ($LASTEXITCODE -eq 0) "'$n': flushed, pending changes delivered" ("'$n': flush failed: " + $f.Trim())
  }
}

# ================================================================= Summary
Head 'SUMMARY'
if ($DryRun) { Log ("Dry run: {0} action(s) would be taken. NOTHING was changed." -f $Count.Planned) 'Cyan' }
else { Log ("Done {0}   Failed {1}   PASS {2}   FAIL {3}   WARN {4}" -f $Count.Done, $Count.Failed, $Count.Pass, $Count.Fail, $Count.Warn) 'Cyan' }
if ($Manual.Count -gt 0) { Log ''; foreach ($m in $Manual) { Log "MANUAL STEP STILL NEEDED: $m" 'Yellow' } }
Log 'What this does not prove: that the files on both sides are identical. A flush plus "no conflicts" is the evidence used here.'
Log "Full log saved to: $LogFile" 'Green'
exit $(if ($Count.Failed -eq 0 -and $Count.Fail -eq 0 -and $Manual.Count -eq 0) { 0 } else { 1 })
