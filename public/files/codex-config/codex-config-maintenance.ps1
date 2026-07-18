# Maintains the portable Codex configuration projection in Dropbox.
# Codex runtime state remains under the real, machine-local ~/.codex directory.

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$dropboxRoot = [IO.Directory]::GetParent($root).FullName
$userRoot = [IO.Path]::GetFullPath($env:USERPROFILE)
$localCodex = Join-Path $userRoot '.codex'
$claudeConfig = Join-Path $dropboxRoot 'claude-config'
$stamped = 0
$junkRemoved = 0
$linksOk = 0

function Set-DropboxIgnored([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    try { $null = Get-Content -LiteralPath $path -Stream com.dropbox.ignored -ErrorAction Stop }
    catch {
        Set-Content -LiteralPath $path -Stream com.dropbox.ignored -Value 1 -ErrorAction Stop
        $null = Get-Content -LiteralPath $path -Stream com.dropbox.ignored -ErrorAction Stop
        $script:stamped++
    }
}

function Get-LinkTargetPath([IO.FileSystemInfo]$item) {
    if (-not $item.LinkType) { return $null }
    $raw = @($item.Target)[0]
    if (-not $raw) { return $null }
    if ([IO.Path]::IsPathRooted($raw)) { return [IO.Path]::GetFullPath($raw) }
    return [IO.Path]::GetFullPath((Join-Path (Split-Path $item.FullName -Parent) $raw))
}

function Test-ExpectedLink([string]$linkPath, [string]$targetPath) {
    if (-not (Test-Path -LiteralPath $linkPath)) {
        Write-Warning "Missing link: $linkPath"
        return
    }
    $item = Get-Item -Force -LiteralPath $linkPath
    $actual = Get-LinkTargetPath $item
    $expected = [IO.Path]::GetFullPath($targetPath)
    if ($actual -and $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        $script:linksOk++
    }
    else { Write-Warning "Unexpected link target: $linkPath -> $actual (expected $expected)" }
}

# Guard against accidental copies of process-owned Codex state in Dropbox.
$runtimeDirs = '.sandbox','.sandbox-bin','.sandbox-secrets','.tmp','tmp','cache',
    'sessions','archived_sessions','sqlite','plugins','vendor_imports','claude',
    'logs','log','scratch','process_manager','ambient-suggestions','memories','pets'
foreach ($name in $runtimeDirs) { Set-DropboxIgnored (Join-Path $root $name) }

$runtimeFiles = 'config.toml','auth.json','history.jsonl','session_index.jsonl',
    'models_cache.json','version.json','installation_id','cap_sid','sandbox.log',
    '.codex-global-state.json','.codex-global-state.json.bak'
foreach ($name in $runtimeFiles) { Set-DropboxIgnored (Join-Path $root $name) }

Get-ChildItem -File -Force -LiteralPath $root -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.sqlite(?:-shm|-wal)?$' } |
    ForEach-Object { Set-DropboxIgnored $_.FullName }

Test-ExpectedLink (Join-Path $localCodex 'AGENTS.md') (Join-Path $root 'AGENTS.md')
Test-ExpectedLink (Join-Path $localCodex 'orchestrator.config.toml') (Join-Path $root 'orchestrator.config.toml')
Test-ExpectedLink (Join-Path $localCodex 'skills') (Join-Path $claudeConfig 'skills')

# Remove stale Dropbox conflict and temporary copies from this small projection.
$cutoff = (Get-Date).AddHours(-1)
$junk = @(Get-ChildItem -File -Force -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object {
    ($_.Name -match 'conflicted copy' -or $_.Name -match '\.tmp(?:\.|$)') -and
    $_.LastWriteTime -lt $cutoff
})
foreach ($item in $junk) {
    Remove-Item -Force -LiteralPath $item.FullName -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $item.FullName)) { $junkRemoved++ }
}

$summary = "$(Get-Date -Format s) stamped=$stamped junk_removed=$junkRemoved links_ok=$linksOk"
$summary
if ($linksOk -ne 3) { exit 1 }
