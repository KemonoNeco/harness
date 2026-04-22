# HARNESS — Soul-Driven Agent Framework (Prompt Layer)

The soul files for a portable, Obsidian-native agent harness. These files are the system prompt: concatenated, scope-aware, markdown-native. Inspired by [OpenClaw](https://github.com/openclaw/openclaw), [IronClaw](https://github.com/nearai/ironclaw), and [pi-mono](https://github.com/badlogic/pi-mono). Full design in [../HARNESS_Research.md](../HARNESS_Research.md).

This repo currently ships **only the prompt framework** — no runtime, no daemon, no manifest. You fill in the user-authored files, concatenate them manually, and paste into Claude Code (or any model) as a custom system prompt. Everything else is future work.

## File map

### Soul files (core — concatenated into the system prompt)

| File | Author | What it is |
|---|---|---|
| [IDENTITY.md](IDENTITY.md) | you | Vitals: name, creature, vibe, emoji, pronouns. Runtime-agnostic by design. |
| [SOUL.md](SOUL.md) | you | The big one. Personality, values, Core Truths, Vibe, Continuity. Anchored section headings (`<!-- anchor: core-truths -->`). |
| [USER.md](USER.md) | you | Who the human is. Primary + optional secondary operator. `## How They Talk` seeds STYLE.md. |
| [BOUNDARIES.md](BOUNDARIES.md) | you | Hard rules, one bullet per rule, each prefixed `[scope: all\|main\|external\|shared\|untrusted]`. Pulled out of SOUL and AGENTS so the future `ZonePolicy` can enforce without parsing prose. |
| [MEMORY.md](MEMORY.md) | mixed | **Index** (not memory) — manifest of topics under `memory/topics/`, with auto-load rules. |
| [STYLE.md](STYLE.md) | framework-distilled | Observed user writing style. Ships empty. |
| [PATTERNS.md](PATTERNS.md) | framework-distilled | Observed PKM / note-management patterns. Ships empty. |
| [GLOSSARY.md](GLOSSARY.md) | framework-distilled | User-specific vocabulary, acronyms, codenames. Ships empty. |

### Memory layer (schema + skeleton)

| Path | Purpose |
|---|---|
| [memory/FORMAT.md](memory/FORMAT.md) | **Canonical spec** for memory entries. Heading grammar, HTML-comment metadata fields, recall-card pattern, stable-ID conventions, backlink syntax. Read this before writing any memory entry. |
| [memory/DISTILL.md](memory/DISTILL.md) | Placeholder for the future distillation job's checklist. Stub now; real checklist lands with the daemon. |
| `memory/daily/` | Short-term append-only logs (`YYYY-MM-DD.md`). Empty until you start writing. |
| `memory/topics/` | Long-term per-topic curated files. Empty until distillation promotes entries. |

## Two axes: scope and authorship

Every soul file opens with a line-1 metadata comment: `<!-- scope: X | author: Y | ... -->`. Grep-friendly, hidden in Obsidian preview, ready for the future loader to parse.

**Authorship** tells you who owns the file:

- **`author: user`** — you edit this by hand. IDENTITY, SOUL, USER, BOUNDARIES.
- **`author: framework`** — the harness distillation pass rewrites this on a schedule. Edit freely to seed or correct, but the next pass will merge your edits with fresh observations. STYLE, PATTERNS, GLOSSARY, topic recall cards.
- **`author: mixed`** — both. MEMORY.md index (you edit the topic list; distillation updates per-topic loading hints).

**Scope** tells you where the file is allowed to be loaded:

| Scope | Meaning |
|---|---|
| `all` | Loaded in every session, every channel, every operator. Soul files default here. |
| `main` | Loaded only in direct owner chats. MEMORY.md and `main`-scoped memory entries. |
| `shared` | Loaded in shared channels (group chats, multi-operator surfaces). |
| `owner-only` | Loaded only when the primary operator is the sole audience. Stricter than `main`. |
| `external` | Scope label for actions that leave the machine (used in BOUNDARIES entries). |
| `untrusted` | Scope label for sessions with non-owner operators. |

Scope tags are **documentation-only today** — there's no runtime to enforce them yet. Treat them as law when hand-assembling prompts; the future `ZonePolicy` will make enforcement automatic.

## How to use this today (no runtime required)

1. **Fill in the four user-authored files.** IDENTITY, SOUL, USER, BOUNDARIES. Follow the `_(italic hints)_` and replace `<!-- PLACEHOLDER: ... -->` sections. Keep it real — sparse-and-honest beats verbose-and-generic.
2. **Leave the framework-distilled files alone** (or seed `STYLE.md#seed-observations`, `PATTERNS.md#seed-observations`, `GLOSSARY.md#seed-entries` if you want — the future distillation pass will merge your seeds).
3. **Concatenate into a system prompt** when starting a new Claude Code session:

   ```bash
   cat IDENTITY.md SOUL.md USER.md BOUNDARIES.md MEMORY.md > /tmp/system-prompt.md
   ```

   Paste that into Claude Code as a custom system prompt (or save as `AGENTS.md` if you're using a Claude Code workspace). HTML-comment metadata lines are harmless for the model — the future manifest loader will strip them automatically.

4. **Start writing memory entries.** When something notable happens, append an entry to `memory/daily/YYYY-MM-DD.md` following the schema in [memory/FORMAT.md](memory/FORMAT.md). Use real ISO-timestamped IDs from day one — when the retrieval layer lands, those entries become the corpus.

5. **Commit everything.** The vault is a git repo; every change is an audit trail. Revert any mistake with `git revert`.

## Memory in one page

Three tiers:

1. **Working** — what the runtime injects per turn (retrieval hits + active-note context). Ephemeral. Doesn't live on disk.
2. **Short-term** — `memory/daily/YYYY-MM-DD.md`. Append-only. You write here per notable event.
3. **Long-term** — `memory/topics/<topic>.md`. One file per topic. Distillation pass promotes from daily logs. Each topic opens with a **recall card** (5–10-bullet hot-state summary) that the runtime can load without pulling the whole topic.

Every entry is a `## HH:MM [tag:X] summary` heading + body + HTML-comment metadata block holding `id`, `operator`, `scope`, `conf`, `supersedes`. Cross-reference with `[[daily/2026-04-01#14:32]]` — Obsidian resolves the link, gives you a backlink graph for free, and the future retrieval layer walks the graph for hop-expansion.

**Never edit past entries.** Corrections create a new entry with `supersedes: <old-id>` in the comment block. The history stays immutable; git is the audit log.

Full spec in [memory/FORMAT.md](memory/FORMAT.md).

## What Harness improves over OpenClaw / your prior workspace

1. **User-authored vs framework-distilled split** — STYLE/PATTERNS/GLOSSARY are auto-generated with a regeneration contract in the header. OpenClaw treats all soul files as hand-edited.
2. **BOUNDARIES.md as a first-class, scope-tagged file** — not scattered across SOUL "Boundaries" + AGENTS "Red Lines". Each rule has a scope tag and can be audited, shared, or enforced independently.
3. **Inline scope declarations on every file** — machine-greppable metadata on line 1. Documented today, enforced by `ZonePolicy` later.
4. **Anchored section headings in SOUL.md** — `<!-- anchor: core-truths -->` lets the future loader reference partial sections without parsing prose.
5. **Runtime-agnostic IDENTITY.md** — Runtime/Instance fields marked optional so identity is portable across Claude Code, local model daemons, and Claude Cowork. OpenClaw assumes a single runtime.
6. **Three-tier memory with entry-level granularity** — stable IDs, Obsidian backlinks as a retrieval graph, recall cards for cheap hot-state loads, append-only with `supersedes:` for corrections. Fixes the monolithic-MEMORY.md lookup pain.
7. **No YAML frontmatter on soul files** — OpenClaw uses YAML on its template reference docs (for site generation). Harness ships with none, so raw concatenation Just Works.

## Intentionally not shipped (future work)

These belong to later cuts. Listed here so it's obvious why they're missing:

- **`soul.toml` manifest** + assembler script — loads files in declared order, strips scope comments, emits a system prompt. Next cut after this one.
- **`AGENTS.md`** — OpenClaw's boot-narration + workspace-etiquette file. When the manifest lands, AGENTS.md returns as pure instructional content (platform formatting, group-chat etiquette, heartbeat rules). Until then, seed its prescriptive content into SOUL.md if you want.
- **`HEARTBEAT.md`** — paired with the daemon's scheduler. No scheduler today, no heartbeat file.
- **`TOOLS.md`** — local infra config (hostnames, ports, API creds). Not soul content — belongs in a sibling concern under `.harness/` or a separate vault-external file so it doesn't leak into the system prompt.
- **`BOOTSTRAP.md`** — OpenClaw's elegant first-run ritual (agent interviews the user and populates the soul files). Needs a boot system that can delete-after-use. Re-evaluate with the manifest.
- **Distillation job** — the thing that rewrites STYLE / PATTERNS / GLOSSARY and promotes daily entries into topics. Stub spec in [memory/DISTILL.md](memory/DISTILL.md); real implementation ships with the daemon.
- **`ZonePolicy` enforcement** — the runtime that reads scope tags and decides what to load in which session. Until it exists, scope tags are documentation.
- **Retrieval layer** — SQLite + FTS5 + sqlite-vec over the memory corpus, MMR reranking, weighted score fusion. The `memory/FORMAT.md` schema is designed to drop straight in.
- **Obsidian plugin, Discord gateway, Rust daemon, sessions, skills** — everything downstream of the prompt layer. See [../HARNESS_Research.md](../HARNESS_Research.md) for the full architecture.

## References

- **Research doc:** [../HARNESS_Research.md](../HARNESS_Research.md) — complete architecture and design rationale.
- **OpenClaw templates** (seed tone): https://github.com/openclaw/openclaw/tree/main/docs/reference/templates
- **Prior workspace** (filled-in reference): https://github.com/KemonoNeco/openclaw-workspace

## Next steps

When ready to move past this cut: the logical next deliverable is a **`soul.toml` manifest** + a ~50-line assembler (Python or Rust) that reads the manifest, orders the files, strips scope-comment metadata, and prints the system prompt. That turns "copy-paste concatenation" into `harness assemble --scope main > prompt.md` and lays the ground for the runtime. Target schema is sketched in [../HARNESS_Research.md](../HARNESS_Research.md) §"The soul file system".
