# A framework brainstorm for soul-driven, Obsidian-native agents

The strongest framework you can build sits at an unfilled seam in the current ecosystem: **an agent whose soul is a pile of markdown, whose body is a Rust daemon, and whose world is your Obsidian vault** — and which can either run its own model *or* step aside and let Claude Code wear it like a costume. OpenClaw proved the markdown-identity paradigm at massive scale (361k stars) but treats the filesystem as a flat workspace; IronClaw reimplemented the same ideas in Rust with WASM sandboxing but is a clone, not an evolution; pi-mono shrank the runtime to ~200 lines of core loop and pushed everything into user-editable files; and none of them treat a **personal knowledge management vault as the agent's native habitat**. That gap is your opening. What follows is a design document for a framework whose working name I'll argue below should be **Golem** (alternatives at the end), built in Rust, borrowing liberally from all four precedents.

## What the claw ecosystem actually taught us

Before architecture, a compressed read of the research. OpenClaw is a TypeScript monorepo built on Mario Zechner's `pi-agent-core` (so pi-mono is literally inside OpenClaw's belly); its central invention is a bundle of plain markdown files — `SOUL.md`, `AGENTS.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `MEMORY.md`, `HEARTBEAT.md`, `BOOT.md`, `BOOTSTRAP.md` — concatenated into the system prompt every turn, with per-file (20 KB) and total (150 KB) character caps, no YAML frontmatter, scope rules (`MEMORY.md` is never visible to sub-agents), and an explicit boot sequence in `AGENTS.md` that declares which files load when. Runtime is a long-lived launchd/systemd daemon ("Gateway") binding loopback-first at `ws://127.0.0.1:18789` with Ed25519-signed pairing for remote nodes; the agent loop is serialized per-session with three queueing modes (`steer` interrupts at the next tool boundary, `followup` waits for "done," `collect` batches). Memory is SQLite + FTS5 + `sqlite-vec` with weighted score fusion and MMR reranking; a silent agent turn flushes context to files before auto-compaction. IronClaw is the NEAR AI Rust rewrite — same soul-file contract, but PostgreSQL+pgvector for multi-user, **WASM tools and WASM channels** via wit-bindgen with credential injection at the host boundary, capability-based sandboxing, and private inference as the default model (`nearai` provider, Tinfoil attestation). Pi-mono's innovations are **`Context = {systemPrompt, messages, tools}` as a single serializable JSON blob**, a typed `streamFn` seam between runtime and provider (swap real LLM / faux / HTTP proxy / replay), sessions stored as JSONL trees keyed by `id`/`parentId` so branching is free and history is preserved, and split tool results (`content` for the LLM, `details` for UI). The closest working Obsidian integrations in that ecosystem (`oscarhenrycollins/obsidianclaw`, `humanitylabs-org/obsidianclaw`) are thin sidebars that pair with the Gateway over WebSocket; nothing deeply integrates the agent into a PKM vault as a first-class inhabitant. **That is the whitespace to occupy.**

## The core thesis: a golem animated by markdown, housed in a vault

Think of the framework as three concentric things. The **soul** is pure markdown — identity, style, memory, checklists — that the user can read, grep, diff, and hand-edit. The **body** is a Rust daemon that embodies the soul by assembling it into a system prompt, routing channels, executing tools, indexing memory, and running heartbeats. The **world** is an Obsidian vault, structured so that agent zones and user zones interleave, so the agent lives in the same knowledge graph the user thinks in. The framework's novel claim is that **a PKM vault is a dramatically better workspace than a flat `~/.openclaw/workspace` directory** because links, daily notes, tags, and canvases are all semantic structure the agent can traverse and extend, and the user's own writing style is continuously observable as ground-truth training signal for the agent's voice.

## Architecture overview and data flow

