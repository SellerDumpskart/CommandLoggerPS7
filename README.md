# CommandLoggerPS7

A unified PowerShell 7 command logger with built-in CMD compatibility. **One file, one install, one uninstall.** Logs every command to TXT/HTML/CSV (day-wise) and lets you paste CMD reference docs into PS7 without translation.

Replaces and supersedes:
- [CommandHistoryLogger](https://github.com/SellerDumpskart/CommandHistoryLogger) (PS5.1-targeted logger)
- [cmdcompat](https://github.com/SellerDumpskart/cmdcompat) (separate CMD compat layer)

Both projects merged into one core script.

## Features

**Logger**
- Multi-format logging — TXT, HTML (styled, sticky header), CSV
- Day-wise folders — `C:\Users\Public\CommandHistory\TXT\2026-04-11\` etc.
- Date rollover — keeps logging into the new day's folder past midnight
- Session detection — DWAgent, MeshCentral, SSH, RDP, CMD-via-PS7, Local
- CMD AutoRun — opening `cmd.exe` drops you into `pwsh.exe` with the logger active
- `cd` without quotes — `cd program files` just works
- White PSReadLine colors for light terminals
- Clean prompt — `C:\path>`, no `PS` prefix

**CMD Compatibility (cmdcompat layer, integrated)**
- `&&` and `||` work (PS7 native)
- `dir /s /b`, `del /q`, `copy /y`, `move /Y`, `ren`, `type`, `set` — all routed through `cmd.exe`
- `%TEMP%`, `%USERPROFILE%`, `%APPDATA%` etc. auto-expanded in args
- Real `curl.exe` (not the PS alias)
- `c <any cmd command>` — force-run anything via CMD
- 80+ shortcuts: `flushdns`, `ports`, `gpforce`, `defenderoff`, `rdpon`, `regbackup`, `domaininfo`, `wsllist`, etc.

Every wrapped command goes through the prompt logger and ends up in TXT/HTML/CSV.

## Install

Open CMD or PowerShell **as Administrator** and run:

```
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SellerDumpskart/CommandLoggerPS7/main/Install.bat' -OutFile 'C:\Install.bat' -UseBasicParsing"; cmd /d /c C:\Install.bat
```

The installer:
1. Installs PowerShell 7 via winget if missing
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

## Caveats

**`set VAR=value` doesn't persist.** Because it runs in a `cmd /c` subshell that dies immediately, the variable is gone the moment the command returns. For persistent env vars in PS7: `$env:VAR = "value"`. For one-line CMD chains where the var only needs to live within that line: `c "set X=1 && echo %X%"` — the whole chain runs in one cmd subshell and works.

**Some PS aliases are removed.** cmdcompat removes the PS aliases for `set`, `move`, `copy`, `del`, `ren`, `rmdir`, `type`, `path`, `cls`, `color`, `dir`, `curl` so the CMD-style wrappers can take over. If you rely on `set` for `Set-Variable` or `del` for `Remove-Item`, use the full cmdlet names instead.

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
- CMD compatibility layer — [cmdcompat](https://github.com/SellerDumpskart/cmdcompat)
