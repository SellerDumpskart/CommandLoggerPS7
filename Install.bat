@echo off
:: =====================================================
::  CommandLoggerPS7 -- One-Click Installer
::  https://github.com/SellerDumpskart/CommandLoggerPS7
:: =====================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Run this as Administrator.
    echo  Right-click Install.bat and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

echo.
echo =====================================================
echo  CommandLoggerPS7 -- One-Click Installer
echo  Target: PowerShell 7 + cmdcompat (unified)
echo =====================================================
echo.

set "REPO=SellerDumpskart/CommandLoggerPS7"
set "BRANCH=main"
set "BASE_URL=https://raw.githubusercontent.com/%REPO%/%BRANCH%"
set "TEMP_DIR=C:\CommandLoggerPS7_temp"

echo [1/8] Setting temporary bootstrap AutoRun...
reg add "HKLM\Software\Microsoft\Command Processor" /v AutoRun /t REG_SZ /d "powershell.exe -NoLogo -NoProfile" /f >nul 2>&1
echo      OK

echo [2/8] Setting execution policy...
powershell.exe -NoLogo -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue"
echo      OK

echo [3/8] Checking PowerShell 7...
if exist "C:\Program Files\PowerShell\7\pwsh.exe" goto :ps7_ok

:: --- Try winget first ---
where winget >nul 2>&1
if %errorlevel% neq 0 goto :ps7_msi_fallback

echo      Installing via winget...
winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements -h
if exist "C:\Program Files\PowerShell\7\pwsh.exe" goto :ps7_ok
echo      winget install did not produce pwsh.exe -- falling back to MSI

:ps7_msi_fallback
:: --- Fallback: download MSI via curl/IWR and install via msiexec ---
set "PS7_MSI_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.4/PowerShell-7.5.4-win-x64.msi"
set "PS7_MSI=%TEMP%\PowerShell-7.5.4-win-x64.msi"

echo      Downloading PowerShell 7 MSI...
where curl >nul 2>&1
if %errorlevel% equ 0 (
    curl.exe -L -o "%PS7_MSI%" "%PS7_MSI_URL%"
) else (
    powershell.exe -NoLogo -NoProfile -Command ^
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
        "Invoke-WebRequest -Uri '%PS7_MSI_URL%' -OutFile '%PS7_MSI%' -UseBasicParsing"
)

if not exist "%PS7_MSI%" (
    echo      FAILED to download PowerShell 7 MSI.
    echo      Install manually from https://github.com/PowerShell/PowerShell/releases
    pause
    exit /b 1
)

echo      Running MSI installer (silent)...
msiexec.exe /i "%PS7_MSI%" /qn /norestart
del /f "%PS7_MSI%" >nul 2>&1

if not exist "C:\Program Files\PowerShell\7\pwsh.exe" (
    echo      FAILED to install PowerShell 7 via MSI.
    pause
    exit /b 1
)

:ps7_ok
echo      OK

echo [4/8] Creating temp folder...
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" >nul 2>&1
mkdir "%TEMP_DIR%" >nul 2>&1
mkdir "%TEMP_DIR%\system" >nul 2>&1
echo      OK

echo [5/8] Downloading files from GitHub...
powershell.exe -NoLogo -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "try { " ^
    "  Invoke-WebRequest -Uri '%BASE_URL%/system/CommandLoggerPS7.ps1' -OutFile '%TEMP_DIR%\system\CommandLoggerPS7.ps1' -UseBasicParsing; " ^
    "  Invoke-WebRequest -Uri '%BASE_URL%/Setup.ps1' -OutFile '%TEMP_DIR%\Setup.ps1' -UseBasicParsing; " ^
    "  Write-Host '     OK' " ^
    "} catch { " ^
    "  Write-Host '     FAILED - check internet connection and repo URL' -ForegroundColor Red; " ^
    "  exit 1 " ^
    "}"

if not exist "%TEMP_DIR%\Setup.ps1" (
    echo      FAILED - Could not download Setup.ps1
    rmdir /s /q "%TEMP_DIR%" >nul 2>&1
    pause
    exit /b 1
)
if not exist "%TEMP_DIR%\system\CommandLoggerPS7.ps1" (
    echo      FAILED - Could not download CommandLoggerPS7.ps1
    rmdir /s /q "%TEMP_DIR%" >nul 2>&1
    pause
    exit /b 1
)

echo [6/8] Running Setup.ps1 in pwsh.exe...
"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%TEMP_DIR%\Setup.ps1'"
echo      OK

echo [7/8] Verifying installation...
reg query "HKLM\Software\Microsoft\Command Processor" /v AutoRun | findstr /i "CommandHistory" >nul 2>&1
if %errorlevel% neq 0 (
    echo      WARNING - Registry not updated. Setup may have failed.
    pause
    exit /b 1
)
if not exist "C:\Users\Public\CommandHistory\_system\CommandLoggerPS7.ps1" (
    echo      WARNING - CommandLoggerPS7.ps1 not found.
    pause
    exit /b 1
)
echo      OK

echo [8/8] Cleaning up...
rmdir /s /q "%TEMP_DIR%" >nul 2>&1
del /f "C:\Install.bat" >nul 2>&1
echo      OK

echo.
echo =====================================================
echo  DONE -- Close and reopen terminal to start logging
echo  Daily driver: PowerShell 7 (pwsh.exe)
echo  Logs:         C:\Users\Public\CommandHistory\
echo =====================================================
echo.
pause
