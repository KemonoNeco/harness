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

# Parse the hook input JSON robustly via python. Pretty-printed input,
# escaped quotes, and null values all confound sed; python handles them.
# If python is missing, fail open — we can't reliably identify the session.
py=""
if command -v python3 >/dev/null 2>&1; then
  py="python3"
elif command -v python >/dev/null 2>&1; then
  py="python"
else
  emit_empty
fi

parsed="$(printf '%s' "${input}" | "${py}" -c '
import json, sys, base64
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def b(x):
    return base64.b64encode((x or "").encode("utf-8")).decode("ascii")
print(b(d.get("session_id") or ""))
print(b(d.get("cwd") or ""))
' 2>/dev/null || true)"

[[ -z "${parsed}" ]] && emit_empty

decode_line() {
  printf '%s' "${parsed}" | awk -v n="$1" 'NR==n{print}' | base64 -d 2>/dev/null || true
}
session_id="$(decode_line 1)"
cwd="$(decode_line 2)"

if [[ -z "${session_id:-}" ]]; then
  emit_empty
fi

# Resolve soul root. Prefer explicit cwd from input; fall back to PWD.
root="${cwd:-${PWD}}"
# Normalise Windows paths: collapse double-escaped backslashes, then convert
# the remaining backslashes to forward slashes so bash glob/test operators
# behave consistently.
root="${root//\\\\/\\}"
root="${root//\\//}"

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

# JSON-escape via python (already proven available above).
escaped="$(printf '%s' "${combined}" | "${py}" -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))' 2>/dev/null || true)"
if [[ -z "${escaped}" ]]; then
  emit_empty
fi

# Emit first, then mark the session as injected — only on successful write.
# If printf fails (closed stdout, disk full, interrupted), leave the marker
# absent so the next prompt in this session gets another chance to inject.
if printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "${escaped}"; then
  : > "${marker}" 2>/dev/null || true
fi
