# setup-dropbox-ignore.ps1 — one-shot per-machine bootstrap for the Dropbox
# ignore system (2026-07-14). Safe to re-run.
#
# Default (always-on machines): writes the maintenance script + README locally
# (bypassing any sync backlog), registers the DropboxIgnoreMaintenance task
# (S4U principal so it fires even at the lock/logon screen; 6-hourly + at logon
# + start-when-available), runs the script once, de-symlinks ~\.claude.json,
# and records this hostname in the README.
#
# -Client (SSH-only clients / laptops): same, but NO recurring task — the
# one-time stamp + de-symlink is all a client needs; junk it uploads later is
# garbage-collected account-wide within ~6 h by an always-on machine's run.
param([switch]$Client)

$cfg = "$env:USERPROFILE\Dropbox\claude-config"
if (-not (Test-Path $cfg)) { throw "claude-config not found at $cfg" }

# ---------- 1. maintenance script (always overwritten: canonical 2026-07-14 version) ----------
$maintenance = @'
# Dropbox ignore maintenance for the synced claude-config folder.
# Dropbox has no working .dropboxignore here (rules.dropboxignore is closed beta),
# so ignores are the com.dropbox.ignored NTFS stream, stamped per item.
# Run daily via scheduled task; safe to re-run (stamping is idempotent).

$root = 'C:\Users\Kenneth\Dropbox\claude-config'
$stamped = 0

function Set-DropboxIgnored([string]$path) {
    if (-not (Test-Path $path)) { return }
    try { $null = Get-Content -Path $path -Stream com.dropbox.ignored -ErrorAction Stop }
    catch { Set-Content -Path $path -Stream com.dropbox.ignored -Value 1; $script:stamped++ }
}

# 1. Runtime/cache dirs (regenerable, machine-local)
$runtimeDirs = 'debug','file-history','shell-snapshots','ide','cache','paste-cache',
    'tasks','backups','plugins','session-env','todos','teams','tmp','sessions',
    'jobs','daemon','.pytest_cache'
foreach ($d in $runtimeDirs) { Set-DropboxIgnored "$root\$d" }

# 2. Machine-local files (ponytail: stream is lost if a file is rewritten by
#    atomic rename; re-stamping daily here is the fix)
$localFiles = 'settings.local.json','history.jsonl','stats-cache.json',
    'daemon.lock','daemon.status.json','.last-cleanup','.last-update-result.json'
foreach ($f in $localFiles) { Set-DropboxIgnored "$root\$f" }

# 3. Swarm agent logs: every subagents dir under projects (new ones appear per session)
Get-ChildItem "$root\projects" -Directory -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object Name -eq 'subagents' |
    ForEach-Object { Set-DropboxIgnored $_.FullName }

# 4. SKILLS ALWAYS SYNC (user directive 2026-07-14): nothing under skills\ is
#    ever auto-ignored by pattern or size — current and future skills sync in
#    full. The ONLY exceptions are __pycache__ and the def14a list below.
#    Those data dirs were MOVED to C:\Users\Kenneth\.claude-local\
#    def14a-voting-control-workspace (env DEF14A_DATA_ROOT) on 2026-07-14;
#    the list stays as a backstop in case a script recreates one in the
#    synced workspace.
$def14aData = 'raw_via_scraper','oos_test','llm_cache','_finalmat_parts','oracle_full',
    'oracle_pilot','cc_labels','_w4a_parts','_econ_parts','_cc_parts','_w1_parts',
    '_w1_port_parts','_w3_parts','_w3int_parts','_ceiling_parts','_kc_table_cache',
    '_diagram_staging','sample','_econ_arm2','tmp'
foreach ($d in $def14aData) {
    Set-DropboxIgnored "$root\skills\def14a-voting-control-workspace\$d"
}
Get-ChildItem "$root\skills" -Directory -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object Name -eq '__pycache__' |
    ForEach-Object { Set-DropboxIgnored $_.FullName }