Four major subsystems compose the daemon, with a fifth living inside Obsidian. The **Soul Loader** watches `vault/agent/soul/*.md`, parses a declarative boot manifest, assembles the system prompt with scope rules, and hot-reloads on change (debounced ~250ms). The **Runtime** (the agent loop) takes an incoming turn, merges in context, calls either an embedded `LlmProvider` *or* hands off to Claude Code via passthrough (the duality explained below), streams tokens out, executes tools, and persists everything to a JSONL session tree. The **Gateway** is the control plane: a Tokio-based WebSocket server bound loopback-first with schema-generated clients, handling auth (Ed25519 pairing for nodes, shared-secret for HTTP), channel multiplexing, and per-session serialization with OpenClaw's three queue modes. The **Memory Engine** wraps SQLite + `sqlite-vec` + FTS5 behind a `MemoryBackend` trait, indexes markdown from configured vault paths with a `notify`-based watcher, and exposes `memory_search/read/write/tree` as tools. Inside Obsidian, the **Obsidian Gateway Plugin** (TypeScript, required because Obsidian plugins can only be TS/JS) is a thin bridge: it proxies vault events (file change, active file, selection) to the daemon over localhost WS, renders agent chat in a sidebar, draws agent zone boundaries visually, and surfaces agent suggestions as callouts or pending edits the user can accept.

Data flow for a typical turn: user sends a Discord DM → Gateway receives it, resolves to the user's default agent → enqueues on that agent's session lane → Runtime pulls next message, invokes Soul Loader to assemble current prompt (identity files + daily log from vault + top-k memory hits + relevant skill descriptions), streams to model, tool calls write into the vault via file tools, stream completes, session JSONL is appended, memory watcher reindexes changed files, Gateway delivers final message over Discord. In passthrough mode, the "stream to model" step becomes "hand the soul-bundle + message to Claude Code as `AGENTS.md` context and stream its output back."

## The soul file system

Keep OpenClaw's contract — plain markdown, no frontmatter on identity files, concatenated into the system prompt, scope rules — but make three significant improvements. **First, introduce a `soul.toml` boot manifest** (not markdown, deliberately) that declares which files load in which scopes, their char caps, and their ordering. This replaces OpenClaw's implicit convention where `AGENTS.md` narrates the boot sequence in prose. The manifest is the contract the daemon enforces; `AGENTS.md` becomes purely instructional for the model. Example:

```toml
[[load]]
file = "identity.md"; scopes = ["*"]; order = 10; max_chars = 4000

[[load]]
file = "soul.md"; scopes = ["*"]; order = 20; max_chars = 20000

[[load]]
file = "memory.md"; scopes = ["main"]; order = 90; max_chars = 20000
visible_to_subagents = false

[[load]]
file = "style.md"; scopes = ["*"]; order = 30; max_chars = 8000
auto_distilled = true  # framework writes this; user edits freely
```

**Second, separate user-authored soul files from framework-distilled ones.** `identity.md`, `soul.md`, `user.md`, `boundaries.md` are yours; `style.md`, `patterns.md`, `glossary.md` are written by the framework from your vault observations (see self-evolution below) and clearly marked. **Third, make composition explicit via `@include` directives** so a `soul.md` can pull in reusable fragments — a shared "be terse and opinionated" fragment, a shared tool-usage rubric — without forcing users to copy-paste. Skills remain AgentSkills-compatible (YAML frontmatter + body) so the existing skill ecosystem drops in; the framework should ship `skill-creator` and `workspace-auditor` skills modeled on the `win4r/openclaw-workspace` pattern.

The scope system is where you can genuinely improve on OpenClaw. Define **four scope dimensions** that compose: *session type* (main / sub-agent / group / heartbeat), *channel* (direct / discord / obsidian / cli), *trust* (owner / trusted / guest), and *context depth* (bootstrap / runtime / on-demand). `memory.md` with `scopes = ["main"]` and `trust = "owner"` prevents a guest in a Discord channel from triggering memory recall — a gap OpenClaw papered over with convention.

## The passthrough/daemon duality

The single most important architectural decision is how to handle "run on Claude Code vs run on a local model." Treat them as **two runtime backends behind a single `Embodiment` trait**, and design everything else to not care which is active. Concretely:

**Embodied mode** (daemon owns the loop): the daemon calls the model directly via a `LlmProvider` trait modeled on IronClaw's (Anthropic API, OpenAI, Ollama, llama.cpp via OpenAI-compat, Tinfoil, Bedrock). The daemon assembles the system prompt, runs the tool loop, handles streaming, manages sessions. This is the only way to work with local models or when Claude Code isn't installed, and the only way to run fully autonomously on a home server or cloud VM.

