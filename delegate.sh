#!/usr/bin/env bash
# delegate — run a non-interactive coding agent against a written spec, and
# catch the ways it silently does nothing.
#
#   ./delegate.sh <project-dir> <spec-path> [extra instructions...]
#
# The agent command is configurable (AGENT_CMD). Defaults to `codex exec`.
#
# Why this exists: a non-interactive agent run has failure modes that a human
# run does not, and every one of them looks like success from the outside.
# They are documented inline where each guard sits. Read them before you
# delete a guard.

set -uo pipefail   # NOT -e: we want to report and notify even when the agent fails.

# --- configuration -----------------------------------------------------------
AGENT_CMD="${AGENT_CMD:-codex exec}"
AGENT_EFFORT_FLAG="${AGENT_EFFORT_FLAG:--c model_reasoning_effort=high}"
AGENT_SANDBOX_FLAG="${AGENT_SANDBOX_FLAG:--s workspace-write}"
AGENT_CWD_FLAG="${AGENT_CWD_FLAG:--C}"
AGENT_ADDDIR_FLAG="${AGENT_ADDDIR_FLAG:---add-dir}"
# Header lines the agent prints that state its own effective config. We echo
# these back after the run — see guard 2.
AGENT_CONFIG_GREP="${AGENT_CONFIG_GREP:-^(model|reasoning effort|sandbox|approval):}"

# --- args --------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
  cat >&2 <<EOF
usage: $0 <project-dir> <spec-path> [extra instructions...]

  project-dir  repo or worktree the agent works in (absolute, or relative to \$PWD)
  spec-path    the written spec, relative to project-dir

env:
  AGENT_CMD              agent invocation (default: "codex exec")
  DELEGATE_WEBHOOK       optional Discord/Slack-compatible webhook for results

exit codes:
  0   agent finished and changed something
  64  bad usage
  65  agent exited 0 but changed nothing  <-- the important one
  66  project or spec not found
  *   the agent's own exit code
EOF
  exit 64
fi

PROJECT_ARG="$1"; shift
SPEC="$1"; shift
EXTRA="${*:-}"

