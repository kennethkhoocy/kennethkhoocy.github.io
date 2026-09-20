# Legacy filename retained for bootstrap compatibility. This script keeps both
# Codex session roots local and installs the selective immutable session mirror.
# Windows PowerShell 5.1 compatible.
[CmdletBinding()]
param(
    [string]$CodexRoot = '',
    [string]$CodexConfigRoot = '',
    [switch]$SelfTest,
    [switch]$Import,
    [switch]$SkipWatcherStart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Write-Status([string]$message) {
    Write-Output "$(Get-Date -Format s) $message"
}

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

function Get-RunningCodexProcesses {
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -ieq 'codex.exe' -or
            ($_.Name -ieq 'node.exe' -and $_.CommandLine -match '(?i)[\\/]@openai[\\/]codex[\\/]bin[\\/]codex\.js(?=["\s]|$)')
        })
    }
    catch { throw "Could not enumerate Codex processes safely: $($_.Exception.Message)" }
}

function Convert-LegacySessionJunction([string]$name) {
    $local = Join-Path $script:codexRoot $name
    $item = Get-Item -Force -LiteralPath $local -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.LinkType) { return }

    $running = Get-RunningCodexProcesses
    if ($running.Count) {
        $details = ($running | ForEach-Object { "$($_.Name) PID=$($_.ProcessId)" }) -join ', '
        throw "An old session junction requires an offline conversion. Exit Codex first. Running: $details"
    }

    $rawTarget = @($item.Target)[0]
    if (-not $rawTarget) { throw "Could not resolve legacy session junction: $local" }
    $target = if ([IO.Path]::IsPathRooted($rawTarget)) {
        [IO.Path]::GetFullPath($rawTarget)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path (Split-Path $local -Parent) $rawTarget))
    }
    $expected = Join-Path $script:codexConfigRoot $name
    if (-not (Test-SamePath $target $expected)) {
        throw "Unexpected session junction target: $local -> $target"
    }

    $stagingBase = if ($SelfTest) {
        Join-Path $env:USERPROFILE '.claude-local\codex-session-mirror-selftest\junction-conversion'
    }
    else {
        Join-Path $env:USERPROFILE '.claude-local\codex-session-mirror-junction-conversion'
    }
    $staging = Join-Path $stagingBase ($name + '-' + [guid]::NewGuid().ToString('N'))
    Assert-PathInside $staging $stagingBase 'Legacy conversion staging'
    $null = New-Item -ItemType Directory -Force -Path $staging

    try {
        if (Test-Path -LiteralPath $target -PathType Container) {
            $robocopyOutput = & robocopy.exe $target $staging /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /SL /NFL /NDL /NJH /NJS /NP
            $robocopyExit = $LASTEXITCODE
            if ($robocopyExit -ge 8) {
                throw "Robocopy failed during legacy session conversion with code $robocopyExit. $($robocopyOutput -join ' ')"
            }
            foreach ($sourceFile in Get-ChildItem -Recurse -File -Force -LiteralPath $target) {
                $relative = $sourceFile.FullName.Substring($target.TrimEnd('\').Length).TrimStart('\')
                $copyPath = Join-Path $staging $relative
                if (-not (Test-Path -LiteralPath $copyPath -PathType Leaf)) {
                    throw "Legacy conversion omitted a file: $($sourceFile.FullName)"
                }
                $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile.FullName).Hash
                $copyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $copyPath).Hash
                if ($sourceHash -ne $copyHash) {
                    throw "Legacy conversion hash mismatch: $($sourceFile.FullName)"
                }
            }
        }

        Remove-Item -Force -LiteralPath $local
        Move-Item -LiteralPath $staging -Destination $local
        Assert-RealDirectory $local "Converted $name root"
        Write-Status "converted legacy session junction to a local directory: $local"
    }
    catch {
        if (-not (Test-Path -LiteralPath $local) -and (Test-Path -LiteralPath $staging -PathType Container)) {
            Move-Item -LiteralPath $staging -Destination $local -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Stop-ExistingMirrorWatchers([string]$watcherPath) {
    $escaped = [Regex]::Escape([IO.Path]::GetFullPath($watcherPath))
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -match '^(?i)powershell(?:_ise)?\.exe$' -and
        $_.ProcessId -ne $PID -and
        $_.CommandLine -match $escaped
    })
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        Write-Status "stopped prior session-mirror watcher PID=$($process.ProcessId)"
    }
}