**Possession mode** (Claude Code drives): the daemon does *not* run the loop. Instead, when a turn comes in, it writes the assembled soul bundle + injected memory hits + user message into a scratch project directory, ensures an `AGENTS.md` composite is current, and spawns Claude Code as a subprocess in `--print` mode (or via Claude Code's SDK when stable) against that directory. It captures streamed output, feeds it back to whatever channel originated the turn, and observes tool calls as they touch the synced workspace. Crucially, the daemon in possession mode is still responsible for: channel fan-out (Discord, Obsidian sidebar, webhooks), workspace sync (keeping the Claude Code project directory mirrored with the live Obsidian vault), memory indexing, heartbeats, and session persistence. Claude Code is just the brain.

The hard part of possession mode is **workspace sync** — Claude Code wants to operate in a project directory, but the source of truth is the Obsidian vault. Solve this with an inotify/FSEvents-driven one-way-with-conflicts sync: the daemon watches the vault and mirrors changes into the Claude Code scratch directory before spawning; after the turn, any files Claude Code touched are diff-merged back into the vault, with conflicts surfaced as callouts in the active Obsidian note. A simpler first cut: just **bind-mount the vault directly** as Claude Code's cwd, scoped to the agent zones, and live with the constraint that possession-mode tool calls happen in-vault. This eliminates sync but requires tighter trust.

Another option worth designing for: a **Claude Cowork / MCP-server façade** where the daemon exposes memory, skills, and soul-context as MCP resources, and Claude Code consumes them via standard MCP. This is more invasive to integrate but gives possession mode access to the full memory engine without shelling out. I would ship bind-mount first, MCP façade second, subprocess-and-sync last.

The `Embodiment` trait itself is small:

```rust
#[async_trait]
pub trait Embodiment: Send + Sync {
    async fn turn(&self, session: &Session, input: Turn, tx: EventTx) -> Result<TurnEnd>;
    fn capabilities(&self) -> Capabilities; // streaming, tools, vision, etc
    fn name(&self) -> &str;                  // "anthropic", "ollama", "claude-code"
}
```

Everything above it (Gateway, Soul Loader, Memory, channels) talks to *this*, not to providers.

## Obsidian integration: zones, plugin, and the learning loop

The vault is the workspace, but the vault is also the user's PKM — the integration has to respect that. Adopt a **three-zone model** at the vault root:

Agent zones (daemon owns writes): `/agent/soul/`, `/agent/memory/`, `/agent/sessions/`, `/agent/skills/`, `/agent/canvas/`, `/agent/distilled/`. These are the files the daemon freely reads and writes; the user can hand-edit but should understand they're the agent's living parts. Shared zones (both write, explicit negotiation): `/inbox/`, `/daily/YYYY-MM-DD.md`, `/agent-scratch/`. Inbox is where users drop notes for the agent to act on; daily notes are collaborative logs the agent appends its own bullets to under its own heading; scratch is for in-progress collaborations. User zones (read-only for the agent by default): everything else — your projects, your research, your private notes. The agent indexes them for memory retrieval, but writes require a permission event that surfaces as an Obsidian modal.

**Enforce zones in the daemon**, not in prompting, via a `ZonePolicy` that wraps the write/edit tools. Make zones user-configurable in `soul.toml` so someone with a different vault layout can re-map.

The **Obsidian plugin** has to be TypeScript because Obsidian's plugin surface is TS-only, but keep it deliberately thin. Its responsibilities: run a WebSocket client that pairs with the daemon on localhost (Ed25519 challenge, same as OpenClaw nodes); render the agent chat sidebar (the agent's channel presence inside the vault); register commands for `/ask`, `/remember`, `/distill`; draw zone indicators (left gutter tint per zone); surface agent suggestions as pending-edit callouts with accept/reject buttons; subscribe to vault events (`modify`, `create`, `delete`, `active-leaf-change`) and forward them to the daemon so the agent has real-time awareness of what you're working on. The heavy lifting — indexing, memory, style analysis, soul composition — stays in Rust.

