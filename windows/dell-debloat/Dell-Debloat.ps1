<#
.SYNOPSIS
  Dell-Debloat.ps1 : detect, remove and block Dell background software on Windows 11.

.DESCRIPTION
  One script for a fresh Windows install on a Dell PC. It does five things, in order:
    1. Makes a restore point (skipped if one exists from the last 3 hours).
    2. Blocks the Dell software driver entries that make Windows Update re-install the Dell agents.
       Only specific hardware IDs are blocked. Windows Update and all other drivers stay untouched.
    3. Stops and disables the Dell watchdog services, then uninstalls the Dell apps properly
       (MSI uninstallers and Store apps), then removes leftover services, tasks and folders.
    4. Removes only the Dell "software component" driver packages (never firmware, BIOS, audio, panel).
    5. Checks the result and prints PASS or FAIL for each check.

  Nothing is deleted without an undo path: folders are MOVED to a backup folder, services and tasks are
  exported first, driver packages are exported first. Uninstalled apps cannot be undone (reinstall from Dell).

  Modes:
    -DryRun   show exactly what would happen, change nothing (safe to run first)
    -Verify   change nothing, only print PASS/FAIL checks (run again after Windows Update and a reboot)
    (neither) do the real cleanup

  Edit the lists in the CONFIG section below to keep or remove other Dell items.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Dell-Debloat.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File .\Dell-Debloat.ps1
  powershell -ExecutionPolicy Bypass -File .\Dell-Debloat.ps1 -Verify
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Verify,
  [switch]$Unattended,        # skip the "type YES" question (for automation)
  [switch]$SkipRestorePoint,  # do not create a restore point
  [switch]$Force,             # run even if this does not look like a Dell PC
  [string]$OutDir = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host ""
  Write-Host "STOP: this needs an Administrator window." -ForegroundColor Red
  Write-Host "  1. Right-click the Start button, choose Terminal (Admin)."
  Write-Host "  2. Run the same command again."
  exit 2
}

# ------------------------------------------- always run in Windows PowerShell 5.1
# The Store app and driver cmdlets can misbehave in PowerShell 7, so re-launch if needed.
if ($PSVersionTable.PSEdition -eq 'Core') {
  $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $relaunch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
  foreach ($k in $PSBoundParameters.Keys) {
    $v = $PSBoundParameters[$k]
    if ($v -is [switch]) { if ($v.IsPresent) { $relaunch += "-$k" } }
    else { $relaunch += "-$k"; $relaunch += ('"{0}"' -f $v) }
  }
  & $ps51 @relaunch
  exit $LASTEXITCODE
}

# ======================================================================= CONFIG
# Names are matched with wildcards against the program name shown in Settings > Apps.
$AppRemove = @(
  'SupportAssist','Dell Connected Service Delivery','Dell Core Services','Dell Data Vault',
  'Dell Optimizer','Dell Digital Delivery','MyDell','Dell TechHub','Dell Update',
  'Dell Customer Connect','Dell Foundation Services','Dell Client Management',
  'Dell Registration','Dell Product Registration','Dell Mobile Connect','Dell Cinema',
  'Dell Remediation','PC-Doctor'
)
# Anything matching this is never touched (regular expression).
$KeepPattern = 'Dell Command|DellCommand|Power Manager|DellPower|Display Manager|Peripheral Manager'

# Services that are removed (exact service names). Other Dell services are only REPORTED.
$SvcRemove = @(
  'DellClientManagementService','DellConnectedServiceDelivery','DellTechHub','SupportAssistAgent',
  'DellDigitalDelivery','DellOptimizer','DDVDataCollector','DDVRulesProcessor','DDVCollectorSvcApi','DellUpdate'
)

# Folders that are MOVED to the backup folder if they exist (never deleted outright).
$FolderRemove = @(
  @{ Root = "$env:ProgramFiles\Dell";                Names = @('Dell Connected Service Delivery','Downloaded_Installations','DTP','Plugins','SupportAssistAgent','SupportAssist','DellDataVault','DellOptimizer','Dell Digital Delivery','TechHub') },
  @{ Root = "${env:ProgramFiles(x86)}\Dell";         Names = @('UpdateService','Dell Connected Service Delivery','SupportAssistAgent','SupportAssist') },
  @{ Root = "$env:ProgramData\Dell";                 Names = @('CoreServices.Client','Dell Connected Service Delivery','Dell TechHub','drivers','DTP','InventoryCollector','orca','Plugins','UIEngine','UpdatePackage','UpdateService','SupportAssist','SARemediation','DellDigitalDelivery') }
)

