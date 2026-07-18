# Selectively mirrors resumable Codex sessions without placing the live session
# directory in Dropbox. Only cli/vscode rollouts are eligible. The mirror uses
# immutable content objects and immutable parent-linked commit manifests.
# Windows PowerShell 5.1 compatible.
[CmdletBinding()]
param(
    [string]$CodexRoot = '',
    [string]$CodexConfigRoot = '',
    [switch]$Once,
    [switch]$Import,
    [switch]$SelfTest,
    [int]$SweepSeconds = 300,
    [int]$QuietSeconds = 5,
    [int]$RunSeconds = 0,
    [string]$ReadyPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:uploaded = 0
$script:downloaded = 0
$script:excluded = 0
$script:deferred = 0
$script:conflicts = 0
$script:errors = 0
$script:eventQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$script:operationLockPath = $null
$script:catalog = @{}

function Find-DropboxRoot {
    $candidates = New-Object Collections.Generic.List[string]
    $candidates.Add((Join-Path $env:USERPROFILE 'Dropbox'))
    $infoPath = Join-Path $env:LOCALAPPDATA 'Dropbox\info.json'
    if (Test-Path -LiteralPath $infoPath -PathType Leaf) {
        $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $info.PSObject.Properties) {
            if ($property.Value.path) { $candidates.Add([string]$property.Value.path) }
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'codex-config') -PathType Container) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Could not find a Dropbox root containing codex-config.'
}