The integration depth that differentiates this framework from anything extant is **active awareness**: because the plugin forwards `active-leaf-change` events, when you're working on note X the agent's next turn can inject "user is currently editing X, here are its backlinks and recent revisions" into the system prompt. Nothing in OpenClaw/IronClaw/pi-mono has this. It's the feature that makes the agent feel inhabited rather than queried.

Don't try to reimplement Dataview, Templater, or Canvas inside the daemon. Instead, **expose them as tools** by shelling out through the plugin: the daemon's `dataview_query` tool sends a query over WS, the plugin runs it in-Obsidian, returns results. Same for rendering canvases, resolving `[[wikilinks]]`, reading frontmatter. The plugin becomes a privileged tool server for Obsidian-native operations.

## Discord gateway and the multi-surface design

Model channels as adapters over a uniform `Channel` trait, the way OpenClaw does. A Discord adapter (Rust `serenity` or `twilight-rs` — twilight is cleaner for this kind of gateway work) lives in its own crate, subscribes to DM and allowlisted-guild messages, maps `(guildId, channelId, userId)` to an agent + session lane, and dispatches turns. Borrow two specific pi-mom patterns that work: **channel = session scope** (each Discord channel gets its own session lane and workspace subdirectory under `vault/agent/sessions/discord/<guild>/<channel>/`), and **thread-based UI separation** (the clean response goes as the main message, verbose tool-call detail goes as thread replies so the channel isn't spammed). Add pairing (`/pair` slash command generates a code, user runs `golem pair <code>` on the daemon CLI, Ed25519 keypair exchanged) so the bot can only be commanded by paired users by default. Use Discord's components (buttons, select menus) for common workflows — "approve this edit," "distill today's notes" — rather than forcing natural language through a slash-command bottleneck.

Design the Gateway so adding a Slack or Matrix or iMessage adapter is ~300 lines of `Channel` implementation, not an architectural change. IronClaw's WASM-channels idea is further down this road — third-party channel plugins sandboxed in wasmtime — and worth a v2 roadmap item, but v1 should be native Rust adapters for velocity.

## Self-evolution and learning from the user

Self-evolution is the most failure-prone feature to design here; get the loop right or the agent will drift, hallucinate rules, and eventually corrupt its own soul. Steal a specific pattern from `win4r/openclaw-workspace`: **distillation is a scheduled job that runs on a checklist, not a free-form self-modification loop.** The heartbeat scheduler (default 30 min, configurable) reads `vault/agent/soul/heartbeat.md`, which contains concrete checkable items like "if daily log has >10 new bullets, run summary skill" or "if any iron-law violations in last 24h, append note to memory." The agent proposes edits to soul files but does not commit them without user sign-off — surface proposals as pending-edit callouts in Obsidian.

For **writing-style learning**, run a weekly batch job that samples N recent user-zone notes (excluding code, including prose), extracts style features (sentence length distribution, tag usage patterns, vocabulary quirks, heading conventions, linking density, preferred call-outs, rhythm of lists vs prose), and produces a `distilled/style.md` that gets included in the soul bundle. Keep it observable: the file literally says "I notice you average 18-word sentences, favor em-dashes over parens, tag everything with `#type/` prefixes, and never use exclamation points outside quoted text." The user can edit, and those edits become reinforcement.

For **note-management learning**, index folder structure and link patterns: does the user link hubs-and-spokes or chains? Does the user file before or after writing? Do tags stabilize in a taxonomy? This goes into `distilled/patterns.md` which informs the agent's own note-creation behavior in shared zones.

For **memory consolidation**, adopt OpenClaw's daily → memory pipeline: append-only daily logs at `vault/agent/memory/YYYY-MM-DD.md`, weekly distillation into topical notes in `vault/agent/memory/topics/`, and hand-curated iron-laws in a single `memory.md` (main-session-only, never visible to sub-agents or guest channels). Before any auto-compaction, run OpenClaw's silent flush-turn — it's a proven pattern and costs little.

Critically: **make evolution reversible.** The entire vault is a git repo with the daemon auto-committing on a schedule. Any soul edit, any distillation, any memory promotion is a commit the user can revert with a standard git undo. This is not hypothetical safety; it's the actual mechanism that makes users trust a self-modifying system.

## Tech stack recommendations (Rust-first)

The research nudges strongly toward Rust for the body, with TypeScript only where the runtime forces it (Obsidian plugin). A concrete stack:

| Layer | Choice | Reason |
|---|---|---|
| Async runtime | `tokio` | Ecosystem default; channel adapters need multiplexed I/O |
| WebSocket | `tokio-tungstenite` + `axum` for HTTP/WS hybrid | Matches IronClaw; `axum` gives Gateway REST for free |
| Schema/RPC | `schemars` + `serde_json` → JSON Schema → TS/Swift clients | Emulates OpenClaw's TypeBox generator pattern |
| DB | `rusqlite` + `sqlite-vec` + FTS5 | Exact OpenClaw memory stack; zero-ops for personal scale |
| File watch | `notify` (v6+) | Standard; has FSEvents/inotify/ReadDirectoryChangesW |
| LLM providers | Roll own `LlmProvider` trait with direct `reqwest` calls per-provider | Matches pi-mono's rationale: SDKs paper over the variability you need control over |
| Model catalog | Scrape OpenRouter+models.dev at build, codegen `models.rs` | pi-mono's pattern |
| Discord | `twilight-rs` | Cleaner separation than `serenity` for gateway-style use |
| WASM (future) | `wasmtime` + `wit-bindgen` | IronClaw's proven choice |
| Config | `serde` + TOML for user config, JSON for wire | Human for soul.toml, machine for session state |
| CLI | `clap` v4 with derive + subcommands | Obvious |
| Tracing | `tracing` + `tracing-subscriber` | Instrument the loop, export to file per session |

The Obsidian plugin uses the standard `obsidian-plugin-api` TypeScript stack with esbuild; keep it < 2000 LOC by pushing logic back to the daemon over WS.

For **Claude Code passthrough**, the initial implementation is `std::process::Command` spawning `claude` with `--print` and a prepared project dir; when Anthropic ships a stable SDK or the existing one stabilizes in Rust bindings, migrate. For **local models**, default to OpenAI-compatible endpoint shape so anything (Ollama, llama.cpp, LM Studio, vLLM, TGI) works with the same provider.

Two deliberate non-choices worth naming: **don't build MCP client support in v1** — pi-mono's argument against MCP (token bloat, opaque behavior, worse than well-documented CLI tools) is sound for a personal-scale harness, and skills cover the same ground more transparently. Add it later if users demand it. And **don't build multi-tenant from day one** — the IronClaw PostgreSQL multi-user story solves a problem you don't have; stay single-user with SQLite and let that constraint sharpen the product.

## Naming and project identity

The name should say *animation via written word*. My strong recommendation is **Golem**: in Jewish mythology a golem is a clay figure brought to life by inscribing a word on a paper (shem) and placing it in its mouth — **this is literally what a soul file does to an agent**. The metaphor is unusually exact, the word is memorable and short, it's not already taken by a major AI framework (some Ethereum-adjacent project used Golem Network but that's dormant and in a different domain — check current trademark status before committing), and it gives you a visual identity (unfired-clay beige, hand-inscribed letterforms). CLI name `golem`, config `golem.toml`, vault folder `/golem/`, daemon `golemd`, Discord handle `@golem`. A golem serves and can be dismissed; it does not pretend to be more than it is. That posture matches the design philosophy.

