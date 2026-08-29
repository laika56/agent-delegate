#!/usr/bin/env bash
# review-status — what has the agent produced that nobody has checked yet?
#
#   ./review-status.sh [project-dir ...]
#
# Why a script and not a notes file: the state used to live in prose — a
# markdown file saying "this section is unreviewed". Nobody updated it after a
# review, so a stale warning sat there and caused the same work to be reviewed
# twice. Git already knows. Ask git.
#
# The convention:
#   commit subject starts with $AGENT_TAG    -> produced by the agent, unreviewed
#   commit subject starts with $REVIEWED_TAG -> a human checked it
# One tag per commit, in the subject line. That is the whole protocol.

set -uo pipefail

AGENT_TAG="${AGENT_TAG:-#agent}"
REVIEWED_TAG="${REVIEWED_TAG:-#reviewed}"
SINCE="${SINCE:-14.days}"

targets=("$@")
[[ ${#targets[@]} -eq 0 ]] && targets=("$PWD")

for t in "${targets[@]}"; do
  [[ -d "$t/.git" || -f "$t/.git" ]] || continue
  name="$(basename "$(cd "$t" && pwd)")"
  printf '\n━━━ %s ━━━\n' "$name"

  # Worktrees: each one is a task that may still be in flight.
  wt="$(git -C "$t" worktree list 2>/dev/null | tail -n +2)"
  if [[ -n "$wt" ]]; then
    echo "worktrees:"
    printf '%s\n' "$wt" | while read -r dir sha br; do
      ahead="$(git -C "$dir" rev-list --count HEAD ^HEAD@{upstream} 2>/dev/null || echo '?')"
      dirty="$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      printf '  %-28s %s  uncommitted=%s\n' "$(basename "$dir")" "$br" "$dirty"
      # Uncommitted changes in an agent worktree usually mean the run stopped
      # partway. It is not automatically a problem, but it is never nothing.
    done
  fi

  # Unreviewed = tagged by the agent, with no later commit claiming review.
  reviewed="$(git -C "$t" log --since="$SINCE" --format='%s' 2>/dev/null \
              | grep -F "$REVIEWED_TAG" || true)"
  echo "unreviewed ($AGENT_TAG without $REVIEWED_TAG):"
  found=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sha="${line%% *}"; subj="${line#* }"
    # A subject naming both tags is already reviewed.
    printf '%s' "$subj" | grep -qF "$REVIEWED_TAG" && continue
    # ...or a later commit references this sha as reviewed.
    printf '%s' "$reviewed" | grep -qF "$sha" && continue
    printf '  %s  %s\n' "$sha" "$subj"
    found=$((found + 1))
  done < <(git -C "$t" log --since="$SINCE" --format='%h %s' 2>/dev/null \
           | grep -F "$AGENT_TAG" || true)
  [[ $found -eq 0 ]] && echo "  none"

  # Untagged commits are the real hazard: invisible to this whole scheme.
  untagged="$(git -C "$t" log --since="$SINCE" --format='%h %s' 2>/dev/null \
              | grep -vF "$AGENT_TAG" | grep -vF "$REVIEWED_TAG" | wc -l | tr -d ' ')"
  [[ "$untagged" != "0" ]] && \
    echo "  note: $untagged commit(s) in the last $SINCE carry no tag — this tool cannot see those"
done

echo
