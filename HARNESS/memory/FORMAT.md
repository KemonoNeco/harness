<!-- scope: all | author: framework | spec-version: 1 -->
# memory/FORMAT.md — Memory Entry Specification

_This is the canonical spec for every memory entry across the three tiers. Written once, referenced by everything. The future distillation job, retrieval layer, and scope enforcer all parse this format — so don't deviate without updating this file and the tooling in the same commit._

## Design goals

1. **Entry-level granularity.** Every discrete fact is individually addressable. Retrieval returns semantic units, not arbitrary chunks.
2. **Stable identifiers.** Cross-references are deterministic — `[[daily/2026-04-01#14:32]]` always resolves to the same entry.
3. **Machine-readable metadata without breaking human readability.** HTML comments hold structured fields; prose stays prose.
4. **Append-only with a correction path.** History is never rewritten. Corrections supersede old entries by ID.
5. **Per-entry scope overrides file scope.** File-level scope is the default; individual entries can narrow or widen.
6. **Works today in plain markdown.** Obsidian preview renders correctly; `grep` audits work; no tooling required to read the files.

## File-level metadata (line 1 of every memory file)

Every file under `memory/` opens with a single HTML-comment line holding file-level metadata:

```markdown
<!-- scope: main | visible-to-subagents: false | author: agent | file-kind: daily -->
```

Fields:

- **scope** — `all | main | shared | owner-only | external | untrusted`. The default scope for entries in this file. Individual entries can override.
- **visible-to-subagents** — `true | false`. Whether spawned sub-agents inherit access to this file.
- **author** — `user | agent | framework | mixed`. Who is the primary writer.
- **file-kind** — `daily | topic | spec | index`. The structural role in the memory system.

## Daily files (`memory/daily/YYYY-MM-DD.md`)

Append-only logs. One file per day. The filename is the ISO date of the local day the entries were written.

### Entry shape

Every entry is a `##` heading followed by a short prose body and a trailing HTML-comment metadata block:

```markdown
## 14:32 [tag:trading] [tag:tai] [refs:alpaca-188222846] XLE stop triggered
8 shares XLE stopped out at $59.00. Iran/oil thesis still active.
Next decision: april 6 ceasefire binary.
<!-- id: 2026-04-01T14:32:00-07:00
     operator: tai
     session: discord-dm-tai
     scope: main
     conf: observed
     supersedes: 2026-03-30T08:15:00-07:00 -->
```

### Heading grammar

```
## HH:MM [tag:X]* [refs:Y]* <short title>
```

- **`HH:MM`** — local time in 24-hour format. Seconds go in the metadata `id` if needed.
- **`[tag:X]`** — zero or more inline tags. Greppable. Tags are lowercase, hyphen-separated. Common tags: `trading`, `lesson`, `workspace`, `user`, `health`, `decision`, `external`.
- **`[refs:Y]`** — zero or more references to external systems or accounts. Examples: `[refs:alpaca-188222846]`, `[refs:linear-INGEST-42]`, `[refs:github-issue-14]`. Use this when the entry touches something with an external ID you'll need to correlate later.
- **`<short title>`** — 3–10 words. The summary you'd want to see in a retrieval hit before deciding whether to read further.

### Body

One short paragraph (2–6 sentences) or a short bullet list. Longer than that → promote to a topic file instead of bloating the daily log. The body should stand alone — someone reading it cold should understand what happened without needing the surrounding entries.

### Metadata block (HTML comment, immediately after body)

```
<!-- id: 2026-04-01T14:32:00-07:00
     operator: tai
     session: discord-dm-tai
     scope: main
     conf: observed
     supersedes: 2026-03-30T08:15:00-07:00
     expires: 2026-07-01 -->
```

Required fields:

- **id** — ISO 8601 timestamp with offset, or a content hash (`sha256:abc123...`) for facts without a specific moment. This is the stable identifier; never change it.
- **operator** — the operator whose action or statement the entry records. Matches operators listed in `USER.md`. Use `system` for agent-authored observations and `framework` for distillation output.
- **scope** — overrides file scope. Use one of `all | main | shared | owner-only | external | untrusted`.

Optional fields:

