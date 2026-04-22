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

# Parse the hook input via python (robust against escapes, multi-line values,
# null fields, pretty-printed JSON). If python isn't available at all we can't
# safely enforce; fall open.
py=""
if command -v python3 >/dev/null 2>&1; then
  py="python3"
elif command -v python >/dev/null 2>&1; then
  py="python"
else
  allow
fi

# Extract tool_name, file_path, old_string in one pass. Missing / null values
# become empty strings. Each field is base64-encoded on its own line so
# newlines or control chars inside `old_string` never corrupt the framing.
parsed="$(printf '%s' "${input}" | "${py}" -c '
import json, sys, base64
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
def b(x):
    return base64.b64encode((x or "").encode("utf-8")).decode("ascii")
print(b(d.get("tool_name") or ""))
print(b(ti.get("file_path") or ""))
print(b(ti.get("old_string") or ""))
' 2>/dev/null || true)"

[[ -z "${parsed}" ]] && allow

decode_line() {
  printf '%s' "${parsed}" | awk -v n="$1" 'NR==n{print}' | base64 -d 2>/dev/null || true
}
tool_name="$(decode_line 1)"
file_path="$(decode_line 2)"
old_string="$(decode_line 3)"

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
  if [[ "${old_string}" == *"<!-- id:"* ]]; then
    block "Harness: the memory contract is append-only. This Edit touches a past entry's metadata block (<!-- id: ... -->). Write a NEW entry with 'supersedes: <old-id>' in its metadata block instead. See HARNESS/memory/FORMAT.md §'Correcting a past entry'."
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