function Install-MirrorWatcher([string]$watcherPath) {
    if ($SelfTest -or $SkipWatcherStart) { return }
    $taskName = 'CodexSessionMirrorWatcher'
    $oldTaskName = 'CodexSessionPolicyWatcher'
    Stop-ExistingMirrorWatchers $watcherPath
    Unregister-ScheduledTask -TaskName $oldTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $oldTaskName -ErrorAction SilentlyContinue

    $argument = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $watcherPath
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $persistence = ''
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        if (-not $task.Settings.Enabled) { throw 'The watcher task is disabled after registration.' }
        Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $taskName -ErrorAction SilentlyContinue
        $persistence = 'scheduled-task'
    }
    catch {
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $null = New-Item -Path $runKey -Force
        Set-ItemProperty -LiteralPath $runKey -Name $taskName -Value ('powershell.exe ' + $argument)
        $persistence = 'HKCU-Run'
        Write-Status "watcher task registration unavailable; installed HKCU Run fallback: $($_.Exception.Message)"
    }

    $stateRoot = Join-Path $env:LOCALAPPDATA 'CodexSessionMirror'
    $null = New-Item -ItemType Directory -Force -Path $stateRoot
    $readyPath = Join-Path $stateRoot ('ready-' + [guid]::NewGuid().ToString('N') + '.txt')
    $startArgument = $argument + ' -ReadyPath "' + $readyPath + '"'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $startArgument -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddMinutes(20)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $readyPath -PathType Leaf) { break }
        $process.Refresh()
        if ($process.HasExited) { throw "Session-mirror watcher exited before readiness with code $($process.ExitCode)." }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
        throw 'Timed out waiting for the session-mirror watcher readiness signal.'
    }
    $ready = Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8
    Remove-Item -Force -LiteralPath $readyPath
    Write-Status "session-mirror watcher ready persistence=$persistence PID=$($process.Id) signal=$ready"
}

try {
    if (-not $CodexRoot) { $CodexRoot = Join-Path $env:USERPROFILE '.codex' }
    if (-not $CodexConfigRoot) { $CodexConfigRoot = Join-Path (Find-DropboxRoot) 'codex-config' }
    $script:codexRoot = [IO.Path]::GetFullPath($CodexRoot)
    $script:codexConfigRoot = [IO.Path]::GetFullPath($CodexConfigRoot)

    if ($SelfTest) {
        $selfTestBase = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.claude-local\codex-session-mirror-selftest'))
        Assert-PathInside $script:codexRoot $selfTestBase 'Self-test Codex root'
        Assert-PathInside $script:codexConfigRoot $selfTestBase 'Self-test codex-config root'
    }
    else {
        $expectedCodex = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex'))
        $expectedConfig = [IO.Path]::GetFullPath((Join-Path (Find-DropboxRoot) 'codex-config'))
        if (-not (Test-SamePath $script:codexRoot $expectedCodex)) { throw "Unexpected production Codex root: $script:codexRoot" }
        if (-not (Test-SamePath $script:codexConfigRoot $expectedConfig)) { throw "Unexpected production codex-config root: $script:codexConfigRoot" }
    }

    Assert-RealDirectory $script:codexRoot 'Codex root'
    Assert-NonRedirectingDirectory $script:codexConfigRoot 'codex-config root' $true
    foreach ($name in 'sessions','archived_sessions') {
        $path = Join-Path $script:codexRoot $name
        if (-not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path }
        Convert-LegacySessionJunction $name
        Assert-RealDirectory $path "Local $name root"
    }

    if ($Import) {
        $running = Get-RunningCodexProcesses
        if ($running.Count) {
            $details = ($running | ForEach-Object { "$($_.Name) PID=$($_.ProcessId)" }) -join ', '
            throw "Explicit inbound import requires Codex to be offline. Running: $details"
        }
    }

    $watcherPath = if ($SelfTest) {
        Join-Path $PSScriptRoot 'watch-codex-session-policy.ps1'
    }
    else {
        Join-Path $script:codexConfigRoot 'watch-codex-session-policy.ps1'
    }
    if (-not (Test-Path -LiteralPath $watcherPath -PathType Leaf)) { throw "Session-mirror script is missing: $watcherPath" }
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($watcherPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw "Session-mirror parse failure: $($parseErrors[0])" }

    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$watcherPath,'-Once')
    if ($Import) { $arguments += '-Import' }
    if ($SelfTest) {
        $arguments += @('-SelfTest','-CodexRoot',$script:codexRoot,'-CodexConfigRoot',$script:codexConfigRoot)
    }
    $mirrorOutput = & powershell.exe @arguments 2>&1
    $mirrorExit = $LASTEXITCODE
    $mirrorOutput | ForEach-Object { Write-Output ([string]$_) }
    $mirrorText = $mirrorOutput -join [Environment]::NewLine
    if ($mirrorExit -ne 0 -or $mirrorText -notmatch 'deferred=0\s+conflicts=0\s+errors=0\s+local_roots_ok=2\s+mirror_roots_ok=2') {
        throw 'Initial session-mirror reconciliation did not verify cleanly.'
    }

    Install-MirrorWatcher $watcherPath
    Write-Status 'SESSION MIRROR SETUP COMPLETE local_roots_ok=2 mirror_roots_ok=2 policy=cli,vscode'
}
catch {
    Write-Status "SESSION MIRROR SETUP INCOMPLETE: $($_.Exception.Message)"
    exit 1
}
