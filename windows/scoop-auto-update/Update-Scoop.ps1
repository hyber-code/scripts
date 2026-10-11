$ErrorActionPreference = "Stop"

$WorkDir  = Join-Path $env:USERPROFILE "Scoop-AutoUpdate"
$LogDir   = Join-Path $WorkDir "Logs"
$StateFile = Join-Path $WorkDir "last-successful-slot.txt"
$ScoopCmd = Join-Path $env:USERPROFILE "scoop\shims\scoop.cmd"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Two update periods each month: 1st–14th and 15th–end.
$Today = Get-Date
$SlotDay = if ($Today.Day -ge 15) { "15" } else { "01" }
$CurrentSlot = "{0:yyyy-MM}-$SlotDay" -f $Today

if (Test-Path $StateFile) {
    $LastSlot = (Get-Content $StateFile -Raw).Trim()
    if ($LastSlot -eq $CurrentSlot) {
        exit 0
    }
}

if (-not (Test-Path $ScoopCmd)) {
    throw "Scoop was not found at: $ScoopCmd"
}

$LogFile = Join-Path $LogDir ("Scoop-Update-{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force

try {
    Write-Host "Updating Scoop and buckets..."
    & $ScoopCmd update
    if ($LASTEXITCODE -ne 0) {
        throw "Scoop/bucket update failed with exit code $LASTEXITCODE."
    }

    Write-Host "Updating all Scoop applications..."
    & $ScoopCmd update --all
    if ($LASTEXITCODE -ne 0) {
        throw "Application update failed with exit code $LASTEXITCODE."
    }

    Write-Host "Removing old application versions..."
    & $ScoopCmd cleanup --all
    if ($LASTEXITCODE -ne 0) {
        throw "Scoop cleanup failed with exit code $LASTEXITCODE."
    }

    Write-Host "Clearing downloaded installer cache..."
    & $ScoopCmd cache rm *

    Write-Host "Checking final status..."
    & $ScoopCmd status

    Set-Content -Path $StateFile -Value $CurrentSlot -Encoding ASCII
    Write-Host "Scoop update completed successfully for $CurrentSlot."
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript
}

