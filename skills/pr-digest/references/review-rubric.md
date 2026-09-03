# Review rubric

The standard the passes in `SKILL.md` are held to. Read it before pass 2.

## Severity

Every finding lands in exactly one bucket. If you are torn between two, it belongs in the lower one.

| Severity | Meaning | Examples |
| --- | --- | --- |
| `major` | The change is wrong, unsafe, or will break something. | Incorrect logic; an unhandled error path that matters; data loss or corruption; a security hole; a broken public contract or migration; a race; a resource leak; a performance cliff on a hot path. |
| `minor` | The change works but carries real cost. | A missing test on the risky branch; inconsistency with how the rest of the repo does this same thing; logic duplicated from somewhere it already exists; a leaky abstraction; a misleading name on a wide surface. |
| `nit` | Taste and polish. | Wording; ordering; a redundant comment; a slightly clumsy expression. |

Hard rules:

- A `nit` never carries a correctness claim. If it might be wrong, it is a major or it is nothing.
- A `major` without a stateable concrete failure is not a major. Demote it or drop it.
- Missing doc comments on exported symbols are a nit at most, never a minor.

## Rules of evidence

- **Cite `path:line`.** Every finding, every severity, from the diff or from the code it affects.
- **State the failure.** Every major names the input or state that triggers it and the wrong
  outcome that results. Writing that sentence is the test for whether the finding is real.
- **Verify before claiming.** "This might not handle X" is not a finding until you have looked at
  whether it handles X. Look, then claim.
- **Ignore what the PR only moved.** Pre-existing problems that the change relocates, reindents, or
  reformats are out of scope unless the change makes them worse.
- **Do not restate the diff.** "Adds a new field" is not a review.
- **Do not duplicate the tooling.** Style the repo's linter or formatter already enforces is not a
  finding. Neither is anything a type checker would reject.
- **Skip the machine-written parts.** Generated files, lockfiles, and vendored trees are named in
  the file table, not reviewed.

## The verification bar (pass 4)

Every candidate is attacked before it is kept. Go back to the code, not to your notes.

| Check | If it fails |
| --- | --- |
| Can I state the concrete failure — trigger and wrong outcome? | Drop, or demote to nit if cheap and obviously true. |
| Is the thing I assumed absent actually absent? | Drop. Absence you did not confirm is not evidence. |
| Does this survive reading the callers and the types? | Drop. |
| Is it pre-existing behaviour the PR only moves? | Drop. |
| Is it already enforced by a linter, type, or test here? | Drop. |

What survives gets a verdict:

- **`confirmed`** — you traced it in the code and can state the failure. Anything reported as a
  major must be `confirmed` or must say plainly why it could not be.
- **`likely`** — you still believe it but could not fully pin it down. Allowed, but the detail must
  end with the one thing that would settle it ("confirm whether `resolve()` is ever called with a
  nil tenant"). A `likely` with no such sentence is an unverified guess wearing a badge.

Dropped candidates are dropped silently. The report is what you found, not a transcript of what you
considered.

## Per-finding fields

The template expects these. Write them before rendering.

| Field | Content |
| --- | --- |
| title | Under 70 characters. The claim alone — no rationale, no consequence clause. |
| location | `path/to/file.go:142`. Multiple sites: the primary one, others in the detail. |
| detail | 2–4 sentences: what is wrong and why it matters. For `likely`, ends with what would settle it. |
| failure | Trigger → wrong outcome. Required for major; omit the element otherwise. |
| suggestion | The smallest change that fixes it. Not a redesign. |
| verdict | `confirmed` or `likely`. Nits carry none. |

Every identifier inside these fields — file paths, functions, types, variables, columns, config
keys, commands — is wrapped in `<code>` when rendered. Write them knowing that: name the exact
symbol rather than describing it, because `<code>resolveTenant()</code>` reads as precision and
"the resolver function" reads as vagueness.

## Calibration

A useful review of a normal PR finds zero to two majors. If a pass produces six, the most likely
explanation is that the bar slipped, not that the PR is exceptional — re-read them against the
severity table before ranking. The opposite failure is real too: a review that finds nothing on a
PR touching auth, migrations, or concurrency probably did not read hard enough.
