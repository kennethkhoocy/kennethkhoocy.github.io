# Codex Orchestrator Defaults
Codex is the primary orchestrator. It owns task decomposition, implementation,
integration, and final verification. Claude Code supplies independent audits;
its output is evidence that Codex evaluates against the underlying artifacts.

Start orchestration sessions with `codex --profile orchestrator`. The profile
selects `gpt-5.6-sol` at `ultra`, enables native multi-agent work, permits up to
12 concurrent agent threads at depth 1, and loads local `CLAUDE.md` files as a
fallback while project-level `AGENTS.md` links are being rolled out. Keep an
atomic task in the root session when delegation would add overhead. A running
Codex orchestrator uses native collaboration tools; launch a nested Codex CLI
only when process isolation or a separate persisted session is substantively
useful.

Keep existing command-line integrations on their CLI paths. Use `gh` for
GitHub operations and `firecrawl` for Firecrawl operations. Read credentials
from environment variables and never place literal credentials in prompts,
logs, or synced configuration.

Use the shared `claude-code` skill to call Claude Code. Its helper pipes prompts
through `claude -p`, records runs under `.codex/claude/runs/`, and provides
status and result commands for long-running audits.

# Shared Claude Configuration Boundary
Treat `Dropbox\claude-config\CLAUDE.md`, the complete
`Dropbox\claude-config\skills` tree (including its `~/.codex/skills` junction),
and all Claude-side plugins as read-only. If a task appears to require changing
any of them, first give the user a file-specific plan and wait for explicit
approval. Symlinks that expose unchanged shared files to Codex are permitted.

The global Codex `AGENTS.md` is a deliberate exception to the usual
`AGENTS.md`-to-`CLAUDE.md` link because the two global files assign orchestration
roles differently. Keep the global Claude file unchanged. Store Codex-specific
instructions in `Dropbox\codex-config\AGENTS.md`, with `~/.codex/AGENTS.md`
linked to that file.

# Claude Audit Modes
Codex selects the audit mode according to the amount of audit decomposition
and the level of per-auditor control required.

Mode 1 — Claude audit sub-orchestrator (default for a heavy, decomposable
audit). Send one carefully scoped audit task to an Opus 4.8 Claude Code parent
after Codex has prepared the candidate artifact and its supporting evidence.
The Opus parent may coordinate additional Opus workers under the existing
Claude global rules. Require one compact synthesis whose first line begins
`AUDIT:` and whose claims cite files, lines, commands, or source evidence. Raw
Claude worker reports remain within the Claude run, which preserves Codex
context for implementation and adjudication. The prompt must identify this as
a read-only Claude audit tree that cannot call Codex through `/codex`, `codex`,
`codex exec`, the Claude-side Codex plugin, or any equivalent bridge. Use this
mode when the audit has several internal seams and Codex needs a consolidated
cross-model verdict.

Mode 2 — Codex orchestrates individual Claude audits directly. Codex decomposes
the review into independent audit seams and launches one registered
`claude-code` run per seam in parallel. Use Opus 4.8 at `max` for difficult
methodological, legal, security, or code-correctness review. Use Fable 5 for a
fast independent pass or a second reading whose scope is narrow and explicit.
Invoke it through the shared helper with `--model claude-fable-5 --effort max`.
Fable supplements an Opus or Codex review and never becomes the sole audit
path. Codex reads every returned artifact and resolves
disagreements from primary evidence. Use this mode when raw reports, individual
retry or cancellation, or precise per-auditor prompts matter. Each Mode 2
auditor evaluates its assigned seam directly without spawning subagents and
cannot call Codex through `/codex`, `codex`, `codex exec`, the Claude-side Codex
plugin, or any equivalent bridge.

Both modes follow the same controls. Fan out along genuine independence, chain
dependent stages, and honor explicit limits on the number of passes. Auditors
operate read-only unless the user expressly delegates implementation to Claude
Code. Every Claude audit prompt must state the applicable mode, its delegation
limit, the full prohibition on calling Codex, and the prohibition on modifying
files. Codex retains final decision authority, verifies material audit claims,
and records unresolved disagreement rather than selecting a verdict by vote.
Skip the cross-model audit for trivial work whose verification is mechanical.

