<!-- scope: main | author: framework | file-kind: spec -->
# memory/DISTILL.md — Distillation Checklist (placeholder)

_This file is a stub. It will eventually hold the checklist the heartbeat-scheduled distillation job runs against the recent `memory/daily/*` files to promote worth-keeping entries into `memory/topics/*`. The job is checklist-driven (not free-form self-modification) per [HARNESS_Research.md §"Self-evolution and learning from the user"](../HARNESS_Research.md)._

## Status

- **Runtime:** not yet built (awaits the Harness daemon).
- **Schedule:** TBD (target: run as a heartbeat task every 24 hours over the prior day's daily file).
- **Outputs:** promotions into `memory/topics/<topic>.md` + refreshed recall cards.
- **Reversibility:** every distillation run is a single git commit. The owner can revert with standard `git revert`.

## What the checklist will eventually contain

_(These are targets, not yet implemented. Each becomes a concrete checklist item when the distillation job ships.)_

- For each new entry in the prior day's daily file:
  - Skip entries tagged `[tag:ephemeral]` or with `conf: inferred` and no corroboration.
  - Classify by primary topic (match against `MEMORY.md`'s topic table).
  - If no matching topic exists but the same classification appears ≥3 times, propose a new topic to the owner (don't auto-create).
  - Copy the entry verbatim into the target topic file under a `### updated YYYY-MM-DD` subheading.
- After all promotions for the day:
  - Regenerate the recall card at the top of each touched topic file.
  - The new recall card should reflect the topic's current hot state: 5–10 bullets, newest-state-wins, deprioritize entries where `expires:` has passed or `supersedes:` chains have later entries.
- Emit a single summary entry into today's daily file describing what was promoted (so the distillation pass is itself auditable in the memory log).
- Commit to git with message `distill: YYYY-MM-DD — N promotions across M topics`.

## Why this file exists now

Shipping the checklist placeholder before the job is built locks the contract. When the distillation job is implemented later, it reads this file as its spec. Keeping the spec and the implementation in the same repo means contract drift is visible as a diff.

---

<!-- PLACEHOLDER: full checklist will land when the distillation job is scheduled for implementation -->