# Only these two Dell "software component" drivers are removed and blocked. Firmware, BIOS,
# audio, panel and the ACPI Dell device driver are never touched.
$DriverInfRemove = @('dcsdsoftware.inf','dellinstrumentation.inf')
$BlockHardwareIds = @('SWC\VID001&PID0001&DCSDSoftware','Root\DellInsDrv')
# ==================================================================== END CONFIG

$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$mode    = if ($Verify) { 'Verify' } elseif ($DryRun) { 'DryRun' } else { 'Run' }
$LogFile = Join-Path $OutDir "Dell-Debloat_${mode}_$stamp.txt"
$BackupDir = Join-Path $env:ProgramData "DellDebloat-Backup\$stamp"
$Count = @{ Done = 0; Failed = 0; Planned = 0; Review = 0; Pass = 0; Fail = 0; Warn = 0 }
$RebootNeeded = $false

function Log([string]$msg, [string]$color = 'Gray') {
  $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $msg
  Write-Host $line -ForegroundColor $color
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}
function Head([string]$t) { Log ''; Log "==================== $t ====================" 'Cyan' }

function Test-Keep([string]$name) { return ($name -match $KeepPattern) }
function Test-Remove([string]$name) {
  foreach ($p in $AppRemove) { if ($name -like "*$p*") { return $true } }
  return $false
}
function Do-Step([string]$What, [scriptblock]$Action) {
  if ($DryRun) { $Count.Planned++; Log "WOULD   $What" 'Cyan'; return $true }
  try { $null = & $Action; $Count.Done++; Log "DONE    $What" 'Green'; return $true }
  catch { $Count.Failed++; Log "FAILED  $What : $($_.Exception.Message)" 'Red'; return $false }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Log "Dell-Debloat  mode=$mode  started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ============================================================ PC and Windows info
Head '0. This PC'
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
Log ("PC       : {0} {1}" -f $cs.Manufacturer, $cs.Model)
Log ("Windows  : {0} build {1}" -f $os.Caption, $os.BuildNumber)
if ($cs.Manufacturer -notmatch 'Dell' -and -not $Force) {
  Log "This does not look like a Dell PC. Nothing done. Use -Force to run anyway." 'Yellow'
  exit 0
}

# =============================================================== detection (read only)
function Get-DellApps {
  $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and ($_.DisplayName -match 'Dell|SupportAssist|MyDell|PC-Doctor') })
}
function Get-DellAppx {
  @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
      ($_.Name -like 'DellInc.*' -or $_.Name -like 'Dell.*' -or $_.Name -like '*SupportAssist*') -and -not (Test-Keep $_.Name) })
}
function Get-DellProvisioned {
  @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
      ($_.DisplayName -like 'DellInc.*' -or $_.DisplayName -like 'Dell.*' -or $_.DisplayName -like '*SupportAssist*') -and -not (Test-Keep $_.DisplayName) })
}
function Get-DellServices {
  @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Dell|SupportAssist|DDV' -or $_.DisplayName -match 'Dell|SupportAssist' })
}
function Get-DellTasks {
  @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
      ($_.TaskName -match 'Dell|SupportAssist' -or $_.TaskPath -match 'Dell') -and -not (Test-Keep "$($_.TaskPath)$($_.TaskName)") })
}
function Get-DellProcesses {
  @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      ($_.ProcessName -like 'Dell.*' -or $_.ProcessName -like 'SupportAssist*' -or $_.ProcessName -like 'DellTechHub*' -or $_.ProcessName -like 'MyDell*' -or $_.ProcessName -like 'DellInstrumentation*') -and -not (Test-Keep $_.ProcessName) })
}
function Get-TargetDrivers {
  @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Where-Object {
      $f = $_.OriginalFileName; $hit = $false
      foreach ($n in $DriverInfRemove) { if ($f -like "*\${n}_*" -or $f -like "*\${n}") { $hit = $true } }
      $hit })
}
function Get-DetectedBlockIds {
  # Static list plus any hardware ID of a matching device that is already present.
  $ids = New-Object System.Collections.Generic.List[string]
  foreach ($i in $BlockHardwareIds) { if (-not $ids.Contains($i)) { $ids.Add($i) } }
  foreach ($d in (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'DCSD|DELL' })) {
    $hw = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data
    foreach ($h in @($hw)) { if ($h -match 'DCSDSoftware|DellInsDrv' -and -not $ids.Contains($h)) { $ids.Add($h) } }
  }
  return $ids.ToArray()
}

$PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$DenyKey   = "$PolicyKey\DenyDeviceIDs"

# ================================================================== VERIFY MODE
function Check([bool]$ok, [string]$pass, [string]$fail, [bool]$warnOnly = $false) {
  if ($ok) { $Count.Pass++; Log "PASS    $pass" 'Green' }
  elseif ($warnOnly) { $Count.Warn++; Log "WARN    $fail" 'Yellow' }
  else { $Count.Fail++; Log "FAIL    $fail" 'Red' }
}
function Run-Verify {
  Head 'CHECKS (nothing is changed)'
  $apps = Get-DellApps | Where-Object { (Test-Remove $_.DisplayName) -and -not (Test-Keep $_.DisplayName) }
  Check (@($apps).Count -eq 0) 'No unwanted Dell programs installed' ("Still installed: " + (($apps | ForEach-Object { $_.DisplayName }) -join '; '))
  $ax = Get-DellAppx; $pv = Get-DellProvisioned
  Check ((@($ax).Count + @($pv).Count) -eq 0) 'No Dell Store apps (installed or provisioned)' ("Store apps still present: " + (($ax | ForEach-Object { $_.Name }) -join '; '))
  $sv = Get-DellServices | Where-Object { $SvcRemove -contains $_.Name }
  Check (@($sv).Count -eq 0) 'Unwanted Dell services are gone' ("Services still present: " + (($sv | ForEach-Object { "$($_.Name) [$($_.State)]" }) -join '; '))
  $other = Get-DellServices | Where-Object { $SvcRemove -notcontains $_.Name -and -not (Test-Keep "$($_.Name) $($_.DisplayName)") }
  Check (@($other).Count -eq 0) 'No other Dell services to review' ("Other Dell services (not touched, please review): " + (($other | ForEach-Object { $_.Name }) -join '; ')) $true
  $pr = Get-DellProcesses
  Check (@($pr).Count -eq 0) 'No Dell background processes running' ("Running: " + (($pr | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join '; '))
  $tk = Get-DellTasks
  Check (@($tk).Count -eq 0) 'No Dell scheduled tasks' ("Tasks present: " + (($tk | ForEach-Object { $_.TaskName }) -join '; ')) $true
  $dr = Get-TargetDrivers
  Check (@($dr).Count -eq 0) 'Dell software driver packages removed' ("Driver packages present: " + (($dr | ForEach-Object { $_.Driver }) -join '; '))
  $present = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'DCSDDRIVER_COMPONENTS|DELLINSTRUMENTATION' -and $_.Status -ne 'Unknown' })
  Check ($present.Count -eq 0) 'Dell software-component devices are not present' ("Devices present: " + (($present | ForEach-Object { $_.InstanceId }) -join '; '))
  $deny = Get-ItemProperty $DenyKey -ErrorAction SilentlyContinue
  $denyVals = @(); if ($deny) { $denyVals = @($deny.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { $_.Value }) }
  $missingIds = @($BlockHardwareIds | Where-Object { $denyVals -notcontains $_ })
  $polOn = (Get-ItemProperty $PolicyKey -ErrorAction SilentlyContinue).DenyDeviceIDs -eq 1
  Check ($polOn -and $missingIds.Count -eq 0) 'Reinstall block is in place (hardware IDs on the deny list)' ("Block missing: " + ($missingIds -join '; '))
  $wu = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue).ExcludeWUDriversInQualityUpdate
  Check ($wu -ne 1) 'Windows Update driver delivery is NOT globally blocked' 'Windows Update drivers are globally excluded by a policy (not set by this script)'
  $wus = Get-Service wuauserv -ErrorAction SilentlyContinue
  Check ($wus -and $wus.StartType -ne 'Disabled') 'Windows Update service is not disabled' 'Windows Update service is disabled'
  $bad = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Error' })
  Check ($bad.Count -eq 0) 'No hardware devices report an error' ("Devices in error: " + (($bad | ForEach-Object { $_.FriendlyName }) -join '; ')) $true
}