# 5. Research-project backstops: cache dirs relocated out of Dropbox on
#    2026-07-14; stamp them if stale code ever recreates one in the synced tree.
$projectBackstops = @(
    'C:\Users\Kenneth\Dropbox\NUS Work\Research\3. Work in Progress\Specialist Directors US\data\interim\exposure_v2_cache',
    'C:\Users\Kenneth\Dropbox\NUS Work\Research\3. Work in Progress\Specialist Directors US\data\interim\director_v1_cache',
    'C:\Users\Kenneth\Dropbox\NUS Work\Research\2. Review\Event Study Delaware\data\totrain\rebuild_0703',
    'C:\Users\Kenneth\Dropbox\NUS Work\Research\2. Review\Event Study Delaware\data\totrain\tmp'
)
foreach ($p in $projectBackstops) { Set-DropboxIgnored $p }

# 5b. Research tree sweep: environment and bytecode dirs are never synced.
$research = 'C:\Users\Kenneth\Dropbox\NUS Work\Research'
if (Test-Path $research) {
    foreach ($d in [System.IO.Directory]::EnumerateDirectories($research,'*','AllDirectories')) {
        if ((Split-Path $d -Leaf) -in '.venv','venv','node_modules','__pycache__','.pytest_cache') {
            Set-DropboxIgnored $d
        }
    }
}

# 5c. Tripwire: alert on many-small-file dirs under Research that are syncing
#     and not ignored — a fresh pipeline cache written into Dropbox (the
#     2026-07-14 exposure_v2_cache incident: 2M files in one 3-hour run).
$alertFile = "$root\DROPBOX-IGNORE-ALERTS.txt"
$whitelist = @(
    'C:\Users\Kenneth\Dropbox\NUS Work\Research\3. Work in Progress\Common Ownership around the World\dual_class\data'
)
if (Test-Path $research) {
    $rootDepth = ($research -split '\\').Count
    $buckets = @{}
    foreach ($f in [System.IO.Directory]::EnumerateFiles($research,'*','AllDirectories')) {
        $parts = $f -split '\\'
        $d = [Math]::Min($parts.Count - 1, $rootDepth + 4)
        $key = ($parts[0..($d-1)] -join '\')
        if ($buckets.ContainsKey($key)) { $buckets[$key]++ } else { $buckets[$key] = 1 }
    }
    $alerts = foreach ($b in ($buckets.GetEnumerator() | Where-Object { $_.Value -gt 5000 })) {
        $p = $b.Key
        if ($whitelist | Where-Object { $p -like "$_*" }) { continue }
        $ignored = $false; $probe = $p
        while ($probe.Length -gt $research.Length) {
            try { $null = Get-Content -Path $probe -Stream com.dropbox.ignored -ErrorAction Stop; $ignored = $true; break } catch {}
            $probe = Split-Path $probe -Parent
        }
        if (-not $ignored) { "$($b.Value) files`t$p" }
    }
    if ($alerts) {
        "== $(Get-Date -Format s) SYNCING dirs >5000 files, not ignored - relocate per CLAUDE.md Local Data Hygiene ==" | Add-Content $alertFile
        $alerts | Add-Content $alertFile
    }
}

# 6. Clean stale conflict/tmp junk (>1h old so live writes are never raced).
#    Conflicted copies are swept RECURSIVELY under claude-config (runtime files
#    only ever conflict from multi-machine races); tmp leftovers root-only.
$cutoff = (Get-Date).AddHours(-1)
$junk = @(Get-ChildItem $root -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match 'conflicted copy' -and $_.LastWriteTime -lt $cutoff
})
$junk += Get-ChildItem $root -File -Force | Where-Object {
    ($_.Name -match '\.tmp\.\w+\.\w+$' -or $_.Name -match '\.tmp\.[0-9a-f]{8}$') -and
    $_.LastWriteTime -lt $cutoff
}
$junk | Remove-Item -Force -ErrorAction SilentlyContinue

