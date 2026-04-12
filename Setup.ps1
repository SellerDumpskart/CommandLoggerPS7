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
    Write-Host "  PowerShell 7 not found. Attempting install..." -ForegroundColor Gray

    $installed = $false

    # --- Try winget first ---
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Trying winget..." -ForegroundColor Gray
        try {
            winget install --id Microsoft.PowerShell --source winget `
                --accept-source-agreements --accept-package-agreements -h | Out-Null
            foreach ($c in $pwshCandidates) { if (Test-Path $c) { $pwshExe = $c; $installed = $true; break } }
        } catch {
            Write-Host "  winget failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  winget not available." -ForegroundColor Gray
    }

    # --- Fallback: direct MSI download ---
    if (-not $installed) {
        Write-Host "  Falling back to direct MSI download..." -ForegroundColor Gray
        $msiUrl  = "https://github.com/PowerShell/PowerShell/releases/download/v7.5.4/PowerShell-7.5.4-win-x64.msi"
        $msiPath = Join-Path $env:TEMP "PowerShell-7.5.4-win-x64.msi"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
            Write-Host "  Running MSI installer (silent)..." -ForegroundColor Gray
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
            foreach ($c in $pwshCandidates) { if (Test-Path $c) { $pwshExe = $c; break } }
        } catch {
            Write-Host "  MSI install failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if (-not $pwshExe) {
        Write-Host "  PowerShell 7 still not found. Aborting." -ForegroundColor Red
        Write-Host "  Install manually from https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Red
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
Write-Host "  - dir /s /b, del /q, copy /y   (pure PS wrappers)" -ForegroundColor Gray
Write-Host "  - move, ren, type, mkdir       (pure PS wrappers)" -ForegroundColor Gray
Write-Host "  - set VAR=value  PERSISTS      (real PS env vars now)" -ForegroundColor Gray
Write-Host "  - echo %USERNAME% etc          (expanded via .NET)" -ForegroundColor Gray
Write-Host "  - curl with %VAR% args         (real curl.exe)" -ForegroundColor Gray
Write-Host "  - 60+ shortcuts: flushdns, ports, gpforce, etc." -ForegroundColor Gray
Write-Host "  - cd program files             (no quotes needed)" -ForegroundColor Gray
Write-Host ""
Write-Host "Works in: interactive PS7, CMD auto-launch, and remote" -ForegroundColor DarkGray
Write-Host "          management tool contexts (DWAgent, MeshCentral)" -ForegroundColor DarkGray
Write-Host ""
