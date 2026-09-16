# Codex configuration in Dropbox

This folder is the portable Codex-specific configuration projection. The live
~\.codex root remains a real machine-local directory, including its session
roots, authentication, SQLite databases, plugin caches, history, and logs.

The portable files are:

- AGENTS.md: global Codex orchestration instructions.
- orchestrator.config.toml: the gpt-5.6-sol/ultra orchestrator profile.
- codex-plugin-manifest.json: reproducible sources for native Codex plugins.
- setup-codex-shared-links.ps1: project-level link creation and repair.
- setup-codex-session-links.ps1: legacy filename for session-mirror setup.
- watch-codex-session-policy.ps1: selective exporter, validator, and explicit
  offline importer.
- codex-config-maintenance.ps1: ignore stamping, mirror repair, and validation.

Each machine uses these links:

    ~\.codex\AGENTS.md
      -> Dropbox\codex-config\AGENTS.md

    ~\.codex\orchestrator.config.toml
      -> Dropbox\codex-config\orchestrator.config.toml

    ~\.codex\skills
      -> Dropbox\claude-config\skills

The session roots remain local:

    ~\.codex\sessions                   real local directory
    ~\.codex\archived_sessions          real local directory
    Dropbox\codex-config\session-mirror selective immutable mirror

This layout enforces the session boundary before Dropbox receives any bytes.
Only rollouts whose first session_meta record identifies both a matching UUID
and a source of cli or vscode are eligible. The exec, app-server, subagent,
malformed, empty, and identity-mismatched rollouts never enter the Dropbox
mirror.

## Session-mirror format

The shared session-mirror contains immutable content objects and immutable
parent-linked commit manifests:

    session-mirror\objects\<uuid>\<length>-<sha256>.jsonl
    session-mirror\commits\<uuid>\<commit-id>.json

An exporter snapshots only through the final complete JSONL newline, validates
the embedded session UUID and source, writes a content-addressed object, checks
its length and SHA-256, and writes the commit manifest last. Importers accept a
commit only after its referenced object has arrived and passes the same checks.

The machine-local catalog is stored under
%LOCALAPPDATA%\CodexSessionMirror. Reconciliation accepts an equal file or a
strict byte-prefix extension. Divergent histories, multiple commit tips, an
invalid graph, and concurrent archive-state changes produce a nonzero conflict
and a machine-local record. A complete local conflict snapshot is retained
under %LOCALAPPDATA%\CodexSessionMirror\conflicts. Explicit imports preserve
replaced or relocated local files under
%LOCALAPPDATA%\CodexSessionMirror\import-backups.

Filesystem events reduce synchronization latency, while a periodic full scan
repairs missed events. The background watcher and scheduled maintenance publish
eligible snapshots and validate inbound commits without changing live local
sessions. An inbound update requires an explicit offline invocation:

    powershell -NoProfile -ExecutionPolicy Bypass -File <Dropbox\codex-config\watch-codex-session-policy.ps1> -Once -Import

The importer revalidates local bytes immediately before replacement and retains
recoverable backups. Missing files never imply deletion. Permanent deletion
requires a future explicit tombstone mechanism.

Global AGENTS.md is deliberately separate from global CLAUDE.md because Codex
is the orchestrator while Opus and Fable serve as Claude auditors. Local
project AGENTS.md files link to same-directory CLAUDE.md only where their
semantics are identical. Known divergent project pairs remain separate.

Dropbox\claude-config\CLAUDE.md, the complete shared skills tree, and
Claude-side plugins are read-only from this setup. A proposed content change
requires a file-specific plan and the user's explicit approval. Ponytail is
installed as a native Codex plugin directly from its GitHub repository. GitHub
and Firecrawl continue to use the gh and firecrawl command-line tools.

## Dropbox ignore behavior

A .dropboxignore file is ineffective on this account because Dropbox's
official ignore-rules feature is unavailable. Accidental process-owned state
under this portable folder is blocked with the com.dropbox.ignored NTFS
stream:

    Set-Content -LiteralPath <path> -Stream com.dropbox.ignored -Value 1

