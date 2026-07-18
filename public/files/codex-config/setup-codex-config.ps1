# One-shot per-machine bootstrap for the selective Dropbox Codex projection.
# Windows PowerShell 5.1 compatible. Safe to re-run.
[CmdletBinding()]
param([switch]$Client)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$assetBase = 'https://kennethkhoocy.github.io/files/codex-config'
$hostName = $env:COMPUTERNAME
$mode = if ($Client) { 'client' } else { 'always-on' }
$bootstrapTemp = Join-Path ([IO.Path]::GetTempPath()) ('codex-config-bootstrap-' + [guid]::NewGuid().ToString('N'))
$backupRoot = Join-Path $env:USERPROFILE ('.claude-local\codex-link-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:codexConfigBackupInitialized = $false
$script:codexConfigOriginallyExisted = $false
$script:codexConfigBackup = $null
$script:codexConfigTouched = $false

function Find-DropboxRoot {
    $candidates = New-Object Collections.Generic.List[string]
    $candidates.Add((Join-Path $env:USERPROFILE 'Dropbox'))
    $infoPath = Join-Path $env:LOCALAPPDATA 'Dropbox\info.json'
    if (Test-Path -LiteralPath $infoPath -PathType Leaf) {
        try {
            $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in $info.PSObject.Properties) {
                if ($property.Value.path) { $candidates.Add([string]$property.Value.path) }
            }
        }
        catch { Write-Warning "Could not parse Dropbox info.json: $($_.Exception.Message)" }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'claude-config\skills') -PathType Container) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Could not find a Dropbox root containing claude-config\skills.'
}

function Get-LinkTargetPath([IO.FileSystemInfo]$item) {
    if (-not $item.LinkType) { return $null }
    $raw = @($item.Target)[0]
    if (-not $raw) { return $null }
    if ([IO.Path]::IsPathRooted($raw)) { return [IO.Path]::GetFullPath($raw) }
    $parent = [IO.Directory]::GetParent($item.FullName).FullName
    return [IO.Path]::GetFullPath((Join-Path $parent $raw))
}

function Test-SamePath([string]$left, [string]$right) {
    return ([IO.Path]::GetFullPath($left)).Equals(
        [IO.Path]::GetFullPath($right),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Ensure-LocalCodexConfig {
    $configPath = Join-Path $script:codexRoot 'config.toml'
    $item = Get-Item -Force -LiteralPath $configPath -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.LinkType) { return }
    if ($item.PSIsContainer) { throw "Codex config path is a directory link: $configPath" }

    $target = Get-LinkTargetPath $item
    $backupPath = Get-BackupPath $configPath
    $temporary = Join-Path $script:codexRoot ('config.toml.desymlink.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $bytes = [IO.File]::ReadAllBytes($configPath)
        [IO.File]::WriteAllBytes($temporary,$bytes)
        Copy-Item -LiteralPath $configPath -Destination $backupPath
        Remove-Item -Force -LiteralPath $configPath
        Move-Item -LiteralPath $temporary -Destination $configPath
        $localItem = Get-Item -Force -LiteralPath $configPath
        if ($localItem.LinkType) { throw "Codex config is still linked after de-symlinking: $configPath" }
        Write-Host "de-symlinked Codex config to a local file; prior target=$target backup=$backupPath"
    }
    catch {
        if (-not (Test-Path -LiteralPath $configPath) -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Copy-Item -LiteralPath $backupPath -Destination $configPath
        }
        throw "Could not de-symlink Codex config safely: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -Force -LiteralPath $temporary -ErrorAction SilentlyContinue
        }
    }
}

function Assert-LocalRuntimeState {
    $criticalNames = '.sandbox','.sandbox-bin','.sandbox-secrets','.tmp','tmp',
        'cache','sessions','archived_sessions','sqlite','plugins','vendor_imports',
        'claude','logs','log','scratch','process_manager','ambient-suggestions',
        'memories','pets','auth.json','history.jsonl','session_index.jsonl',
        'models_cache.json','version.json','installation_id','cap_sid','sandbox.log',
        '.codex-global-state.json','.codex-global-state.json.bak'
    $criticalPaths = @($criticalNames | ForEach-Object { Join-Path $script:codexRoot $_ })
    $criticalPaths += @(Get-ChildItem -Force -LiteralPath $script:codexRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.sqlite(?:-shm|-wal)?$' } |
        Select-Object -ExpandProperty FullName)
    foreach ($path in $criticalPaths) {
        $item = Get-Item -Force -LiteralPath $path -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType) {
            throw "Process-owned Codex runtime state must remain local, but this path is linked: $path"
        }
    }
    Write-Host 'Codex runtime-state locality OK'
}

