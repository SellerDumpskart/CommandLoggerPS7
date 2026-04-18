# =====================================================
#  CommandLoggerPS7 -- Unified core script
#  https://github.com/SellerDumpskart/CommandLoggerPS7
#
#  Single-file integration of:
#    - Day-wise TXT/HTML/CSV command logger
#    - Session detection (DWAgent/MeshCentral/SSH/RDP/CMD)
#    - Custom cd (handles spaces without quotes)
#    - cmdcompat layer (CMD-compatible function wrappers)
#    - PSReadLine colors auto-detect dark/light terminal background
#
#  Requires: PowerShell 7+
# =====================================================

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "CommandLoggerPS7 requires PowerShell 7+. Current: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    return
}

# -------------------------------------------------------------
# GLOBALS
# -------------------------------------------------------------
$Global:CHL_Root       = "C:\Users\Public\CommandHistory"
$Global:CHL_System     = "$Global:CHL_Root\_system"
$Global:CHL_Computer   = $env:COMPUTERNAME
$Global:CHL_User       = $env:USERNAME
$Global:CHL_Today      = (Get-Date -Format "yyyy-MM-dd")
$Global:CHL_Session    = ""
$Global:CHL_LastHistId = 0

# =============================================================
# SECTION 1: LOGGER
# =============================================================

function Get-SessionType {
    $s = "Local-PowerShell7"
    try {
        $pr1 = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -EA SilentlyContinue
        if (-not $pr1) { return $s }
        $pr2 = Get-CimInstance Win32_Process -Filter "ProcessId=$($pr1.ParentProcessId)" -EA SilentlyContinue
        $n1 = if ($pr2) { $pr2.Name.ToLower() } else { "" }
        $pr3 = if ($pr2) { Get-CimInstance Win32_Process -Filter "ProcessId=$($pr2.ParentProcessId)" -EA SilentlyContinue } else { $null }
        $n2 = if ($pr3) { $pr3.Name.ToLower() } else { "" }
        $pr4 = if ($pr3) { Get-CimInstance Win32_Process -Filter "ProcessId=$($pr3.ParentProcessId)" -EA SilentlyContinue } else { $null }
        $n3 = if ($pr4) { $pr4.Name.ToLower() } else { "" }
        $all = "$n1|$n2|$n3"
        if     ($all -match "dwagent|dwservice|dwrcs|windowssecurityservice") { $s = "Remote-DWAgent" }
        elseif ($all -match "meshagent|meshcentral")                          { $s = "Remote-MeshCentral" }
        elseif ($all -match "sshd|openssh")                                   { $s = "Remote-SSH" }
        elseif ($all -match "rdpclip|mstsc")                                  { $s = "Remote-RDP" }
        elseif ($all -match "cmd")                                            { $s = "Local-CMD-via-PS7" }
    } catch {}
    return $s
}

function Initialize-LogFolders {
    @("$Global:CHL_Root\TXT\$Global:CHL_Today",
      "$Global:CHL_Root\HTML\$Global:CHL_Today",
      "$Global:CHL_Root\CSV\$Global:CHL_Today") | ForEach-Object {
        if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    }
}

function Get-LogPaths {
    $tag = "$Global:CHL_Computer`_$Global:CHL_User`_$Global:CHL_Session"
    return @{
        TXT  = "$Global:CHL_Root\TXT\$Global:CHL_Today\$tag.txt"
        HTML = "$Global:CHL_Root\HTML\$Global:CHL_Today\$tag.html"
        CSV  = "$Global:CHL_Root\CSV\$Global:CHL_Today\$tag.csv"
    }
}

function Update-DateRollover {
    # If we crossed midnight, switch to today's folder
    $now = Get-Date -Format "yyyy-MM-dd"
    if ($now -ne $Global:CHL_Today) {
        $Global:CHL_Today = $now
        Initialize-LogFolders
    }
}

