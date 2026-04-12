# =====================================================
#  CommandLoggerPS7 -- Unified core script
#  https://github.com/SellerDumpskart/CommandLoggerPS7
#
#  Single-file integration of:
#    - Day-wise TXT/HTML/CSV command logger
#    - Session detection (DWAgent/MeshCentral/SSH/RDP/CMD)
#    - Custom cd (handles spaces without quotes)
#    - cmdcompat layer (CMD-compatible function wrappers)
#    - PSReadLine white colors for light terminals
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
    # Define the smart-cd function in global scope
    function global:Invoke-SmartCd {
        param(
            [Parameter(ValueFromRemainingArguments=$true)]
            [string[]]$Path
        )
        if ($Path.Count -gt 1)      { Set-Location ($Path -join " ") }
        elseif ($Path.Count -eq 1)  { Set-Location $Path[0] }
        else                        { Set-Location $HOME }
    }
    # Force-overwrite the built-in cd alias to point at our function.
    # Set-Alias -Force works on AllScope aliases; Remove-Item does not.
    Set-Alias -Name cd -Value Invoke-SmartCd -Scope Global -Force -Option AllScope
}

function Set-LightTerminalColors {
    if (Get-Module -ListAvailable PSReadLine) {
        try {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
            Set-PSReadLineOption -Colors @{
                Command   = 'White'; Parameter = 'White'; Operator = 'White'
                Variable  = 'White'; String    = 'White'; Number   = 'White'
                Member    = 'White'; Keyword   = 'White'
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

    # ---- ECHO: prints with %VAR% expansion ----
    function global:Invoke-CmdEcho {
        $text = ($args -join ' ')
        $expanded = [Environment]::ExpandEnvironmentVariables($text)
        Write-Host $expanded
    }

    # ---- SET: actually persists because it's real PS env-var assignment ----
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
            Set-Item -Path "Env:$name" -Value $value
        } else {
            # `set VAR` (no =): show just that var
            $name = $joined.Trim()
            $val  = [Environment]::GetEnvironmentVariable($name)
            if ($val) { "$name=$val" }
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
    function global:Invoke-CmdCurl {
        $expanded = $args | ForEach-Object { [Environment]::ExpandEnvironmentVariables("$_") }
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
    Set-Alias -Name dir    -Value Invoke-CmdDir    -Scope Global -Force -Option AllScope
    Set-Alias -Name move   -Value Invoke-CmdMove   -Scope Global -Force -Option AllScope
    Set-Alias -Name copy   -Value Invoke-CmdCopy   -Scope Global -Force -Option AllScope
    Set-Alias -Name del    -Value Invoke-CmdDel    -Scope Global -Force -Option AllScope
    Set-Alias -Name erase  -Value Invoke-CmdDel    -Scope Global -Force
    Set-Alias -Name ren    -Value Invoke-CmdRen    -Scope Global -Force -Option AllScope
    Set-Alias -Name rename -Value Invoke-CmdRen    -Scope Global -Force
    Set-Alias -Name rmdir  -Value Invoke-CmdRmdir  -Scope Global -Force -Option AllScope
    Set-Alias -Name rd     -Value Invoke-CmdRmdir  -Scope Global -Force
    Set-Alias -Name type   -Value Invoke-CmdType   -Scope Global -Force -Option AllScope
    Set-Alias -Name mkdir  -Value Invoke-CmdMkdir  -Scope Global -Force -Option AllScope
    Set-Alias -Name md     -Value Invoke-CmdMkdir  -Scope Global -Force
    Set-Alias -Name echo   -Value Invoke-CmdEcho   -Scope Global -Force -Option AllScope
    Set-Alias -Name set    -Value Invoke-CmdSet    -Scope Global -Force -Option AllScope
    Set-Alias -Name cls    -Value Invoke-CmdCls    -Scope Global -Force -Option AllScope
    Set-Alias -Name clear  -Value Invoke-CmdCls    -Scope Global -Force
    Set-Alias -Name title  -Value Invoke-CmdTitle  -Scope Global -Force
    Set-Alias -Name ver    -Value Invoke-CmdVer    -Scope Global -Force
    Set-Alias -Name vol    -Value Invoke-CmdVol    -Scope Global -Force
    Set-Alias -Name curl   -Value Invoke-CmdCurl   -Scope Global -Force -Option AllScope
    Set-Alias -Name mklink -Value Invoke-CmdMklink -Scope Global -Force
    Set-Alias -Name assoc  -Value Invoke-CmdAssoc  -Scope Global -Force
    Set-Alias -Name ftype  -Value Invoke-CmdFtype  -Scope Global -Force
    Set-Alias -Name color  -Value Invoke-CmdColor  -Scope Global -Force

    # ---- 'c' shortcut: still tries cmd.exe for users who want raw CMD access ----
    # In contexts where cmd.exe works, this runs arbitrary CMD commands.
    # In contexts where cmd.exe is blocked, this will silently fail.
    function global:c { & cmd.exe /c "cd /d ""$PWD"" && $($args -join ' ')" }

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
    function global:envvars      { & cmd.exe /c "set" }
    function global:showpath     { & cmd.exe /c "echo %PATH%" }

    # ---- GROUP POLICY ----
    function global:gpforce     { & gpupdate.exe /force /wait:0 }
    function global:gpolist     { & gpresult.exe /r /scope:computer; & gpresult.exe /r /scope:user }
    function global:gpouser     { & gpresult.exe /r /scope:user }
    function global:gpocomputer { & gpresult.exe /r /scope:computer }
    function global:gpoverify   { & gpresult.exe /z }
    function global:gpohtml     { & gpresult.exe /h "$env:TEMP\gporeport.html"; Start-Process "$env:TEMP\gporeport.html" }

    # ---- REGISTRY ----
    function global:regquery  { & cmd.exe /c "reg query $($args -join ' ')" }
    function global:regadd    { & cmd.exe /c "reg add $($args -join ' ')" }
    function global:regdelete { & cmd.exe /c "reg delete $($args -join ' ')" }
    function global:regexport { & cmd.exe /c "reg export $($args -join ' ')" }
    function global:regimport { & cmd.exe /c "reg import $($args -join ' ')" }
    function global:regbackup { & cmd.exe /c "reg export HKLM\SOFTWARE %TEMP%\HKLM_SOFTWARE_backup.reg /y & reg export HKLM\SYSTEM %TEMP%\HKLM_SYSTEM_backup.reg /y & reg export HKCU %TEMP%\HKCU_backup.reg /y & echo Backed up to %TEMP%" }

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
    function global:defenderoff { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f" }
    function global:defenderon  { & cmd.exe /c "reg delete ""HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"" /v DisableRealtimeMonitoring /f" }
    function global:uacoff      { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"" /v EnableLUA /t REG_DWORD /d 0 /f" }
    function global:uacon       { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"" /v EnableLUA /t REG_DWORD /d 1 /f" }
    function global:rdpon       { & cmd.exe /c "reg add ""HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server"" /v fDenyTSConnections /t REG_DWORD /d 0 /f & netsh advfirewall firewall set rule group=""remote desktop"" new enable=Yes" }
    function global:rdpoff      { & cmd.exe /c "reg add ""HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server"" /v fDenyTSConnections /t REG_DWORD /d 1 /f & netsh advfirewall firewall set rule group=""remote desktop"" new enable=No" }
    function global:nlaoff      { & cmd.exe /c "reg add ""HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"" /v UserAuthentication /t REG_DWORD /d 0 /f" }
    function global:nlaon       { & cmd.exe /c "reg add ""HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"" /v UserAuthentication /t REG_DWORD /d 1 /f" }
    function global:fastbootoff { & cmd.exe /c "reg add ""HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power"" /v HiberbootEnabled /t REG_DWORD /d 0 /f" }
    function global:fastbooton  { & cmd.exe /c "reg add ""HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power"" /v HiberbootEnabled /t REG_DWORD /d 1 /f" }
    function global:showhidden  { & cmd.exe /c "reg add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"" /v Hidden /t REG_DWORD /d 1 /f & reg add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"" /v ShowSuperHidden /t REG_DWORD /d 1 /f" }
    function global:showext     { & cmd.exe /c "reg add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"" /v HideFileExt /t REG_DWORD /d 0 /f" }
    function global:disabletelemetry { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection"" /v AllowTelemetry /t REG_DWORD /d 0 /f"; & sc.exe config DiagTrack start= disabled; & sc.exe stop DiagTrack }
    function global:disablecortana   { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search"" /v AllowCortana /t REG_DWORD /d 0 /f" }
    function global:disableonedrive  { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive"" /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f" }
    function global:taskbarclean { & cmd.exe /c "reg add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"" /v TaskbarMn /t REG_DWORD /d 0 /f & reg add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"" /v TaskbarDa /t REG_DWORD /d 0 /f & reg add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"" /v ShowTaskViewButton /t REG_DWORD /d 0 /f" }
    function global:numlockon  { & cmd.exe /c "reg add ""HKU\.DEFAULT\Control Panel\Keyboard"" /v InitialKeyboardIndicators /t REG_SZ /d 2 /f" }
    function global:autologon  { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"" /v AutoAdminLogon /t REG_SZ /d 1 /f & reg add ""HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"" /v DefaultUserName /t REG_SZ /d $($args[0]) /f & reg add ""HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"" /v DefaultPassword /t REG_SZ /d $($args[1]) /f" }
    function global:autologoff { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"" /v AutoAdminLogon /t REG_SZ /d 0 /f & reg delete ""HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"" /v DefaultPassword /f" }
    function global:wupause    { & cmd.exe /c "reg add ""HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"" /v PauseUpdatesExpiryTime /t REG_SZ /d ""2099-01-01T00:00:00"" /f" }
    function global:wuresume   { & cmd.exe /c "reg delete ""HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"" /v PauseUpdatesExpiryTime /f" }
    function global:wuserver   { & cmd.exe /c "reg query ""HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"" /s" }
    function global:deliveryopt { & cmd.exe /c "reg query ""HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config""" }

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
    function global:wingetinstall { & winget.exe install $($args -join ' ') }
    function global:wingetsearch  { & winget.exe search $($args -join ' ') }
    function global:wingetupgrade { & winget.exe upgrade --all }
    function global:wingetlist    { & winget.exe list }

    # ---- REPAIR AND CLEANUP ----
    function global:repair    { & sfc.exe /scannow; & dism.exe /Online /Cleanup-Image /RestoreHealth }
    function global:bitlocker { & cmd.exe /c "manage-bde -status" }
    function global:activation { & cmd.exe /c "cscript //nologo C:\Windows\System32\slmgr.vbs /xpr" }
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
    Set-LightTerminalColors

    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Close-HtmlLog } | Out-Null
}

Start-CommandLoggerPS7