function Get-BackupPath([string]$sourcePath) {
    $null = New-Item -ItemType Directory -Force -Path $backupRoot
    $leaf = Split-Path -Leaf $sourcePath
    return Join-Path $backupRoot (([guid]::NewGuid().ToString('N')) + '.' + $leaf + '.bak')
}

function Ensure-FileLink([string]$linkPath, [string]$targetPath) {
    $linkPath = [IO.Path]::GetFullPath($linkPath)
    $targetPath = [IO.Path]::GetFullPath($targetPath)
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Required link target is missing: $targetPath"
    }

    $backupPath = $null
    $item = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.PSIsContainer) { throw "A directory occupies the file-link path: $linkPath" }
        $actual = Get-LinkTargetPath $item
        if ($actual -and (Test-SamePath $actual $targetPath)) {
            Write-Host "link OK: $linkPath -> $targetPath"
            return
        }
        if ($item.LinkType) { throw "Unexpected existing link: $linkPath -> $actual" }
        $backupPath = Get-BackupPath $linkPath
        Move-Item -LiteralPath $linkPath -Destination $backupPath
        Write-Host "preserved existing file: $backupPath"
    }

    try {
        $commandLine = 'mklink "{0}" "{1}"' -f $linkPath,$targetPath
        $output = & cmd.exe /d /c $commandLine 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
        $created = Get-Item -Force -LiteralPath $linkPath
        $actual = Get-LinkTargetPath $created
        if (-not $actual -or -not (Test-SamePath $actual $targetPath)) {
            throw "Created link resolves to '$actual'."
        }
        Write-Host "linked: $linkPath -> $targetPath"
    }
    catch {
        $failed = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
        if ($failed -and $failed.LinkType) { Remove-Item -Force -LiteralPath $linkPath }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $linkPath
        }
        throw "Could not create file symlink '$linkPath'. Enable Windows Developer Mode or rerun elevated. $($_.Exception.Message)"
    }
}

function Ensure-SkillsJunction([string]$linkPath, [string]$targetPath) {
    $linkPath = [IO.Path]::GetFullPath($linkPath)
    $targetPath = [IO.Path]::GetFullPath($targetPath)
    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        throw "Shared skills directory is missing: $targetPath"
    }

    $backupPath = $null
    $item = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
    if ($item) {
        $actual = Get-LinkTargetPath $item
        if ($actual -and (Test-SamePath $actual $targetPath)) {
            Write-Host "link OK: $linkPath -> $targetPath"
            return
        }
        if ($item.LinkType) { throw "Unexpected existing skills link: $linkPath -> $actual" }
        if (-not $item.PSIsContainer) { throw "A file occupies the skills-link path: $linkPath" }
        $backupPath = Get-BackupPath $linkPath
        Move-Item -LiteralPath $linkPath -Destination $backupPath
        Write-Host "preserved existing skills directory: $backupPath"
    }

    try {
        $null = New-Item -ItemType Junction -Path $linkPath -Target $targetPath -ErrorAction Stop
        $created = Get-Item -Force -LiteralPath $linkPath
        $actual = Get-LinkTargetPath $created
        if (-not $actual -or -not (Test-SamePath $actual $targetPath)) {
            throw "Created skills junction resolves to '$actual'."
        }
        Write-Host "linked: $linkPath -> $targetPath"
    }
    catch {
        $failed = Get-Item -Force -LiteralPath $linkPath -ErrorAction SilentlyContinue
        if ($failed -and $failed.LinkType) { Remove-Item -Force -LiteralPath $linkPath }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $linkPath
        }
        throw "Could not create the shared-skills junction: $($_.Exception.Message)"
    }
}

