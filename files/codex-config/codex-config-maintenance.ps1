# Maintains the portable Codex configuration projection in Dropbox.
# Process-owned state and the live Codex session roots remain machine-local.
# Windows PowerShell 5.1 compatible.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$dropboxRoot = [IO.Directory]::GetParent($root).FullName
$userRoot = [IO.Path]::GetFullPath($env:USERPROFILE)
$localCodex = Join-Path $userRoot '.codex'
$claudeConfig = Join-Path $dropboxRoot 'claude-config'
$script:stamped = 0
$script:unignored = 0
$script:junkRemoved = 0
$script:linksOk = 0
$script:localRootsOk = 0

function Test-DropboxIgnored([string]$path) {
    try {
        $null = Get-Content -LiteralPath $path -Stream com.dropbox.ignored -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Set-DropboxIgnored([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (-not (Test-DropboxIgnored $path)) {
        Set-Content -LiteralPath $path -Stream com.dropbox.ignored -Value 1 -ErrorAction Stop
        $script:stamped++
    }
    if (-not (Test-DropboxIgnored $path)) { throw "Could not set Dropbox ignore stream: $path" }
}

function Get-LinkTargetPath([IO.FileSystemInfo]$item) {
    if (-not $item.LinkType) { return $null }
    $raw = @($item.Target)[0]
    if (-not $raw) { return $null }
    if ([IO.Path]::IsPathRooted($raw)) { return [IO.Path]::GetFullPath($raw) }
    return [IO.Path]::GetFullPath((Join-Path (Split-Path $item.FullName -Parent) $raw))
}

function Test-ExpectedLink([string]$linkPath, [string]$targetPath, [string]$requiredLinkType = '') {
    if (-not (Test-Path -LiteralPath $linkPath)) {
        Write-Warning "Missing link: $linkPath"
        return
    }
    $item = Get-Item -Force -LiteralPath $linkPath
    $actual = Get-LinkTargetPath $item
    $expected = [IO.Path]::GetFullPath($targetPath)
    if ($actual -and $actual.Equals($expected,[StringComparison]::OrdinalIgnoreCase) -and
        (-not $requiredLinkType -or $item.LinkType -eq $requiredLinkType)) {
        $script:linksOk++
    }
    else { Write-Warning "Unexpected link target: $linkPath -> $actual (expected $expected)" }
}

function Test-RealLocalRoot([string]$path) {
    $item = Get-Item -Force -LiteralPath $path -ErrorAction SilentlyContinue
    if ($item -and $item.PSIsContainer -and -not $item.LinkType -and
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) {
        $script:localRootsOk++
        return
    }
    Write-Warning "Session root must be a real local directory: $path"
}

# Dropbox receives only the small portable projection. These names are
# process-owned Codex state and remain ignored if an accidental copy appears.
$runtimeDirs = '.sandbox','.sandbox-bin','.sandbox-secrets','.tmp','tmp','cache',
    'sqlite','plugins','vendor_imports','claude','logs','log','scratch',
    'process_manager','ambient-suggestions','memories','pets','sessions',
    'archived_sessions'
foreach ($name in $runtimeDirs) { Set-DropboxIgnored (Join-Path $root $name) }

$runtimeFiles = 'config.toml','auth.json','history.jsonl','session_index.jsonl',
    'models_cache.json','version.json','installation_id','cap_sid','sandbox.log',
    '.codex-global-state.json','.codex-global-state.json.bak',
    'session-sync-allowlist.txt'
foreach ($name in $runtimeFiles) { Set-DropboxIgnored (Join-Path $root $name) }

Get-ChildItem -File -Force -LiteralPath $root -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.sqlite(?:-shm|-wal)?$' } |
    ForEach-Object { Set-DropboxIgnored $_.FullName }

Test-ExpectedLink (Join-Path $localCodex 'AGENTS.md') (Join-Path $root 'AGENTS.md')
Test-ExpectedLink (Join-Path $localCodex 'orchestrator.config.toml') (Join-Path $root 'orchestrator.config.toml')
Test-ExpectedLink (Join-Path $localCodex 'skills') (Join-Path $claudeConfig 'skills') 'Junction'
Test-RealLocalRoot (Join-Path $localCodex 'sessions')
Test-RealLocalRoot (Join-Path $localCodex 'archived_sessions')

$mirrorScript = Join-Path $root 'watch-codex-session-policy.ps1'
if (-not (Test-Path -LiteralPath $mirrorScript -PathType Leaf)) {
    throw "Session-mirror script is missing: $mirrorScript"
}
$mirrorOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mirrorScript -Once 2>&1
$mirrorExit = $LASTEXITCODE
$mirrorOutput | ForEach-Object { Write-Output $_ }
$mirrorLines = @($mirrorOutput | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
$mirrorSummary = if ($mirrorLines.Count) { $mirrorLines[-1].Trim() } else { '' }
$mirrorPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\s+uploaded=(\d+)\s+downloaded=(\d+)\s+excluded=(\d+)\s+deferred=(\d+)\s+conflicts=(\d+)\s+errors=(\d+)\s+local_roots_ok=2\s+mirror_roots_ok=2$'
$match = [Regex]::Match($mirrorSummary,$mirrorPattern)
if ($mirrorExit -ne 0 -or -not $match.Success -or [int]$match.Groups[5].Value -ne 0 -or [int]$match.Groups[6].Value -ne 0) {
    throw "Session-mirror reconciliation failed. Last line: $mirrorSummary"
}
$uploaded = [int]$match.Groups[1].Value
$downloaded = [int]$match.Groups[2].Value
$excluded = [int]$match.Groups[3].Value
$deferred = [int]$match.Groups[4].Value

# Remove only stale temporary artifacts created by this mirror implementation.
$cutoff = (Get-Date).AddDays(-1)
$mirrorRoot = Join-Path $root 'session-mirror'
if (Test-Path -LiteralPath $mirrorRoot -PathType Container) {
    foreach ($item in Get-ChildItem -Recurse -File -Force -LiteralPath $mirrorRoot -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\.codex-mirror-[0-9a-f]{32}\.(?:tmp|bak|failed)$' -and
        $_.LastWriteTime -lt $cutoff
    }) {
        Remove-Item -Force -LiteralPath $item.FullName
        if (-not (Test-Path -LiteralPath $item.FullName)) { $script:junkRemoved++ }
    }
}

$summary = "$(Get-Date -Format s) stamped=$($script:stamped) unignored=$($script:unignored) junk_removed=$($script:junkRemoved) uploaded=$uploaded downloaded=$downloaded excluded=$excluded deferred=$deferred conflicts=0 links_ok=$($script:linksOk) local_roots_ok=$($script:localRootsOk) mirror_roots_ok=2"
$summary
if ($script:linksOk -ne 3 -or $script:localRootsOk -ne 2) { exit 1 }
