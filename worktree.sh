#!/usr/bin/env bash
# worktree — give each delegated task its own checkout, so tasks do not queue.
#
#   ./worktree.sh <project-dir> <task-name>
#
# Why: if every delegation shares one working tree, task B cannot start until
# you have reviewed and committed task A. Writing ten specs in advance then
# buys you nothing — execution still serialises at one. A worktree per task is
# what makes a queue of specs actually mean parallel work.

set -uo pipefail

if [[ $# -lt 2 ]]; then
  cat >&2 <<EOF
usage: $0 <project-dir> <task-name>

  task-name    short slug, no slashes. Becomes branch "\$BRANCH_PREFIX<name>".

env:
  BRANCH_PREFIX   default "agent/"
  WORKTREE_ROOT   default "<project>/../.worktrees/<project-name>"
  BASE_BRANCH     default: main, else master, else current HEAD
EOF
  exit 64
fi

PROJECT_ARG="$1"
NAME="$2"

[[ "$PROJECT_ARG" = /* ]] && PROJECT="$PROJECT_ARG" || PROJECT="$PWD/$PROJECT_ARG"
PROJECT="$(cd "$PROJECT" && pwd)" || exit 66
[[ -d "$PROJECT/.git" || -f "$PROJECT/.git" ]] || { echo "not a git repo: $PROJECT" >&2; exit 66; }

# A slash here would scatter the worktree somewhere unintended.
[[ "$NAME" == */* ]] && { echo "no slashes in the task name: $NAME" >&2; exit 64; }

PREFIX="${BRANCH_PREFIX:-agent/}"
BRANCH="${PREFIX}${NAME}"

if [[ -n "${BASE_BRANCH:-}" ]]; then
  BASE="$BASE_BRANCH"
elif git -C "$PROJECT" show-ref --verify --quiet refs/heads/main; then
  BASE="main"
elif git -C "$PROJECT" show-ref --verify --quiet refs/heads/master; then
  BASE="master"
else
  BASE="$(git -C "$PROJECT" rev-parse --abbrev-ref HEAD)"
  echo "warning: no main/master — basing on '$BASE'. Confirm that is what you want." >&2
fi

WTDIR="${WORKTREE_ROOT:-$(dirname "$PROJECT")/.worktrees/$(basename "$PROJECT")}/$NAME"

[[ -e "$WTDIR" ]] && { echo "already exists: $WTDIR" >&2; exit 66; }
git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$BRANCH" \
  && { echo "branch already exists: $BRANCH" >&2; exit 66; }

mkdir -p "$(dirname "$WTDIR")"
git -C "$PROJECT" worktree add -b "$BRANCH" "$WTDIR" "$BASE" || exit $?

# Share node_modules by symlink rather than reinstalling per worktree. Node
# follows symlinks, and a large project makes this the difference between
# seconds and several minutes plus gigabytes per task.
#
# Link every node_modules, not just the root one: a project with a nested
# package.json (functions/, packages/*) breaks at runtime with
# "Cannot find module ..." if you only link the top level.
LINKED=()
while IFS= read -r NM; do
  REL="${NM#"$PROJECT"/}"
  TARGET="$WTDIR/$REL"
  [[ -e "$TARGET" ]] && continue
  mkdir -p "$(dirname "$TARGET")"
  ln -s "$NM" "$TARGET"
  echo "shared node_modules -> $REL"
  LINKED+=("$REL")
done < <(find "$PROJECT" -maxdepth 3 -name node_modules -type d -not -path "*/node_modules/*" 2>/dev/null)

# A .gitignore usually says `node_modules/` with a trailing slash, which matches
# a DIRECTORY and not a SYMLINK. Leave it and the worktree shows permanent
# uncommitted entries — which makes the "agent did not commit" warning fire
# forever and buries the real ones.
#
# Excluded locally (.git/info/exclude) rather than by editing .gitignore: that
# file is shared with the agent and with everyone else on the repo.
if [[ ${#LINKED[@]} -gt 0 ]]; then
  EXCLUDE="$(git -C "$WTDIR" rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$EXCLUDE")"
  {
    echo "# node_modules symlinks created by worktree.sh"
    echo "# .gitignore's 'node_modules/' does not match symlinks (trailing slash)"
    printf '/%s\n' "${LINKED[@]}"
  } >> "$EXCLUDE"
fi

cat <<EOF

worktree: $WTDIR
branch:   $BRANCH  (based on $BASE)

next — point a delegation at it:
  ./delegate.sh "$WTDIR" <spec-path>

Commit the spec BEFORE creating the worktree. A worktree branched from a commit
that predates the spec does not contain the spec, and the delegation then fails
with "no such spec" while every path you typed looks correct.
EOF
