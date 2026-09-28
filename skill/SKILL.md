---
name: agent-delegate
description: Hand a written spec to a non-interactive coding agent (codex exec by default, any CLI via AGENT_CMD) in its own git worktree, and catch the five ways such a run silently does nothing. Use when the user wants to delegate a task to a headless agent, set up a worktree per task, or list agent commits nobody has reviewed.
---

# agent-delegate

Three bash scripts and a spec template. The scripts catch failures that look like success.

| Guard | What goes wrong | What the harness does |
|---|---|---|
| Nothing changed | Exit 0, tests pass, no file or commit changed (the agent asked "shall I proceed?" and exited) | Compares `git status` and `HEAD` before and after; if neither moved, the exit code becomes 65 |
| Silent effort downgrade | A headless run does not inherit the reasoning effort chosen interactively | Echoes the agent's own config header after every run |
| Hang on stdin | Detached run waits forever on "Reading additional input from stdin…" | Runs the agent with `</dev/null` |
| Commit fails in a worktree | `.git` is a file there; a sandbox that opens only the cwd blocks `index.lock` | Detects a worktree and grants the shared git dir |
| Exit code swallowed | `./delegate.sh … \| tail` reports tail's status | Documents `set -o pipefail` (works in bash and zsh) |

## Files

- `delegate.sh <project-dir> <spec-path> [extra instructions]` — run the agent on the spec with all five guards
- `worktree.sh <project-dir> <task-name>` — one isolated checkout per task, sharing `node_modules`
- `review-status.sh <project-dir>` — agent commits that have no review tag yet
- `SPEC-TEMPLATE.md` — the spec format (file ownership table, generated example table, acceptance commands)

## Workflow

When the user asks to delegate a task:

1. Copy `SPEC-TEMPLATE.md` into the project, fill it with the user, and **commit the spec
   before creating the worktree** — a worktree branched earlier does not contain it and the
   run fails with "no such spec".
2. `./worktree.sh <project> <task-name>` — task names cannot contain `/`.
3. `set -o pipefail; ./delegate.sh <worktree> <spec-path>` and read the exit code:
   0 = changes made, 64 = bad usage, 65 = ran but nothing changed, 66 = project or spec not found, anything else = the agent's own exit code.
4. Later, `./review-status.sh <project>` lists what is still unreviewed.

## Configuration (environment)

`AGENT_CMD` (default `codex exec`), `AGENT_EFFORT_FLAG`, `AGENT_SANDBOX_FLAG`,
`DELEGATE_WEBHOOK` (optional result notice), `BRANCH_PREFIX` (default `agent/`),
`AGENT_TAG` / `REVIEWED_TAG` (commit tags `review-status.sh` looks for).

## What this does not do

It cannot make a bad spec good, and it does not review the agent's code. It makes a run that
did nothing, hung, or lost its exit code visible instead of green.
