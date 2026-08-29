# Spec: <name>

> Copy this file. A vague spec does not produce vague work — it produces
> confident work built on invented assumptions, which costs more to find than
> to have specified.

## Why

<What is wrong now. Include the measurement that made you notice, not just the
description. "It sometimes fails" is not a why; "3 of 3,228 decision days
liquidated the whole book on a data gap" is.>

## Scope

- ✅ This task: <exactly what changes>
- ❌ Not this task: <what stays untouched, and why>

**Does behaviour change?** <yes / no. If no, say what number must stay
identical, and make it an acceptance criterion.>

## File ownership

| File | This task |
|---|---|
| `path/to/file` | ✏️ modify |
| `path/to/new` | ➕ create |
| `path/to/other` | 🚫 **forbidden** |
| everything else | 🚫 **forbidden** |

> Two tasks touching one file means a merge conflict you resolve by hand. Split
> ownership here, not later.

## Signature and behaviour

```
def thing(a: T, b: U) -> V
```

| # | Condition | Expected |
|---|---|---|
| 1 | <normal> | <value> |
| 2 | <boundary: 0, empty, single element, max> | <value> |
| 3 | <invalid> | <exception type and message> |

Rounding, units, timezone: <state them, or they get invented>

## Example I/O

| input | expected |
|---:|---:|
| … | … |

> **Generate this table, do not hand-fill it.** If the algorithm is public
> (checksum, log return, a documented formula), write three lines of an
> independent implementation and emit the table from it. Free, and independent
> in a way your own arithmetic is not. Hand-checking is for when no independent
> source exists — and it is where a formula error hides. One was caught exactly
> this way while writing a spec: the general form disagreed with the closed
> form, and only the cross-check noticed.

## If this parses external data

Attach a **distribution**, not samples. N ≥ 300, three or more query shapes.
Count values per field and put it in a table: how many distinct units, what
percentage carries formatting variants (thousands separators), what fraction is
null.

> Samples plus "everything else unverified" is not enough. *Noting* the coverage
> limit and *widening* it are different things. A spec written from a narrow
> sample gets implemented faithfully and passes its own tests — the mismatch
> only surfaces against real data, after review. Measured: a task passing
> 127/127 tests threw on 88 of 325 real records (27%).

## Acceptance criteria

Executable commands with expected output. This is what makes the work
self-judging — and it decides the review cost.

```
1. <test command>              -> <n/n pass>
2. <verification script>       -> <0 mismatches>
3. git diff --stat             -> <only the owned files>
4. <behaviour-invariance check> -> <exact expected number>
```

> **Run these yourself before delegating.** A spec whose criteria cannot be
> satisfied gets bounced back, and you pay for the round trip.
>
> Criterion 3 is not optional. Scope creep is otherwise invisible.
>
> Most tasks need no bespoke verification script — make the example table above
> executable and that *is* the verification. A dedicated script earns its keep
> in one case: parsing external data.

## Mutation check

> Name one change to the implementation that MUST break a test. Have the agent
> make it, report which test failed, and revert.
>
> Tests written against an implementation agree with that implementation by
> construction and catch nothing. This is how you find that out cheaply.

Break `<specific line>` → test `<name>` must fail.

## Do not

- Add dependencies. Stop and report instead.
- Touch files outside the ownership table.
- "Improve" anything out of scope. Report it, leave it.
- Reformat, re-style, or reorganise imports.