function Ensure-Asset([string]$name, [switch]$Refresh) {
    $destination = Join-Path $script:codexConfig $name
    if (-not $Refresh -and (Test-Path -LiteralPath $destination -PathType Leaf)) {
        try {
            if ((Get-Item -LiteralPath $destination).Length -gt 0) {
                Write-Host "synced asset kept: $name"
                return
            }
        }
        catch { Write-Warning "Existing asset is unreadable and will be refreshed: $name" }
    }

    $temporary = Join-Path $bootstrapTemp $name
    $parent = [IO.Directory]::GetParent($temporary).FullName
    $null = New-Item -ItemType Directory -Force -Path $parent
    Invoke-WebRequest -UseBasicParsing -Uri "$assetBase/$name" -OutFile $temporary
    if (-not (Test-Path -LiteralPath $temporary -PathType Leaf) -or (Get-Item -LiteralPath $temporary).Length -eq 0) {
        throw "Downloaded asset is empty: $name"
    }
    Move-Item -Force -LiteralPath $temporary -Destination $destination
    Write-Host "asset written: $name"
}

function Assert-PortableAssets {
    $agentsPath = Join-Path $script:codexConfig 'AGENTS.md'
    $agentsText = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
    foreach ($marker in '# Codex Orchestrator Defaults','# Shared Claude Configuration Boundary','# Claude Audit Modes') {
        if ($agentsText -notmatch [Regex]::Escape($marker)) {
            throw "Portable AGENTS.md lacks required marker: $marker"
        }
    }

    $profilePath = Join-Path $script:codexConfig 'orchestrator.config.toml'
    $profileText = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
    $firstSection = [Regex]::Match($profileText,'(?m)^\[')
    $topLevel = if ($firstSection.Success) { $profileText.Substring(0,$firstSection.Index) } else { $profileText }
    foreach ($pattern in '(?m)^model[ \t]*=[ \t]*"gpt-5\.6-sol"[ \t]*$',
        '(?m)^model_reasoning_effort[ \t]*=[ \t]*"ultra"[ \t]*$') {
        if ($topLevel -notmatch $pattern) { throw "Portable orchestrator profile failed top-level validation: $pattern" }
    }
    $features = [Regex]::Match($profileText,'(?ms)^\[features\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)')
    if (-not $features.Success -or $features.Groups['body'].Value -notmatch '(?m)^multi_agent[ \t]*=[ \t]*true[ \t]*$') {
        throw 'Portable orchestrator profile does not enable multi_agent inside [features].'
    }
    $agents = [Regex]::Match($profileText,'(?ms)^\[agents\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)')
    if (-not $agents.Success -or
        $agents.Groups['body'].Value -notmatch '(?m)^max_threads[ \t]*=[ \t]*12[ \t]*$' -or
        $agents.Groups['body'].Value -notmatch '(?m)^max_depth[ \t]*=[ \t]*1[ \t]*$') {
        throw 'Portable orchestrator profile lacks max_threads=12 or max_depth=1 inside [agents].'
    }

    $manifestPath = Join-Path $script:codexConfig 'codex-plugin-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema_version -ne 1) { throw 'Unsupported or missing plugin-manifest schema_version.' }
    $ponytail = @($manifest.plugins | Where-Object {
        $_.marketplace -eq 'ponytail' -and
        $_.source -eq 'DietrichGebert/ponytail' -and
        $_.ref -eq 'main' -and
        $_.plugin -eq 'ponytail@ponytail'
    })
    if ($ponytail.Count -ne 1) { throw 'Plugin manifest lacks the required Ponytail GitHub entry.' }

    foreach ($scriptName in 'codex-config-maintenance.ps1','setup-codex-shared-links.ps1') {
        $scriptPath = Join-Path $script:codexConfig $scriptName
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
        if ($parseErrors.Count) { throw "PowerShell parse failure in ${scriptName}: $($parseErrors[0])" }
    }
    Write-Host 'portable asset validation OK'
}

