#Requires -RunAsAdministrator

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " CommandLoggerPS7 -- Setup" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

$root   = "C:\Users\Public\CommandHistory"
$system = "$root\_system"
$src    = Split-Path $PSCommandPath -Parent

# -------------------------------------------------------------
# [1/6] Ensure PowerShell 7 is installed
# -------------------------------------------------------------
Write-Host "[1/6] Checking for PowerShell 7..." -ForegroundColor Yellow

$pwshExe = $null
$pwshCandidates = @(
    "C:\Program Files\PowerShell\7\pwsh.exe",
    "$env:ProgramFiles\PowerShell\7\pwsh.exe"
)
foreach ($c in $pwshCandidates) { if (Test-Path $c) { $pwshExe = $c; break } }

if (-not $pwshExe) {
    Write-Host "  PowerShell 7 not found. Installing via winget..." -ForegroundColor Gray
    try {
        winget install --id Microsoft.PowerShell --source winget `
            --accept-source-agreements --accept-package-agreements -h | Out-Null
    } catch {
        Write-Host "  winget install failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    foreach ($c in $pwshCandidates) { if (Test-Path $c) { $pwshExe = $c; break } }
    if (-not $pwshExe) {
        Write-Host "  PowerShell 7 still not found. Aborting." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  OK -- $pwshExe" -ForegroundColor Green

# -------------------------------------------------------------
# [2/6] Create folders
# -------------------------------------------------------------
Write-Host "[2/6] Creating folders..." -ForegroundColor Yellow
@($root, $system, "$root\TXT", "$root\HTML", "$root\CSV") | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}
Write-Host "  OK -- $root" -ForegroundColor Green

# -------------------------------------------------------------
# [3/6] Copy unified core script
# -------------------------------------------------------------
Write-Host "[3/6] Copying CommandLoggerPS7.ps1..." -ForegroundColor Yellow
Copy-Item "$src\system\CommandLoggerPS7.ps1" "$system\CommandLoggerPS7.ps1" -Force
Write-Host "  OK" -ForegroundColor Green

# -------------------------------------------------------------
# [4/6] Execution policy + PS7 profile
# -------------------------------------------------------------
Write-Host "[4/6] Setting execution policy and PS7 profile..." -ForegroundColor Yellow
try { Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop } catch {}

$ps7ProfilePath = Join-Path (Split-Path $pwshExe -Parent) "profile.ps1"
$loggerBlock = @"
# -- CommandLoggerPS7 --
if (-not `$Global:CHL_Loaded) {
    `$Global:CHL_Loaded = `$true
    if (Test-Path "C:\Users\Public\CommandHistory\_system\CommandLoggerPS7.ps1") {
        try { . "C:\Users\Public\CommandHistory\_system\CommandLoggerPS7.ps1" } catch {}
    }
}
# -- End CommandLoggerPS7 --
"@

if (-not (Test-Path (Split-Path $ps7ProfilePath -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path $ps7ProfilePath -Parent) -Force | Out-Null
}

$existing = if (Test-Path $ps7ProfilePath) { Get-Content $ps7ProfilePath -Raw -ErrorAction SilentlyContinue } else { "" }
if ($existing -notmatch "CommandLoggerPS7") {
    Add-Content -Path $ps7ProfilePath -Value $loggerBlock -Encoding UTF8
    Write-Host "  Profile block added" -ForegroundColor Gray
} else {
    Write-Host "  Profile block already present" -ForegroundColor DarkGray
}
Write-Host "  OK -- $ps7ProfilePath" -ForegroundColor Green

# -------------------------------------------------------------
# [5/6] CMD AutoRun -> launcher .cmd -> pwsh.exe + logger
# -------------------------------------------------------------
Write-Host "[5/6] Setting CMD AutoRun -> pwsh.exe..." -ForegroundColor Yellow

$launcherPath = "$system\L.cmd"
$launcherContent = "@echo off`r`ntitle %comspec%`r`n`"$pwshExe`" -NoLogo -ExecutionPolicy Bypass -NoExit -File `"$system\CommandLoggerPS7.ps1`""
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII

$regPath = "HKLM:\Software\Microsoft\Command Processor"
if (-not (Test-Path $regPath)) { New-Item $regPath -Force | Out-Null }
Set-ItemProperty $regPath -Name AutoRun -Value $launcherPath -Type String
Remove-ItemProperty "HKCU:\Software\Microsoft\Command Processor" -Name AutoRun -ErrorAction SilentlyContinue
Write-Host "  OK -- launcher: $launcherPath" -ForegroundColor Green

# -------------------------------------------------------------
# [6/6] Done
# -------------------------------------------------------------
Write-Host "[6/6] Done." -ForegroundColor Yellow
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " DONE -- Close and reopen terminal to start logging" -ForegroundColor Green
Write-Host " Daily driver: PowerShell 7 (pwsh.exe)" -ForegroundColor Green
Write-Host " Logs:         C:\Users\Public\CommandHistory\" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "What works now:" -ForegroundColor Cyan
Write-Host "  - && and ||                    (PS7 native)" -ForegroundColor Gray
Write-Host "  - dir /s /b, del /q, copy /y   (cmdcompat wrappers)" -ForegroundColor Gray
Write-Host "  - move /Y, ren, type, set      (cmdcompat wrappers)" -ForegroundColor Gray
Write-Host "  - %TEMP%, %USERPROFILE% etc    (auto-expanded)" -ForegroundColor Gray
Write-Host "  - curl with %VAR% args         (real curl.exe)" -ForegroundColor Gray
Write-Host "  - c <any cmd command>          (force CMD)" -ForegroundColor Gray
Write-Host "  - 80+ shortcuts: flushdns, ports, gpforce, etc." -ForegroundColor Gray
Write-Host "  - cd program files             (no quotes needed)" -ForegroundColor Gray
Write-Host ""
Write-Host "Caveat: 'set VAR=value' runs in a cmd subshell, so the var" -ForegroundColor DarkYellow
Write-Host "        does NOT persist into your PS7 session." -ForegroundColor DarkYellow
Write-Host "        For persistent env vars, use:  `$env:VAR = 'value'" -ForegroundColor DarkYellow
Write-Host ""
