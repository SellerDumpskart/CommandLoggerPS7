# CommandLoggerPS7

A unified PowerShell 7 command logger with built-in CMD compatibility. **One file, one install, one uninstall.** Logs every command to TXT/HTML/CSV (day-wise) and lets you paste CMD reference docs into PS7 without translation.

Replaces and supersedes:
- [CommandHistoryLogger](https://github.com/SellerDumpskart/CommandHistoryLogger) (PS5.1-targeted logger)
- [cmdcompat](https://github.com/SellerDumpskart/cmdcompat) (separate CMD compat layer)

Both projects merged into one core script.

## Features

**Logger**
- Multi-format logging — TXT, HTML (styled dark theme, sticky header), CSV
- Day-wise folders — `C:\Users\Public\CommandHistory\TXT\2026-04-11\` etc.
- Date rollover — keeps logging into the new day's folder past midnight
- Session detection — DWAgent, MeshCentral, SSH, RDP, CMD-via-PS7, Local
- CMD AutoRun — opening `cmd.exe` drops you into `pwsh.exe` with the logger active
- Clean prompt — `C:\path>`, no `PS` prefix

**CMD Compatibility (pure PowerShell — no cmd.exe dependency)**
- `&&` and `||` work (PS7 native)
- `dir /s /b /a` — parsed and translated to `Get-ChildItem`
- `del /s /q`, `copy /y`, `move /Y`, `ren` — pure PS cmdlets
- `mkdir`, `rmdir /s /q` — `New-Item` / `Remove-Item`
- `type file.txt` — `Get-Content`
- `echo %USERNAME%` — `Write-Output` with `[Environment]::ExpandEnvironmentVariables`
- `set VAR=value` — **actually persists** (real PS env-var via `Set-Item Env:`)
- `set X=%Y%\bin` — expands `%Y%` before storing
- `%TEMP%`, `%USERPROFILE%`, `%APPDATA%` etc. auto-expanded in args
- `curl` — real `curl.exe` with `%VAR%` expansion (not the PS alias)
- `start "" "path.bat"` — strips CMD-style empty title, forwards to `Start-Process`
- `cd program files` — joins args with space, no quotes needed
- `cd wrong || echo fallback` — `ThrowTerminatingError` triggers `||`
- `cls`, `title`, `ver`, `vol` — pure PS equivalents
- `c <any cmd command>` — force-run via CMD (works in normal terminals, fails gracefully in service contexts)
- 60+ shortcuts: `flushdns`, `ports`, `gpforce`, `defenderoff`, `rdpon`, `regbackup`, `showip`, `regquery`, `wsllist`, etc.
- Dynamic terminal colors — auto-detects and applies readable text color

Every command goes through the prompt logger and ends up in TXT/HTML/CSV.

**Works in all contexts:**
- Interactive PS7 sessions
- CMD windows (auto-launched into PS7 via AutoRun)
- Remote management tools (DWAgent, MeshCentral, similar) — no cmd.exe dependency

## Install

Open CMD or PowerShell **as Administrator** and run:

```
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SellerDumpskart/CommandLoggerPS7/main/Install.bat' -OutFile 'C:\Install.bat' -UseBasicParsing"; cmd /d /c C:\Install.bat
```

The installer:
1. Installs PowerShell 7 via winget (falls back to MSI download if winget is unavailable)
2. Drops `CommandLoggerPS7.ps1` into `C:\Users\Public\CommandHistory\_system\`
3. Adds dot-source line to PS7's machine-wide `profile.ps1`
4. Sets CMD's AutoRun registry key to launch `pwsh.exe` with the logger
5. Verifies and cleans up

Close and reopen the terminal. Done.

## Update

```
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SellerDumpskart/CommandLoggerPS7/main/Update.bat' -OutFile 'C:\Update.bat' -UseBasicParsing"; cmd /d /c C:\Update.bat
```

Updater only re-pulls the core script — does not touch profile, registry, or PS7 install.

## Uninstall

```
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SellerDumpskart/CommandLoggerPS7/main/Uninstall.bat' -OutFile 'C:\Uninstall.bat' -UseBasicParsing"; cmd /d /c C:\Uninstall.bat
```

PowerShell 7 itself is NOT removed. Logs are preserved unless you opt in to delete them.

## Light Terminal Fix

The default text color is **White** (optimized for dark terminals). If you're on a light-background terminal and text is hard to read:

**Quick fix (current session only):**

```powershell
Set-PSReadLineOption -Colors @{Command='Black';Parameter='Black';Operator='Black';Variable='Black';String='Black';Number='Black';Member='Black';Keyword='Black';Comment='Black';Type='Black'}
```

**Permanent fix (survives restart):**

1. Open your PS7 terminal and run:
   ```powershell
   notepad $PROFILE
   ```
2. If it says the file doesn't exist, click **Yes** to create it.
3. Notepad opens. Paste this line into it:
   ```powershell
   Set-PSReadLineOption -Colors @{Command='Black';Parameter='Black';Operator='Black';Variable='Black';String='Black';Number='Black';Member='Black';Keyword='Black';Comment='Black';Type='Black'}
   ```
4. Save and close Notepad.
5. Close the terminal, open a new one. Black text every time.

## Folder layout

```
C:\Users\Public\CommandHistory\
├── _system\
│   ├── CommandLoggerPS7.ps1   # unified core (logger + cmdcompat)
│   └── L.cmd                  # CMD AutoRun launcher
├── TXT\2026-04-11\COMPUTER_USER_SESSION.txt
├── HTML\2026-04-11\COMPUTER_USER_SESSION.html
└── CSV\2026-04-11\COMPUTER_USER_SESSION.csv
```

## Repo layout

```
CommandLoggerPS7/
├── Install.bat
├── Update.bat
├── Uninstall.bat
├── Setup.ps1
├── README.md
└── system/
    └── CommandLoggerPS7.ps1
```

## How it works

```
Terminal opens
  → CMD AutoRun or PS7 profile loads CommandLoggerPS7.ps1
  → Detects session type (DWAgent/SSH/RDP/CMD/Local)
  → Creates today's log folders
  → Installs prompt logger (captures every command to TXT/HTML/CSV)
  → Installs smart cd (spaces without quotes, || support)
  → Installs CMD-compatible wrappers (pure PS, no cmd.exe)
  → Sets terminal colors
  → Ready
```

When you type a command:
```
User types: dir /b
  → PS7 resolves 'dir' → alias → Invoke-CmdDir
  → Parses /b → calls Get-ChildItem -Name
  → Output displayed
  → Prompt function fires → captures command → writes to TXT + HTML + CSV
```

## Caveats

**`set VAR=value` now persists.** Unlike the old cmdcompat (which ran `set` in a cmd subshell that died immediately), this version uses `Set-Item Env:VAR` — the variable stays in your PS7 session.

**Some PS aliases are overwritten.** cmdcompat overwrites PS aliases for `dir`, `copy`, `move`, `del`, `ren`, `rmdir`, `type`, `echo`, `set`, `cls`, `curl`, `start` so CMD-style wrappers take over. If you need the original PS cmdlets, use their full names (`Get-ChildItem`, `Copy-Item`, `Remove-Item`, etc.).

**`md` and `rd` are not overwritten.** These are read-only PS functions. They still work natively via PS's built-in `New-Item`/`Remove-Item`. Use `mkdir` / `rmdir` for CMD-compatible behavior with switch parsing.

**`c`, `mklink`, `assoc`, `ftype`, `color` require cmd.exe.** These fail gracefully in service-launched contexts (DWAgent, MeshCentral) where cmd.exe output is blocked. A friendly message is printed instead.

**`-NoProfile` sessions don't auto-load.** If a remote tool launches `pwsh -NoProfile`, the logger won't load. Manually load it for that session:
```powershell
. C:\Users\Public\CommandHistory\_system\CommandLoggerPS7.ps1
```

## Requirements

- Windows 10 / 11
- Admin rights (one-time, for install/update/uninstall)
- Internet (only during install/update)

## Credits

- Logger architecture, session detection, multi-format logging — adapted from [CommandHistoryLogger](https://github.com/SellerDumpskart/CommandHistoryLogger)
- CMD compatibility layer — evolved from [cmdcompat](https://github.com/SellerDumpskart/cmdcompat), rewritten as pure PowerShell