Runner-up names if Golem is unavailable or feels too heavy: **Familiar** (witch's companion that learns its human — strong metaphor for the learning loop, but softer and more whimsical); **Homunculus** (alchemical created being — accurate but a mouthful); **Tulpa** (mind-made companion — strong but has occult-internet baggage); **Shem** (the paper/word itself — extremely on-the-nose but niche); **Codex** (the PKM-book framing — collides with OpenAI Codex); **Hearth** (the warm-home framing — nice but less evocative of animation). Avoid anything "-claw" or "-paw" because it signals derivative rather than successor.

## Open questions and risks to think through

Several design decisions will bite if not resolved before coding begins, and several risks need mitigation plans rather than solutions.

**On the passthrough/embodied duality**: does the daemon share sessions across both modes, or are they separate session spaces? I'd argue share-by-default — the user should be able to start a turn on a local model and continue on Claude Code without losing context — but this requires the JSONL session format to be provider-agnostic (which it already is in pi-mono's design, so adopting their format solves it). What happens when Claude Code's tool set diverges from the daemon's? You need a capability negotiation step and a "this session is pinned to embodiment X" flag on serialized sessions.

**On Obsidian as source of truth**: Obsidian itself is closed-source, has no official sync protocol, and occasionally changes plugin APIs. Building the agent's identity inside Obsidian creates platform risk. Mitigation: the vault is just a directory of markdown; if Obsidian disappears, Logseq/Silverbullet/Zettlr work on the same files; the plugin is the only component that dies. Design the daemon so the plugin is optional — a `--no-obsidian` mode should be fully functional via CLI + Discord, with the vault still present as plain files.

