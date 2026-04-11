@echo off
:: =====================================================
::  CommandLoggerPS7 -- One-Click Updater
::  Re-downloads CommandLoggerPS7.ps1 from GitHub.
::  Does NOT touch profile, registry, or PS7 install.
:: =====================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Run this as Administrator.
    echo.
    pause
    exit /b 1
)

echo.
echo =====================================================
echo  CommandLoggerPS7 -- Updater
echo =====================================================
echo.

set "REPO=SellerDumpskart/CommandLoggerPS7"
set "BRANCH=main"
set "BASE_URL=https://raw.githubusercontent.com/%REPO%/%BRANCH%"
set "TARGET=C:\Users\Public\CommandHistory\_system\CommandLoggerPS7.ps1"

if not exist "C:\Users\Public\CommandHistory\_system" (
    echo  ERROR: CommandLoggerPS7 is not installed.
    echo  Run Install.bat first.
    pause
    exit /b 1
)

echo [1/3] Backing up current core script...
if exist "%TARGET%" (
    copy /Y "%TARGET%" "%TARGET%.bak" >nul 2>&1
    echo      OK -- backup at %TARGET%.bak
) else (
    echo      No existing file -- fresh download
)

echo [2/3] Downloading latest from GitHub...
powershell.exe -NoLogo -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "try { " ^
    "  Invoke-WebRequest -Uri '%BASE_URL%/system/CommandLoggerPS7.ps1' -OutFile '%TARGET%' -UseBasicParsing; " ^
    "  Write-Host '     OK' " ^
    "} catch { " ^
    "  Write-Host '     FAILED - check internet connection' -ForegroundColor Red; " ^
    "  exit 1 " ^
    "}"

if not exist "%TARGET%" (
    echo      FAILED - Could not download. Restoring backup...
    if exist "%TARGET%.bak" copy /Y "%TARGET%.bak" "%TARGET%" >nul 2>&1
    pause
    exit /b 1
)

echo [3/3] Done.
del /f "%TARGET%.bak" >nul 2>&1
del /f "C:\Update.bat" >nul 2>&1

echo.
echo =====================================================
echo  UPDATED -- Close and reopen terminal for changes
echo =====================================================
echo.
pause
