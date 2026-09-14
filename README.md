# agent-delegate

A harness for handing work to a non-interactive coding agent — and catching the
five ways it silently does nothing.

Works with any agent that takes a prompt and a working directory. Defaults to
`codex exec`; set `AGENT_CMD` for anything else.

---

## The problem

You delegate a task. Twenty minutes later the run finishes. Exit code 0. The log
is 1,424 lines. The test suite passes.

Nothing was changed.

The agent planned the work, wrote *"shall I proceed with this design?"*, and
exited — into a non-interactive run with nobody there to answer. Tests passed
because tests always pass when the code does not change.

That is one failure mode. There are five, and none of them look like failure.

---

## The five guards

Each one is a real incident, not a hypothetical. They sit inline in the scripts
with the same notes.

**1 · Exit 0, nothing changed.** The run snapshots `git status` *and* `HEAD`
before and after. If neither moved, the exit code is rewritten to **65** so it
cannot pass as success. `HEAD` matters as much as the working tree: an agent
that commits its work leaves a clean status, and comparing only the tree marks a
good run as a no-op.

**2 · Reasoning effort silently defaults to none.** A non-interactive run often
does not inherit the model settings you chose interactively. Output looks
entirely normal; only the quality drops. The harness echoes back the agent's own
config header after every run, so a silent downgrade is visible.

**3 · The run hangs on stdin.** Without `</dev/null` the agent blocks forever on
"Reading additional input from stdin…" when detached. It does not time out.

**4 · Commits fail inside a worktree.** In a git worktree `.git` is a file
pointing at the parent repo. A sandbox that opens only the working directory
lets the agent edit files and then die at commit time with
`Unable to create '.../index.lock': Operation not permitted`. The harness
detects a worktree and grants the shared git dir explicitly.

**5 · The exit code gets swallowed by a pipe.** `./delegate.sh … | tail` reports
`$?` from `tail`, not from the script — so a "spec not found" (66) reads as 0.
Use `set -o pipefail`. Note that `${PIPESTATUS[0]}` is **bash** syntax: under
zsh it expands to an empty string, silently. zsh spells it `${pipestatus[1]}`.
`pipefail` works in both, which is why it is the advice here.

---

## What's in the box

| File | What it does |
|---|---|
| `delegate.sh` | Run an agent against a spec, with all five guards |
| `worktree.sh` | One isolated checkout per task, with shared `node_modules` |
| `review-status.sh` | What the agent produced that nobody has reviewed |
| `SPEC-TEMPLATE.md` | The spec format that makes delegation actually work |

---

## Use

```bash
# 1. Write the spec. Commit it BEFORE creating the worktree.
cp SPEC-TEMPLATE.md myproject/specs/01-parser.md
$EDITOR myproject/specs/01-parser.md
git -C myproject add specs/01-parser.md && git -C myproject commit -m "spec: parser"

# 2. Give the task its own checkout.
./worktree.sh myproject parser

# 3. Run it.
./delegate.sh ../.worktrees/myproject/parser specs/01-parser.md

# 4. Later, see what is unreviewed.
./review-status.sh myproject
```

Order matters in step 1→2. A worktree branched from a commit that predates the
spec **does not contain the spec**, and the run fails with "no such spec" while
every path you typed is correct.

### Why a worktree per task

Share one working tree and task B cannot start until you have reviewed and
committed task A. Writing ten specs in advance then buys nothing — execution
still serialises at one. Measured on one repo before the change: twelve
delegations over six days, never more than two in a day.

### Configuration

```bash
AGENT_CMD="codex exec"                        # any agent taking (prompt, cwd)
AGENT_EFFORT_FLAG="-c model_reasoning_effort=high"
AGENT_SANDBOX_FLAG="-s workspace-write"
DELEGATE_WEBHOOK="https://..."                # optional result notification
BRANCH_PREFIX="agent/"                        # worktree.sh
AGENT_TAG="#agent"                            # review-status.sh
REVIEWED_TAG="#reviewed"
```

---

## The spec is the product

The harness catches silent failures. It cannot make a bad spec good.

`SPEC-TEMPLATE.md` carries the parts that are learned the expensive way:

- **File ownership as a table.** Two tasks touching one file is a merge conflict
  you resolve by hand.
- **Generate the example table, don't hand-fill it.** Three lines of an
  independent implementation is free and independent in a way your own
  arithmetic is not. A formula error was caught exactly this way, while writing
  a spec: the general form disagreed with the closed form.
- **For external data, attach a distribution, not samples.** N ≥ 300, per-field
  value counts. *Noting* a coverage limit and *widening* it are different
  things. Measured: a task passing 127/127 tests threw on 88 of 325 real
  records — 27%.
- **Acceptance criteria as runnable commands, including `git diff --stat`.**
  Scope creep is otherwise invisible.
- **A mutation check.** Name a change that must break a test. Tests written
  against an implementation agree with it by construction and catch nothing;
  this is the cheap way to find that out.

Run the acceptance criteria yourself before you delegate. A spec that cannot be
satisfied gets bounced back and you pay for the round trip.

---

## Review order

Do not read the run log. One log was 4,467 lines against 299 lines of produced
code — reading it costs more than the delegation saved. Open it only when stuck.

Stop at the first step that fails:

| # | Check | How much you read |
|---|---|---|
| 0 | **Did anything get produced?** `git status`, then `grep` for the symbol the spec required | a few lines |
| 1 | Run the tests yourself | a few lines |
| 2 | `git diff --stat` — anything outside scope? | a few lines |
| 3 | Read the implementation. Not the tests yet | ~30% of the output |
| 4 | Do the test *names* cover the spec's items? | the list only |
| 5 | Read test bodies only if 3–4 smelled | as needed |

Step 0 comes before step 1 because **when nothing changed, the tests always
pass**. A passing suite is not evidence the work happened.

---

## Verified

Ten cases, driven by stub agents so every branch is exercised:

| Case | Expected | Result |
|---|---|---|
| Agent plans, asks for approval, exits | exit 65 | ✅ |
| Agent writes a file | exit 0, no warning | ✅ |
| Agent commits and leaves a clean tree | exit 0, no warning | ✅ |
| Missing project / missing spec | exit 66 | ✅ |
| `delegate.sh` / `worktree.sh` with no arguments | exit 64 + usage | ✅ |
| `review-status.sh` with no arguments | defaults to cwd, exit 0 | ✅ |
| All three scripts under bash 3.2 | parse clean | ✅ |
| Worktree created | branch correct, spec present inside | ✅ |
| review-status on a tagged commit | listed as unreviewed | ✅ |
| review-status with untagged commits | warns they are invisible | ✅ |

Writing those tests found a bug in this harness: it writes its log inside the
project, so its own run directory changed `git status`, `before` never equalled
`after`, and guard 1 was disabled — silently. It had gone unnoticed because that
directory happened to be gitignored in the repo it was written in. Now filtered
explicitly.

## Requirements

`bash`, `git`, `python3` (only for the optional webhook). No installation, no
network calls except a webhook you configure yourself. Every script is under
210 lines (delegate.sh is 207; the two helpers are 68 and 106) — read them before you run them.

## License

MIT.
