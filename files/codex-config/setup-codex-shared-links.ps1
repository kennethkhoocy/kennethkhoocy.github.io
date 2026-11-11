[CmdletBinding()]
param(
    [switch]$IncludeKnownProjects
)

$ErrorActionPreference = 'Stop'
$codexConfig = [IO.Path]::GetFullPath($PSScriptRoot)
$dropboxRoot = [IO.Directory]::GetParent($codexConfig).FullName
$claudeConfig = Join-Path $dropboxRoot 'claude-config'
$userRoot = [IO.Path]::GetFullPath($env:USERPROFILE)
$codexRoot = Join-Path $userRoot '.codex'
$backupRoot = Join-Path $userRoot ('.claude-local\codex-link-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$results = [Collections.Generic.List[object]]::new()

function Add-Result([string]$path, [string]$status, [string]$detail) {
    $results.Add([pscustomobject]@{ Path = $path; Status = $status; Detail = $detail })
}

function Get-LinkTargetPath([IO.FileSystemInfo]$item) {
    if (-not $item.LinkType) { return $null }
    $raw = @($item.Target)[0]
    if (-not $raw) { return $null }
    if ([IO.Path]::IsPathRooted($raw)) { return [IO.Path]::GetFullPath($raw) }
    return [IO.Path]::GetFullPath((Join-Path (Split-Path $item.FullName -Parent) $raw))
}

function Set-FileSymbolicLink(
    [string]$linkPath,
    [string]$targetPath,
    [switch]$RequireIdenticalExistingFile,
    [switch]$RelativeTarget
) {
    $linkPath = [IO.Path]::GetFullPath($linkPath)
    $targetPath = [IO.Path]::GetFullPath($targetPath)

    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        Add-Result $linkPath 'SKIP' "Target is missing: $targetPath"
        return
    }

    $backupPath = $null
    $item = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.PSIsContainer) {
            Add-Result $linkPath 'SKIP' 'A directory occupies the link path.'
            return
        }

        $resolvedTarget = Get-LinkTargetPath $item
        if ($resolvedTarget -and $resolvedTarget.Equals($targetPath, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Result $linkPath 'OK' "Already linked to $targetPath"
            return
        }

        if ($item.LinkType) {
            Add-Result $linkPath 'ERROR' "Existing link points to $resolvedTarget"
            return
        }

        if ($RequireIdenticalExistingFile) {
            $linkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $linkPath).Hash
            $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash
            if ($linkHash -ne $targetHash) {
                Add-Result $linkPath 'SKIP' 'Existing file differs from the requested link target.'
                return
            }
        }

        try {
            $null = New-Item -ItemType Directory -Force -Path $backupRoot
            $backupName = ([guid]::NewGuid().ToString('N')) + '.' + (Split-Path -Leaf $linkPath) + '.bak'
            $backupPath = Join-Path $backupRoot $backupName
            [pscustomobject]@{
                OriginalPath = $linkPath
                BackupPath = $backupPath
                OriginalSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $linkPath).Hash
                TargetPath = $targetPath
                State = 'planned'
            } | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $backupRoot 'manifest.jsonl')
            Move-Item -LiteralPath $linkPath -Destination $backupPath
        }
        catch {
            Add-Result $linkPath 'ERROR' "Could not create the recoverable backup: $($_.Exception.Message)"
            return
        }
    }

    try {
        if ($RelativeTarget) {
            Push-Location (Split-Path $linkPath -Parent)
            try {
                $commandOutput = & cmd.exe /d /c 'mklink "AGENTS.md" "CLAUDE.md"' 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($commandOutput -join [Environment]::NewLine) }
            }
            finally { Pop-Location }
            $link = Get-Item -Force -LiteralPath $linkPath
        }
        else {
            $commandLine = 'mklink "{0}" "{1}"' -f $linkPath, $targetPath
            $commandOutput = & cmd.exe /d /c $commandLine 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($commandOutput -join [Environment]::NewLine) }
            $link = Get-Item -Force -LiteralPath $linkPath
        }
        $resolvedTarget = Get-LinkTargetPath $link
        if (-not $resolvedTarget -or -not $resolvedTarget.Equals($targetPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Created link resolves to '$resolvedTarget' instead of '$targetPath'."
        }
        Add-Result $linkPath 'LINKED' (($link.Target -join ';') + $(if ($backupPath) { "; backup=$backupPath" } else { '' }))
    }
    catch {
        $failedItem = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
        if ($failedItem -and $failedItem.LinkType) { Remove-Item -Force -LiteralPath $linkPath }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $linkPath
        }
        Add-Result $linkPath 'ERROR' $_.Exception.Message
    }
}

