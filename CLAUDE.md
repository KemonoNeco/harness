# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Harness — a soul-driven, Obsidian-native agent framework. Successor to `openclaw-workspace` inspired by OpenClaw, IronClaw, and pi-mono. Full architectural design in [HARNESS_Research.md](HARNESS_Research.md).

**Current state:** only the prompt-framework layer ships. No runtime, no daemon, no manifest, no loader. `HARNESS/` contains markdown soul files that concatenate into a custom system prompt for Claude Code (or any model). Everything downstream (Rust daemon, `Embodiment` trait, Obsidian plugin, Discord gateway, distillation job, retrieval layer) is designed but not built.

## Directory layout

- `HARNESS/` — soul files at the root. **Core** files live here, not in subfolders. See [HARNESS/README.md](HARNESS/README.md).
- `HARNESS/memory/` — memory layer. Entry schema in [HARNESS/memory/FORMAT.md](HARNESS/memory/FORMAT.md). **Read FORMAT.md before writing any memory entry.**
- `.obsidian/` — shared Obsidian vault config. Workspace state files are gitignored.
- `HARNESS_Research.md` — design doc. Authoritative reference for decisions not yet implemented.

## How the prompt framework works

Every soul file opens with a line-1 HTML comment carrying metadata: `<!-- scope: X | author: Y | ... -->`. These are hidden in Obsidian preview, greppable, and will be parsed by the future `soul.toml` loader. HTML comments are prompt-harmless — raw concatenation into a system prompt Just Works today.

**Two axes on every file:**

- **Authorship** — `user` (you edit by hand), `framework` (distillation rewrites it), or `mixed`. Framework-distilled files (`STYLE.md`, `PATTERNS.md`, `GLOSSARY.md`) carry a regeneration-contract blockquote warning readers not to treat them as source-of-truth.
- **Scope** — `all | main | shared | owner-only | external | untrusted`. Documentation-only today; the future `ZonePolicy` enforces it. When assembling prompts manually, respect scope tags as if enforcement existed.

**Assembling the prompt (today, manually):**

```bash
cat HARNESS/{IDENTITY,SOUL,USER,BOUNDARIES,MEMORY}.md > /tmp/system-prompt.md
```

Paste into Claude Code as a custom system prompt. The framework-distilled files (`STYLE.md`/`PATTERNS.md`/`GLOSSARY.md`) are intentionally excluded until distillation has populated them.

## Key architectural improvements over OpenClaw (don't regress these)

1. **User-authored vs framework-distilled split.** `STYLE.md`, `PATTERNS.md`, `GLOSSARY.md` are auto-generated. If you add new distilled files, give them a regeneration-contract header.
2. **`BOUNDARIES.md` is first-class.** Do not scatter rules into `SOUL.md` "Boundaries" or a future `AGENTS.md` "Red Lines" section. Every rule gets a `[scope: X]` prefix.
3. **`MEMORY.md` is an index**, not a monolith. Long-term memory lives one file per topic under `memory/topics/`. Never collapse this back into a single `MEMORY.md`.
4. **Runtime-agnostic `IDENTITY.md`.** `Runtime`/`Instance` fields are optional by design — soul identities must stay portable across Claude Code, local-model daemons, and Claude Cowork.
5. **Three-tier memory with entry-level granularity and stable IDs.** See below.

## Memory semantics (critical — the schema is stable, the tooling isn't)

Three tiers:

- **Working** — runtime-injected per turn (retrieval hits + active-note context). Ephemeral; doesn't live on disk.
- **Short-term** — `HARNESS/memory/daily/YYYY-MM-DD.md`. Append-only log of notable events.
- **Long-term** — `HARNESS/memory/topics/<topic>.md`. One file per topic, curated by distillation. Each opens with a **recall card** (5–10-bullet hot-state summary).

**Entry format** (from `memory/FORMAT.md` — read it before writing any entry):

```markdown
## HH:MM [tag:X] [refs:Y] short title
Body (2-6 sentences).
<!-- id: 2026-04-01T14:32:00-07:00
     operator: tai
     scope: main
     conf: observed
     supersedes: 2026-03-30T08:15:00-07:00 -->
```

**Append-only invariant.** Never edit past entries. Corrections create a new entry with `supersedes: <old-id>` in the metadata block. Git is the audit log — every memory write should be a commit.

**Per-entry scope overrides file scope.** A daily file defaults to `scope: main`, but individual entries can narrow (`owner-only`) or widen (`all`). The future `ZonePolicy` reads entry-level first, file-level as fallback.

**IDs are stable and greppable.** ISO 8601 timestamps for events, `sha256:` prefix + 12 hex for timeless facts. Cross-reference with Obsidian wiki-link syntax: `[[daily/2026-04-01#14:32]]`. This gives the future retrieval layer a backlink graph via Obsidian's link index.

## Intentionally not shipped

Don't build these without talking to the user first — they're deferred by design, not by oversight:

- `soul.toml` manifest + assembler (next logical cut)
- `AGENTS.md` boot narration + workspace etiquette
- `HEARTBEAT.md`, `TOOLS.md`, `BOOTSTRAP.md`
- Distillation job (stub spec in `HARNESS/memory/DISTILL.md`)
- `ZonePolicy` enforcement
- Retrieval layer (SQLite + FTS5 + sqlite-vec)
- Rust daemon, Obsidian plugin, Discord gateway