function Write-CommandLog {
    param([string]$Command, [int]$ExitCode = 0)
    if ([string]::IsNullOrWhiteSpace($Command)) { return }
    Update-DateRollover
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $p  = Get-LogPaths
    $c  = $Command.Trim()

    # ---- TXT ----
    Add-Content -Path $p.TXT -Value "[$ts] [$Global:CHL_Session] [$Global:CHL_User@$Global:CHL_Computer] $c" -Encoding UTF8

    # ---- CSV (utf8NoBOM so Excel doesn't choke) ----
    [PSCustomObject]@{
        DateTime    = $ts
        Computer    = $Global:CHL_Computer
        User        = $Global:CHL_User
        SessionType = $Global:CHL_Session
        PID         = $PID
        Command     = $c
        ExitCode    = $ExitCode
    } | Export-Csv -Path $p.CSV -Append -NoTypeInformation -Encoding utf8NoBOM

    # ---- HTML ----
    $ec = $c -replace "&","&amp;" -replace "<","&lt;" -replace ">","&gt;" -replace "'","&#39;" -replace '"',"&quot;"
    $rc = if ($ExitCode -ne 0) { "error" } else { "ok" }
    $hr = "<tr class=""$rc""><td>$ts</td><td>$Global:CHL_Session</td><td>$Global:CHL_User</td><td>$Global:CHL_Computer</td><td class=""cmd"">$ec</td><td>$ExitCode</td></tr>"

    if (-not (Test-Path $p.HTML)) {
        $hh = @"
<!DOCTYPE html><html><head><meta charset='UTF-8'><title>PS7 Command History</title>
<style>
body{font-family:Consolas,monospace;background:#0f0f0f;color:#e0e0e0;padding:20px}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#1a1a2e;color:#00bcd4;padding:8px;text-align:left;position:sticky;top:0}
td{padding:6px 8px;border-bottom:1px solid #222;vertical-align:top}
tr.ok:hover{background:#1a1a1a}
tr.error{background:#2a0a0a}
.cmd{color:#80ff80}
tr.error .cmd{color:#ff6b6b}
h2{color:#00bcd4}
</style></head><body>
<h2>PS7 Command History &mdash; $Global:CHL_Today &mdash; $Global:CHL_Computer</h2>
<table><thead><tr>
<th>DateTime</th><th>Session</th><th>User</th><th>Computer</th><th>Command</th><th>Exit</th>
</tr></thead><tbody>
"@
        Set-Content -Path $p.HTML -Value $hh -Encoding UTF8
    }
    Add-Content -Path $p.HTML -Value $hr -Encoding UTF8
}

function Write-SessionBanner {
    $p = Get-LogPaths
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $p.TXT -Value @"
========================================
 SESSION START: $ts
 User:    $Global:CHL_User
 Machine: $Global:CHL_Computer
 Session: $Global:CHL_Session
 Shell:   PowerShell $($PSVersionTable.PSVersion)
 PID:     $PID
========================================
"@ -Encoding UTF8
}

function Close-HtmlLog {
    $p = Get-LogPaths
    if (Test-Path $p.HTML) {
        Add-Content -Path $p.HTML -Value "</tbody></table></body></html>" -Encoding UTF8
    }
}

function Register-PromptLogger {
    function global:prompt {
        $lastSuccess = $?
        try {
            $lc = Get-History -Count 1 -ErrorAction SilentlyContinue
            if ($lc -and $lc.Id -ne $Global:CHL_LastHistId) {
                $Global:CHL_LastHistId = $lc.Id
                Write-CommandLog -Command $lc.CommandLine -ExitCode $(if ($lastSuccess) { 0 } else { 1 })
            }
        } catch {}
        "$((Get-Location).Path)> "
    }
}

function Register-SmartCd {
    # Define the smart-cd function in global scope as an ADVANCED function
    # [CmdletBinding()] is required for terminating errors to propagate out
    # of the function in a way that PS7's || / && pipeline operators respect.
    function global:Invoke-SmartCd {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments=$true)]
            [string[]]$Path
        )
        $target = if ($Path.Count -gt 1)     { $Path -join ' ' }
                  elseif ($Path.Count -eq 1) { $Path[0] }
                  else                       { $HOME }

        if (-not (Test-Path -LiteralPath $target)) {
            $global:LASTEXITCODE = 1
            # Throw a terminating error via PSCmdlet so pipeline chain operators trigger
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Management.Automation.ItemNotFoundException]::new(
                        "Cannot find path '$target' because it does not exist."),
                    'PathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $target
                )
            )
        }
        Set-Location -LiteralPath $target
        $global:LASTEXITCODE = 0
    }
    Set-Alias -Name cd -Value Invoke-SmartCd -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
}

function Set-TerminalColors {
    if (Get-Module -ListAvailable PSReadLine) {
        try {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
            # Detect terminal background: if light-colored, use dark text; if dark, use light text.
            $bg = $Host.UI.RawUI.BackgroundColor
            $lightBackgrounds = @('White','Gray','Yellow','Cyan','Green','DarkGray')
            $isDark = $bg -notin $lightBackgrounds

            if ($isDark) {
                # Dark background → light/vivid colors (classic terminal look)
                Set-PSReadLineOption -Colors @{
                    Command   = 'Yellow'
                    Parameter = 'Cyan'
                    Operator  = 'White'
                    Variable  = 'Green'
                    String    = 'DarkCyan'
                    Number    = 'White'
                    Member    = 'White'
                    Keyword   = 'Magenta'
                    Comment   = 'DarkGreen'
                    Type      = 'Gray'
                }
            } else {
                # Light background → dark/muted colors for readability
                Set-PSReadLineOption -Colors @{
                    Command   = 'DarkBlue'
                    Parameter = 'DarkCyan'
                    Operator  = 'Black'
                    Variable  = 'DarkGreen'
                    String    = 'DarkRed'
                    Number    = 'Black'
                    Member    = 'DarkMagenta'
                    Keyword   = 'DarkMagenta'
                    Comment   = 'DarkGray'
                    Type      = 'DarkGray'
                }
            }
        } catch {}
    }
}

# =============================================================
# SECTION 2: CMDCOMPAT LAYER
# Source: https://github.com/SellerDumpskart/cmdcompat
# Differences vs upstream:
#   - Removed `&&` function (PS7 has native && operator)
#   - Added `dir` wrapper (CMD-style switches like /s /b)
# =============================================================

function Expand-CmdVars([string]$text) {
    [regex]::Replace($text, '%([^%]+)%', {
        param($match)
        $val = [System.Environment]::GetEnvironmentVariable($match.Groups[1].Value)
        if ($val) { $val } else { $match.Value }
    })
}

function Initialize-CmdCompat {
    # -----------------------------------------------------------
    # CMD BUILT-IN WRAPPERS -- PURE POWERSHELL (no cmd.exe)
    # -----------------------------------------------------------
    # Design note: The previous version routed everything through
    # `cmd.exe /c "..."`. That breaks in environments where cmd.exe
    # output is swallowed (service-launched sessions, remote tools
    # like DWAgent/MeshCentral, some elevated contexts). These
    # implementations use native PowerShell cmdlets instead, which
    # work in every context and also make `set VAR=value` actually
    # persist (since it's now real PS env-var assignment).
    # -----------------------------------------------------------

    # ---- DIR: supports CMD-style /b /s /a switches ----
    function global:Invoke-CmdDir {
        $pathArgs  = @()
        $bare      = $false
        $recursive = $false
        $force     = $false
        foreach ($a in $args) {
            switch -Regex ($a) {
                '^/b' { $bare = $true }
                '^/s' { $recursive = $true }
                '^/a' { $force = $true }
                '^/'  { }  # ignore other switches
                default { $pathArgs += (Expand-CmdVars $a) }
            }
        }
        $target = if ($pathArgs.Count -gt 0) { $pathArgs -join ' ' } else { '.' }
        $gciParams = @{ Path = $target; ErrorAction = 'SilentlyContinue' }
        if ($recursive) { $gciParams.Recurse = $true }
        if ($force)     { $gciParams.Force   = $true }
        if ($bare) {
            Get-ChildItem @gciParams -Name
        } else {
            Get-ChildItem @gciParams
        }
    }

    # ---- DEL / ERASE: supports /q /s /f ----
    function global:Invoke-CmdDel {
        $pathArgs = @()
        $recursive = $false
        foreach ($a in $args) {
            switch -Regex ($a) {
                '^/s' { $recursive = $true }
                '^/q' { }
                '^/f' { }
                '^/'  { }
                default { $pathArgs += (Expand-CmdVars $a) }
            }
        }
        foreach ($p in $pathArgs) {
            Remove-Item -Path $p -Force -Recurse:$recursive -ErrorAction SilentlyContinue
        }
    }

    # ---- COPY: supports /y ----
    function global:Invoke-CmdCopy {
        $pathArgs = @()
        foreach ($a in $args) {
            if ($a -notmatch '^/') { $pathArgs += (Expand-CmdVars $a) }
        }
        if ($pathArgs.Count -ge 2) {
            $dest = $pathArgs[-1]
            $srcs = $pathArgs[0..($pathArgs.Count - 2)]
            Copy-Item -Path $srcs -Destination $dest -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- MOVE: supports /y ----
    function global:Invoke-CmdMove {
        $pathArgs = @()
        foreach ($a in $args) {
            if ($a -notmatch '^/') { $pathArgs += (Expand-CmdVars $a) }
        }
        if ($pathArgs.Count -ge 2) {
            $dest = $pathArgs[-1]
            $srcs = $pathArgs[0..($pathArgs.Count - 2)]
            Move-Item -Path $srcs -Destination $dest -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- REN / RENAME ----
    function global:Invoke-CmdRen {
        $pathArgs = @($args | ForEach-Object { Expand-CmdVars $_ })
        if ($pathArgs.Count -ge 2) {
            Rename-Item -Path $pathArgs[0] -NewName $pathArgs[1] -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- MKDIR / MD ----
    function global:Invoke-CmdMkdir {
        foreach ($a in $args) {
            if ($a -notmatch '^/') {
                $p = Expand-CmdVars $a
                New-Item -ItemType Directory -Path $p -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    # ---- RMDIR / RD: supports /s /q ----
    function global:Invoke-CmdRmdir {
        $pathArgs = @()
        $recursive = $false
        foreach ($a in $args) {
            switch -Regex ($a) {
                '^/s' { $recursive = $true }
                '^/q' { }
                '^/'  { }
                default { $pathArgs += (Expand-CmdVars $a) }
            }
        }
        foreach ($p in $pathArgs) {
            Remove-Item -Path $p -Force -Recurse:$recursive -ErrorAction SilentlyContinue
        }
    }

    # ---- TYPE: cat a file ----
    function global:Invoke-CmdType {
        foreach ($a in $args) {
            if ($a -notmatch '^/') {
                Get-Content -Path (Expand-CmdVars $a) -ErrorAction SilentlyContinue
            }
        }
    }

    # ---- ECHO: prints with %VAR% expansion (uses Write-Output so > redirect works) ----
    function global:Invoke-CmdEcho {
        $text = ($args -join ' ')
        $expanded = [Environment]::ExpandEnvironmentVariables($text)
        Write-Output $expanded
    }

    # ---- SET: real PS env-var assignment, with %VAR% expansion in values (CMD-compatible) ----
    function global:Invoke-CmdSet {
        if ($args.Count -eq 0) {
            # `set` with no args: list all env vars (CMD behavior)
            Get-ChildItem Env: | ForEach-Object { "$($_.Name)=$($_.Value)" }
            return
        }
        $joined = ($args -join ' ')
        if ($joined -match '^([^=]+)=(.*)$') {
            $name  = $matches[1].Trim()
            $value = $matches[2]
            # Expand %VAR% references in the value before storing (matches cmd behavior)
            $value = [Environment]::ExpandEnvironmentVariables($value)
            Set-Item -Path "Env:$name" -Value $value
        } else {
            # `set VAR` or `set PATH` (no =): show vars starting with that prefix (CMD behavior)
            $prefix = $joined.Trim()
            Get-ChildItem Env: | Where-Object { $_.Name -like "$prefix*" } | ForEach-Object { "$($_.Name)=$($_.Value)" }
        }
    }

    # ---- CLS / CLEAR ----
    function global:Invoke-CmdCls { Clear-Host }

    # ---- TITLE ----
    function global:Invoke-CmdTitle {
        $Host.UI.RawUI.WindowTitle = ($args -join ' ')
    }

    # ---- VER: Windows version ----
    function global:Invoke-CmdVer {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { "Microsoft Windows [Version $($os.Version)]" }
    }

    # ---- VOL: drive label/serial ----
    function global:Invoke-CmdVol {
        $drive = if ($args.Count -gt 0) { ($args[0] -replace '[:\\]','') } else { (Get-Location).Drive.Name }
        $v = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${drive}:'" -ErrorAction SilentlyContinue
        if ($v) {
            " Volume in drive ${drive} is $($v.VolumeName)"
            " Volume Serial Number is $($v.VolumeSerialNumber)"
        }
    }

    # ---- CURL: real curl.exe (calls the .exe directly, no cmd.exe) ----
    # IMPORTANT: @(...) forces array context so that `@expanded` splats correctly
    # even when $args has only one element. Without the @() wrap, ForEach-Object
    # returns a scalar string, and @scalar splats character-by-character.
    function global:Invoke-CmdCurl {
        $expanded = @($args | ForEach-Object { [Environment]::ExpandEnvironmentVariables("$_") })
        & curl.exe @expanded
    }

    # ---- MKLINK: requires cmd.exe (no PS equivalent); call it directly via .exe ----
    # If cmd.exe is unavailable in this context, mklink won't work. That's unavoidable.
    function global:Invoke-CmdMklink {
        $joined = ($args -join ' ')
        Write-Host "mklink requires cmd.exe; not supported in cmd-less contexts." -ForegroundColor DarkYellow
        Write-Host "Use New-Item -ItemType SymbolicLink instead." -ForegroundColor DarkYellow
    }

    # ---- ASSOC / FTYPE: use assoc.exe / ftype.exe via cmd (fallback to no-op message) ----
    function global:Invoke-CmdAssoc {
        Write-Host "assoc/ftype require cmd.exe built-ins; not supported in cmd-less contexts." -ForegroundColor DarkYellow
    }
    function global:Invoke-CmdFtype {
        Write-Host "assoc/ftype require cmd.exe built-ins; not supported in cmd-less contexts." -ForegroundColor DarkYellow
    }

    # ---- COLOR: PS equivalent for terminal foreground ----
    function global:Invoke-CmdColor {
        Write-Host "'color' changes the CMD window color; use PSReadLine or terminal settings in PS7." -ForegroundColor DarkYellow
    }

    # Force-overwrite the built-in aliases (works on AllScope ones)
    # All Set-Alias calls use -ErrorAction SilentlyContinue so the script never
    # spams startup with errors if an alias can't be overwritten in some edge case.
    Set-Alias -Name dir    -Value Invoke-CmdDir    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name move   -Value Invoke-CmdMove   -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name copy   -Value Invoke-CmdCopy   -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name del    -Value Invoke-CmdDel    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name erase  -Value Invoke-CmdDel    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name ren    -Value Invoke-CmdRen    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name rename -Value Invoke-CmdRen    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name rmdir  -Value Invoke-CmdRmdir  -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name type   -Value Invoke-CmdType   -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name mkdir  -Value Invoke-CmdMkdir  -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    # Note: 'md' and 'rd' are read-only PS functions that cannot be overwritten
    # by Set-Alias. They still work natively via PS's built-in New-Item/Remove-Item,
    # so they're left alone. Use 'mkdir' / 'rmdir' for CMD-compatible behavior.
    Set-Alias -Name echo   -Value Invoke-CmdEcho   -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name set    -Value Invoke-CmdSet    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name cls    -Value Invoke-CmdCls    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name clear  -Value Invoke-CmdCls    -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name title  -Value Invoke-CmdTitle  -Scope Global -Force -ErrorAction SilentlyContinue
    Set-Alias -Name ver    -Value Invoke-CmdVer    -Scope Global -Force -ErrorAction SilentlyContinue
    Set-Alias -Name vol    -Value Invoke-CmdVol    -Scope Global -Force -ErrorAction SilentlyContinue
    Set-Alias -Name curl   -Value Invoke-CmdCurl   -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue
    Set-Alias -Name mklink -Value Invoke-CmdMklink -Scope Global -Force -ErrorAction SilentlyContinue
    Set-Alias -Name assoc  -Value Invoke-CmdAssoc  -Scope Global -Force -ErrorAction SilentlyContinue
    Set-Alias -Name ftype  -Value Invoke-CmdFtype  -Scope Global -Force -ErrorAction SilentlyContinue
    Set-Alias -Name color  -Value Invoke-CmdColor  -Scope Global -Force -ErrorAction SilentlyContinue

    # ---- START: CMD-style `start "" "path"` compatibility ----
    # CMD's `start` requires an empty quoted title before a quoted path:
    #   start "" "C:\path\to\file.bat"
    # PS7 aliases `start` to Start-Process, which interprets "" as the
    # FilePath argument and rejects it. This wrapper strips a leading
    # empty-string arg (the CMD title) and forwards the real path.
    function global:Invoke-CmdStart {
        $a = @($args)
        # Strip leading empty/whitespace title arg if present
        if ($a.Count -gt 0 -and [string]::IsNullOrWhiteSpace($a[0])) {
            $a = if ($a.Count -gt 1) { $a[1..($a.Count - 1)] } else { @() }
        }
        if ($a.Count -eq 0) {
            Write-Host "start: no path specified" -ForegroundColor DarkYellow
            return
        }
        $expanded = @($a | ForEach-Object { [Environment]::ExpandEnvironmentVariables("$_") })
        $filePath = $expanded[0]
        if ($expanded.Count -gt 1) {
            Start-Process -FilePath $filePath -ArgumentList ($expanded[1..($expanded.Count - 1)])
        } else {
            Start-Process -FilePath $filePath
        }
    }
    Set-Alias -Name start -Value Invoke-CmdStart -Scope Global -Force -Option AllScope -ErrorAction SilentlyContinue

    # ---- 'c' shortcut: still tries cmd.exe for users who want raw CMD access ----
    # In contexts where cmd.exe works, this runs arbitrary CMD commands.
    # In contexts where cmd.exe is blocked, this will silently fail.
    function global:c { & cmd.exe /c "cd /d ""$PWD"" && $($args -join ' ')" }

    # =========================================================================
    # BYPASS-INSTALL WORKFLOW HELPERS
    # =========================================================================
    # Tooling specifically for the "download a script from the web and run it"
    # workflow. Logs the URL, file path, and exit code so the chat history has
    # a complete trail of what was fetched and what happened.
    # =========================================================================

    # ---- Internal: shared GitHub URL expander ----
    function global:Expand-GhRef {
        param([string]$Ref)
        # Accepts "user/repo/path/to/file.bat" or "user/repo@branch/path/to/file.bat"
        # Defaults to main branch if no @branch specified.
        if ($Ref -match '^([^/]+)/([^/]+)(?:@([^/]+))?/(.+)$') {
            $user   = $matches[1]
            $repo   = $matches[2]
            $branch = if ($matches[3]) { $matches[3] } else { 'main' }
            $path   = $matches[4]
            return "https://raw.githubusercontent.com/$user/$repo/$branch/$path"
        }
        # If it already looks like a URL, pass through
        if ($Ref -match '^https?://') { return $Ref }
        return $null
    }

    # ---- gh: shorthand to download a file from a GitHub repo ----
    # Usage: gh user/repo/path/to/file.bat
    #        gh user/repo@dev/path/to/file.bat
    function global:gh {
        if ($args.Count -eq 0) {
            Write-Host "Usage: gh <user>/<repo>[@branch]/<path>" -ForegroundColor DarkYellow
            Write-Host "  e.g. gh SellerDumpskart/psimouse/psimouse.bat" -ForegroundColor DarkGray
            return
        }
        $url = Expand-GhRef $args[0]
        if (-not $url) {
            Write-Host "Invalid GitHub ref. Use: user/repo/path or user/repo@branch/path" -ForegroundColor Red
            return
        }
        $filename = Split-Path -Leaf $url
        $dest = Join-Path $env:TEMP $filename
        Write-Host "Downloading $url" -ForegroundColor DarkCyan
        Write-Host "  -> $dest" -ForegroundColor DarkGray
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
            $global:CHL_LastUrl  = $url
            $global:CHL_LastFile = $dest
            Write-Host "OK" -ForegroundColor Green
            Write-Host "  lasturl  = $url" -ForegroundColor DarkGray
            Write-Host "  lastfile = $dest" -ForegroundColor DarkGray
        } catch {
            Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # ---- runweb: download AND run a script from a URL or GitHub ref ----
    # Usage: runweb <url-or-ghref> [args...]
    #        runweb https://example.com/installer.bat
    #        runweb SellerDumpskart/psimouse/psimouse.bat
    function global:runweb {
        if ($args.Count -eq 0) {
            Write-Host "Usage: runweb <url-or-ghref> [args...]" -ForegroundColor DarkYellow
            Write-Host "  e.g. runweb SellerDumpskart/psimouse/psimouse.bat" -ForegroundColor DarkGray
            return
        }
        $ref = $args[0]
        $url = Expand-GhRef $ref
        if (-not $url) { $url = $ref }  # treat as raw URL
        $filename = Split-Path -Leaf $url
        if (-not $filename -or $filename -notmatch '\.(bat|cmd|exe|ps1)$') {
            $filename = "runweb_$(Get-Random).bat"
        }
        $dest = Join-Path $env:TEMP $filename
        Write-Host "[runweb] Fetching $url" -ForegroundColor DarkCyan
        Write-Host "[runweb]      to $dest" -ForegroundColor DarkGray
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "[runweb] DOWNLOAD FAILED: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        $global:CHL_LastUrl  = $url
        $global:CHL_LastFile = $dest
        Write-Host "[runweb] Downloaded ($((Get-Item $dest).Length) bytes), executing..." -ForegroundColor DarkCyan
        $extraArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
        $ext = [System.IO.Path]::GetExtension($dest).ToLower()
        switch ($ext) {
            '.ps1' { & pwsh.exe -ExecutionPolicy Bypass -NoProfile -File $dest @extraArgs }
            '.exe' { & $dest @extraArgs }
            default { & cmd.exe /c "`"$dest`" $($extraArgs -join ' ')" }
        }
        Write-Host "[runweb] Exit code: $LASTEXITCODE" -ForegroundColor DarkCyan
    }

    # ---- runwebps: same as runweb but force PowerShell with bypass ----
    function global:runwebps {
        if ($args.Count -eq 0) {
            Write-Host "Usage: runwebps <url-or-ghref> [args...]" -ForegroundColor DarkYellow
            return
        }
        $ref = $args[0]
        $url = Expand-GhRef $ref
        if (-not $url) { $url = $ref }
        $filename = Split-Path -Leaf $url
        if (-not $filename -or $filename -notmatch '\.ps1$') {
            $filename = "runwebps_$(Get-Random).ps1"
        }
        $dest = Join-Path $env:TEMP $filename
        Write-Host "[runwebps] Fetching $url" -ForegroundColor DarkCyan
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "[runwebps] DOWNLOAD FAILED: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        $global:CHL_LastUrl  = $url
        $global:CHL_LastFile = $dest
        $extraArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
        Write-Host "[runwebps] Executing with -ExecutionPolicy Bypass -NoProfile" -ForegroundColor DarkCyan
        & pwsh.exe -ExecutionPolicy Bypass -NoProfile -File $dest @extraArgs
        Write-Host "[runwebps] Exit code: $LASTEXITCODE" -ForegroundColor DarkCyan
    }

    # ---- verify: download a file and check its SHA-256 against an expected hash ----
    # Usage: verify <url-or-ghref> <expected-sha256>
    function global:verify {
        if ($args.Count -lt 2) {
            Write-Host "Usage: verify <url-or-ghref> <expected-sha256>" -ForegroundColor DarkYellow
            return
        }
        $ref      = $args[0]
        $expected = $args[1].ToLower().Trim()
        $url = Expand-GhRef $ref
        if (-not $url) { $url = $ref }
        $filename = Split-Path -Leaf $url
        if (-not $filename) { $filename = "verify_$(Get-Random).bin" }
        $dest = Join-Path $env:TEMP $filename
        Write-Host "[verify] Downloading $url" -ForegroundColor DarkCyan
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "[verify] DOWNLOAD FAILED: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        $actual = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLower()
        Write-Host "[verify] Expected: $expected" -ForegroundColor DarkGray
        Write-Host "[verify] Actual:   $actual"   -ForegroundColor DarkGray
        if ($actual -eq $expected) {
            Write-Host "[verify] PASS - hash matches" -ForegroundColor Green
            $global:CHL_LastUrl  = $url
            $global:CHL_LastFile = $dest
        } else {
            Write-Host "[verify] FAIL - hash mismatch! File saved at $dest for inspection." -ForegroundColor Red
        }
    }

    # ---- lasturl / lastfile: recall the last downloaded URL and file path ----
    function global:lasturl  { if ($global:CHL_LastUrl)  { $global:CHL_LastUrl }  else { Write-Host "(no recent url)"  -ForegroundColor DarkGray } }
    function global:lastfile { if ($global:CHL_LastFile) { $global:CHL_LastFile } else { Write-Host "(no recent file)" -ForegroundColor DarkGray } }

    # ---- viewlog: open today's HTML log in the default browser ----
    function global:viewlog {
        $today = Get-Date -Format "yyyy-MM-dd"
        $logDir = "C:\Users\Public\CommandHistory\HTML\$today"
        if (-not (Test-Path $logDir)) {
            Write-Host "No logs for today ($today)" -ForegroundColor DarkYellow
            return
        }
        $logs = Get-ChildItem $logDir -Filter *.html -ErrorAction SilentlyContinue
        if ($logs.Count -eq 0) {
            Write-Host "No HTML logs found in $logDir" -ForegroundColor DarkYellow
            return
        }
        # Open the most recently modified one
        $latest = $logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Host "Opening $($latest.FullName)" -ForegroundColor DarkCyan
        Start-Process $latest.FullName
    }

    # ---- searchlog: grep across all TXT logs for a pattern ----
    # Usage: searchlog <pattern>
    function global:searchlog {
        if ($args.Count -eq 0) {
            Write-Host "Usage: searchlog <pattern>" -ForegroundColor DarkYellow
            return
        }
        $pattern = $args -join ' '
        $logRoot = "C:\Users\Public\CommandHistory\TXT"
        if (-not (Test-Path $logRoot)) {
            Write-Host "No log directory at $logRoot" -ForegroundColor DarkYellow
            return
        }
        Write-Host "Searching for '$pattern' in $logRoot..." -ForegroundColor DarkCyan
        Get-ChildItem $logRoot -Recurse -Filter *.txt -ErrorAction SilentlyContinue |
            Select-String -Pattern $pattern -SimpleMatch |
            ForEach-Object {
                Write-Host "$($_.Filename):$($_.LineNumber): " -NoNewline -ForegroundColor DarkGray
                Write-Host $_.Line
            }
    }

    # ---- bypass: run any command with execution policy bypass ----
    # Usage: bypass <ps1-file-or-script-block>
    function global:bypass {
        if ($args.Count -eq 0) {
            Write-Host "Usage: bypass <script.ps1> [args...]" -ForegroundColor DarkYellow
            return
        }
        $first = $args[0]
        $extraArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
        if (Test-Path $first) {
            & pwsh.exe -ExecutionPolicy Bypass -NoProfile -File $first @extraArgs
        } else {
            # Treat as inline script
            $cmd = $args -join ' '
            & pwsh.exe -ExecutionPolicy Bypass -NoProfile -Command $cmd
        }
    }
    # =========================================================================
    # END BYPASS-INSTALL WORKFLOW HELPERS
    # =========================================================================


    # ---- NETWORK SHORTCUTS ----
    function global:flushdns       { & ipconfig.exe /flushdns }
    function global:registerdns    { & ipconfig.exe /registerdns }
    function global:releaseip      { & ipconfig.exe /release }
    function global:renewip        { & ipconfig.exe /renew }
    function global:displaydns     { & ipconfig.exe /displaydns }
    function global:showip         { & ipconfig.exe | Select-String "IPv4|IPv6" }
    function global:showgateway    { & ipconfig.exe | Select-String "Default Gateway" }
    function global:showwifi       { & netsh.exe wlan show interfaces }
    function global:wifiprofiles   { & netsh.exe wlan show profiles }
    function global:wifidisconnect { & netsh.exe wlan disconnect }
    function global:ports          { & netstat.exe -ano | Select-String "LISTENING" }
    function global:portfind       { & netstat.exe -ano | Select-String $args[0] }
    function global:connections    { & netstat.exe -ano | Select-String "ESTABLISHED" }
    function global:openports      { & netstat.exe -an | Select-String "LISTENING" }
    function global:routetable     { & route.exe print }
    function global:arptable       { & arp.exe -a }
    function global:showproxy      { & netsh.exe winhttp show proxy }
    function global:resetproxy     { & netsh.exe winhttp reset proxy }
    function global:fwstatus       { & netsh.exe advfirewall show allprofiles state }
    function global:netreset       { & netsh.exe int ip reset; & netsh.exe winsock reset; & ipconfig.exe /flushdns; & ipconfig.exe /release; & ipconfig.exe /renew }
    function global:winsockreset   { & netsh.exe winsock reset }
    function global:ipreset        { & netsh.exe int ip reset }
    function global:tcpreset       { & netsh.exe int tcp reset }
    function global:showdns        { & netsh.exe interface ip show dnsservers }

    # ---- FIREWALL ----
    function global:netshfwoff   { & netsh.exe advfirewall set allprofiles state off }
    function global:netshfwon    { & netsh.exe advfirewall set allprofiles state on }
    function global:netshfwreset { & netsh.exe advfirewall reset }
    function global:netshfwshow  { & netsh.exe advfirewall firewall show rule name=all }

    # ---- PROCESSES ----
    function global:fkill { & taskkill.exe /F /IM $($args -join ' ') }
    function global:fpid  { & taskkill.exe /F /PID $($args -join ' ') }

    # ---- SYSTEM INFO ----
    function global:localusers   { & net.exe user }
    function global:localgroups  { & net.exe localgroup }
    function global:admins       { & net.exe localgroup administrators }
    function global:enableadmin  { & net.exe user administrator /active:yes }
    function global:disableadmin { & net.exe user administrator /active:no }
    function global:whogroups    { & whoami.exe /groups }
    function global:whopriv      { & whoami.exe /priv }
    function global:whoall       { & whoami.exe /all }
    function global:savedcreds   { & cmdkey.exe /list }
    function global:services     { & sc.exe query type= service state= all }
    function global:drivers      { & driverquery.exe /v /fo list }
    function global:hotfixes     { & wmic.exe qfe get HotFixID,InstalledOn,Description /format:table }
    function global:lastpatch    { & wmic.exe qfe get HotFixID,InstalledOn }
    function global:installed    { & wmic.exe product get name,version /format:list }
    function global:startups     { & wmic.exe startup get caption,command }
    function global:diskhealth   { & wmic.exe diskdrive get status,model,size }
    function global:productkey   { & wmic.exe path softwarelicensingservice get OA3xOriginalProductKey }
    function global:envvars      { Get-ChildItem Env: | ForEach-Object { "$($_.Name)=$($_.Value)" } }
    function global:showpath     { $env:PATH -split ';' | Where-Object { $_ } }

    # ---- GROUP POLICY ----
    function global:gpforce     { & gpupdate.exe /force /wait:0 }
    function global:gpolist     { & gpresult.exe /r /scope:computer; & gpresult.exe /r /scope:user }
    function global:gpouser     { & gpresult.exe /r /scope:user }
    function global:gpocomputer { & gpresult.exe /r /scope:computer }
    function global:gpoverify   { & gpresult.exe /z }
    function global:gpohtml     { & gpresult.exe /h "$env:TEMP\gporeport.html"; Start-Process "$env:TEMP\gporeport.html" }

    # ---- REGISTRY ----
    function global:regquery  { & reg.exe query @args }
    function global:regadd    { & reg.exe add @args }
    function global:regdelete { & reg.exe delete @args }
    function global:regexport { & reg.exe export @args }
    function global:regimport { & reg.exe import @args }
    function global:regbackup {
        $tmp = $env:TEMP
        & reg.exe export "HKLM\SOFTWARE" "$tmp\HKLM_SOFTWARE_backup.reg" /y
        & reg.exe export "HKLM\SYSTEM"   "$tmp\HKLM_SYSTEM_backup.reg"   /y
        & reg.exe export "HKCU"          "$tmp\HKCU_backup.reg"          /y
        Write-Output "Backed up to $tmp"
    }

    # ---- CERTIFICATES ----
    function global:showcerts  { & certutil.exe -store my }
    function global:rootcerts  { & certutil.exe -store root }
    function global:hashfile   { & certutil.exe -hashfile $($args -join ' ') }
    function global:verifycert { & certutil.exe -verify $($args -join ' ') }

    # ---- ACTIVE DIRECTORY ----
    function global:domaininfo { & nltest.exe /dsgetdc:; & dsregcmd.exe /status }
    function global:dclist     { & nltest.exe /dclist: }
    function global:trustinfo  { & nltest.exe /domain_trusts /all_trusts }
    function global:fsmo       { & netdom.exe query fsmo }
    function global:replstatus { & repadmin.exe /replsummary }
    function global:replshow   { & repadmin.exe /showrepl }
    function global:adsite     { & nltest.exe /dsgetsite }
    function global:adkds      { & dsquery.exe server -isgc }
    function global:gcverify   { & nltest.exe /dsgetdc: /gc }
    function global:sitelink   { & repadmin.exe /showconn }

    # ---- WINDOWS UPDATE ----
    function global:wuscan     { & usoclient.exe StartScan }
    function global:wudownload { & usoclient.exe StartDownload }
    function global:wuinstall  { & usoclient.exe StartInstall }
    function global:wureboot   { & usoclient.exe RestartDevice }
    function global:wuforce    { & usoclient.exe StartScan; & usoclient.exe StartDownload; & usoclient.exe StartInstall }
    function global:wustatus   { & sc.exe query wuauserv; & sc.exe query bits; & sc.exe query cryptSvc }
    function global:wulog      { & wevtutil.exe qe Microsoft-Windows-WindowsUpdateClient/Operational /c:20 /rd:true /f:text }
    function global:wuhistory  { & wmic.exe qfe list full /format:table }
    function global:wudisable  { & sc.exe config wuauserv start= disabled; & sc.exe stop wuauserv }
    function global:wuenable   { & sc.exe config wuauserv start= auto; & sc.exe start wuauserv }

    # ---- BYPASS TOGGLES ----
    function global:defenderoff { & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f }
    function global:defenderon  { & reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /f }
    function global:uacoff      { & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f }
    function global:uacon       { & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 1 /f }
    function global:rdpon       {
        & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
        & netsh.exe advfirewall firewall set rule group="remote desktop" new enable=Yes
    }
    function global:rdpoff      {
        & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 1 /f
        & netsh.exe advfirewall firewall set rule group="remote desktop" new enable=No
    }
    function global:nlaoff      { & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f }
    function global:nlaon       { & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 1 /f }
    function global:fastbootoff { & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f }
    function global:fastbooton  { & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 1 /f }
    function global:showhidden  {
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSuperHidden /t REG_DWORD /d 1 /f
    }
    function global:showext     { & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f }
    function global:disabletelemetry {
        & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
        & sc.exe config DiagTrack start= disabled
        & sc.exe stop DiagTrack
    }
    function global:disablecortana   { & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f }
    function global:disableonedrive  { & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f }
    function global:taskbarclean {
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f
    }
    function global:numlockon  { & reg.exe add "HKU\.DEFAULT\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 2 /f }
    function global:autologon  {
        if ($args.Count -lt 2) { Write-Host "Usage: autologon <username> <password>" -ForegroundColor DarkYellow; return }
        & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
        & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d $args[0] /f
        & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d $args[1] /f
    }
    function global:autologoff {
        & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 0 /f
        & reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
    }
    function global:wupause    { & reg.exe add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseUpdatesExpiryTime /t REG_SZ /d "2099-01-01T00:00:00" /f }
    function global:wuresume   { & reg.exe delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseUpdatesExpiryTime /f }
    function global:wuserver   { & reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /s }
    function global:deliveryopt { & reg.exe query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" }

    # ---- BOOT AND POWER ----
    function global:safeboot     { & bcdedit.exe /set "{current}" safeboot minimal }
    function global:safebootnet  { & bcdedit.exe /set "{current}" safeboot network }
    function global:safebootoff  { & bcdedit.exe /deletevalue "{current}" safeboot }
    function global:bootinfo     { & bcdedit.exe /enum }
    function global:sleepoff     { & powercfg.exe -change -standby-timeout-ac 0; & powercfg.exe -change -standby-timeout-dc 0 }
    function global:hibernateoff { & powercfg.exe -h off }
    function global:hibernateon  { & powercfg.exe -h on }
    function global:smb1off      { & dism.exe /online /Disable-Feature /FeatureName:SMB1Protocol /NoRestart }
    function global:smb1on       { & dism.exe /online /Enable-Feature /FeatureName:SMB1Protocol /NoRestart }

    # ---- WSL ----
    function global:wsllist     { & wsl.exe --list --verbose }
    function global:wslshutdown { & wsl.exe --shutdown }
    function global:wslstatus   { & wsl.exe --status }
    function global:wslupdate   { & wsl.exe --update }

    # ---- PACKAGE MANAGERS ----
    # ---- PACKAGE MANAGERS ----
    # winget may not be in PATH on Server builds or freshly imaged boxes.
    # Resolver looks for it via Get-Command first, then falls back to the
    # well-known WindowsApps location under the current user profile.
    function global:Get-WingetPath {
        $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $candidates = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
        )
        foreach ($c in $candidates) {
            $resolved = Resolve-Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolved) { return $resolved.Path }
        }
        return $null
    }
    function global:wingetinstall {
        $w = Get-WingetPath
        if ($w) { & $w install @args } else { Write-Host "winget not found. Install 'App Installer' from the Microsoft Store." -ForegroundColor DarkYellow }
    }
    function global:wingetsearch {
        $w = Get-WingetPath
        if ($w) { & $w search @args } else { Write-Host "winget not found." -ForegroundColor DarkYellow }
    }
    function global:wingetupgrade {
        $w = Get-WingetPath
        if ($w) { & $w upgrade --all } else { Write-Host "winget not found." -ForegroundColor DarkYellow }
    }
    function global:wingetlist {
        $w = Get-WingetPath
        if ($w) { & $w list } else { Write-Host "winget not found." -ForegroundColor DarkYellow }
    }

    # ---- REPAIR AND CLEANUP ----
    function global:repair    { & sfc.exe /scannow; & dism.exe /Online /Cleanup-Image /RestoreHealth }
    function global:bitlocker { & manage-bde.exe -status }
    function global:activation { & cscript.exe //nologo C:\Windows\System32\slmgr.vbs /xpr }
    function global:cleartemp { Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "Temp files cleared" }
    function global:wureset   { & net.exe stop wuauserv; & net.exe stop cryptSvc; & net.exe stop bits; & net.exe stop msiserver; Rename-Item "C:\Windows\SoftwareDistribution" "SoftwareDistribution.old" -Force -ErrorAction SilentlyContinue; Rename-Item "C:\Windows\System32\catroot2" "catroot2.old" -Force -ErrorAction SilentlyContinue; & net.exe start wuauserv; & net.exe start cryptSvc; & net.exe start bits; & net.exe start msiserver; Write-Host "Windows Update components reset" }
    function global:wucleardownload { & net.exe stop wuauserv; Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue; & net.exe start wuauserv; Write-Host "WU download cache cleared" }
    function global:clearevt  { Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object { & wevtutil.exe cl $_.LogName 2>$null }; Write-Host "Event logs cleared" }

    # ---- SESSIONS ----
    function global:qusers   { & quser.exe }
    function global:sessions { & qwinsta.exe }

    # ---- BRIDGE UTILITIES ----
    function global:run {
        param([string]$Block)
        $Block -split "`n" | ForEach-Object {
            $line = $_.Trim()
            if ($line -ne "") { & cmd.exe /c $line }
        }
    }
    function global:opencmd { Start-Process cmd.exe -ArgumentList "/k cd /d $PWD" }
    function global:bg      { Start-Process -FilePath $args[0] -ArgumentList ($args[1..$args.Length] -join ' ') -WindowStyle Hidden }
    function global:bgmin   { Start-Process -FilePath $args[0] -ArgumentList ($args[1..$args.Length] -join ' ') -WindowStyle Minimized }
}

# =============================================================
# SECTION 3: BOOT
# =============================================================

function Start-CommandLoggerPS7 {
    $Global:CHL_Session    = Get-SessionType
    $Global:CHL_Today      = (Get-Date -Format "yyyy-MM-dd")
    $Global:CHL_LastHistId = 0

    Initialize-LogFolders
    Write-SessionBanner
    Register-PromptLogger
    Register-SmartCd
    Initialize-CmdCompat
    Set-TerminalColors

    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Close-HtmlLog } | Out-Null
}

Start-CommandLoggerPS7
