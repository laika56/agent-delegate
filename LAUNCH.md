# Launch drafts — agent-delegate

Drafts only. Nothing here has been posted.

**Rules followed:** every number below is measured, not estimated. No claim
appears here that is not already in `README.md`.

**Numbers available to cite**

| Claim | Value | Where it came from |
|---|---|---|
| Log from a run that changed nothing | **1,424 lines**, exit 0 | one incident |
| Log size vs code produced | **4,467 lines** log, **299 lines** of code | one delegation |
| Delegation throughput on a shared working tree | **12 runs / 6 days**, never >2 in a day | one repo, before worktrees |
| Spec written from a narrow sample | **127/127** tests passing, **88 of 325** real records threw (27%) | one parser task |
| Test cases this harness passed | **10** | stub agents, both directions |
| Bug found in the harness while testing it | **1** | guard 5 was silently disabled |
| Size | **under 200 lines** per script | `wc -l` |

**Do not claim:** a success rate, time saved, that it works with every agent
(only `codex exec` was exercised), or any number not in the table above.

---

## Reddit — r/ClaudeAI

Norm: problem first. The interesting content here is the failure taxonomy, not
the scripts.

### Title options

1. Five ways a non-interactive coding agent silently does nothing — and how each one looks like success
2. My delegated task exited 0, logged 1,424 lines, passed all tests, and changed no files
3. Tests passing is not evidence the work happened

### Body

I delegate tasks to a coding agent running non-interactively — write a spec,
point the agent at it, come back later.

One run came back: exit code 0, log 1,424 lines, full test suite passing.
Nothing had been changed.

The agent had planned the work, written "shall I proceed with this design?", and
exited — into a run with nobody there to answer. Tests passed because tests
always pass when the code doesn't change.

That's one of five failure modes I've hit, and none of them look like failure:

**1. Exit 0, nothing changed.** Snapshot `git status` *and* `HEAD` before and
after; rewrite the exit code to 65 if neither moved. HEAD matters as much as the
tree — an agent that commits its work leaves a clean status, so comparing only
the working tree marks a *good* run as a no-op. I got that wrong first.

**2. Reasoning effort silently defaults to none.** A non-interactive run often
doesn't inherit the model settings you picked interactively. Output looks
completely normal. Only the quality drops. Echo the agent's own config header
back after every run.

**3. Hangs on stdin.** Without `</dev/null` it blocks forever on "Reading
additional input from stdin…". It does not time out.

**4. Commits fail inside a worktree.** `.git` there is a *file* pointing at the
parent repo. A sandbox that opens only the working directory lets the agent edit
files and then die at commit time with `Unable to create '.../index.lock':
Operation not permitted`.

**5. Exit code swallowed by a pipe.** `./run.sh … | tail` reports `$?` from
`tail`. Use `pipefail` — and note `${PIPESTATUS[0]}` is bash-only; under zsh it
expands to an empty string, silently. zsh spells it `${pipestatus[1]}`.

There's also a throughput thing that took me too long to see: if every
delegation shares one working tree, task B can't start until you've reviewed and
committed task A. Writing ten specs in advance buys nothing — execution still
serialises at one. Measured before I fixed it: 12 delegations over 6 days, never
more than 2 in a day. One worktree per task is what makes a queue mean anything.

Ten test cases with stub agents, both directions. **Testing it found a bug in
it**: the harness writes its log inside the project, so its own run directory
changed `git status`, before never equalled after, and guard 1 was disabled —
silently. It went unnoticed originally because that directory happened to be
gitignored in the repo it was written in.

Agent-agnostic in principle (`AGENT_CMD`), though I've only exercised it against
`codex exec`. bash + git.

[link]

---

## Hacker News — Show HN

Norm: plain. The taxonomy is the substance; lead with it and keep the tone flat.

### Title options

1. Show HN: A harness for delegating to a coding agent that catches when it does nothing
2. Show HN: Five silent failure modes of non-interactive coding agents
3. Show HN: agent-delegate – guards for unattended agent runs

### Body

A wrapper for running a coding agent non-interactively against a written spec.

The motivating case: a run returned exit 0, a 1,424-line log, and a passing test
suite, having changed nothing. The agent had asked for approval and exited, into
a run with nobody to answer. The suite passed because the code hadn't changed.

Five guards, each from an actual incident:

1. Exit 0 with nothing changed — compares `git status` and `HEAD` before/after,
   rewrites the exit code to 65. Comparing only the working tree is wrong: an
   agent that commits leaves a clean status.
2. Reasoning effort defaulting to none in a non-interactive run — echoes the
   agent's config header back so a silent downgrade is visible.
3. Blocking forever on stdin without `</dev/null`.
4. Commit failing inside a git worktree, where `.git` is a file pointing at the
   parent repo and the sandbox never opened it.
5. Exit code swallowed by a pipe. `${PIPESTATUS[0]}` is bash-only and expands to
   empty under zsh; `pipefail` works in both.

Also worktree creation (one per task, node_modules shared by symlink — with the
detail that `node_modules/` in .gitignore has a trailing slash and therefore
does not match a symlink, so the worktree shows permanent uncommitted entries
unless you exclude them locally), and a status script that derives "what is
unreviewed" from git tags rather than a prose file that goes stale.

Ten test cases against stub agents. Writing them found a bug in the harness: it
writes its log inside the project, so its own run directory changed `git status`
and guard 1 never fired. That had gone unnoticed because the directory happened
to be gitignored where it was written.

`AGENT_CMD` is configurable, but `codex exec` is the only agent I've actually
run it against.

bash and git; python3 only for an optional webhook. Under 200 lines per script.

---

## X

### Option 1 — the incident

> A delegated task came back:
> exit code 0
> 1,424-line log
> full test suite passing
> zero files changed
>
> The agent asked "shall I proceed?" and exited. Nobody was there to answer.
>
> Tests passed because the code never changed.
>
> [link]

### Option 2 — the counter-intuitive guard

> Checking whether a delegated agent did anything:
>
> comparing `git status` before/after is wrong.
>
> An agent that commits its work leaves a clean status — so a good run looks
> like a no-op.
>
> Compare HEAD too.
>
> [link]

### Option 3 — the throughput one

> Wrote 10 specs in advance so my agent would never idle.
>
> It still ran one at a time.
>
> They all shared one working tree — task B couldn't start until I'd reviewed
> and committed task A. 12 runs in 6 days, never more than 2 in a day.
>
> One worktree per task fixed it.
>
> [link]

### Option 4 — the zsh detail

> `${PIPESTATUS[0]}` is bash.
>
> Under zsh it expands to an empty string. Silently. Your exit-code check
> passes and means nothing.
>
> zsh: `${pipestatus[1]}`
> Both: `set -o pipefail`
>
> [link]

---

## Sequencing

Reddit first; the failure taxonomy is what people respond to and the feedback is
usable before HN. HN second, and only if nothing in the Reddit thread turns up a
correctness problem — Show HN gets one shot.

The zsh post (X option 4) is the strongest standalone: it is useful to someone
who never installs this, which is what makes it travel.

Not on the same day as the other product. Two launches in one day from the same
account reads as a campaign.