[[ "$PROJECT_ARG" = /* ]] && PROJECT="$PROJECT_ARG" || PROJECT="$PWD/$PROJECT_ARG"
[[ -d "$PROJECT" ]]        || { echo "no such project: $PROJECT" >&2; exit 66; }
[[ -f "$PROJECT/$SPEC" ]]  || { echo "no such spec: $PROJECT/$SPEC" >&2; exit 66; }

RUN_DIR="$PROJECT/.delegate-runs"
mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/$(date +%Y%m%d-%H%M%S)-$(basename "${SPEC%.md}").log"

notify() {
  [[ -z "${DELEGATE_WEBHOOK:-}" ]] && return 0
  python3 - "$DELEGATE_WEBHOOK" "$1" "$(printf '%s' "$2" | head -c 1700)" <<'PY' 2>/dev/null || true
import json, sys, urllib.request
url, title, body = sys.argv[1], sys.argv[2], sys.argv[3]
req = urllib.request.Request(
    url,
    data=json.dumps({"content": f"**{title}**\n```\n{body}\n```"}).encode(),
    # A default urllib User-Agent is rejected with 403 by some webhook hosts.
    headers={"Content-Type": "application/json", "User-Agent": "curl/8.7.1"},
)
urllib.request.urlopen(req, timeout=15).read()
PY
}

# --- the prompt --------------------------------------------------------------
# Rules that live only in a project instructions file get forgotten in a long
# run. Re-assert the load-bearing ones on every delegation; it costs nothing and
# the failure it prevents is expensive.
PROMPT="Read $SPEC and execute it exactly as written.

Commit inside THIS directory when you are done. Do not switch branches.

Do NOT ask for approval before acting. This is a non-interactive run — there is
nobody to answer you. If the spec is contradictory or empty so that you cannot
proceed, do not ask: write down what blocks you and stop.

--- three rules that get forgotten in long runs ---

[1] Quantify. Any verification-shaped statement opens with
    \`verified n% (numerator/denominator)\`. State the denominator and how you
    cut it. Words like 'verified' without a denominator are not a marker.
    What you did not look at, say so. Numbers from elsewhere: label as reported.

[2] The completion report is commands and their output, not prose:
    ## What I did / ## Commands run / ## Anything unexpected / ## Deviations
    ## What I could not verify
    A passing test suite is NOT evidence the work happened — when nothing
    changes, tests always pass.

[3] Ask about design, never about procedure.
    ASK:       contradictory spec, undefined expected behaviour, work that
               needs to go outside the stated scope, deleting files.
    DON'T ASK: branch, commit, file location, code style, comment language.
    Adding a dependency is forbidden — stop and report instead."

[[ -n "$EXTRA" ]] && PROMPT="$PROMPT

$EXTRA"

# --- guard 1: worktree git metadata ------------------------------------------
# In a git worktree, .git is a FILE pointing at the parent repo's
# .git/worktrees/<name>/. A sandbox that only opens the working directory will
# let the agent edit files and then fail at commit time with:
#   fatal: Unable to create '.../.git/worktrees/<name>/index.lock':
#          Operation not permitted
# Committing touches objects, refs and logs, so the shared git dir must be
# writable too. In an ordinary repo the two paths are equal and nothing is added.
COMMON_GIT="$(cd "$PROJECT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
OWN_GIT="$(cd "$PROJECT" && git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
ADD_DIR=()
if [[ -n "$COMMON_GIT" && "$COMMON_GIT" != "$OWN_GIT" ]]; then
  ADD_DIR=("$AGENT_ADDDIR_FLAG" "$COMMON_GIT")
  echo "worktree detected — granting write to shared git dir: $COMMON_GIT"
fi
# NOTE the ${ADD_DIR[@]+...} expansion below. bash 3.2 (the system bash on
# macOS) treats "${empty[@]}" as an unbound variable under `set -u` and aborts.
# This only shows up in a plain repo, so testing solely in worktrees hides it.

# --- guard 2: snapshot before ------------------------------------------------
# Compare before/after to catch "exited 0, changed nothing". HEAD is captured as
# well as the working tree: an agent that commits its work leaves a clean
# `git status`, so comparing only the working tree marks a successful run as a
# no-op.
#
# Filter out our own run directory. It lives inside the project, so the log we
# are about to write is itself a change to `git status` — leave it in and
# before never equals after, which disables guard 5 entirely and silently.
# (An earlier version relied on the run dir being gitignored. That holds in the
# repo it was written in and nowhere else.)
tree_state() {
  cd "$PROJECT" && git status --porcelain 2>/dev/null \
    | grep -vF "$(basename "$RUN_DIR")" | sort
}
BEFORE="$(tree_state)"
BEFORE_HEAD="$(cd "$PROJECT" && git rev-parse HEAD 2>/dev/null)"

echo "spec:   $PROJECT_ARG / $SPEC"
echo "agent:  $AGENT_CMD"
echo "log:    $LOG"
echo

# --- guard 3: stdin ----------------------------------------------------------
# Without </dev/null the agent blocks forever on "Reading additional input from
# stdin..." when run detached. It does not time out. It just sits there.
# shellcheck disable=SC2086
$AGENT_CMD \
  $AGENT_CWD_FLAG "$PROJECT" \
  ${ADD_DIR[@]+"${ADD_DIR[@]}"} \
  $AGENT_SANDBOX_FLAG \
  $AGENT_EFFORT_FLAG \
  "$PROMPT" \
  < /dev/null > "$LOG" 2>&1
STATUS=$?

# --- guard 4: did the settings actually apply? -------------------------------
# Reasoning effort commonly defaults to none in a non-interactive run, and an
# interactive `/model` choice does not carry over. The run looks completely
# normal; only the quality drops. Echo the agent's own config header so a
# silent downgrade is visible.
echo "--- effective settings ---"
grep -E "$AGENT_CONFIG_GREP" "$LOG" || echo "(no config header found — verify manually)"
echo "--------------------------"
echo "exit=$STATUS / log $(wc -l < "$LOG") lines"

# Surface only the final report. Logs run to thousands of lines; reading them
# costs more than the delegation saved.
LAST="$(grep -n '^tokens used$' "$LOG" | tail -1 | cut -d: -f1)"
REPORT=""
if [[ -n "$LAST" ]]; then
  REPORT="$(tail -n "+$((LAST + 2))" "$LOG")"
  printf '\n=============== completion report ===============\n%s\n=================================================\n(full log: %s)\n' \
    "$REPORT" "$LOG"
fi

# --- guard 5: exited 0 but did nothing ---------------------------------------
# The quietest failure: the agent plans, asks "shall I proceed?", and exits.
# Exit code 0. A four-figure log. A passing test suite, because the code never
# changed. Indistinguishable from success unless you diff the tree.
AFTER="$(tree_state)"
AFTER_HEAD="$(cd "$PROJECT" && git rev-parse HEAD 2>/dev/null)"
if [[ "$BEFORE" == "$AFTER" && "$BEFORE_HEAD" == "$AFTER_HEAD" ]]; then
  {
    echo
    echo "!! nothing changed — the agent did no work."
    echo "   Check the end of the log; it most likely asked for approval or"
    echo "   reported a blocker:  tail -30 $LOG"
  } >&2
  [[ $STATUS -eq 0 ]] && STATUS=65   # never let this masquerade as success
fi

if [[ $STATUS -eq 0 ]]; then
  notify "delegate ok — $(basename "$SPEC")" "${REPORT:-see $LOG}"
else
  notify "delegate FAILED ($STATUS) — $(basename "$SPEC")" "$(tail -30 "$LOG")"
fi

exit $STATUS