if ($Verify) {
  Run-Verify
  Head 'SUMMARY'
  Log ("PASS {0}   FAIL {1}   WARN {2}" -f $Count.Pass, $Count.Fail, $Count.Warn) 'Cyan'
  Log 'What this does not prove: it cannot predict future Windows Update offers. Run it again after the next Windows Update and a restart.'
  Log "Log saved to: $LogFile" 'Green'
  exit $(if ($Count.Fail -eq 0) { 0 } else { 1 })
}

# ================================================================ 1. DETECT + PLAN
Head '1. What was found'
$dellApps = Get-DellApps
$toRemoveApps = @($dellApps | Where-Object { (Test-Remove $_.DisplayName) -and -not (Test-Keep $_.DisplayName) } |
  Sort-Object @{ Expression = { if ($_.DisplayName -like '*Core Services*') { 1 } else { 0 } } })
foreach ($a in $dellApps) {
  if ($toRemoveApps -contains $a) { Log ("REMOVE  program : {0} {1}" -f $a.DisplayName, $a.DisplayVersion) 'Yellow' }
  elseif (Test-Keep $a.DisplayName) { Log ("KEEP    program : {0}" -f $a.DisplayName) }
  else { $Count.Review++; Log ("REVIEW  program : {0} (not on the remove list, left alone)" -f $a.DisplayName) }
}
$appx = Get-DellAppx; $prov = Get-DellProvisioned
foreach ($x in $appx) { Log ("REMOVE  Store app: {0}" -f $x.Name) 'Yellow' }
foreach ($x in $prov) { Log ("REMOVE  Store app (provisioned for new users): {0}" -f $x.DisplayName) 'Yellow' }
$svcAll = Get-DellServices
$svcTargets = @($svcAll | Where-Object { $SvcRemove -contains $_.Name })
foreach ($s in $svcAll) {
  if ($SvcRemove -contains $s.Name) { Log ("REMOVE  service : {0} [{1}, {2}]" -f $s.Name, $s.State, $s.StartMode) 'Yellow' }
  elseif (Test-Keep "$($s.Name) $($s.DisplayName)") { Log ("KEEP    service : {0}" -f $s.Name) }
  else { $Count.Review++; Log ("REVIEW  service : {0} ({1}) not on the remove list, left alone" -f $s.Name, $s.DisplayName) }
}
$tasks = Get-DellTasks
foreach ($t in $tasks) { Log ("REMOVE  task    : {0}{1}" -f $t.TaskPath, $t.TaskName) 'Yellow' }
$drivers = Get-TargetDrivers
foreach ($d in $drivers) { Log ("REMOVE  driver  : {0} ({1})" -f $d.Driver, (Split-Path $d.OriginalFileName -Leaf)) 'Yellow' }
$folders = @()
foreach ($f in $FolderRemove) { foreach ($n in $f.Names) { $p = Join-Path $f.Root $n; if (Test-Path -LiteralPath $p) { $folders += $p } } }
foreach ($p in $folders) { Log ("MOVE    folder  : {0} (to backup, not deleted)" -f $p) 'Yellow' }
$blockIds = Get-DetectedBlockIds
foreach ($i in $blockIds) { Log ("BLOCK   hardware ID: {0}" -f $i) 'Yellow' }
Log 'Never touched: BIOS, firmware, audio, panel, ACPI Dell device driver, Dell Command Update, Windows Update itself.'

$nothing = (@($toRemoveApps).Count + @($appx).Count + @($prov).Count + @($svcTargets).Count + @($tasks).Count + @($drivers).Count + @($folders).Count) -eq 0

# ====================================================================== CONFIRM
if (-not $DryRun -and -not $Unattended) {
  Log ''
  Write-Host "Backups go to: $BackupDir" -ForegroundColor Cyan
  Write-Host "Type YES to apply the changes above, anything else cancels: " -NoNewline
  $answer = Read-Host
  if ($answer -ne 'YES') { Log 'Cancelled by the user. Nothing was changed.' 'Yellow'; exit 0 }
}
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }

# ========================================================= 2. RESTORE POINT
Head '2. Restore point'
if ($SkipRestorePoint) { Log 'Skipped (-SkipRestorePoint).' 'Yellow' }
else {
  $recent = $null
  try {
    $recent = Get-ComputerRestorePoint -ErrorAction Stop | Where-Object {
      ([Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)) -gt (Get-Date).AddHours(-3) } | Select-Object -First 1
  } catch {}
  if ($recent) { Log ("A restore point from the last 3 hours exists ({0}). Not making another." -f $recent.Description) 'Green' }
  else {
    $ok = Do-Step 'Create a restore point "Before Dell-Debloat"' {
      Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
      Checkpoint-Computer -Description 'Before Dell-Debloat' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    }
    if (-not $ok -and -not $DryRun) {
      Log 'Could not make a restore point, so nothing was changed. Fix System Protection or re-run with -SkipRestorePoint.' 'Red'
      exit 3
    }
  }
}