function Ensure-SkillsLink {
    $linkPath = Join-Path $codexRoot 'skills'
    $targetPath = Join-Path $claudeConfig 'skills'
    $item = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
    if ($item) {
        $resolvedTarget = Get-LinkTargetPath $item
        if ($resolvedTarget -and $resolvedTarget.Equals([IO.Path]::GetFullPath($targetPath), [StringComparison]::OrdinalIgnoreCase)) {
            Add-Result $linkPath 'OK' "Already linked to $targetPath"
        }
        else {
            Add-Result $linkPath 'ERROR' 'Existing skills path is not the expected shared link.'
        }
        return
    }

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Add-Result $linkPath 'SKIP' "Shared skills target is missing: $targetPath"
        return
    }
    try {
        $link = New-Item -ItemType Junction -Path $linkPath -Target $targetPath -ErrorAction Stop
        Add-Result $linkPath 'LINKED' ($link.Target -join ';')
    }
    catch { Add-Result $linkPath 'ERROR' $_.Exception.Message }
}

$portableAgents = Join-Path $codexConfig 'AGENTS.md'
$portableProfile = Join-Path $codexConfig 'orchestrator.config.toml'
foreach ($requiredTarget in $portableAgents,$portableProfile,(Join-Path $claudeConfig 'skills')) {
    if (-not (Test-Path -LiteralPath $requiredTarget)) {
        throw "Required shared target is missing: $requiredTarget"
    }
}

if (Test-Path -LiteralPath $codexRoot) {
    $codexRootItem = Get-Item -Force -LiteralPath $codexRoot
    if ($codexRootItem.LinkType) {
        throw "The Codex runtime root must remain machine-local, but it is a link: $codexRoot"
    }
}
else { $null = New-Item -ItemType Directory -Force -Path $codexRoot }

foreach ($pair in @(
    @((Join-Path $codexRoot 'AGENTS.md'),$portableAgents),
    @((Join-Path $codexRoot 'orchestrator.config.toml'),$portableProfile)
)) {
    $livePath = $pair[0]
    $targetPath = $pair[1]
    if (Test-Path -LiteralPath $livePath -PathType Leaf) {
        $liveItem = Get-Item -Force -LiteralPath $livePath
        if (-not $liveItem.LinkType) {
            $liveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $livePath).Hash
            $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash
            if ($liveHash -ne $targetHash) {
                throw "Existing global file differs from its portable target: $livePath"
            }
        }
    }
}

Set-FileSymbolicLink `
    -linkPath (Join-Path $codexRoot 'AGENTS.md') `
    -targetPath $portableAgents `
    -RequireIdenticalExistingFile
Set-FileSymbolicLink `
    -linkPath (Join-Path $codexRoot 'orchestrator.config.toml') `
    -targetPath $portableProfile `
    -RequireIdenticalExistingFile
Ensure-SkillsLink

if ($IncludeKnownProjects) {
    $projectRoots = @(
        "$dropboxRoot\Apps\Overleaf\The Price of Delaware Corporate Law Reform",
        "$dropboxRoot\Apps\Overleaf\US-China Decoupling and Board Composition",
        "$dropboxRoot\Apps\Overleaf\Visual saliency and investment decisions",
        "$dropboxRoot\NUS Work\Admin\AsLEA2026",
        "$dropboxRoot\NUS Work\Research\2. Review\Reflective Loss",
        "$dropboxRoot\NUS Work\Research\2. Review\Reflective Loss\Drafts\manuscript-editing-template",
        "$dropboxRoot\NUS Work\Research\2. Review\Research on Collective Action Problems\2. EBOR Proofs",
        "$dropboxRoot\NUS Work\Research\2. Review\Shareholder ES Proposals",
        "$dropboxRoot\NUS Work\Research\2. Review\Shareholder ES Proposals\replication",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\Common Ownership around the World",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\Sandro_Project",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\Specialist Directors China",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\Specialist Directors US",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\US Foreign Ownership",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\Visual Saliency",
        "$dropboxRoot\NUS Work\Research\7. To Read\GCGC",
        "$dropboxRoot\NUS Work\Research\7. To Read\NUS_SMU_Talk",
        "$dropboxRoot\NUS Work\Research\manuscript-editing-template-libre",
        "$dropboxRoot\NUS Work\Research\Test\manuscript-editing-template-libre",
        "$dropboxRoot\NUS Work\Teaching Corp Fin",
        "$dropboxRoot\NUS Work\Teaching_Canvas",
        "$dropboxRoot\NUS Work\Teaching_Canvas\LL4489VLL5489VLLJ5489VLL6489V_Corporate_Law_and_Economics_2520",
        "$dropboxRoot\Research_Dashboard",
        "$userRoot\NUS Dropbox\Chian Yian Kenneth Khoo\1. Specialist directors",
        "$dropboxRoot\Apps\Overleaf\Controlling Shareholders",
        "$dropboxRoot\NUS Work\Research\3. Work in Progress\Foreign Ownership China",
        "$userRoot\SGX"
    )

    foreach ($root in $projectRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            Add-Result $root 'SKIP' 'Project root is unavailable on this machine.'
            continue
        }
        Set-FileSymbolicLink `
            -linkPath (Join-Path $root 'AGENTS.md') `
            -targetPath (Join-Path $root 'CLAUDE.md') `
            -RequireIdenticalExistingFile `
            -RelativeTarget
    }
}

$results | Format-Table -AutoSize -Wrap
if ($results.Status -contains 'ERROR') { exit 1 }