Full rationale in [HARNESS/README.md](HARNESS/README.md) §"Intentionally not shipped".

## Verification commands

- `grep -rn "PLACEHOLDER:" HARNESS/` — list every spot awaiting user input.
- `grep -rln "^<!-- scope:" HARNESS/*.md` — verify every root-level soul file has a line-1 scope declaration.
- `grep -rn "\[scope:" HARNESS/BOUNDARIES.md` — verify every boundary rule has an inline scope tag.
- `grep -L "<!-- id:" HARNESS/memory/**/*.md` — every memory file should have at least one entry with an `id` (ignore `.gitkeep`).
- `grep -rh "^<!-- id:" HARNESS/memory/ | sort | uniq -d` — should be empty (no duplicate IDs).

## Git workflow notes

- Default branch on the remote is `main`. Local `master` was used for the initial bootstrap commit and then rebased onto the API-created init commit on `main`.
- Pushing directly to `main` is blocked by policy — always work on a feature branch and open a PR.
- Soul-file commits should be single-purpose: one commit per meaningful change. Memory writes should each be their own commit so git revert works cleanly.

## Loading into Claude Cowork

Harness ships a Cowork plugin at [plugin/](plugin/) that auto-loads the soul bundle into every Cowork session opened against this repo — no manual `cat`, no pre-assembled `SYSTEM_PROMPT.md`, no commit of a regenerated bundle. The live soul files are the single source of truth; the plugin reads them at session start every time.

Install once:

```bash
claude plugin install ./plugin
```

What the plugin delivers:

1. **Soul injection.** A `UserPromptSubmit` hook ([plugin/hooks/inject-soul.sh](plugin/hooks/inject-soul.sh)) cats [HARNESS/IDENTITY.md](HARNESS/IDENTITY.md), [HARNESS/SOUL.md](HARNESS/SOUL.md), [HARNESS/USER.md](HARNESS/USER.md), [HARNESS/BOUNDARIES.md](HARNESS/BOUNDARIES.md), [HARNESS/MEMORY.md](HARNESS/MEMORY.md) on the first prompt of each session and returns them as `additionalContext`. Idempotent per session via a marker file under `${CLAUDE_PLUGIN_DATA}/injected-sessions/`. Fail-open — if any file is missing, the hook emits nothing rather than breaking the session.
2. **Memory contract enforcement.** A `PreToolUse` hook ([plugin/hooks/enforce-memory-append-only.sh](plugin/hooks/enforce-memory-append-only.sh)) on `Edit`/`Write` blocks any mutation of a past `<!-- id: ... -->` entry under `HARNESS/memory/` — corrections must use `supersedes:` per [FORMAT.md](HARNESS/memory/FORMAT.md). Also refuses writes to `FORMAT.md` / `DISTILL.md` themselves.
3. **`new-memory-entry` skill.** [plugin/skills/new-memory-entry/SKILL.md](plugin/skills/new-memory-entry/SKILL.md) scaffolds a well-formed entry — tags, ISO-8601 id, scope, optional `supersedes:`, correct append-not-overwrite shape.

Plugin-scoped instructions live in [plugin/CLAUDE.md](plugin/CLAUDE.md). It's auto-injected alongside this file when the plugin is installed, and instructs the model to treat the soul bundle as its operating prompt and honour BOUNDARIES scope tags.

The soul files are never regenerated or committed in derived form. Edit them freely; next session, the plugin picks up your changes.

### Building for webapp upload

The Claude webapp's plugin uploader only accepts `.plugin` or `.zip` archives — it can't ingest a bare directory. Use [scripts/build-plugin.py](scripts/build-plugin.py) to package [plugin/](plugin/) into both formats:

```bash
python scripts/build-plugin.py           # writes dist/harness.plugin + dist/harness.zip
python scripts/build-plugin.py --clean   # removes dist/ first
```

Both files are byte-identical — the webapp treats `.plugin` and `.zip` the same; pick whichever extension your browser's file picker prefers. The archive layout puts `.claude-plugin/plugin.json` at the archive root (no `plugin/` wrapper directory), which is what both `claude plugin validate` and the webapp installer expect:

```
.claude-plugin/plugin.json
CLAUDE.md
hooks/hooks.json
hooks/inject-soul.sh
hooks/enforce-memory-append-only.sh
skills/new-memory-entry/SKILL.md
```

`dist/`, `*.plugin`, and `*.zip` are gitignored — rebuild locally whenever the plugin sources change. For CLI installs (`claude plugin install ./plugin`) the build step isn't needed; it's only required for the webapp path.

**Verify before uploading:**

```bash
claude plugin validate ./plugin          # validates the source; same contents go in the archive
python -m zipfile -l dist/harness.plugin # lists archive contents
```

## Reference material

- [HARNESS_Research.md](HARNESS_Research.md) — full architectural design, every subsystem, every deferred decision explained.
- [HARNESS/README.md](HARNESS/README.md) — user-facing overview of the prompt framework.
- [HARNESS/memory/FORMAT.md](HARNESS/memory/FORMAT.md) — canonical memory entry schema.
- Prior workspace: https://github.com/KemonoNeco/openclaw-workspace (filled-in reference shape).
- OpenClaw templates: https://github.com/openclaw/openclaw/tree/main/docs/reference/templates (seed tone).
