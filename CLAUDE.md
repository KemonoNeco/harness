# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

HARNESS is a **soul-driven AI agent framework** — currently a markdown-first design specification and prompt scaffold. The eventual runtime is a Rust daemon (`golemd`) + TypeScript Obsidian plugin, not yet implemented. Today, the framework is used by concatenating soul files into a system prompt.

The full architecture is documented in `HARNESS_Research.md` (27 KB). `HARNESS/README.md` is the practical overview.

## Commands

There is no build system yet (no package.json, Cargo.toml, etc.). The framework is used directly as markdown.

To assemble a system prompt from soul files:
```bash
cat HARNESS/IDENTITY.md HARNESS/SOUL.md HARNESS/STYLE.md HARNESS/USER.md HARNESS/BOUNDARIES.md HARNESS/MEMORY.md > /tmp/system-prompt.md
```

The canonical concatenation order (will be formalized in a future `soul.toml`) is:
`IDENTITY.md → SOUL.md → STYLE.md → USER.md → BOUNDARIES.md → MEMORY.md`

## Architecture

### Three Layers

**Layer 1 — Soul Files** (`HARNESS/*.md`)
Plain markdown files that define an agent's identity. Two axes:
- *Scope*: `all` (every session) vs. `main` (owner-direct only) vs. others — see scope table below
- *Authorship*: user-authored (`IDENTITY`, `SOUL`, `USER`, `BOUNDARIES`, `MEMORY`) vs. framework-distilled (`STYLE`, `PATTERNS`, `GLOSSARY`)

Every file starts with a line-1 HTML comment for machine-greppable metadata:
```html
<!-- scope: all | author: user | regenerate: false | ... -->
```

**Layer 2 — Memory System** (`HARNESS/memory/`)
Three tiers:
- *Working*: ephemeral, injected per turn (runtime will manage)
- *Short-term*: `memory/daily/YYYY-MM-DD.md` — append-only daily logs
- *Long-term*: `memory/topics/<topic>.md` — curated distilled entries

All entries follow the canonical schema in `memory/FORMAT.md`: HTML-comment metadata blocks with stable ISO 8601 IDs, append-only with `supersedes:` chains for corrections, and Obsidian wiki-links for cross-references.

**Layer 3 — Future Runtime** (not yet implemented)
Rust daemon subsystems: Soul Loader, Agent Loop, Gateway (WebSocket + Ed25519), Memory Engine (SQLite + FTS5 + sqlite-vec). TypeScript Obsidian plugin for vault sync. Multi-channel support: Discord, Obsidian, Claude Code passthrough, CLI.

### Scope System

| Scope | Meaning |
|-------|---------|
| `all` | Every session, every channel, always loaded |
| `main` | Direct owner chats only |
| `shared` | Multi-operator sessions |
| `owner-only` | Sole audience (stricter than `main`) |
| `external` | External actions (emails, posts, API calls) |
| `untrusted` | Non-owner operators / guests |

### Passthrough/Daemon Duality

The core abstraction is a single `Embodiment` trait:
- **Embodied mode**: daemon calls the model directly (full autonomy)
- **Possession mode**: Claude Code is the brain, daemon is the subprocess with workspace sync

### Vault Zone Model (for future Obsidian plugin)

- *Agent zones* (daemon writes): `/agent/soul/`, `/agent/memory/`, etc.
- *Shared zones* (both write): `/inbox/`, `/daily/`, `/agent-scratch/`
- *User zones* (read-only for agent): everything else

### Key Invariants

- **Append-only memory**: no destructive edits; corrections use `supersedes:` chains; git is the audit log
- **No YAML frontmatter**: raw concatenation of files must just work
- **Scope as law**: scope tags are documentation today, hard contracts when runtime enforcement lands
- **BOUNDARIES.md is first-class**: scope-tagged hard rules, never scattered in prose