"$(Get-Date -Format s) stamped=$stamped junk_removed=$($junk.Count)"
'@
Set-Content -Path "$cfg\dropbox-ignore-maintenance.ps1" -Value $maintenance -Encoding utf8
Write-Host "maintenance script written"

# ---------- 2. README (written only if the synced copy has not arrived) ----------
$readmePath = "$cfg\DROPBOX-IGNORE-README.md"
if (-not (Test-Path $readmePath)) {
$readme = @'
# How Dropbox ignoring works in this folder

A `.dropboxignore` file does NOT work — Dropbox's official ignore-rules feature
(`rules.dropboxignore` in the Dropbox root) is closed beta and not enabled on
this account. The working mechanism is the `com.dropbox.ignored` NTFS stream,
stamped per file/folder:

    Set-Content -Path <path> -Stream com.dropbox.ignored -Value 1

Stamping an already-synced item keeps it on the local disk but REMOVES it from
dropbox.com and all other devices.

`dropbox-ignore-maintenance.ps1` (in this folder) stamps everything that should
not sync — runtime dirs, machine-local files, `projects\**\subagents` swarm
logs, relocated-cache backstops, and (in `NUS Work\Research`) every `.venv`,
`venv`, `node_modules`, `__pycache__`, and `.pytest_cache` dir — and deletes
stale conflicted-copy/tmp junk at the root. It is idempotent and re-stamps
daily because atomic-rename writes strip the stream from files. The systemic
rule (interim ML/LLM caches live at `C:\Users\Kenneth\.claude-local\<project>\`,
never in Dropbox; only curated raw + cleaned data sync) is in global CLAUDE.md
under "Local Data Hygiene".

What stays synced: `skills`, `skills-retired`, `agents`, `commands`, `hooks`,
`channels`, `clo-author`, `CLAUDE.md`, `settings.json`, main conversation
transcripts (`projects\<slug>\*.jsonl`), and auto-memory
(`projects\C--Users-Kenneth\memory`).

SKILLS ALWAYS SYNC (user directive 2026-07-14): the maintenance script never
auto-ignores anything under `skills\` by pattern or size, so every current and
future skill syncs in full (only `__pycache__` is stamped). The
def14a-voting-control-workspace bulk data (~8.4 GB scraped SEC data, 20 dirs)
was moved out of Dropbox to `C:\Users\Kenneth\.claude-local\
def14a-voting-control-workspace`; scripts resolve it via the `DEF14A_DATA_ROOT`
env var, defaulting to that path. The script's def14a stamp list remains only
as a backstop should a script recreate one of those dirs in the synced tree.

## Per-machine setup (run once on every machine)

Run the hosted bootstrap (works even before Dropbox sync catches up):

    Invoke-WebRequest https://kennethkhoocy.github.io/files/claude-config/setup-dropbox-ignore.ps1 -OutFile "$env:TEMP\setup-dropbox-ignore.ps1"
    # always-on machines (desktops/servers):
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\setup-dropbox-ignore.ps1"
    # SSH-only clients / laptops:
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\setup-dropbox-ignore.ps1" -Client

Always-on machines get the DropboxIgnoreMaintenance task: 6-hourly, plus
at-logon and start-when-available so missed windows catch up. The task runs
under an S4U principal (run whether user is logged on or not, no stored
password), so it keeps firing even when the machine sits at the lock/logon
screen for days. -Client machines
get NO recurring task — the one-time stamps + `~\.claude.json` de-symlink are
all they need; junk they upload later is garbage-collected account-wide within
~6 h by an always-on machine's run (caveat: that GC can also delete a client's
just-uploaded subagent logs locally while a session is still running there — if
a client regularly runs heavy swarm work, set it up WITHOUT -Client instead).

Done on: DESKTOP-0C7PLAP (this machine, 2026-07-14).
Pending: DESKTOP-7NI0FG4, DESKTOP-7CBIOGE, LAPTOP-O0I1ANMG.
'@
Set-Content -Path $readmePath -Value $readme -Encoding utf8
Write-Host "README written"
} else { Write-Host "README already present (synced copy kept)" }

# ---------- 3. scheduled task (always-on machines only) ----------
if ($Client) {
    Write-Host "client mode: no scheduled task registered (an always-on machine's 6-hourly run garbage-collects account-wide)"
} else {
    $ok = $false
    cmd /c "schtasks /delete /f /tn DropboxIgnoreMaintenance >nul 2>&1"
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$cfg\dropbox-ignore-maintenance.ps1`""
        $daily = New-ScheduledTaskTrigger -Daily -At 6am
        $daily.Repetition = (New-ScheduledTaskTrigger -Once -At 6am `
            -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Hours 24)).Repetition
        $logon = New-ScheduledTaskTrigger -AtLogOn
        # S4U: run whether or not anyone is logged on (no stored password). Without
        # this the default interactive principal silently skips every firing while
        # the machine sits at the lock/logon screen — days on end on these hosts.
        # S4U tokens are local-only (no network creds); the script is pure local NTFS.
        $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -LogonType S4U -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        Register-ScheduledTask -TaskName 'DropboxIgnoreMaintenance' -Action $action `
            -Trigger $daily,$logon -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
        Write-Host "scheduled task registered (S4U: runs at lock/logon screen; 6-hourly + at logon + start-when-available)"
        $ok = $true
    } catch { Write-Host "Register-ScheduledTask failed ($($_.Exception.Message)); falling back to schtasks" }
    if (-not $ok) {
        # /np /ru = the schtasks spelling of S4U (run whether logged on or not, no stored password)
        schtasks /create /f /tn "DropboxIgnoreMaintenance" /sc daily /st 06:00 /ri 360 /du 24:00 /np /ru "$env:USERNAME" /tr "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '$cfg\dropbox-ignore-maintenance.ps1'"
        schtasks /create /f /tn "DropboxIgnoreMaintenanceLogon" /sc onlogon /np /ru "$env:USERNAME" /tr "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '$cfg\dropbox-ignore-maintenance.ps1'"
    }
}

# ---------- 4. de-symlink ~\.claude.json ----------
$l = Get-Item "$env:USERPROFILE\.claude.json" -Force -ErrorAction SilentlyContinue
if ($l -and $l.LinkType -eq 'SymbolicLink') {
    $s = $l.Target; $l.Delete(); Copy-Item $s "$env:USERPROFILE\.claude.json"
    Write-Host "de-symlinked ~\.claude.json to a real local file"
} else { Write-Host "~\.claude.json already a real local file (or absent)" }

# ---------- 5. run maintenance once ----------
& powershell -NoProfile -ExecutionPolicy Bypass -File "$cfg\dropbox-ignore-maintenance.ps1"

# ---------- 6. record this hostname in the README ----------
$hn = $env:COMPUTERNAME
$date = Get-Date -Format yyyy-MM-dd
$mode = if ($Client) { 'client' } else { 'always-on' }
$txt = Get-Content $readmePath -Raw
if ($txt -match "Pending:.*$hn") {
    $txt = $txt -replace "Done on: ", "Done on: $hn ($date, $mode), "
    $txt = $txt -replace "(Pending:[^\r\n]*?)(, )?$hn", '$1'
    $txt = $txt -replace "Pending: ,\s*", "Pending: "
    Set-Content -Path $readmePath -Value $txt -Encoding utf8
    Write-Host "README updated: $hn marked done ($mode)"
} else { Write-Host "README Done-on line already covers $hn (or hostname unlisted)" }

Write-Host "SETUP COMPLETE on $hn ($mode mode)"