function Test-SamePath([string]$left, [string]$right) {
    return ([IO.Path]::GetFullPath($left)).Equals(
        [IO.Path]::GetFullPath($right),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-PathInside([string]$path, [string]$root, [string]$label) {
    $fullPath = [IO.Path]::GetFullPath($path)
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) {
        throw "$label escapes its permitted root: $fullPath"
    }
}

function Assert-RealDirectory([string]$path, [string]$label) {
    $item = Get-Item -Force -LiteralPath $path -ErrorAction Stop
    if (-not $item.PSIsContainer -or (Test-RedirectingReparsePoint $item $false)) {
        throw "$label must be a real directory: $path"
    }
}

function Test-RedirectingReparsePoint([IO.FileSystemInfo]$item, [bool]$allowCloudPlaceholder) {
    $isReparse = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    if (-not $isReparse) { return $false }
    $targets = @($item.Target | Where-Object { $_ })
    if ($item.LinkType -or $targets.Count) { return $true }
    return (-not $allowCloudPlaceholder)
}

function Assert-NonRedirectingDirectory([string]$path, [string]$label, [bool]$allowCloudPlaceholder) {
    $item = Get-Item -Force -LiteralPath $path -ErrorAction Stop
    if (-not $item.PSIsContainer -or (Test-RedirectingReparsePoint $item $allowCloudPlaceholder)) {
        throw "$label must be a nonredirecting directory: $path"
    }
}

function Ensure-SafeParentDirectory([string]$path, [string]$root, [string]$label, [bool]$allowCloudPlaceholder = $false) {
    Assert-PathInside $path $root $label
    Assert-NonRedirectingDirectory $root "$label root" $allowCloudPlaceholder
    $parent = [IO.Directory]::GetParent([IO.Path]::GetFullPath($path)).FullName
    $rootPrefix = [IO.Path]::GetFullPath($root).TrimEnd('\')
    $relative = $parent.Substring($rootPrefix.Length).TrimStart('\')
    $current = $rootPrefix
    if ($relative) {
        foreach ($component in $relative.Split('\')) {
            if (-not $component -or $component -eq '.' -or $component -eq '..') {
                throw "$label contains an invalid path component."
            }
            $current = Join-Path $current $component
            if (-not (Test-Path -LiteralPath $current)) {
                $null = New-Item -ItemType Directory -Path $current
            }
            Assert-NonRedirectingDirectory $current "$label parent" $allowCloudPlaceholder
        }
    }
}

function Assert-SafeExistingParentChain([string]$path, [string]$root, [string]$label, [bool]$allowCloudPlaceholder = $false) {
    Assert-PathInside $path $root $label
    Assert-NonRedirectingDirectory $root "$label root" $allowCloudPlaceholder
    $parent = [IO.Directory]::GetParent([IO.Path]::GetFullPath($path)).FullName
    $rootPrefix = [IO.Path]::GetFullPath($root).TrimEnd('\')
    $relative = $parent.Substring($rootPrefix.Length).TrimStart('\')
    $current = $rootPrefix
    if ($relative) {
        foreach ($component in $relative.Split('\')) {
            $current = Join-Path $current $component
            if (-not (Test-Path -LiteralPath $current)) { break }
            Assert-NonRedirectingDirectory $current "$label parent" $allowCloudPlaceholder
        }
    }
}

function Get-SafeFiles([string]$root, [string]$pattern, [bool]$allowCloudPlaceholder = $false) {
    $results = New-Object Collections.Generic.List[IO.FileInfo]
    $queue = New-Object Collections.Generic.Queue[string]
    $queue.Enqueue([IO.Path]::GetFullPath($root))
    while ($queue.Count) {
        $directory = $queue.Dequeue()
        foreach ($item in Get-ChildItem -Force -LiteralPath $directory -ErrorAction Stop) {
            if ($item.PSIsContainer) {
                if (Test-RedirectingReparsePoint $item $allowCloudPlaceholder) {
                    throw "Reparse point found inside a session root: $($item.FullName)"
                }
                $queue.Enqueue($item.FullName)
            }
            elseif (Test-RedirectingReparsePoint $item $allowCloudPlaceholder) {
                throw "Reparse file found inside a session-mirror root: $($item.FullName)"
            }
            elseif ($item.Name -like $pattern) {
                $results.Add($item)
            }
        }
    }
    return @($results | ForEach-Object { $_ })
}

function Write-MirrorLog([string]$message) {
    $line = "$(Get-Date -Format s) $message"
    if ($Once -or $SelfTest) { Write-Host $line }
    $parent = [IO.Directory]::GetParent($script:logPath).FullName
    $null = New-Item -ItemType Directory -Force -Path $parent
    if (Test-Path -LiteralPath $script:logPath -PathType Leaf) {
        $info = Get-Item -LiteralPath $script:logPath
        if ($info.Length -gt 5MB) {
            [IO.File]::WriteAllText($script:logPath,"$(Get-Date -Format s) log rotated" + [Environment]::NewLine,$utf8NoBom)
        }
    }
    [IO.File]::AppendAllText($script:logPath,$line + [Environment]::NewLine,$utf8NoBom)
}

function Get-SessionIdFromFileName([string]$path) {
    $match = [Regex]::Match(
        [IO.Path]::GetFileName($path),
        '(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?=\.jsonl$)'
    )
    if ($match.Success) { return $match.Groups[1].Value.ToLowerInvariant() }
    return $null
}

function Get-CanonicalRelativePath([string]$path, [string]$root, [string]$sessionId, [string]$state) {
    $fullPath = [IO.Path]::GetFullPath($path)
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Rollout escapes its session root: $fullPath"
    }
    $relative = $fullPath.Substring($fullRoot.Length).Replace('\','/')
    $escapedId = [Regex]::Escape($sessionId)
    $pattern = if ($state -eq 'archived_sessions') {
        "^rollout-[^/]*$escapedId\.jsonl$"
    }
    else {
        "^\d{4}/\d{2}/\d{2}/rollout-[^/]*$escapedId\.jsonl$"
    }
    if ($relative -notmatch $pattern) {
        throw "Noncanonical rollout path: $relative"
    }
    return $relative
}

function Get-RolloutSource([string]$path, [string]$expectedSessionId = '') {
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
        try {
            $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,4096,$true)
            try { $line = $reader.ReadLine() }
            finally { $reader.Dispose() }
        }
        finally { $stream.Dispose() }
        if (-not $line) { return 'pending' }
        $record = $line | ConvertFrom-Json
        if ([string]$record.type -ne 'session_meta' -or -not $record.payload) { return 'ineligible' }
        if ($expectedSessionId) {
            try { $payloadId = ([guid]([string]$record.payload.id)).ToString().ToLowerInvariant() }
            catch { return 'ineligible' }
            if ($payloadId -ne $expectedSessionId.ToLowerInvariant()) { return 'ineligible' }
        }
        if ($record.payload.source -isnot [string]) { return 'ineligible' }
        $source = ([string]$record.payload.source).ToLowerInvariant()
        if ($source -eq 'cli' -or $source -eq 'vscode') { return $source }
        return 'ineligible'
    }
    catch { return 'pending' }
}

function Copy-ExactBytes([IO.Stream]$source, [IO.Stream]$destination, [int64]$count) {
    $buffer = New-Object byte[] (1MB)
    $remaining = $count
    while ($remaining -gt 0) {
        $wanted = [int][Math]::Min($buffer.Length,$remaining)
        $read = $source.Read($buffer,0,$wanted)
        if ($read -le 0) { throw 'Unexpected end of rollout while creating a snapshot.' }
        $destination.Write($buffer,0,$read)
        $remaining -= $read
    }
}

function Set-LengthToLastCompleteLine([string]$path) {
    $stream = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        if ($stream.Length -eq 0) { return [int64]0 }
        $position = $stream.Length - 1
        while ($position -ge 0) {
            $stream.Position = $position
            if ($stream.ReadByte() -eq 10) {
                $completeLength = $position + 1
                $stream.SetLength($completeLength)
                return [int64]$completeLength
            }
            $position--
        }
        $stream.SetLength(0)
        return [int64]0
    }
    finally { $stream.Dispose() }
}

function New-CompleteSnapshot($entry) {
    $null = New-Item -ItemType Directory -Force -Path $script:stagingRoot
    $temporary = Join-Path $script:stagingRoot ($entry.SessionId + '-' + [guid]::NewGuid().ToString('N') + '.jsonl')
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $source = [IO.File]::Open($entry.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
        try {
            $capturedLength = $source.Length
            $destination = [IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { Copy-ExactBytes $source $destination $capturedLength }
            finally { $destination.Dispose() }
        }
        finally { $source.Dispose() }

        $capturedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash
        $completeLength = Set-LengthToLastCompleteLine $temporary
        if ($completeLength -eq 0) {
            Remove-Item -Force -LiteralPath $temporary
            return $null
        }
        $sourceName = Get-RolloutSource $temporary $entry.SessionId
        if ($sourceName -ne 'cli' -and $sourceName -ne 'vscode') {
            Remove-Item -Force -LiteralPath $temporary
            return $null
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash
        return [pscustomobject]@{
            Path = $temporary
            Length = [int64]$completeLength
            Hash = $hash
            CapturedLength = [int64]$capturedLength
            CapturedHash = $capturedHash
            Source = $sourceName
            LastWriteUtc = (Get-Item -LiteralPath $entry.Path).LastWriteTimeUtc.ToString('o')
        }
    }
    catch {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -Force -LiteralPath $temporary -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Test-Prefix([string]$shorterPath, [string]$longerPath, [int64]$shorterLength) {
    $left = [IO.File]::Open($shorterPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $right = [IO.File]::Open($longerPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $leftBuffer = New-Object byte[] (1MB)
        $rightBuffer = New-Object byte[] (1MB)
        $remaining = $shorterLength
        while ($remaining -gt 0) {
            $wanted = [int][Math]::Min($leftBuffer.Length,$remaining)
            $leftRead = $left.Read($leftBuffer,0,$wanted)
            $rightRead = $right.Read($rightBuffer,0,$wanted)
            if ($leftRead -ne $wanted -or $rightRead -ne $wanted) { return $false }
            for ($index=0; $index -lt $wanted; $index++) {
                if ($leftBuffer[$index] -ne $rightBuffer[$index]) { return $false }
            }
            $remaining -= $wanted
        }
        return $true
    }
    finally {
        $left.Dispose()
        $right.Dispose()
    }
}

function Get-FileRelation([string]$leftPath, [int64]$leftLength, [string]$leftHash,
                          [string]$rightPath, [int64]$rightLength, [string]$rightHash) {
    if ($leftLength -eq $rightLength) {
        if ($leftHash -eq $rightHash) { return 'equal' }
        return 'divergent'
    }
    if ($leftLength -lt $rightLength) {
        if (Test-Prefix $leftPath $rightPath $leftLength) { return 'right-extends-left' }
        return 'divergent'
    }
    if (Test-Prefix $rightPath $leftPath $rightLength) { return 'left-extends-right' }
    return 'divergent'
}

function Install-VerifiedFile([string]$source, [string]$destination, [string]$hash, [int64]$length,
                              [string]$retainedBackupPath = '') {
    $parent = [IO.Directory]::GetParent($destination).FullName
    $null = New-Item -ItemType Directory -Force -Path $parent
    $temporary = Join-Path $parent ('.codex-mirror-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::Copy($source,$temporary,$false)
    try {
        $temporaryInfo = Get-Item -LiteralPath $temporary
        $temporaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash
        if ($temporaryInfo.Length -ne $length -or $temporaryHash -ne $hash) {
            throw "Staged copy verification failed: $destination"
        }
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $retainOnSuccess = -not [string]::IsNullOrWhiteSpace($retainedBackupPath)
            $backup = if ($retainOnSuccess) {
                Assert-PathInside $retainedBackupPath $script:importBackupRoot 'Import backup'
                Ensure-SafeParentDirectory $retainedBackupPath $script:importBackupRoot 'Import backup'
                if (Test-Path -LiteralPath $retainedBackupPath) {
                    throw "Import backup path already exists: $retainedBackupPath"
                }
                $retainedBackupPath
            }
            else { Join-Path $parent ('.codex-mirror-' + [guid]::NewGuid().ToString('N') + '.bak') }
            $replacementCompleted = $false
            $backupConsumed = $false
            try {
                [IO.File]::Replace($temporary,$destination,$backup,$true)
                $replacementCompleted = $true
                $finalInfo = Get-Item -LiteralPath $destination
                $finalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
                if ($finalInfo.Length -ne $length -or $finalHash -ne $hash) {
                    $failedReplacement = Join-Path $parent ('.codex-mirror-' + [guid]::NewGuid().ToString('N') + '.failed')
                    [IO.File]::Replace($backup,$destination,$failedReplacement,$true)
                    $backupConsumed = $true
                    Remove-Item -Force -LiteralPath $failedReplacement -ErrorAction SilentlyContinue
                    throw "Final copy verification failed and the prior file was restored: $destination"
                }
            }
            finally {
                if ($replacementCompleted -and -not $backupConsumed -and -not $retainOnSuccess -and
                    (Test-Path -LiteralPath $backup -PathType Leaf)) {
                    Remove-Item -Force -LiteralPath $backup -ErrorAction SilentlyContinue
                }
                elseif (Test-Path -LiteralPath $backup -PathType Leaf) {
                    Write-MirrorLog "replacement backup retained path=$backup"
                }
            }
        }
        else {
            Move-Item -LiteralPath $temporary -Destination $destination
            $finalInfo = Get-Item -LiteralPath $destination
            $finalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
            if ($finalInfo.Length -ne $length -or $finalHash -ne $hash) {
                throw "Final copy verification failed: $destination"
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -Force -LiteralPath $temporary -ErrorAction SilentlyContinue
        }
    }
}

function Write-ImmutableTextFile([string]$path, [string]$text) {
    $parent = [IO.Directory]::GetParent($path).FullName
    $null = New-Item -ItemType Directory -Force -Path $parent
    $temporary = Join-Path $parent ('.codex-mirror-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary,$text,$utf8NoBom)
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $existing = Get-Item -Force -LiteralPath $path
            if (Test-RedirectingReparsePoint $existing $true) {
                throw "Immutable file is a redirecting reparse point: $path"
            }
            $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
            $temporaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash
            if ($existingHash -ne $temporaryHash) { throw "Immutable file collision: $path" }
            return
        }
        Move-Item -LiteralPath $temporary -Destination $path
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -Force -LiteralPath $temporary -ErrorAction SilentlyContinue
        }
    }
}

function Get-RunningCodexProcesses {
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -ieq 'codex.exe' -or
            ($_.Name -ieq 'node.exe' -and $_.CommandLine -match '(?i)[\\/]@openai[\\/]codex[\\/]bin[\\/]codex\.js(?=["\s]|$)')
        })
    }
    catch { throw "Could not enumerate Codex processes safely: $($_.Exception.Message)" }
}

function Assert-NoCodexWritersForImport {
    if ($SelfTest) { return }
    $running = Get-RunningCodexProcesses
    if ($running.Count) {
        $details = ($running | ForEach-Object { "$($_.Name) PID=$($_.ProcessId)" }) -join ', '
        throw "Inbound session import requires Codex to be offline. Running: $details"
    }
}

function Test-CanImportNow {
    if (-not $Import -or -not $Once) { return $false }
    if ($SelfTest) { return $true }
    return ((Get-RunningCodexProcesses).Count -eq 0)
}

function Register-Conflict([string]$sessionId, [string]$reason, [string]$localPath, [string]$otherPath, [string]$snapshotPath = '') {
    $script:conflicts++
    $directory = Join-Path $script:conflictRoot $sessionId
    $null = New-Item -ItemType Directory -Force -Path $directory
    $preservedSnapshot = $null
    if ($snapshotPath -and (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        $snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshotPath).Hash
        $preservedSnapshot = Join-Path $directory ('local-' + $snapshotHash + '.jsonl')
        if (-not (Test-Path -LiteralPath $preservedSnapshot -PathType Leaf)) {
            [IO.File]::Copy($snapshotPath,$preservedSnapshot,$false)
        }
        $preservedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $preservedSnapshot).Hash
        if ($preservedHash -ne $snapshotHash) { throw "Conflict snapshot verification failed: $preservedSnapshot" }
    }
    $record = [ordered]@{
        session_id = $sessionId
        observed_at_utc = [DateTime]::UtcNow.ToString('o')
        reason = $reason
        local_path = $localPath
        other_path = $otherPath
        preserved_local_snapshot = $preservedSnapshot
    }
    $recordPath = Join-Path $directory ((Get-Date -Format 'yyyyMMdd-HHmmssfff') + '-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($recordPath,($record | ConvertTo-Json -Depth 4),$utf8NoBom)
    Write-MirrorLog "CONFLICT session=$sessionId reason=$reason record=$recordPath"
}

function Get-LocalEntries {
    $eligible = @{}
    $ineligible = @{}
    $conflicted = @{}
    foreach ($state in 'sessions','archived_sessions') {
        $root = Join-Path $script:codexRoot $state
        foreach ($file in Get-SafeFiles $root 'rollout-*.jsonl') {
            $sessionId = Get-SessionIdFromFileName $file.FullName
            if (-not $sessionId) {
                $script:excluded++
                continue
            }
            $relative = Get-CanonicalRelativePath $file.FullName $root $sessionId $state
            $source = Get-RolloutSource $file.FullName $sessionId
            $entry = [pscustomobject]@{
                SessionId = $sessionId
                Path = $file.FullName
                State = $state
                RelativePath = $relative
                Source = $source
            }
            if ($source -eq 'cli' -or $source -eq 'vscode') {
                if ($conflicted.ContainsKey($sessionId)) { continue }
                if ($ineligible.ContainsKey($sessionId)) {
                    Register-Conflict $sessionId 'eligible and ineligible local rollouts share one UUID' $file.FullName $ineligible[$sessionId].Path
                    $ineligible.Remove($sessionId)
                    $conflicted[$sessionId] = $true
                    continue
                }
                if ($eligible.ContainsKey($sessionId)) {
                    Register-Conflict $sessionId 'duplicate eligible local rollout paths' $file.FullName $eligible[$sessionId].Path
                    $eligible.Remove($sessionId)
                    $conflicted[$sessionId] = $true
                }
                else { $eligible[$sessionId] = $entry }
            }
            else {
                $script:excluded++
                if ($conflicted.ContainsKey($sessionId)) { continue }
                if ($eligible.ContainsKey($sessionId)) {
                    Register-Conflict $sessionId 'eligible and ineligible local rollouts share one UUID' $eligible[$sessionId].Path $file.FullName
                    $eligible.Remove($sessionId)
                    $conflicted[$sessionId] = $true
                }
                else { $ineligible[$sessionId] = $entry }
            }
        }
    }
    return [pscustomobject]@{Eligible=$eligible;Ineligible=$ineligible;Conflicted=$conflicted}
}

function Get-ObjectPath($commit) {
    $relative = [string]$commit.object_relative_path
    $match = [Regex]::Match($relative,'^(?<id>[0-9a-f-]{36})/(?<length>[0-9]+)-(?<hash>[0-9A-F]{64})\.jsonl$')
    if (-not $match.Success) {
        throw "Invalid object path in commit $($commit.commit_id): $relative"
    }
    if ($match.Groups['id'].Value -ne ([string]$commit.session_id).ToLowerInvariant() -or
        [int64]$match.Groups['length'].Value -ne [int64]$commit.length -or
        $match.Groups['hash'].Value -ne [string]$commit.sha256) {
        throw "Object path components disagree with commit metadata: $relative"
    }
    $path = Join-Path $script:objectsRoot ($relative.Replace('/','\'))
    Assert-PathInside $path $script:objectsRoot 'Commit object'
    Assert-SafeExistingParentChain $path $script:objectsRoot 'Commit object' $true
    return $path
}

function Get-RemoteState {
    $bySession = @{}
    $pendingIds = @{}
    $conflictedIds = @{}
    if (-not (Test-Path -LiteralPath $script:commitsRoot -PathType Container)) {
        return [pscustomobject]@{Tips=@{};Pending=$pendingIds;Conflicted=$conflictedIds;All=@{}}
    }
    $all = @{}
    foreach ($file in Get-SafeFiles $script:commitsRoot '*.json' $true) {
        try {
            $commit = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$commit.schema_version -ne 1) { throw 'unsupported schema' }
            $sessionId = ([guid]([string]$commit.session_id)).ToString().ToLowerInvariant()
            $commitId = ([guid]([string]$commit.commit_id)).ToString().ToLowerInvariant()
            $expectedManifest = Join-Path (Join-Path $script:commitsRoot $sessionId) ($commitId + '.json')
            if (-not (Test-SamePath $file.FullName $expectedManifest)) { throw 'manifest path does not match its session and commit IDs' }
            if ($all.ContainsKey($commitId)) { throw 'duplicate commit ID' }
            $source = ([string]$commit.source).ToLowerInvariant()
            if ($source -ne 'cli' -and $source -ne 'vscode') { throw 'ineligible source' }
            if ([string]$commit.state -ne 'sessions' -and [string]$commit.state -ne 'archived_sessions') {
                throw 'invalid state'
            }
            if ([string]$commit.sha256 -notmatch '^[0-9A-F]{64}$') { throw 'invalid SHA-256' }
            if ([int64]$commit.length -le 0) { throw 'invalid length' }
            $relativePattern = if ([string]$commit.state -eq 'archived_sessions') {
                '^rollout-[^/]+\.jsonl$'
            }
            else {
                '^\d{4}/\d{2}/\d{2}/rollout-[^/]+\.jsonl$'
            }
            if ([string]$commit.relative_path -notmatch $relativePattern) { throw 'invalid relative rollout path' }
            if ((Get-SessionIdFromFileName ([string]$commit.relative_path)) -ne $sessionId) {
                throw 'session UUID does not match the rollout filename'
            }
            $objectPath = Get-ObjectPath $commit
            if (-not (Test-Path -LiteralPath $objectPath -PathType Leaf)) { throw 'object has not arrived' }
            $objectInfo = Get-Item -LiteralPath $objectPath
            if (Test-RedirectingReparsePoint $objectInfo $true) {
                throw 'object is a reparse point'
            }
            if ($objectInfo.Length -ne [int64]$commit.length) { throw 'object length mismatch' }
            $objectHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
            if ($objectHash -ne [string]$commit.sha256) { throw 'object hash mismatch' }
            if ((Get-RolloutSource $objectPath $sessionId) -ne $source) { throw 'object source or session UUID mismatch' }
            $entry = [pscustomobject]@{
                Commit = $commit
                CommitId = $commitId
                ParentId = if ($commit.parent_commit) { ([guid]([string]$commit.parent_commit)).ToString().ToLowerInvariant() } else { $null }
                SessionId = $sessionId
                ObjectPath = $objectPath
                ManifestPath = $file.FullName
            }
            $all[$commitId] = $entry
            if (-not $bySession.ContainsKey($sessionId)) {
                $bySession[$sessionId] = New-Object Collections.Generic.List[object]
            }
            $bySession[$sessionId].Add($entry)
        }
        catch {
            $idMatch = [Regex]::Match($file.FullName,'(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
            if ($idMatch.Success) { $pendingIds[$idMatch.Value.ToLowerInvariant()] = $true }
            else { $script:errors++ }
            Write-MirrorLog "remote commit pending path=$($file.FullName) reason=$($_.Exception.Message)"
        }
    }

    $tips = @{}
    foreach ($sessionId in $bySession.Keys) {
        if ($pendingIds.ContainsKey($sessionId)) { continue }
        $entries = @($bySession[$sessionId] | ForEach-Object { $_ })
        $children = @{}
        try {
            $roots = @($entries | Where-Object { -not $_.ParentId })
            if ($roots.Count -ne 1) { throw "commit graph has $($roots.Count) roots" }
            foreach ($entry in $entries) {
                if ($entry.ParentId) {
                    if (-not $all.ContainsKey($entry.ParentId) -or $all[$entry.ParentId].SessionId -ne $sessionId) {
                        throw "missing parent $($entry.ParentId)"
                    }
                    $parent = $all[$entry.ParentId]
                    if ([string]$parent.Commit.source -ne [string]$entry.Commit.source) {
                        throw "source changes between parent $($parent.CommitId) and child $($entry.CommitId)"
                    }
                    $edgeRelation = Get-FileRelation $parent.ObjectPath ([int64]$parent.Commit.length) ([string]$parent.Commit.sha256) $entry.ObjectPath ([int64]$entry.Commit.length) ([string]$entry.Commit.sha256)
                    if ($edgeRelation -ne 'equal' -and $edgeRelation -ne 'right-extends-left') {
                        throw "child $($entry.CommitId) is not an equal or strict-prefix extension of parent $($parent.CommitId)"
                    }
                    $children[$entry.ParentId] = $true
                }
            }
            foreach ($entry in $entries) {
                $seen = @{}
                $cursor = $entry
                while ($cursor) {
                    if ($seen.ContainsKey($cursor.CommitId)) { throw "cycle detected at commit $($cursor.CommitId)" }
                    $seen[$cursor.CommitId] = $true
                    $cursor = if ($cursor.ParentId) { $all[$cursor.ParentId] } else { $null }
                }
            }
        }
        catch {
            Register-Conflict $sessionId "invalid remote commit graph: $($_.Exception.Message)" $null $null
            $conflictedIds[$sessionId] = $true
            continue
        }
        $sessionTips = @($entries | Where-Object { -not $children.ContainsKey($_.CommitId) })
        if ($sessionTips.Count -ne 1) {
            Register-Conflict $sessionId "remote commit graph has $($sessionTips.Count) tips" $null $null
            $conflictedIds[$sessionId] = $true
            continue
        }
        $tips[$sessionId] = $sessionTips[0]
    }
    if ($pendingIds.Count) {
        $script:deferred += $pendingIds.Count
        $script:errors += $pendingIds.Count
    }
    return [pscustomobject]@{Tips=$tips;Pending=$pendingIds;Conflicted=$conflictedIds;All=$all}
}

function Load-Catalog {
    $script:catalog = @{}
    if (-not (Test-Path -LiteralPath $script:catalogPath -PathType Leaf)) { return }
    $document = Get-Content -LiteralPath $script:catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$document.schema_version -ne 1) { throw 'Unsupported local session-mirror catalog.' }
    foreach ($property in $document.entries.PSObject.Properties) {
        $script:catalog[$property.Name.ToLowerInvariant()] = $property.Value
    }
}

function Save-Catalog {
    $parent = [IO.Directory]::GetParent($script:catalogPath).FullName
    $null = New-Item -ItemType Directory -Force -Path $parent
    $entries = [ordered]@{}
    foreach ($key in ($script:catalog.Keys | Sort-Object)) { $entries[$key] = $script:catalog[$key] }
    $document = [ordered]@{
        schema_version = 1
        updated_at_utc = [DateTime]::UtcNow.ToString('o')
        entries = $entries
    }
    $temporary = $script:catalogPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary,($document | ConvertTo-Json -Depth 8),$utf8NoBom)
    try {
        if (Test-Path -LiteralPath $script:catalogPath -PathType Leaf) {
            $backup = $script:catalogPath + '.' + [guid]::NewGuid().ToString('N') + '.bak'
            [IO.File]::Replace($temporary,$script:catalogPath,$backup,$true)
            Remove-Item -Force -LiteralPath $backup -ErrorAction SilentlyContinue
        }
        else { Move-Item -LiteralPath $temporary -Destination $script:catalogPath }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -Force -LiteralPath $temporary -ErrorAction SilentlyContinue
        }
    }
}

function Set-CatalogEntry([string]$sessionId, $commit, $localEntry) {
    $script:catalog[$sessionId] = [ordered]@{
        commit_id = [string]$commit.commit_id
        sha256 = [string]$commit.sha256
        length = [int64]$commit.length
        state = [string]$commit.state
        relative_path = [string]$commit.relative_path
        local_path = if ($localEntry) { [string]$localEntry.Path } else { $null }
        observed_at_utc = [DateTime]::UtcNow.ToString('o')
    }
}

function Publish-LocalSnapshot($localEntry, $snapshot, $parentEntry) {
    $objectName = "$($snapshot.Length)-$($snapshot.Hash).jsonl"
    $objectRelative = "$($localEntry.SessionId)/$objectName"
    $objectPath = Join-Path $script:objectsRoot ($objectRelative.Replace('/','\'))
    Assert-PathInside $objectPath $script:objectsRoot 'Mirror object'
    Ensure-SafeParentDirectory $objectPath $script:objectsRoot 'Mirror object' $true
    if (Test-Path -LiteralPath $objectPath -PathType Leaf) {
        $existing = Get-Item -Force -LiteralPath $objectPath
        if (Test-RedirectingReparsePoint $existing $true) {
            throw "Immutable object is a redirecting reparse point: $objectPath"
        }
        $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
        if ($existing.Length -ne $snapshot.Length -or $existingHash -ne $snapshot.Hash) {
            throw "Immutable object collision: $objectPath"
        }
    }
    else { Install-VerifiedFile $snapshot.Path $objectPath $snapshot.Hash $snapshot.Length }

    $commitId = [guid]::NewGuid().ToString().ToLowerInvariant()
    $commit = [ordered]@{
        schema_version = 1
        commit_id = $commitId
        parent_commit = if ($parentEntry) { $parentEntry.CommitId } else { $null }
        session_id = $localEntry.SessionId
        source = $snapshot.Source
        object_relative_path = $objectRelative
        sha256 = $snapshot.Hash
        length = [int64]$snapshot.Length
        state = $localEntry.State
        relative_path = $localEntry.RelativePath
        logical_last_write_utc = $snapshot.LastWriteUtc
        publisher_host = $env:COMPUTERNAME
        published_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $manifestPath = Join-Path (Join-Path $script:commitsRoot $localEntry.SessionId) ($commitId + '.json')
    Ensure-SafeParentDirectory $manifestPath $script:commitsRoot 'Mirror commit' $true
    Write-ImmutableTextFile $manifestPath ($commit | ConvertTo-Json -Depth 6)
    $script:uploaded++
    Write-MirrorLog "published session=$($localEntry.SessionId) commit=$commitId state=$($localEntry.State) bytes=$($snapshot.Length)"
    return [pscustomobject]@{
        Commit = [pscustomobject]$commit
        CommitId = $commitId
        ParentId = if ($parentEntry) { $parentEntry.CommitId } else { $null }
        SessionId = $localEntry.SessionId
        ObjectPath = $objectPath
        ManifestPath = $manifestPath
    }
}

function Get-NewImportBackupPath([string]$sessionId, [string]$label) {
    $directory = Join-Path $script:importBackupRoot $sessionId
    $name = '{0}-{1}-{2}.jsonl' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')),$label,[guid]::NewGuid().ToString('N')
    $path = Join-Path $directory $name
    Assert-PathInside $path $script:importBackupRoot 'Import backup'
    Ensure-SafeParentDirectory $path $script:importBackupRoot 'Import backup'
    return $path
}

function Assert-LocalSnapshotUnchanged($localEntry, $expectedSnapshot) {
    if (-not (Test-Path -LiteralPath $localEntry.Path -PathType Leaf)) {
        throw "Local rollout disappeared during explicit import: $($localEntry.Path)"
    }
    $fresh = New-CompleteSnapshot $localEntry
    if (-not $fresh) { throw "Local rollout became unreadable during explicit import: $($localEntry.Path)" }
    try {
        if ($fresh.Length -ne $expectedSnapshot.Length -or
            $fresh.Hash -ne $expectedSnapshot.Hash -or
            $fresh.CapturedLength -ne $expectedSnapshot.CapturedLength -or
            $fresh.CapturedHash -ne $expectedSnapshot.CapturedHash) {
            throw "Local rollout changed during explicit import: $($localEntry.Path)"
        }
    }
    finally { Remove-Item -Force -LiteralPath $fresh.Path -ErrorAction SilentlyContinue }
}

function Import-RemoteCommit($remoteEntry, $localEntry) {
    if (-not $Import -or -not $Once) {
        throw 'Inbound session import requires the explicit -Once -Import mode.'
    }
    Assert-NoCodexWritersForImport
    $commit = $remoteEntry.Commit
    $stateRoot = Join-Path $script:codexRoot ([string]$commit.state)
    $destination = Join-Path $stateRoot (([string]$commit.relative_path).Replace('/','\'))
    Assert-PathInside $destination $stateRoot 'Imported rollout'
    Ensure-SafeParentDirectory $destination $stateRoot 'Imported rollout'

    $snapshot = $null
    try {
        if ($localEntry) {
            $snapshot = New-CompleteSnapshot $localEntry
            if (-not $snapshot) { throw "Could not snapshot local rollout before import: $($localEntry.Path)" }
            $relation = Get-FileRelation $snapshot.Path $snapshot.Length $snapshot.Hash $remoteEntry.ObjectPath ([int64]$commit.length) ([string]$commit.sha256)
            if ($relation -ne 'equal' -and $relation -ne 'right-extends-left') {
                throw "Remote commit does not contain the complete local rollout prefix: $($localEntry.SessionId)"
            }
            Assert-LocalSnapshotUnchanged $localEntry $snapshot
        }

        Assert-NoCodexWritersForImport
        $replacementBackup = Get-NewImportBackupPath $remoteEntry.SessionId 'replaced'
        Install-VerifiedFile $remoteEntry.ObjectPath $destination ([string]$commit.sha256) ([int64]$commit.length) $replacementBackup
        try { (Get-Item -LiteralPath $destination).LastWriteTimeUtc = [DateTime]::Parse([string]$commit.logical_last_write_utc).ToUniversalTime() }
        catch { Write-MirrorLog "could not restore logical mtime path=$destination reason=$($_.Exception.Message)" }

        if ($localEntry -and -not (Test-SamePath $localEntry.Path $destination)) {
            Assert-LocalSnapshotUnchanged $localEntry $snapshot
            Assert-NoCodexWritersForImport
            $relocatedBackup = Get-NewImportBackupPath $remoteEntry.SessionId 'relocated'
            [IO.File]::Move($localEntry.Path,$relocatedBackup)
            Write-MirrorLog "prior local state retained path=$relocatedBackup"
        }
    }
    finally {
        if ($snapshot -and (Test-Path -LiteralPath $snapshot.Path -PathType Leaf)) {
            Remove-Item -Force -LiteralPath $snapshot.Path -ErrorAction SilentlyContinue
        }
    }
    $script:downloaded++
    Write-MirrorLog "imported session=$($remoteEntry.SessionId) commit=$($remoteEntry.CommitId) state=$($commit.state) bytes=$($commit.length)"
    return [pscustomobject]@{
        SessionId = $remoteEntry.SessionId
        Path = $destination
        State = [string]$commit.state
        RelativePath = [string]$commit.relative_path
        Source = [string]$commit.source
    }
}

function Enter-ReconciliationLock {
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            return [IO.File]::Open(
                $script:operationLockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] { Start-Sleep -Milliseconds 250 }
    }
    throw 'Timed out waiting for the cross-session session-mirror operation lock.'
}

function Invoke-Reconciliation {
    $operationLock = $null
    try {
        $operationLock = Enter-ReconciliationLock
        Load-Catalog
        $remoteState = Get-RemoteState
        $localState = Get-LocalEntries
        $ids = @($localState.Eligible.Keys + $remoteState.Tips.Keys + $script:catalog.Keys | Sort-Object -Unique)

        foreach ($sessionId in $ids) {
            if ($remoteState.Conflicted.ContainsKey($sessionId)) { continue }
            if ($remoteState.Pending.ContainsKey($sessionId)) {
                $script:deferred++
                continue
            }
            if ($localState.Conflicted.ContainsKey($sessionId)) { continue }
            $localEntry = if ($localState.Eligible.ContainsKey($sessionId)) { $localState.Eligible[$sessionId] } else { $null }
            $remoteEntry = if ($remoteState.Tips.ContainsKey($sessionId)) { $remoteState.Tips[$sessionId] } else { $null }
            if ($localState.Ineligible.ContainsKey($sessionId) -and $remoteEntry) {
                Register-Conflict $sessionId 'remote eligible commit collides with an ineligible local rollout' $localState.Ineligible[$sessionId].Path $remoteEntry.ManifestPath
                continue
            }

            if (-not $localEntry -and $remoteEntry) {
                if (-not (Test-CanImportNow)) {
                    $script:deferred++
                    continue
                }
                try {
                    $localEntry = Import-RemoteCommit $remoteEntry $null
                    Set-CatalogEntry $sessionId $remoteEntry.Commit $localEntry
                }
                catch {
                    if ($_.Exception.Message -like 'Inbound session import requires Codex to be offline*') {
                        $script:deferred++
                        Write-MirrorLog "import deferred session=$sessionId reason=$($_.Exception.Message)"
                    }
                    else { Register-Conflict $sessionId $_.Exception.Message $null $remoteEntry.ManifestPath }
                }
                continue
            }
            if ($localEntry -and -not $remoteEntry) {
                if ($script:catalog.ContainsKey($sessionId)) {
                    $script:deferred++
                    $script:errors++
                    Write-MirrorLog "remote history unavailable for cataloged session=$sessionId; refusing a new root commit"
                    continue
                }
                $snapshot = New-CompleteSnapshot $localEntry
                if (-not $snapshot) {
                    $script:deferred++
                    continue
                }
                try {
                    $remoteEntry = Publish-LocalSnapshot $localEntry $snapshot $null
                    Set-CatalogEntry $sessionId $remoteEntry.Commit $localEntry
                }
                catch { Register-Conflict $sessionId $_.Exception.Message $localEntry.Path $null }
                finally { Remove-Item -Force -LiteralPath $snapshot.Path -ErrorAction SilentlyContinue }
                continue
            }
            if (-not $localEntry -and -not $remoteEntry) {
                if ($script:catalog.ContainsKey($sessionId)) {
                    $script:deferred++
                    $script:errors++
                    Write-MirrorLog "cataloged session is absent locally and remotely session=$sessionId"
                }
                continue
            }

            $snapshot = New-CompleteSnapshot $localEntry
            if (-not $snapshot) {
                $script:deferred++
                continue
            }
            try {
                $relation = Get-FileRelation $snapshot.Path $snapshot.Length $snapshot.Hash $remoteEntry.ObjectPath ([int64]$remoteEntry.Commit.length) ([string]$remoteEntry.Commit.sha256)
                $sameState = ($localEntry.State -eq [string]$remoteEntry.Commit.state)
                $catalogEntry = if ($script:catalog.ContainsKey($sessionId)) { $script:catalog[$sessionId] } else { $null }
                $localStateChanged = $catalogEntry -and ([string]$catalogEntry.state -ne $localEntry.State)
                $localContentChanged = $catalogEntry -and (
                    [string]$catalogEntry.sha256 -ne $snapshot.Hash -or
                    [int64]$catalogEntry.length -ne $snapshot.Length
                )
                $remoteChanged = $catalogEntry -and ([string]$catalogEntry.commit_id -ne $remoteEntry.CommitId)
                $remoteStateChanged = $catalogEntry -and ([string]$catalogEntry.state -ne [string]$remoteEntry.Commit.state)

                if ($relation -eq 'divergent') {
                    Register-Conflict $sessionId 'local and remote rollouts diverge from their common byte prefix' $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path
                }
                elseif (-not $sameState -and -not $catalogEntry -and $relation -eq 'left-extends-right') {
                    Register-Conflict $sessionId 'local content advanced while remote archive state is authoritative but no local base catalog exists' $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path
                }
                elseif (-not $sameState -and $catalogEntry -and (
                    ($localStateChanged -and $remoteChanged) -or
                    ($remoteStateChanged -and $localContentChanged)
                )) {
                    Register-Conflict $sessionId 'concurrent content and archive-state changes' $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path
                }
                elseif ($relation -eq 'left-extends-right') {
                    if (-not $sameState -and $remoteStateChanged) {
                        Register-Conflict $sessionId 'remote archive-state change conflicts with local appended content' $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path
                    }
                    else {
                        $newEntry = Publish-LocalSnapshot $localEntry $snapshot $remoteEntry
                        Set-CatalogEntry $sessionId $newEntry.Commit $localEntry
                    }
                }
                elseif ($relation -eq 'right-extends-left') {
                    if (-not $sameState -and $localStateChanged) {
                        Register-Conflict $sessionId 'local archive-state change conflicts with remotely appended content' $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path
                    }
                    elseif (-not (Test-CanImportNow)) { $script:deferred++ }
                    else {
                        try {
                            $localEntry = Import-RemoteCommit $remoteEntry $localEntry
                            Set-CatalogEntry $sessionId $remoteEntry.Commit $localEntry
                        }
                        catch {
                            if ($_.Exception.Message -like 'Inbound session import requires Codex to be offline*') {
                                $script:deferred++
                                Write-MirrorLog "import deferred session=$sessionId reason=$($_.Exception.Message)"
                            }
                            else { throw }
                        }
                    }
                }
                elseif ($sameState) {
                    Set-CatalogEntry $sessionId $remoteEntry.Commit $localEntry
                }
                elseif ($catalogEntry -and $localStateChanged -and -not $remoteChanged) {
                    $newEntry = Publish-LocalSnapshot $localEntry $snapshot $remoteEntry
                    Set-CatalogEntry $sessionId $newEntry.Commit $localEntry
                }
                elseif (-not $catalogEntry -or ($remoteChanged -and -not $localStateChanged)) {
                    if (-not (Test-CanImportNow)) { $script:deferred++ }
                    else {
                        try {
                            $localEntry = Import-RemoteCommit $remoteEntry $localEntry
                            Set-CatalogEntry $sessionId $remoteEntry.Commit $localEntry
                        }
                        catch {
                            if ($_.Exception.Message -like 'Inbound session import requires Codex to be offline*') {
                                $script:deferred++
                                Write-MirrorLog "import deferred session=$sessionId reason=$($_.Exception.Message)"
                            }
                            else { throw }
                        }
                    }
                }
                else {
                    Register-Conflict $sessionId 'concurrent archive-state changes' $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path
                }
            }
            catch { Register-Conflict $sessionId $_.Exception.Message $localEntry.Path $remoteEntry.ManifestPath $snapshot.Path }
            finally { Remove-Item -Force -LiteralPath $snapshot.Path -ErrorAction SilentlyContinue }
        }
        Save-Catalog
    }
    finally {
        if ($operationLock) { $operationLock.Dispose() }
    }
}

function Get-MutexName([string]$prefix, [string]$value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value.ToLowerInvariant())) }
    finally { $sha.Dispose() }
    return 'Local\' + $prefix + '-' + ([BitConverter]::ToString($hash,0,8)).Replace('-','')
}

$watchers = New-Object Collections.Generic.List[object]
$subscriptions = New-Object Collections.Generic.List[object]
$singletonMutex = $null
try {
    if ($Import -and -not $Once) { throw 'The -Import switch requires -Once.' }
    if (-not $CodexRoot) { $CodexRoot = Join-Path $env:USERPROFILE '.codex' }
    if (-not $CodexConfigRoot) { $CodexConfigRoot = Join-Path (Find-DropboxRoot) 'codex-config' }
    $script:codexRoot = [IO.Path]::GetFullPath($CodexRoot)
    $script:codexConfigRoot = [IO.Path]::GetFullPath($CodexConfigRoot)

    if ($SelfTest) {
        $selfTestBase = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.claude-local\codex-session-mirror-selftest'))
        Assert-PathInside $script:codexRoot $selfTestBase 'Self-test Codex root'
        Assert-PathInside $script:codexConfigRoot $selfTestBase 'Self-test codex-config root'
        $localStateRoot = Join-Path $script:codexRoot '.mirror-state'
    }
    else {
        $expectedCodex = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex'))
        $expectedConfig = [IO.Path]::GetFullPath((Join-Path (Find-DropboxRoot) 'codex-config'))
        if (-not (Test-SamePath $script:codexRoot $expectedCodex)) { throw "Unexpected production Codex root: $script:codexRoot" }
        if (-not (Test-SamePath $script:codexConfigRoot $expectedConfig)) { throw "Unexpected production codex-config root: $script:codexConfigRoot" }
        $localStateRoot = Join-Path $env:LOCALAPPDATA 'CodexSessionMirror'
        if ($RunSeconds -ne 0) { throw 'RunSeconds is restricted to self-test mode.' }
    }

    Assert-RealDirectory $script:codexRoot 'Codex root'
    Assert-NonRedirectingDirectory $script:codexConfigRoot 'codex-config root' $true
    foreach ($state in 'sessions','archived_sessions') {
        $local = Join-Path $script:codexRoot $state
        $null = New-Item -ItemType Directory -Force -Path $local
        Assert-RealDirectory $local "Local $state root"
    }

    $script:mirrorRoot = Join-Path $script:codexConfigRoot 'session-mirror'
    $script:objectsRoot = Join-Path $script:mirrorRoot 'objects'
    $script:commitsRoot = Join-Path $script:mirrorRoot 'commits'
    $null = New-Item -ItemType Directory -Force -Path $script:objectsRoot
    $null = New-Item -ItemType Directory -Force -Path $script:commitsRoot
    Assert-NonRedirectingDirectory $script:mirrorRoot 'session mirror' $true
    Assert-NonRedirectingDirectory $script:objectsRoot 'session mirror objects' $true
    Assert-NonRedirectingDirectory $script:commitsRoot 'session mirror commits' $true

    $null = New-Item -ItemType Directory -Force -Path $localStateRoot
    Assert-RealDirectory $localStateRoot 'Local session-mirror state root'
    $script:stagingRoot = Join-Path $localStateRoot 'staging'
    $script:conflictRoot = Join-Path $localStateRoot 'conflicts'
    $script:importBackupRoot = Join-Path $localStateRoot 'import-backups'
    $script:catalogPath = Join-Path $localStateRoot 'catalog.json'
    $script:logPath = Join-Path $localStateRoot 'mirror.log'
    $script:operationLockPath = Join-Path $localStateRoot 'reconcile.lock'
    $null = New-Item -ItemType Directory -Force -Path $script:stagingRoot
    $null = New-Item -ItemType Directory -Force -Path $script:conflictRoot
    $null = New-Item -ItemType Directory -Force -Path $script:importBackupRoot
    Assert-RealDirectory $script:stagingRoot 'Local session-mirror staging root'
    Assert-RealDirectory $script:conflictRoot 'Local session-mirror conflict root'
    Assert-RealDirectory $script:importBackupRoot 'Local session-mirror import-backup root'

    if ($Import) { Assert-NoCodexWritersForImport }

    if ($Once) {
        Invoke-Reconciliation
        $summary = "uploaded=$($script:uploaded) downloaded=$($script:downloaded) excluded=$($script:excluded) deferred=$($script:deferred) conflicts=$($script:conflicts) errors=$($script:errors) local_roots_ok=2 mirror_roots_ok=2"
        Write-MirrorLog $summary
        if ($script:conflicts -or $script:errors) { exit 1 }
        exit 0
    }

    $singletonCreated = $false
    $singletonMutex = New-Object Threading.Mutex($false,(Get-MutexName 'CodexSessionMirrorWatcher' $script:codexRoot),[ref]$singletonCreated)
    if (-not $singletonCreated) {
        Write-MirrorLog 'session mirror watcher already running'
        exit 0
    }

    foreach ($root in @(
        (Join-Path $script:codexRoot 'sessions'),
        (Join-Path $script:codexRoot 'archived_sessions'),
        $script:objectsRoot,
        $script:commitsRoot
    )) {
        $watcher = New-Object IO.FileSystemWatcher($root,'*')
        $watcher.IncludeSubdirectories = $true
        $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size, CreationTime'
        foreach ($eventName in 'Created','Changed','Deleted','Renamed') {
            $sourceIdentifier = 'CodexSessionMirror-' + $PID + '-' + [guid]::NewGuid().ToString('N')
            $job = Register-ObjectEvent -InputObject $watcher -EventName $eventName -SourceIdentifier $sourceIdentifier -MessageData $script:eventQueue -Action {
                $event.MessageData.Enqueue([DateTime]::UtcNow)
            }
            $subscriptions.Add([pscustomobject]@{SourceIdentifier=$sourceIdentifier;JobId=$job.Id})
        }
        $errorIdentifier = 'CodexSessionMirror-' + $PID + '-' + [guid]::NewGuid().ToString('N')
        $errorJob = Register-ObjectEvent -InputObject $watcher -EventName Error -SourceIdentifier $errorIdentifier -MessageData $script:eventQueue -Action {
            $event.MessageData.Enqueue([DateTime]::MinValue)
        }
        $subscriptions.Add([pscustomobject]@{SourceIdentifier=$errorIdentifier;JobId=$errorJob.Id})
        $watcher.EnableRaisingEvents = $true
        $watchers.Add($watcher)
    }

    Invoke-Reconciliation
    if ($ReadyPath) {
        $readyParent = [IO.Directory]::GetParent([IO.Path]::GetFullPath($ReadyPath)).FullName
        $null = New-Item -ItemType Directory -Force -Path $readyParent
        [IO.File]::WriteAllText($ReadyPath,"READY pid=$PID time=$([DateTime]::UtcNow.ToString('o'))",$utf8NoBom)
    }
    Write-MirrorLog "session mirror watcher ready roots=$($script:codexRoot) mirror=$($script:mirrorRoot)"

    $nextSweep = [DateTime]::UtcNow.AddSeconds($SweepSeconds)
    $stopAt = if ($RunSeconds -gt 0) { [DateTime]::UtcNow.AddSeconds($RunSeconds) } else { $null }
    $firstEvent = $null
    $lastEvent = $null
    while (-not $stopAt -or [DateTime]::UtcNow -lt $stopAt) {
        $eventTime = [DateTime]::MinValue
        while ($script:eventQueue.TryDequeue([ref]$eventTime)) {
            if (-not $firstEvent) { $firstEvent = [DateTime]::UtcNow }
            $lastEvent = [DateTime]::UtcNow
            $eventTime = [DateTime]::MinValue
        }
        $now = [DateTime]::UtcNow
        $quietReady = $lastEvent -and (($now - $lastEvent).TotalSeconds -ge $QuietSeconds)
        $maximumDelayReached = $firstEvent -and (($now - $firstEvent).TotalSeconds -ge 60)
        if ($quietReady -or $maximumDelayReached -or $now -ge $nextSweep) {
            try { Invoke-Reconciliation }
            catch {
                $script:errors++
                Write-MirrorLog "reconciliation error=$($_.Exception.Message)"
            }
            $firstEvent = $null
            $lastEvent = $null
            $nextSweep = [DateTime]::UtcNow.AddSeconds($SweepSeconds)
        }
        Start-Sleep -Milliseconds 250
    }
    Write-MirrorLog 'session mirror self-test watcher window complete'
}
catch {
    $location = if ($_.InvocationInfo) { " line=$($_.InvocationInfo.ScriptLineNumber) command=$($_.InvocationInfo.MyCommand)" } else { '' }
    try { Write-MirrorLog "session mirror stopped error=$($_.Exception.Message)$location" } catch {}
    exit 1
}
finally {
    foreach ($subscription in $subscriptions) {
        Unregister-Event -SourceIdentifier $subscription.SourceIdentifier -ErrorAction SilentlyContinue
        Remove-Job -Id $subscription.JobId -Force -ErrorAction SilentlyContinue
    }
    foreach ($watcher in $watchers) { $watcher.Dispose() }
    if ($singletonMutex) { $singletonMutex.Dispose() }
}
