---
name: new-memory-entry
description: Scaffold a new memory entry in HARNESS/memory/ honoring the append-only schema in HARNESS/memory/FORMAT.md. Use when the operator wants to log an event, capture a decision, record a correction, or promote a daily entry. Also use whenever you (the agent) want to write to memory yourself.
---

# new-memory-entry

You are writing a new entry into the Harness memory system. Past entries are **immutable** — the plugin's `PreToolUse` hook will block any `Edit`/`Write` that mutates a historical `<!-- id: … -->` block. Corrections are always NEW entries that point at the old one via `supersedes:`.

Full spec: [HARNESS/memory/FORMAT.md](../../../HARNESS/memory/FORMAT.md). Read it before writing if anything below feels under-specified.

## Decide where the entry goes

- **Daily log** — `HARNESS/memory/daily/YYYY-MM-DD.md`. Default for event-shaped entries (something happened, a decision was made). Use the operator's local date.
- **Topic file** — `HARNESS/memory/topics/<topic>.md`. Only write here if the user explicitly asks for a topic promotion, or you're doing a distillation pass. Most of the time: daily log.

If the daily file doesn't exist yet, create it with a single line-1 file-level metadata comment:
```
<!-- scope: main | visible-to-subagents: false | author: agent | file-kind: daily -->
```
then append the first entry below it.

## Entry shape

```markdown
## HH:MM [tag:X] [tag:Y] [refs:Z] short title
Body: 2–6 sentences. Stands alone when read cold. Link to external refs if useful.
<!-- id: 2026-04-22T14:32:00-07:00
     operator: <who>
     session: <optional-session-id>
     scope: <all|main|shared|owner-only|external|untrusted>
     conf: <observed|stated|hearsay|inferred>
     supersedes: <optional-prior-id> -->
```

Rules to satisfy:

1. **`HH:MM`** heading prefix in 24-hour local time. Seconds go in `id`, not the heading.
2. **Tags** are lowercase, hyphen-separated, bracketed as `[tag:value]`. Zero or more per entry.
3. **Refs** are `[refs:external-id]` — Alpaca/Jira/GitHub/etc. correlation keys. Zero or more.
4. **Title** is 3–10 words, summary-first.
5. **Body** is a 2–6-sentence paragraph or a short bullet list. Longer than that → promote to a topic file.
6. **Metadata block** is a single HTML comment immediately after the body with:
   - `id` — ISO 8601 timestamp with offset for events, or `sha256:<first-12-hex>` for timeless facts. Never reuse an id.
   - `operator` — who the entry is *about* (matches `HARNESS/USER.md`). Use `system` for your own observations, `framework` for distillation output.
   - `scope` — required per-entry; overrides file scope. Pick the narrowest scope that's still accurate.
   - `conf` — optional but encouraged: `observed` / `stated` / `hearsay` / `inferred`.
   - `session` — optional. Useful for retrieval filtering later.
   - `supersedes` — optional. **Required when this entry corrects an earlier one.** Value is the old entry's `id` verbatim.
   - `expires` — optional ISO date. Use for time-bound facts ("conference next week").

## Writing the entry

1. Determine the target file path.
2. If it doesn't exist, use `Write` to create it with the line-1 file metadata comment + the new entry.
3. If it does exist, use `Edit` to **append** the new entry at the end of the file. `old_string` must match the final line(s) of the existing file (so you're adding, not overwriting). Never put an existing `<!-- id:` marker in `old_string` — that's the shape the hook blocks.
4. Verify: after the write, run `grep -rh "^<!-- id:" HARNESS/memory/ | sort | uniq -d` — it should return nothing. If it does, you collided with an existing id; regenerate the timestamp (bump the seconds) and write again.

## Correcting a past entry

Never edit the prior entry. Write a NEW entry:
- Give it a clear corrective title (e.g. "XLE stop price was $59.04 not $59.00").
- Put `supersedes: <prior-id>` in the metadata block. The prior id is pasted verbatim from the entry you're correcting.
- Set `operator: system` if you (the agent) discovered the error from your own re-check.

## Worked example (from FORMAT.md §"Correcting a past entry")

```markdown
## 16:48 [tag:trading] [tag:correction] XLE stop price was $59.04 not $59.00
Prior entry had the stop price wrong by $0.04. Re-checked the Alpaca fill.
<!-- id: 2026-04-01T16:48:00-07:00
     operator: system
     scope: main
     conf: observed
     supersedes: 2026-04-01T14:32:00-07:00 -->
```

## Don't

- Don't edit `HARNESS/memory/FORMAT.md` or `HARNESS/memory/DISTILL.md` — those are schema docs; the hook blocks writes there too.
- Don't skip the metadata block. An entry without `<!-- id: … -->` fails the repo's grep audits ([CLAUDE.md verification commands](../../../CLAUDE.md)).
- Don't collapse multiple events into one entry. Entry-level granularity is a design goal of the schema.
