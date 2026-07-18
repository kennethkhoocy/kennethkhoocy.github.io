# Codex configuration in Dropbox

This folder is the portable projection for Codex-specific configuration. The
live `~\.codex` directory remains a real, machine-local directory because Codex
sessions, authentication, SQLite databases, plugin caches, history, and other
runtime state are unsafe to synchronize while processes are active.

The portable files are:

- `AGENTS.md`: global Codex orchestration instructions.
- `orchestrator.config.toml`: the `gpt-5.6-sol`/`ultra` orchestrator profile.
- `codex-plugin-manifest.json`: reproducible sources for native Codex plugins.
- `setup-codex-shared-links.ps1`: per-machine link creation and repair.
- `codex-config-maintenance.ps1`: ignore stamping and link verification.

Each machine uses these mappings:

```text
~\.codex\AGENTS.md
  -> Dropbox\codex-config\AGENTS.md

~\.codex\orchestrator.config.toml
  -> Dropbox\codex-config\orchestrator.config.toml

~\.codex\skills
  -> Dropbox\claude-config\skills
```

Global `AGENTS.md` is deliberately separate from global `CLAUDE.md` because
Codex is the orchestrator while Opus and Fable serve as Claude auditors. Local
project `AGENTS.md` files link to same-directory `CLAUDE.md` only where their
semantics are identical. Known divergent project pairs remain separate.

`Dropbox\claude-config\CLAUDE.md`, the complete shared `skills` tree, and
Claude-side plugins are read-only from this setup. A proposed content change
requires a file-specific plan and the user's explicit approval. Ponytail is
installed as a native Codex plugin directly from its GitHub repository. GitHub
and Firecrawl continue to use the `gh` and `firecrawl` command-line tools.

## Dropbox ignore behavior

A `.dropboxignore` file is ineffective on this account because Dropbox's
official ignore-rules feature is unavailable. The working mechanism is the
`com.dropbox.ignored` NTFS stream, stamped per file or directory:

```powershell
Set-Content -LiteralPath <path> -Stream com.dropbox.ignored -Value 1
```

`codex-config-maintenance.ps1` stamps any accidentally copied runtime state
under this small portable folder, removes stale root-level conflicted or
temporary copies, and verifies the three required links. It never traverses or
modifies the real `~\.codex` runtime tree. Its summary has the form:

```text
2026-07-18T15:42:00 stamped=N junk_removed=M links_ok=3
```

## Per-machine bootstrap prompts

### Prompt A — always-on hosts

> This machine is an ALWAYS-ON host. Download
> https://kennethkhoocy.github.io/files/codex-config/setup-codex-config.ps1 to
> a temp path with `Invoke-WebRequest -OutFile` and run it with
> `powershell -NoProfile -ExecutionPolicy Bypass -File <path>` (no flags). It
> is a one-shot, idempotent bootstrap: prepares the selective Dropbox Codex
> projection, creates the global Codex and shared-skills links, installs native
> Codex plugins from their GitHub sources, registers the recurring
> `CodexConfigMaintenance` task (6-hourly), runs maintenance once, and records
> this hostname in the README. Report the full output, especially
> `stamped=N junk_removed=M links_ok=3` and `SETUP COMPLETE`.

### Prompt B — client machines

> This machine is a CLIENT (not always on). Download
> https://kennethkhoocy.github.io/files/codex-config/setup-codex-config.ps1 to
> a temp path with `Invoke-WebRequest -OutFile` and run it with the client
> flag: `powershell -NoProfile -ExecutionPolicy Bypass -File <path> -Client`.
> It performs only the one-time setup: the selective Dropbox projection,
> global Codex and shared-skills links, native Codex plugins, and local ignore
> stamps. It deliberately registers no recurring task; always-on machines run
> the account-wide maintenance. Report the full output, especially
> `stamped=N junk_removed=M links_ok=3` and `SETUP COMPLETE ... (client mode;
> no scheduled task)`.

Always-on hosts receive a six-hourly task plus at-logon and
start-when-available triggers. Registering its S4U principal requires an
elevated PowerShell; a non-elevated attempt exits with `SETUP INCOMPLETE` and
can be rerun safely after elevation. Client mode leaves no Codex maintenance
task.

Done on: DESKTOP-0C7PLAP (2026-07-18, links and maintenance verified; S4U task pending an elevated bootstrap run).