function Invoke-CodexJson([string[]]$arguments) {
    $output = & codex @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "codex $($arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Normalize-GitHubRepository([string]$source) {
    $normalized = $source.Trim().ToLowerInvariant().Replace('\','/')
    $normalized = $normalized -replace '^git@github\.com:',''
    $normalized = $normalized -replace '^https?://github\.com/',''
    $normalized = $normalized.TrimEnd('/')
    $normalized = $normalized -replace '\.git$',''
    return $normalized
}

function Get-MarketplaceInstallMetadata($marketplace) {
    $metadataPath = Join-Path ([string]$marketplace.root) '.codex-marketplace-install.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Marketplace install metadata is missing: $metadataPath"
    }
    return (Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Initialize-CodexConfigBackup {
    if ($script:codexConfigBackupInitialized) { return }
    $script:codexConfigBackupInitialized = $true
    $configPath = Join-Path $script:codexRoot 'config.toml'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $null = New-Item -ItemType Directory -Force -Path $backupRoot
        $script:codexConfigBackup = Join-Path $backupRoot 'config.toml.pre-bootstrap'
        Copy-Item -LiteralPath $configPath -Destination $script:codexConfigBackup
        $script:codexConfigOriginallyExisted = $true
        Write-Host "preserved Codex config: $($script:codexConfigBackup)"
    }
}

function Restore-CodexConfigOnFailure {
    if (-not $script:codexConfigTouched) { return }
    $configPath = Join-Path $script:codexRoot 'config.toml'
    if ($script:codexConfigOriginallyExisted -and (Test-Path -LiteralPath $script:codexConfigBackup -PathType Leaf)) {
        Copy-Item -Force -LiteralPath $script:codexConfigBackup -Destination $configPath
        Write-Host "restored Codex config after bootstrap failure: $configPath"
    }
    elseif (Test-Path -LiteralPath $configPath -PathType Leaf) {
        Remove-Item -Force -LiteralPath $configPath
        Write-Host 'removed Codex config created by the failed bootstrap'
    }
}

function Set-PluginEnabledInConfig([string]$pluginId, [bool]$enabled) {
    Initialize-CodexConfigBackup
    $configPath = Join-Path $script:codexRoot 'config.toml'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $text = [IO.File]::ReadAllText($configPath)
    }
    else { $text = '' }

    $escapedId = [Regex]::Escape($pluginId)
    $sectionPattern = '(?ms)^\[plugins\."' + $escapedId + '"\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)'
    $match = [Regex]::Match($text,$sectionPattern)
    $value = if ($enabled) { 'true' } else { 'false' }
    if ($match.Success) {
        $section = $match.Value
        if ($section -match '(?m)^enabled[ \t]*=') {
            $replacement = [Regex]::Replace($section,'(?m)^enabled[ \t]*=.*$',"enabled = $value")
        }
        else { $replacement = $section.TrimEnd() + [Environment]::NewLine + "enabled = $value" + [Environment]::NewLine + [Environment]::NewLine }
        $text = $text.Substring(0,$match.Index) + $replacement + $text.Substring($match.Index + $match.Length)
    }
    else {
        if ($text.Length -gt 0 -and -not $text.EndsWith([Environment]::NewLine)) { $text += [Environment]::NewLine }
        $text += [Environment]::NewLine + '[plugins."' + $pluginId + '"]' + [Environment]::NewLine + "enabled = $value" + [Environment]::NewLine
    }
    $temporaryConfig = Join-Path $script:codexRoot ('config.toml.codex-bootstrap.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryConfig,$text,$utf8NoBom)
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            [IO.File]::Replace($temporaryConfig,$configPath,$null)
        }
        else { Move-Item -LiteralPath $temporaryConfig -Destination $configPath }
        $script:codexConfigTouched = $true
    }
    finally {
        if (Test-Path -LiteralPath $temporaryConfig -PathType Leaf) {
            Remove-Item -Force -LiteralPath $temporaryConfig -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Codex plugin policy: $pluginId enabled=$value"
}

function Install-NativePlugins {
    $manifestPath = Join-Path $script:codexConfig 'codex-plugin-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $manifest.plugins) {
        $marketplaces = Invoke-CodexJson @('plugin','marketplace','list','--json')
        $marketplace = @($marketplaces.marketplaces | Where-Object name -eq $entry.marketplace)[0]
        if ($marketplace) {
            $actualSource = [string]$marketplace.marketplaceSource.source
            if ((Normalize-GitHubRepository $actualSource) -ne (Normalize-GitHubRepository ([string]$entry.source))) {
                throw "Marketplace '$($entry.marketplace)' points to unexpected source: $actualSource"
            }
            $metadata = Get-MarketplaceInstallMetadata $marketplace
            if ([string]$metadata.ref_name -ne [string]$entry.ref) {
                $null = Invoke-CodexJson @('plugin','marketplace','remove',[string]$entry.marketplace,'--json')
                $null = Invoke-CodexJson @('plugin','marketplace','add',[string]$entry.source,'--ref',[string]$entry.ref,'--json')
                Write-Host "Git marketplace ref repaired: $($entry.marketplace) -> $($entry.ref)"
            }
            else {
                $null = Invoke-CodexJson @('plugin','marketplace','upgrade',[string]$entry.marketplace,'--json')
                Write-Host "Git marketplace refreshed: $($entry.marketplace)"
            }
        }
        else {
            $null = Invoke-CodexJson @('plugin','marketplace','add',[string]$entry.source,'--ref',[string]$entry.ref,'--json')
            Write-Host "Git marketplace added: $($entry.source)@$($entry.ref)"
        }

        $marketplaces = Invoke-CodexJson @('plugin','marketplace','list','--json')
        $marketplace = @($marketplaces.marketplaces | Where-Object name -eq $entry.marketplace)[0]
        if (-not $marketplace) { throw "Marketplace verification failed: $($entry.marketplace)" }
        $metadata = Get-MarketplaceInstallMetadata $marketplace
        if ((Normalize-GitHubRepository ([string]$metadata.source)) -ne (Normalize-GitHubRepository ([string]$entry.source)) -or
            [string]$metadata.ref_name -ne [string]$entry.ref) {
            throw "Marketplace source/ref verification failed: $($entry.marketplace)"
        }

        $plugins = Invoke-CodexJson @('plugin','list','--available','--json')
        $plugin = @($plugins.installed | Where-Object pluginId -eq $entry.plugin)[0]
        if (-not $plugin) {
            $null = Invoke-CodexJson @('plugin','add',[string]$entry.plugin,'--json')
            Write-Host "native Codex plugin installed: $($entry.plugin)"
        }
        Set-PluginEnabledInConfig ([string]$entry.plugin) $true
        $verified = Invoke-CodexJson @('plugin','list','--json')
        $installed = @($verified.installed | Where-Object pluginId -eq $entry.plugin)[0]
        if (-not $installed -or -not $installed.installed -or -not $installed.enabled) {
            throw "Native plugin verification failed: $($entry.plugin)"
        }
        if ((Normalize-GitHubRepository ([string]$installed.source.url)) -ne (Normalize-GitHubRepository ([string]$entry.source))) {
            throw "Native plugin source verification failed: $($entry.plugin)"
        }
        if ([string]$installed.source.ref -ne [string]$entry.ref) {
            throw "Native plugin ref verification failed: $($entry.plugin) expected=$($entry.ref) actual=$($installed.source.ref)"
        }
        Write-Host "plugin OK: $($entry.plugin) version=$($installed.version) source=$($installed.source.url)"
    }
}

