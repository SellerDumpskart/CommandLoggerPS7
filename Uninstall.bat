@echo off
:: =====================================================
::  CommandLoggerPS7 -- Uninstaller
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
echo  CommandLoggerPS7 -- Uninstaller
echo =====================================================
echo.
echo  This will:
echo   - Remove CMD AutoRun registry key
echo   - Remove CommandLoggerPS7 from PowerShell 7 profile
echo   - Remove C:\Users\Public\CommandHistory\_system folder
echo.
echo  This will NOT uninstall PowerShell 7 itself.
echo.
set /p confirm="  Continue? (Y/N): "
if /i not "%confirm%"=="Y" (
    echo  Cancelled.
    pause
    exit /b 0
)

echo.
set /p dellogs="  Also delete all log files? (Y/N): "
echo.

echo [1/4] Removing CMD AutoRun registry key...
reg delete "HKLM\Software\Microsoft\Command Processor" /v AutoRun /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Command Processor" /v AutoRun /f >nul 2>&1
echo      OK

echo [2/4] Cleaning PS7 profile...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p = \"$env:ProgramFiles\PowerShell\7\profile.ps1\"; " ^
    "if (Test-Path $p) { " ^
    "  $lines = Get-Content $p; " ^
    "  $skip = $false; " ^
    "  $clean = @(); " ^
    "  foreach ($line in $lines) { " ^
    "    if ($line -match 'CommandLoggerPS7') { $skip = $true } " ^
    "    if (-not $skip) { $clean += $line } " ^
    "    if ($line -match 'End CommandLoggerPS7') { $skip = $false } " ^
    "  }; " ^
    "  Set-Content $p ($clean -join \"`n\") -Encoding UTF8; " ^
    "  Write-Host '      cleaned PS7 profile' -ForegroundColor Gray " ^
    "}"
echo      OK

echo [3/4] Removing system files...
if exist "C:\Users\Public\CommandHistory\_system" (
    rmdir /s /q "C:\Users\Public\CommandHistory\_system" >nul 2>&1
)
echo      OK

if /i "%dellogs%"=="Y" (
    echo [4/4] Deleting log files...
    if exist "C:\Users\Public\CommandHistory" rmdir /s /q "C:\Users\Public\CommandHistory" >nul 2>&1
    echo      OK
) else (
    echo [4/4] Keeping log files at C:\Users\Public\CommandHistory\
)

echo.
del /f "C:\Uninstall.bat" >nul 2>&1

echo =====================================================
echo  UNINSTALLED
if /i not "%dellogs%"=="Y" (
    echo.
    echo  Logs preserved at:
    echo    C:\Users\Public\CommandHistory\TXT\
    echo    C:\Users\Public\CommandHistory\HTML\
    echo    C:\Users\Public\CommandHistory\CSV\
)
echo.
echo  Note: PowerShell 7 was not removed.
echo  To remove it: winget uninstall Microsoft.PowerShell
echo =====================================================
echo.
pause
