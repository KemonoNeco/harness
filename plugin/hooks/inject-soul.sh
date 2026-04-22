#!/usr/bin/env bash
# Harness soul injector — fires on UserPromptSubmit.
# Reads the live soul files from the session's cwd and returns their
# concatenation as `additionalContext` on the first prompt of each session.
# Subsequent prompts in the same session short-circuit via a marker file.
#
# Fail-open: any error (missing files, malformed input, write failures) exits 0
# with no additionalContext so sessions never break because of this hook.

set -uo pipefail

emit_empty() {
  printf '{"continue": true}\n'
  exit 0
}

input="$(cat || true)"
if [[ -z "${input}" ]]; then
  emit_empty
fi

# Extract session_id and cwd from the hook input JSON. Tolerate absence.
session_id="$(printf '%s' "${input}" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
cwd="$(printf '%s' "${input}" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

if [[ -z "${session_id:-}" ]]; then
  emit_empty
fi

# Resolve soul root. Prefer explicit cwd from input; fall back to PWD.
root="${cwd:-${PWD}}"
# JSON may double-escape backslashes on Windows paths; normalise.
root="${root//\\\\/\\}"

# Per-session idempotency marker.
data_dir="${CLAUDE_PLUGIN_DATA:-${root}/.claude/harness-plugin-data}"
marker_dir="${data_dir}/injected-sessions"
marker="${marker_dir}/${session_id}"
mkdir -p "${marker_dir}" 2>/dev/null || true
if [[ -f "${marker}" ]]; then
  emit_empty
fi

# Canonical soul bundle order — mirrors HARNESS/CLAUDE.md line 30.
files=(
  "${root}/HARNESS/IDENTITY.md"
  "${root}/HARNESS/SOUL.md"
  "${root}/HARNESS/USER.md"
  "${root}/HARNESS/BOUNDARIES.md"
  "${root}/HARNESS/MEMORY.md"
)
for f in "${files[@]}"; do
  if [[ ! -r "${f}" ]]; then
    # Partial repo — fail open so we don't brick the session.
    emit_empty
  fi
done

preamble=$'### Harness soul bundle (auto-injected)\n\nThe following five files are concatenated and injected at session start so your behaviour follows them without any manual paste. They are the live contents of the repository, not a frozen copy — treat them as a prefix to your system prompt.\n\n---\n\n'

bundle="$(cat "${files[@]}")"
combined="${preamble}${bundle}"

# JSON-escape the combined string. Use python if present (reliable on any
# platform); fall back to a sed pipeline that handles the common cases.
escape_json() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
  elif command -v python >/dev/null 2>&1; then
    python -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
  else
    # Minimal escaping: backslash, quote, control chars.
    sed -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g' \
        -e ':a;N;$!ba;s/\n/\\n/g' \
        -e 's/\r/\\r/g' \
        -e 's/\t/\\t/g' \
      | awk 'BEGIN{printf "\""} {printf "%s", $0} END{printf "\""}'
  fi
}

escaped="$(printf '%s' "${combined}" | escape_json)"
if [[ -z "${escaped}" ]]; then
  emit_empty
fi

# Mark session as injected only after we know we have content to return.
: > "${marker}" 2>/dev/null || true

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "${escaped}"