function Remove-BootstrapTask([string]$taskName) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "removed scheduled task: $taskName"
    }
}

function Set-MaintenanceTask([string]$maintenancePath) {
    $taskNames = @('CodexConfigMaintenance','CodexConfigMaintenanceLogon')
    if ($Client) {
        foreach ($taskName in $taskNames) { Remove-BootstrapTask $taskName }
        foreach ($taskName in $taskNames) {
            if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
                throw "Client mode could not remove scheduled task: $taskName"
            }
        }
        Write-Host 'client mode: no recurring Codex maintenance task registered'
        return
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $argument = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $maintenancePath
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
        $daily = New-ScheduledTaskTrigger -Daily -At 6am
        $daily.Repetition = (New-ScheduledTaskTrigger -Once -At 6am -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Hours 24)).Repetition
        $logon = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType S4U -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        Register-ScheduledTask -TaskName 'CodexConfigMaintenance' -Action $action -Trigger $daily,$logon -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Could not register the S4U maintenance task. Rerun from an elevated PowerShell. $($_.Exception.Message)"
    }

    $task = Get-ScheduledTask -TaskName 'CodexConfigMaintenance' -ErrorAction SilentlyContinue
    if (-not $task) { throw 'Scheduled-task verification failed for CodexConfigMaintenance.' }
    $taskAction = @($task.Actions)[0]
    if (-not $taskAction -or $taskAction.Execute -notmatch '(?i)powershell(?:\.exe)?$' -or
        $taskAction.Arguments -notlike "*$maintenancePath*") {
        throw 'Scheduled-task action does not run the expected maintenance script.'
    }
    if ([string]$task.Principal.LogonType -ne 'S4U') {
        throw "Scheduled-task principal is not S4U: $($task.Principal.LogonType)"
    }
    $repeatTrigger = @($task.Triggers | Where-Object { [string]$_.Repetition.Interval -eq 'PT6H' })
    $logonTrigger = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
    if (-not $repeatTrigger -or -not $logonTrigger) {
        throw 'Scheduled task lacks the required six-hour or at-logon trigger.'
    }
    if (-not $task.Settings.StartWhenAvailable -or $task.Settings.DisallowStartIfOnBatteries -or
        $task.Settings.StopIfGoingOnBatteries -or -not $task.Settings.Enabled) {
        throw 'Scheduled-task settings failed start-when-available, battery, or enabled-state verification.'
    }
    Remove-BootstrapTask 'CodexConfigMaintenanceLogon'
    Write-Host 'scheduled task registered: CodexConfigMaintenance (S4U, 6-hourly, at logon, start when available)'
}