# =============================================== 3. BLOCK REINSTALL (before removal)
Head '3. Block the Dell software drivers from coming back'
Do-Step "Add $(@($blockIds).Count) hardware ID(s) to the device-install deny list (Windows Update stays on)" {
  if (-not (Test-Path $PolicyKey)) { New-Item -Path $PolicyKey -Force | Out-Null }
  if (-not (Test-Path $DenyKey))   { New-Item -Path $DenyKey -Force | Out-Null }
  reg.exe export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall' (Join-Path $BackupDir 'deviceinstall-policy-before.reg') /y 2>$null | Out-Null
  New-ItemProperty -Path $PolicyKey -Name 'DenyDeviceIDs' -Value 1 -PropertyType DWord -Force | Out-Null
  # 0 = only block NEW installs, never disable devices that already work
  New-ItemProperty -Path $PolicyKey -Name 'DenyDeviceIDsRetroactive' -Value 0 -PropertyType DWord -Force | Out-Null
  $existing = @((Get-ItemProperty $DenyKey).PSObject.Properties | Where-Object { $_.Name -match '^\d+$' })
  $have = @($existing | ForEach-Object { $_.Value })
  $next = 1; if ($existing.Count -gt 0) { $next = (($existing | ForEach-Object { [int]$_.Name } | Measure-Object -Maximum).Maximum) + 1 }
  foreach ($id in $blockIds) {
    if ($have -notcontains $id) { New-ItemProperty -Path $DenyKey -Name ([string]$next) -Value $id -PropertyType String -Force | Out-Null; $next++ }
  }
} | Out-Null

# ===================================== 4. STOP WATCHDOGS, KILL PROCESSES, UNINSTALL
Head '4. Stop the Dell watchdog services and processes'
foreach ($s in $svcTargets) {
  Do-Step "Disable and stop service $($s.Name)" {
    Set-Service -Name $s.Name -StartupType Disabled -ErrorAction Stop
    Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
  } | Out-Null
}
foreach ($p in (Get-DellProcesses)) {
  Do-Step "Stop process $($p.ProcessName) (PID $($p.Id))" { Stop-Process -Id $p.Id -Force -ErrorAction Stop } | Out-Null
}

Head '5. Uninstall Dell programs'
function Invoke-MsiUninstall([string]$guid, [string]$name) {
  $safe = ($name -replace '[^A-Za-z0-9]', '_')
  $msiLog = Join-Path $BackupDir "msi_$safe.log"
  for ($try = 1; $try -le 4; $try++) {
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $guid /qn /norestart /L*v `"$msiLog`"" -Wait -PassThru
    $c = $p.ExitCode
    if ($c -eq 3010 -or $c -eq 1641) { $script:RebootNeeded = $true; return }
    if ($c -eq 0 -or $c -eq 1605) { return }
    if ($c -eq 1618) { Start-Sleep -Seconds 30; continue }   # another installation is running, wait and retry
    throw "msiexec exit code $c (log: $msiLog)"
  }
  throw 'msiexec stayed busy (1618) after 4 tries. Restart Windows and run again.'
}
foreach ($a in $toRemoveApps) {
  $name = $a.DisplayName
  $guid = $null
  if ($a.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $guid = $a.PSChildName }
  elseif ($a.UninstallString -match '(\{[0-9A-Fa-f-]{36}\})') { $guid = $Matches[1] }
  if ($guid -and ($a.UninstallString -match 'msiexec' -or $a.WindowsInstaller -eq 1)) {
    Do-Step "Uninstall (MSI) $name" { Invoke-MsiUninstall $guid $name } | Out-Null
  }
  elseif ($a.QuietUninstallString) {
    Do-Step "Uninstall (quiet) $name" {
      $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $($a.QuietUninstallString)" -Wait -PassThru
      if ($p.ExitCode -notin 0, 3010) { throw "exit code $($p.ExitCode)" }
    } | Out-Null
  }
  else {
    $Count.Review++
    Log "MANUAL  $name has no silent uninstaller. Remove it in Settings > Apps > Installed apps, then run this script again." 'Yellow'
  }
}