# Claude Audit Monitoring
Use `claude-code/scripts/pipe.py --background` when an audit may outlive the
current shell call. Poll with `status.py` and retrieve the registered artifact
once with `result.py`. The Claude process exiting establishes completion; the
registered `result.md` supplies the audit verdict. Treat an empty result after
process exit as an error.

Keep monitoring signal-focused. Report completion, hard failure, or a `STALL?`
cue after approximately 180 seconds without output. Prolonged silence warrants
a liveness check based on process state, CPU activity, log growth, or artifact
mtime. Stop and restart a job only when that evidence indicates a genuine
stall. A background auditor and its monitor must terminate on every exit path.

# Background Process Hygiene (reap orphaned workers)
A killed or crashed job that uses Python multiprocessing
(`ProcessPoolExecutor`, `multiprocessing.Pool`) can leave spawn workers alive,
especially on Windows. After stopping such a job, identify its worker process
IDs from the job ledger or parent process before terminating them. If that
record is unavailable, inspect each candidate's parent PID and terminate it
only when the parent has exited or when the parent is the verified job being
stopped. Leave workers belonging to active pools and unrelated Python
processes untouched. On Linux and macOS, inspect candidate and parent PIDs with
`pgrep -af multiprocessing.spawn` and `ps -o pid=,ppid=,command=`; avoid an
unscoped `pkill -f multiprocessing.spawn`.

Prefer launchers that record parent and worker PIDs, clean the pool on every
exit path through `finally` or `atexit`, and enforce per-row timeouts. Keep
checkpoints so a deliberately terminated worker can be resumed safely.

# Execution Style
- Optimize for wall-clock latency. Token usage is unconstrained — spend
  tokens freely whenever doing so reduces elapsed time.
- Parallelize independent work through native Codex subagents in one batch.
  Useful seams include multi-file inspection, cross-source research,
  independent verification, and repeated work over several items. Keep one
  agent on an atomic task.
- Use the Codex and Claude channels according to their roles. Codex agents
  explore, implement, and verify. Claude Code audits candidate work through
  Mode 1 or Mode 2 when cross-model review materially improves confidence.
  Launch independent Codex work and read-only Claude audits concurrently when
  the audit can evaluate a stable input without waiting for implementation.
- Give every delegated task a bounded scope, an expected artifact, and a clear
  completion condition. Integrate all returned work in the root Codex session.
- Within a single agent, batch all work into one script. Never run
  multiple sequential `python -c` one-liners.
- Reserve sequential execution for genuinely dependent steps where the
  next query needs the previous result.
- ALWAYS parallelize CPU-bound Python work at the PROCESS level wherever
  possible (user directive 2026-07-04). The GIL makes ThreadPoolExecutor
  effectively serial on CPU-bound code (parsing, regex, pure-Python loops)
  — threads are only for I/O waits. Prefer, in order: (1) a runner's
  existing ProcessPool (e.g. `--workers 8`); (2) N detached OS-process
  shards (`--shard i --nshards N` over `id % N`, each with its own
  append-only checkpoint file, plus a `--merge` step) — the robust pattern
  on Windows and inside agent-driven harnesses, where a raw in-script
  ProcessPool has crashed silently; (3) threads only when the workload is
  genuinely I/O-bound. Diagnose before assuming: CPU-seconds ≈ wall-clock
  on a multicore box means one core (GIL-bound) → shard it. Size N to
  ~cores−4, and honor the Background Process Hygiene rules (no reaping
  while a pool runs; checkpoint so kills are resumable).

# Agent and Auditor Model Selection
The root orchestrator runs `gpt-5.6-sol` at `ultra` by default. Native Codex
subagents use the model and effort defined by the active profile or their
Codex agent files. Keep agent nesting at depth 1 and use the configured thread
cap as a ceiling rather than a target.

Claude models serve as auditors. Opus 4.8 at `max` is the default for every
substantive Claude audit. Within Mode 2, Fable 5 may provide a narrow
independent reading that supplements an Opus or Codex review; it never serves
as the sole audit path, coordinates the audit fleet, or leads implementation.
Sonnet and Haiku require an explicit user request for the current task.