- **session** — opaque session identifier (`discord-dm-tai`, `main-session-2026-04-01`, `cron-flight-price-watch`). Lets retrieval filter by origin.
- **conf** — confidence / provenance: `observed` (the agent saw it directly), `stated` (the operator said so — might be wrong), `hearsay` (third-party via another operator), `inferred` (agent's own deduction). Retrieval can weight by this.
- **supersedes** — the `id` of a prior entry this one replaces. The retrieval layer prefers the newest non-superseded entry.
- **expires** — ISO date after which the entry should be deprioritized by retrieval. Useful for time-bound facts ("conference next week," "temporary workaround until version 2.0").
- **refs** — URL or identifier of an external source backing the entry (a git SHA, a Jira ticket, a URL). Separate from `[refs:Y]` inline tags (which are for correlation); `refs:` in metadata is for provenance.

### Correcting a past entry

Never edit the old entry. Write a new one. Set `supersedes: <old-id>`. The new entry's timestamp marks _when the correction was made_, not when the underlying fact changed.

Example correction:

```markdown
## 16:48 [tag:trading] [tag:correction] XLE stop price was $59.04 not $59.00
Prior entry had the stop price wrong by $0.04. Re-checked the Alpaca fill.
<!-- id: 2026-04-01T16:48:00-07:00
     operator: system
     scope: main
     conf: observed
     supersedes: 2026-04-01T14:32:00-07:00 -->
```

## Topic files (`memory/topics/<topic>.md`)

One file per topic. Populated by the distillation pass, not directly edited in normal flow (user seeding is fine). Each topic file has three sections:

### Section 1 — File-level metadata (line 1)

Same as daily files, but with `file-kind: topic`.

### Section 2 — Recall card

A compact, human-and-LLM-scannable summary of the topic's current hot state. 5–10 bullets max. Rendered as a markdown blockquote so Obsidian formats it prominently. Regenerated on every distillation pass.

```markdown
> **Recall card** (hot state as of 2026-04-02)
> - Tai account #188222846: ~$911, cash 65.6%, SCHD+GLD only, XLE closed 2026-04-01
> - Jazz account #677577179: ~$1,431, -3.2%, LLY + SPY (FDA binary april 10)
> - Framework: 5-pillar scoring, iran-hormuz rule caps composite at -0.5
> - Fractional = DAY stops only, renew at market open
> - Conviction: 4/10 (defensive, awaiting april 6 outcome)
```

The recall card is what the runtime loads when the topic is **relevant but not deep-dive**. Short enough to include in the system prompt without budget anxiety.

### Section 3 — Historical entries

Append-only log of promoted daily entries, newest first. Grouped under `## updated YYYY-MM-DD` subheadings that mark distillation passes:

```markdown
## Historical entries

### updated 2026-04-02

#### 14:32 [tag:trading] [tag:tai] XLE stop triggered
(same shape as daily entries — heading + body + metadata block)

### updated 2026-04-01

#### 09:15 [tag:trading] [tag:framework] 5-pillar scoring locked in
...
```

Historical entries keep their original `id` (timestamp from the daily file). Promotion copies the entry verbatim; it doesn't rewrite.

## Stable-ID conventions

- **Event facts** — use the ISO 8601 timestamp of when the event happened, with local offset. `2026-04-01T14:32:00-07:00`.
- **Timeless facts** (e.g. a person's birthday, a machine's hostname) — use a content hash of the normalized fact. `sha256:` prefix + first 12 hex chars is enough. Recompute on meaningful content change (not on reformatting).
- **Distillation outputs** — use the distillation pass's ISO date + a content hash suffix. `2026-04-02-dist:sha256:abc123`.
- **Never reuse IDs.** Even for superseded entries, the old ID stays valid as a reference target.

## Cross-references

Use Obsidian wiki-link syntax against IDs:

- **Within the same file:** `[[#14:32]]` — references the entry whose heading starts with `## 14:32` in this file.
- **To another daily:** `[[daily/2026-04-01#14:32]]` — references the 14:32 entry in that day's file.
- **To a topic:** `[[topics/trading]]` or `[[topics/trading#2026-04-02]]` for a specific promotion.
- **To a timeless fact:** `[[topics/operators#sha256:abc123]]` — same anchor syntax, content-hash ID.

Obsidian resolves these in preview, gives you backlinks for free, and lets the future retrieval layer traverse the graph by walking Obsidian's link index rather than parsing prose.

## Per-entry scope examples

File-level `scope: main`, entry narrows to `owner-only`:

```markdown
## 22:10 [tag:health] [tag:private] doctor appointment result
<body>
<!-- id: ... | operator: user | scope: owner-only -->
```

File-level `scope: main`, entry widens to `all` (safe to surface in any session):

```markdown
## 10:00 [tag:workspace] [tag:infra] gateway bound to loopback:18789
<body>
<!-- id: ... | operator: system | scope: all -->
```

The runtime's `ZonePolicy` reads the entry-level scope first, falling back to the file-level scope if absent.

## Grep audits

Useful queries for hand-auditing memory health:

- **Every entry has an ID:** `grep -L "<!-- id:" memory/**/*.md` should return nothing except `.gitkeep` files.
- **No duplicate IDs:** `grep -rh "^<!-- id:" memory/ | sort | uniq -d` should be empty.
- **Every tag I'm looking for:** `grep -rn "\[tag:trading\]" memory/`.
- **Everything from a specific operator:** `grep -rn "operator: tai" memory/`.
- **Superseded chains:** `grep -rn "supersedes:" memory/` to audit correction history.

## What happens when tooling lands

This spec is stable. When the runtime retrieval layer, distillation job, and `ZonePolicy` ship, they consume this format verbatim — no schema migration, no re-chunking of prior entries. That's why the spec is written in full now, even before any of the tooling exists. Every daily entry written starting today contributes to the corpus the future retrieval layer will index.
