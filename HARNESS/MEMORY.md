<!-- scope: main | visible-to-subagents: false | author: mixed -->
# MEMORY.md — Long-Term Memory Index

_This file is an **index**, not the memory itself. Curated long-term memory lives in one file per topic under `memory/topics/`. This file lists the active topics, their scopes, and brief notes on when the runtime should load each topic's recall card._

_Scope:_ `main` — this file is loaded only in direct owner chats. Never in shared channels, never visible to sub-agents or guest operators._

## How memory works here (one-paragraph summary)

You wake up fresh each session. These files are your continuity. **Three tiers:** the **working** memory is what the runtime injects into the current turn (retrieval hits + active-note context — ephemeral). The **short-term** memory is `memory/daily/YYYY-MM-DD.md` — append-only, you write to it during heartbeats and whenever something notable happens. The **long-term** memory is `memory/topics/<topic>.md` — one file per topic, curated by the distillation pass. For entry schema, see [memory/FORMAT.md](memory/FORMAT.md).

## Active topics

_(List each topic file under `memory/topics/` here. Each row declares the topic's scope, a one-line description, and whether its recall card should auto-load in main sessions. Add topics as they emerge from distillation — don't pre-create empty topic files.)_

| Topic | File | Scope | Auto-load recall card? | Description |
|---|---|---|---|---|
| _(none yet)_ | _(none yet)_ | _(none yet)_ | _(none yet)_ | _(none yet)_ |

<!-- PLACEHOLDER: populate this table as topics get distilled. Example row for reference:
| operators  | memory/topics/operators.md  | main      | yes | Who the owner(s) are, relationships, key context -->

## Loading rules

The runtime (once it exists) decides what to pull into the system prompt based on the rules below. Document them here; enforce them later.

- **Always-load in main session:** any topic row marked `auto-load: yes`. These are the hot-state recall cards that make the agent feel continuous. Keep this list short — 3–6 topics max.
- **On-demand only:** topics marked `auto-load: no` are retrieved only when the conversation surfaces a relevant keyword or the agent explicitly queries `memory_search`.
- **Never in shared/untrusted:** topics scoped `main` or `owner-only` never appear in sub-agents, shared channels, or untrusted operator sessions. The `ZonePolicy` enforces this — but you should also treat the scope tag as law when hand-assembling prompts today.
- **Daily files (`memory/daily/*`) are not auto-loaded.** They're the append stream; the distillation pass promotes from them into topics.

## Writing to memory

- **During a session:** when something is worth remembering, append an entry to `memory/daily/YYYY-MM-DD.md` using the schema in [memory/FORMAT.md](memory/FORMAT.md). Never edit past entries — corrections go as new entries with `supersedes:` set.
- **Between sessions:** the distillation job (future — driven by [memory/DISTILL.md](memory/DISTILL.md)) reads recent daily files, decides what's worth promoting, and appends to the relevant topic files. The job also refreshes each topic's **recall card** — the 5–10-bullet hot-state summary at the top of each topic file.
- **Commit discipline:** every memory write is a git commit. The vault is the audit log. The owner can revert any memory change with `git revert`.

## What not to put in memory

Memory is for things that inform future turns. Skip:

- **Ephemeral task state** — that's `TASKS.md` or conversation context.
- **Anything derivable from the code / vault** — file paths, recent changes, git history.
- **Patterns / style / glossary terms** — those have their own distilled files (`PATTERNS.md`, `STYLE.md`, `GLOSSARY.md`).
- **Passwords, tokens, raw secrets** — if a secret is worth remembering, remember the _location_ (keychain entry, 1Password item ID), not the value.

---

_This file is an index. The memory itself is in `memory/topics/`. See [memory/FORMAT.md](memory/FORMAT.md) for the entry schema._