Session selection does not depend on a post-creation ignore stamp. Excluded
rollouts stay in local session roots and therefore never enter Dropbox.

codex-config-maintenance.ps1 stamps accidental runtime-state copies, performs
a complete session reconciliation, removes only stale mirror temporary files,
and verifies the required links and local roots. Its final summary has this
form:

    2026-07-18T15:42:00 stamped=N unignored=0 junk_removed=M uploaded=N downloaded=N excluded=N deferred=N conflicts=0 links_ok=3 local_roots_ok=2 mirror_roots_ok=2

## Ownership and cross-machine resume

Each session UUID has one writer at a time. The handoff sequence is:

1. Exit Codex on the current owner and allow the mirror watcher to publish the
   final committed generation.
2. Wait for Dropbox to finish on both machines.
3. Run the bootstrap or watch-codex-session-policy.ps1 -Once -Import on the
   receiving machine while Codex is closed, then use codex resume <UUID>.

The receiving machine keeps SQLite and its session index local. Current Codex
falls back to canonical rollout filenames when resuming by UUID and repairs its
local index. Direct UUID resume is therefore the dependable handoff path. Use
codex unarchive <UUID> before resuming an archived session. Keep machines on
compatible Codex versions and use codex fork <UUID> for concurrent,
independent continuations.

## Per-machine bootstrap prompts

### Prompt A — always-on hosts

> This machine is an ALWAYS-ON host. Download
> https://kennethkhoocy.github.io/files/codex-config/setup-codex-config.ps1 to
> a temp path with Invoke-WebRequest -OutFile and run it with
> powershell -NoProfile -ExecutionPolicy Bypass -File <path> (no flags).
> Run it from ordinary PowerShell or Claude Code after every Codex process has
> closed. It is a one-shot, idempotent bootstrap: prepares the selective
> Dropbox Codex projection, keeps both session roots local, installs the
> immutable cli/vscode session mirror, creates the global Codex and shared
> skills links, installs native Codex plugins from their GitHub sources,
> registers the six-hourly CodexConfigMaintenance task, runs maintenance
> once, and records this hostname in the README. Report the full output,
> especially SESSION MIRROR SETUP COMPLETE, session-mirror watcher ready,
> conflicts=0 links_ok=3 local_roots_ok=2 mirror_roots_ok=2, and
> SETUP COMPLETE.

### Prompt B — client machines

> This machine is a CLIENT (not always on). Download
> https://kennethkhoocy.github.io/files/codex-config/setup-codex-config.ps1 to
> a temp path with Invoke-WebRequest -OutFile and run it with the client
> flag: powershell -NoProfile -ExecutionPolicy Bypass -File <path> -Client.
> Run it from ordinary PowerShell or Claude Code after every Codex process has
> closed. It performs the one-time selective projection, local session-root
> validation, immutable cli/vscode session-mirror setup, global Codex and
> shared-skills links, native plugin installation, and local ignore stamps.
> It registers no six-hourly maintenance task. The at-logon session-mirror
> watcher is installed on clients because it publishes eligible sessions while
> the machine is in use. Report the full output, especially
> SESSION MIRROR SETUP COMPLETE, session-mirror watcher ready,
> conflicts=0 links_ok=3 local_roots_ok=2 mirror_roots_ok=2, and
> SETUP COMPLETE ... (client mode; no recurring maintenance task).

Always-on hosts receive a six-hourly maintenance task in addition to the
at-logon session-mirror watcher. Registering the maintenance task's S4U
principal requires an elevated PowerShell; a non-elevated attempt exits with
SETUP INCOMPLETE and can be rerun safely after elevation. Client mode leaves no
six-hourly Codex maintenance task.

Done on: DESKTOP-0C7PLAP (2026-07-18; configuration links verified; production
mirror audited for cli/vscode-only eligibility; all exec, subagent, and invalid
rollouts remain local; per-user watcher active through the HKCU Run fallback).