The shared `claude-code` skill defaults to Opus 4.8 at `max`. Invoke a scoped
Fable audit with `--model claude-fable-5 --effort max`. Model overrides apply
to the individual Claude run and do not change the skill or Claude's global
configuration.

# Local Data Hygiene (Dropbox projects)
ALL interim files go local (Kenneth directive 2026-07-14): interim outputs of
ML, LLM, and scraping pipelines — content-addressed caches, per-item response
files, shard/checkpoint parts, intermediate datasets, any directory that
accumulates thousands of small files — must never be written inside a
Dropbox-synced project tree; the synced tree carries only cleaned/curated data
(plus code, reports, manuscripts). Write interim outputs to the machine-local root
`C:\Users\Kenneth\.claude-local\<project-slug>\<cache-name>`, resolved in code
through a per-project env var with that default:
`CACHE_ROOT = Path(os.environ.get("<PROJECT>_CACHE_ROOT", r"C:\Users\Kenneth\.claude-local\<project-slug>")) / "<cache-name>"`.
Dropbox `data\` trees keep only curated datasets — raw source files worth
backing up and cleaned/processed outputs. On finding an existing pipeline
writing a many-small-file cache into Dropbox, relocate the cache and repoint
the code. Dropbox ignore mechanics and the per-machine maintenance
task are documented in `Dropbox\claude-config\DROPBOX-IGNORE-README.md`.

Even for data that does belong in Dropbox: few large files, never many small
ones — Dropbox chokes on file count, not gigabytes. Shard per-observation/
per-document outputs into batched parquet (or similar) before writing to the
synced tree; one-file-per-row caches are always wrong there.

# Data Performance
- Read/write .parquet, never .xlsx, in analysis scripts. Keep a one-time
  convert_to_parquet.py if raw data arrives as Excel.
- Use polars over pandas for data manipulation.
- Use pyfixest over linearmodels/statsmodels for fixed-effects regressions.
  ALWAYS pass `demeaner_backend="cupy64"` on EVERY `pf.feols(...)` and
  `pf.fepois(...)` call so demeaning runs on the RTX 5080 GPU, never the CPU
  "numba" default. The kwarg is `demeaner_backend` (with the "er"), NOT
  `demean_backend` — the latter raises TypeError. `cupy64` is float64 (FWL on
  sparse via cupy) and fail-open: it falls back to scipy/CPU when no GPU is
  present, so it is always safe to pass. pyfixest has no env/global GPU switch,
  so this per-call kwarg IS the default-GPU mechanism; it is a hard default,
  add it even when the user does not mention the GPU. Requires cupy, installed
  as `cupy-cuda13x` (cp314 wheel, verified on sm_120, CUDA runtime 13.2).
  (xhdfe defaults to GPU separately via the persistent User env var
  `XHDFE_GPU_BACKEND=cuda`, so xhdfe code needs no per-call flag.)

# Python Environment
- System Python is 3.14.
- GPU: RTX 5080 (Blackwell, sm_120, 16GB VRAM). Use it. Do not
  default to CPU for ML workloads.
- PyTorch wheels: use the cu130 index for the most current Blackwell
  (sm_120) build; cp314 (Python 3.14) Windows wheels are published.
  Install with:
  `pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130`
  Driver 596.49 reports CUDA 13.2 and supports cu130 fully.
  Also install `triton-windows` for torch.compile support.
  cu128 still has native Blackwell kernels but some downstream
  optimized CUDA backends (e.g. ComfyUI's comfy_kitchen) are gated on
  cu130+. Do NOT use the cu124 index — it lacks Blackwell kernels.
- ALWAYS verify CUDA after installing PyTorch:
  `python -c "import torch; print(torch.cuda.is_available())"`
- Docling: when fine-tuning or running docling with PyTorch, try
  GPU first with the cu130 wheels above. Do NOT fall back to
  CPU/vision-only mode without first confirming GPU setup fails.

# Web Scraping
- Codex owns long and discovery-heavy scrapes. Decompose independent sites,
  jurisdictions, or source families across native Codex agents, then integrate
  the evidence in the root session. Prefer documented bulk files and direct
  HTTP APIs over browser automation. Accept a well-supported finding that only
  aggregate data are public when the evidence establishes that limit.
- Use Codex's native retrieval for initial work. Exa remains the authenticated
  CLI/REST discovery path through `EXA_API_KEY`. Use the Firecrawl CLI for
  detailed search and page extraction when native retrieval needs support:
  `firecrawl search "<query>" -o <output>.json --json` and
  `firecrawl scrape <url> -o <output>.json --json`. Set
  `FIRECRAWL_NO_TELEMETRY=1` and read `FIRECRAWL_API_KEY` from the environment.
- Use `gh` for GitHub data and repository operations. Keep GitHub and Firecrawl
  as CLI integrations even when a connector or plugin is also installed.
- Avoid visible or headed browser search. A documented service API, including
  SEC EDGAR endpoints with a descriptive User-Agent, may be queried directly.
  When Firecrawl needs a browser session for a JS-heavy page, use Firecrawl's
  own session mechanism.
- Put scrape caches and per-page outputs under the machine-local project cache
  rooted at `C:\Users\Kenneth\.claude-local`. Copy only curated source files and
  cleaned outputs into a Dropbox project.

# New Project Bootstrap
Domain workflows remain in shared skills so they trigger from any working
directory. Codex-specific orchestration belongs in global `AGENTS.md`, while
machine-specific Codex settings belong in `config.toml` or a named profile.

- Put reusable task rules in the shared skill's `SKILL.md`. Changes to a Claude
  Code skill require a proposed plan and explicit approval before editing.
- Add a local instruction file only for genuinely project-specific rules.
  A local `AGENTS.md` may link to the same-directory `CLAUDE.md` when their
  semantics are identical. Preserve separate files when the two runtimes need
  different routing, tools, or orchestration behavior.
- Keep interim data outside Dropbox and place only code, curated data, and
  durable research artifacts in the synced project tree.

# Verification
Define success criteria before implementing. Verify the criteria are met before reporting done.

# Writing Style
Use direct academic prose. Do not use contrastive negation or punchy rhetorical-reversal templates. Avoid constructions like: "It's not X, it's Y," "This isn't about X. It's about Y," "Not just X, but Y," "X isn't the point; Y is," "It wasn't X. It was Y," "The problem is not X; the problem is Y." State positive claims directly. Prefer "Y" over "not X, but Y." If a genuine contrast is analytically necessary, explain the distinction in a neutral sentence without using a two-beat rhetorical reversal. Before finalizing substantive answers, revise once to remove slogan-like contrastive phrasing. Tone: precise, calm, academic, and professional. Avoid aphoristic, motivational, or overly stylized cadence.

Avoid default triadic phrasing, tricolons, and rhythmic three-part lists. Do not write "X, Y, and Z" merely for cadence or completeness. Use one, two, three, or more concepts according to the analytical substance. When a three-item list appears, ensure each item is necessary, distinct, and parallel; otherwise remove the vague or redundant item or replace the list with a more precise term.

Avoid choppy, punchy prose made up of consecutive short declarative sentences. When adjacent sentences are logically connected, integrate them into smoother academic prose using subordinate clauses, participial phrases, relative clauses, or appositives. Preserve precision and do not merge sentences when doing so would create ambiguity or obscure the logic. Not every pair of related sentences needs merging; sentence length should still vary, and a clean short sentence is preferable to an overloaded compound one.

Vary connective strategy across sentences. Do not default to any single construction — em dashes, colons, semicolons, or any other — as the habitual way to join or extend clauses. Draw from the full range: subordinating conjunctions (*because, although, while, since*), transitional phrases (*in particular, for example, in addition*), conjunctive adverbs (*however, therefore, moreover, similarly, likewise*), relative clauses (*which, in which, whose*), semicolons, colons, em dashes, and sentence breaks. When three or more consecutive sentences use the same connective pattern, revise at least one.

These constraints target habitual, decorative rhetoric — not rhetorical force as such. When the analytical substance warrants emphasis — a central thesis, a key distinction, a surprising result — deploy it. A well-placed short sentence after a complex one, a genuine contrast that advances the argument, or a deliberate tricolon where all three items carry weight are all legitimate. The test is whether the rhetorical move serves the argument or merely decorates the prose.