Head '6. Remove Dell Store apps'
foreach ($x in $appx) {
  Do-Step "Remove Store app $($x.Name)" { Remove-AppxPackage -Package $x.PackageFullName -AllUsers -ErrorAction Stop } | Out-Null
}
foreach ($x in $prov) {
  Do-Step "Deprovision Store app $($x.DisplayName) (stops it returning for new users)" { Remove-AppxProvisionedPackage -Online -PackageName $x.PackageName -ErrorAction Stop | Out-Null } | Out-Null
}

# ================================================ 7. LEFTOVER SERVICES / TASKS
Head '7. Remove leftover services and scheduled tasks (exported first)'
foreach ($s in @(Get-DellServices | Where-Object { $SvcRemove -contains $_.Name })) {
  Do-Step "Delete leftover service $($s.Name) (registry export saved)" {
    reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($s.Name)" (Join-Path $BackupDir "service_$($s.Name).reg") /y 2>$null | Out-Null
    $r = & sc.exe delete $s.Name
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1060) { throw "sc.exe delete said: $r" }
  } | Out-Null
}
foreach ($t in @(Get-DellTasks)) {
  Do-Step "Remove task $($t.TaskPath)$($t.TaskName) (XML saved)" {
    $xml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath
    $safe = (("$($t.TaskPath)$($t.TaskName)") -replace '[\\/: ]', '_')
    Set-Content -Path (Join-Path $BackupDir "task_$safe.xml") -Value $xml -Encoding UTF8
    Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
  } | Out-Null
}

# ================================================================= 8. DRIVERS
Head '8. Remove the Dell software-component driver packages (exported first)'
foreach ($d in @(Get-TargetDrivers)) {
  Do-Step "Remove driver package $($d.Driver) ($(Split-Path $d.OriginalFileName -Leaf))" {
    $dest = Join-Path $BackupDir ("driver_" + $d.Driver -replace '\.inf$', '')
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $e = & pnputil.exe /export-driver $d.Driver $dest 2>&1 | Out-String
    $o = & pnputil.exe /delete-driver $d.Driver /uninstall /force 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { throw "pnputil said: $o" }
    if ($LASTEXITCODE -eq 3010) { $script:RebootNeeded = $true }
  } | Out-Null
}

# ================================================================= 9. FOLDERS
Head '9. Move leftover Dell folders to the backup folder'
foreach ($p in @($folders | Where-Object { Test-Path -LiteralPath $_ })) {
  Do-Step "Move $p" {
    $dest = Join-Path $BackupDir ('folder_' + ($p -replace '[:\\ ]', '_'))
    Move-Item -LiteralPath $p -Destination $dest -ErrorAction Stop
  } | Out-Null
}

# ================================================================ 10. CHECKS
if (-not $DryRun) {
  Head '10. Checks right now'
  Run-Verify
}

# ================================================================== SUMMARY
Head 'SUMMARY'
if ($DryRun) {
  Log ("Dry run: {0} action(s) would be taken. NOTHING was changed." -f $Count.Planned) 'Cyan'
  if ($nothing) { Log 'Nothing Dell-related to remove was found.' 'Green' }
  Log 'To apply for real, run the same command without -DryRun.'
} else {
  Log ("Done {0}   Failed {1}   Review/manual {2}   PASS {3}   FAIL {4}   WARN {5}" -f $Count.Done, $Count.Failed, $Count.Review, $Count.Pass, $Count.Fail, $Count.Warn) 'Cyan'
  Log "Backups (undo path): $BackupDir"
  Log 'Undo: restore point "Before Dell-Debloat" (or the one you made), reg import the saved .reg files, schtasks /create /xml for saved tasks, pnputil /add-driver for saved drivers, move folders back. Uninstalled programs need a reinstall from Dell.'
  if ($RebootNeeded) { Log 'A restart is needed to finish. Restart Windows, then run again with -Verify.' 'Yellow' }
  else { Log 'Next: restart Windows, then run again with -Verify. After the next Windows Update, run -Verify once more.' 'Yellow' }
  Log 'Not proven until you do that: whether Windows Update tries to bring the Dell software back.'
}
Log "Full log saved to: $LogFile" 'Green'
exit $(if ($Count.Failed -eq 0 -and $Count.Fail -eq 0) { 0 } else { 1 })