**On soul-file hijacking**: the ClawSec research on SOUL.md-hijack scenarios is real — a malicious tool output or channel message can write into `soul/memory.md` and then be loaded as trusted instruction next turn. Mitigation: the `ZonePolicy` must treat writes to soul/ as requiring explicit confirmation; `chmod 444` is offered as a hardening option; memory writes from untrusted channels go into a `pending/` subfolder for review.

**On style-learning feedback loops**: if the agent learns to write like you and then you start learning to write like it, you get degenerate convergence. Mitigation: sample the user zone only, exclude agent-authored files from style corpus, surface the distilled style.md for user review before it takes effect.

**On Claude Code passthrough going stale**: Anthropic ships Claude Code updates weekly; subprocess invocation contracts change; stdout format changes. Mitigation: pin a tested Claude Code version in config, run a smoke-test turn on daemon startup, degrade gracefully to embodied mode with a warning if passthrough breaks.

**On scope enforcement vs agent usefulness**: too-strict zones will make the agent feel cramped; too-loose and it scribbles on your research notes. Mitigation: start conservative (agent zones writable, shared zones append-only, user zones read-only) and add a `scope_overrides.toml` for users who want to loosen per-folder.

**On heartbeat spam**: OpenClaw's default 30-min heartbeat plus auto-distillation will, over a year, produce thousands of commits and potentially many notifications. Mitigation: `HEARTBEAT_OK` silent return as default; notifications only on findings; weekly commit squash; user can see a weekly digest note of what the agent did while they weren't looking.

**On the unknowns**: `KemonoNeco/openclaw-workspace` could not be located by research — it may be private, renamed, or deleted. If the user has access to it, its contents likely include specific zone conventions worth adopting; the closest public analog (`win4r/openclaw-workspace`) is documented above and provides strong patterns. Also worth resolving before v1: whether to ship the WASM tool sandbox from day one (IronClaw's hardening) or defer it — I'd defer because it's a large engineering investment and the daemon runs on the user's own machine with their own trust assumptions.

## Closing synthesis

The four-repo research converges on a surprisingly consistent architecture that no one has quite combined into the right shape: markdown soul files (OpenClaw's contribution), Rust-native sandbox-forward daemon (IronClaw's contribution), minimal-core-with-pushed-out-concerns discipline (pi-mono's contribution), and **PKM-native knowledge habitat** (nobody's contribution yet, your opening). Build Golem in Rust with a single `Embodiment` trait abstracting over "local model loop" and "Claude Code subprocess"; keep the soul as user-owned markdown governed by a small TOML manifest; make the Obsidian vault the workspace with zone policy enforced in the daemon and realtime awareness via a thin TS plugin; reuse the SQLite+FTS5+sqlite-vec memory stack verbatim from OpenClaw because it's proven; adopt pi-mono's JSONL session tree format because it's the cleanest durable format going; design Discord as one adapter on a `Channel` trait that also fits Slack, Matrix, and future WASM channels; make self-evolution checklist-driven and git-reversible, not free-form. If you ship the first vertical slice as `golemd` + a CLI + a minimal Obsidian plugin + soul-file loading + embodied-mode with Anthropic + passthrough-mode via subprocess + SQLite memory + file-based sessions, you have something genuinely novel in eight weeks. Discord, heartbeat, style distillation, WASM sandbox are v2. The thing that will make it take off isn't the Rust or the Discord or the sandbox — it's the moment a user realizes their Obsidian vault just started writing back with their own voice, and every edit the agent made is sitting in git, ready to revert.