function Update-HostRecord([string]$readmePath) {
    $date = Get-Date -Format 'yyyy-MM-dd'
    $record = "- $hostName - $date - $mode"
    $text = [IO.File]::ReadAllText($readmePath)
    if ($text -notmatch '(?m)^## Bootstrap records\s*$') {
        $text = $text.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + '## Bootstrap records' + [Environment]::NewLine + [Environment]::NewLine
    }
    $pattern = '(?m)^- ' + [Regex]::Escape($hostName) + ' .*$'
    if ([Regex]::IsMatch($text,$pattern)) { $text = [Regex]::Replace($text,$pattern,$record) }
    else { $text = $text.TrimEnd() + [Environment]::NewLine + $record + [Environment]::NewLine }
    [IO.File]::WriteAllText($readmePath,$text,$utf8NoBom)
    Write-Host "README host record updated: $hostName ($mode)"
}

try {
    $null = New-Item -ItemType Directory -Force -Path $bootstrapTemp
    $dropboxRoot = Find-DropboxRoot
    $claudeConfig = Join-Path $dropboxRoot 'claude-config'
    $script:codexConfig = Join-Path $dropboxRoot 'codex-config'
    $script:codexRoot = Join-Path $env:USERPROFILE '.codex'
    $claudeGlobal = Join-Path $claudeConfig 'CLAUDE.md'
    $claudeSkills = Join-Path $claudeConfig 'skills'

    if (-not (Test-Path -LiteralPath $claudeGlobal -PathType Leaf)) { throw "Global CLAUDE.md is missing: $claudeGlobal" }
    $claudeHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $claudeGlobal).Hash

    if (Test-Path -LiteralPath $script:codexRoot) {
        $codexRootItem = Get-Item -Force -LiteralPath $script:codexRoot
        if ($codexRootItem.LinkType) { throw "The live .codex root must be machine-local, but it is a link: $($script:codexRoot)" }
    }
    else { $null = New-Item -ItemType Directory -Force -Path $script:codexRoot }
    Ensure-LocalCodexConfig
    Assert-LocalRuntimeState
    $null = New-Item -ItemType Directory -Force -Path $script:codexConfig

    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codexCommand) { throw 'Required CLI is missing from PATH: codex' }
    Write-Host "CLI OK: codex -> $($codexCommand.Source)"
    foreach ($commandName in 'gh','firecrawl') {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if (-not $command) { throw "Required CLI is missing from PATH: $commandName" }
        Write-Host "CLI OK: $commandName -> $($command.Source)"
    }

    foreach ($name in 'AGENTS.md','orchestrator.config.toml','codex-plugin-manifest.json','DROPBOX-IGNORE-README.md') {
        Ensure-Asset $name
    }
    foreach ($name in 'codex-config-maintenance.ps1','setup-codex-shared-links.ps1') {
        Ensure-Asset $name -Refresh
    }
    Assert-PortableAssets

    Ensure-FileLink (Join-Path $script:codexRoot 'AGENTS.md') (Join-Path $script:codexConfig 'AGENTS.md')
    Ensure-FileLink (Join-Path $script:codexRoot 'orchestrator.config.toml') (Join-Path $script:codexConfig 'orchestrator.config.toml')
    Ensure-SkillsJunction (Join-Path $script:codexRoot 'skills') $claudeSkills

    $profileProbe = & codex --profile orchestrator debug prompt-input 2>&1
    $profileProbeExit = $LASTEXITCODE
    $profileProbeText = $profileProbe -join [Environment]::NewLine
    if ($profileProbeExit -ne 0 -or $profileProbeText -notmatch '# Codex Orchestrator Defaults') {
        throw "The orchestrator profile did not load the portable AGENTS.md marker. $profileProbeText"
    }
    Write-Host 'orchestrator profile load OK: gpt-5.6-sol ultra'

    $linkHelper = Join-Path $script:codexConfig 'setup-codex-shared-links.ps1'
    $helperOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $linkHelper -IncludeKnownProjects 2>&1
    $helperExit = $LASTEXITCODE
    $helperOutput | ForEach-Object { Write-Host $_ }
    if ($helperExit -ne 0) { throw 'Project-link helper reported an error.' }

    Set-PluginEnabledInConfig 'github@openai-curated' $false
    $prePluginState = Invoke-CodexJson @('plugin','list','--json')
    foreach ($cliPlugin in @($prePluginState.installed | Where-Object { $_.pluginId -match '^(github|firecrawl)@' })) {
        Set-PluginEnabledInConfig ([string]$cliPlugin.pluginId) $false
    }
    Install-NativePlugins
    $postPluginState = Invoke-CodexJson @('plugin','list','--json')
    $enabledCliPlugin = @($postPluginState.installed | Where-Object {
        $_.pluginId -match '^(github|firecrawl)@' -and $_.enabled
    })
    if ($enabledCliPlugin) {
        throw "A CLI-only integration remains enabled as a Codex plugin: $($enabledCliPlugin.pluginId -join ', ')"
    }
    Write-Host 'CLI-only plugin policy verified: GitHub and Firecrawl connectors disabled'

    $maintenancePath = Join-Path $script:codexConfig 'codex-config-maintenance.ps1'
    $maintenanceOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $maintenancePath 2>&1
    $maintenanceExit = $LASTEXITCODE
    $maintenanceOutput | ForEach-Object { Write-Host $_ }
    if ($maintenanceExit -ne 0) { throw "Maintenance script exited $maintenanceExit." }
    $summaryLines = @($maintenanceOutput | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
    $summaryLine = if ($summaryLines.Count) { $summaryLines[-1].Trim() } else { '' }
    if ($summaryLine -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\s+stamped=\d+\s+junk_removed=\d+\s+links_ok=3$') {
        throw "Maintenance verification did not report an exact links_ok=3 summary. Last line: $summaryLine"
    }

    $claudeHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $claudeGlobal).Hash
    if ($claudeHashAfter -ne $claudeHashBefore) { throw 'Protected global CLAUDE.md changed during setup.' }
    Write-Host "protected CLAUDE.md unchanged: SHA256=$claudeHashAfter"

    Set-MaintenanceTask $maintenancePath
    Update-HostRecord (Join-Path $script:codexConfig 'DROPBOX-IGNORE-README.md')
    if ($Client) {
        Write-Host "SETUP COMPLETE on $hostName (client mode; no scheduled task)"
    }
    else { Write-Host "SETUP COMPLETE on $hostName (always-on mode)" }
}
catch {
    $bootstrapError = $_.Exception.Message
    try { Restore-CodexConfigOnFailure }
    catch { Write-Host "WARNING: Codex config restoration failed: $($_.Exception.Message)" -ForegroundColor Yellow }
    Write-Host "SETUP INCOMPLETE on $hostName ($mode mode): $bootstrapError" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $bootstrapTemp) {
        $resolvedTemp = [IO.Path]::GetFullPath($bootstrapTemp)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemp.StartsWith($systemTemp,[StringComparison]::OrdinalIgnoreCase) -and
            ([IO.Path]::GetFileName($resolvedTemp) -like 'codex-config-bootstrap-*')) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
