#!/usr/bin/env bash
# Harness memory append-only enforcer — PreToolUse hook on Edit/Write.
# Blocks any mutation of a past memory entry. Past entries are identified by
# an `<!-- id:` marker in the existing file (or in Edit's `old_string`).
#
# Contract: exit 2 blocks the tool call and surfaces stderr to the model.
# Exit 0 allows the tool call. Exit 1 is a non-blocking warning (unused here).

set -uo pipefail

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

allow() {
  exit 0
}

input="$(cat || true)"
[[ -z "${input}" ]] && allow

tool_name="$(printf '%s' "${input}" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
file_path="$(printf '%s' "${input}" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

[[ -z "${tool_name:-}" ]] && allow
[[ -z "${file_path:-}" ]] && allow

# Normalise backslashes (Windows JSON escaping) and convert to forward slashes.
file_path="${file_path//\\\\/\\}"
file_path_fs="${file_path//\\//}"

# Only enforce inside HARNESS/memory/.
case "${file_path_fs}" in
  */HARNESS/memory/*) ;;
  *) allow ;;
esac

# Schema docs are never entry files — block any Edit/Write touching them.
case "${file_path_fs}" in
  */HARNESS/memory/FORMAT.md|*/HARNESS/memory/DISTILL.md)
    block "Harness: $(basename "${file_path_fs}") is a schema document, not a memory entry. Do not edit it as part of a memory write. If the schema itself needs to change, do it as a separate, deliberate commit outside a memory-write flow."
    ;;
esac

if [[ "${tool_name}" == "Edit" ]]; then
  # Extract old_string. Use python for robust JSON parsing when available;
  # fall back to a newline-tolerant sed for the common single-line case.
  old_string=""
  if command -v python3 >/dev/null 2>&1; then
    old_string="$(printf '%s' "${input}" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("old_string",""),end="")' 2>/dev/null || true)"
  elif command -v python >/dev/null 2>&1; then
    old_string="$(printf '%s' "${input}" | python -c 'import json,sys;d=json.load(sys.stdin);sys.stdout.write(d.get("tool_input",{}).get("old_string",""))' 2>/dev/null || true)"
  fi

  if [[ "${old_string}" == *"<!-- id:"* ]]; then
    block "Harness: the memory contract is append-only. This Edit touches a past entry's metadata block (<!-- id: ... -->). Write a NEW entry with 'supersedes: <old-id>' in its metadata block instead. See HARNESS/memory/FORMAT.md §'Correcting a past entry'."
  fi

  # Even without python, if the existing file has ids and Edit would rewrite
  # chunks containing them, block conservatively.
  if [[ -z "${old_string}" && -f "${file_path_fs}" ]] && grep -q "^<!-- id:" "${file_path_fs}" 2>/dev/null; then
    # We can't see old_string — fall open rather than block indiscriminately.
    :
  fi
  allow
fi

if [[ "${tool_name}" == "Write" ]]; then
  # Write to a non-existent file (creating a new daily) is fine.
  if [[ ! -f "${file_path_fs}" ]]; then
    allow
  fi
  # Write to an existing file that has no entries (empty placeholder) is fine.
  if ! grep -q "^<!-- id:" "${file_path_fs}" 2>/dev/null; then
    allow
  fi
  # Existing file with entries → Write would overwrite past entries. Block.
  block "Harness: '${file_path_fs}' already contains memory entries. Writing over it would destroy the append-only log. Use Edit to append a NEW entry at the end of the file instead."
fi

allow
