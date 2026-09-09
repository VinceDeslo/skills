# Crawl method

How to enumerate every state and every transition of one entity across one or more codebases. The
output of this procedure is the JSON spec described in [spec-format.md](spec-format.md); nothing in
the diagram or table exists that was not found by these steps and cited to a file and line.

## 1. Locate the definition

Find where the entity and its state field are declared. Search for the entity name as a type and for
the field that carries its state — usually `status`, `state`, `phase`, `stage`, or `lifecycle`.

```bash
rg -n --type-add 'code:*.{go,ts,tsx,js,py,rb,rs,java,kt,cs,sql,prisma,proto,graphql}' -t code \
  '(type|class|struct|interface|enum|model)\s+<Entity>\b'
rg -n '<Entity>(Status|State|Phase)\b'
```

Record the definition site as `definition` in the spec. If the entity exists in several languages
(a TypeScript type mirrored in Go, a Prisma model mirrored in SQL), record each mirror; they may
disagree, and a disagreement is a caveat.

## 2. Enumerate the states

Collect the value set from every source of truth, then reconcile:

| Source | What to search |
| --- | --- |
| Enum or union type | the type body; `enum`, `type X = 'a' \| 'b'`, `const X = [...] as const`, Go `const ( ... = iota )`, Python `class X(Enum)` |
| Database | migrations: `CHECK (status IN (...))`, `CREATE TYPE ... AS ENUM`, column `DEFAULT` (the default is usually the initial state) |
| Validation | zod / pydantic / joi schemas, protobuf enums, GraphQL enums, OpenAPI schemas |
| Literals in code | `rg -n "status\s*(=|==|===|!=|:)\s*['\"]" ` — a literal missing from the enum is a state or a bug |

For each state write one sentence on what it **represents** in the domain (not "the status is
paid" but "payment captured; eligible for fulfilment"). Read the code that branches on the state to
learn what it means. Mark `initial` on the state written at creation, and `terminal` on states with
no outgoing edge in any writer.

A state that appears in a literal but not in the declared enum stays in the list with a caveat.
A declared state that no writer ever produces stays in the list with a note that it is unreachable.

## 3. Find every writer

An edge exists wherever the state field is written. Search widely, then open every hit:

```bash
rg -n '\.status\s*=|status:\s|SetStatus\(|setStatus\(|status =|"status"\s*:|status = \$|status=' <paths>
rg -n 'UPDATE\s+<table>.*\bstatus\b|update\(\{.*status|\.update\(.*status' <paths>
rg -n 'transition|Transition|ALLOWED_TRANSITIONS|allowedTransitions|canTransition|isValid.*Transition' <paths>
rg -n '<entity>\.(created|updated|deleted|\w+ed)\b' <paths>          # domain events that imply a status change
rg -n 'INSERT INTO <table>|create\(\{|\.Create\(' <paths>            # creation sets the initial state
```

Include these writer classes, and tag the actor for each:

- **user** — HTTP handlers, GraphQL resolvers, CLI commands, UI actions that a human triggers.
- **agent** — another automated actor inside the product acting with intent (an investigation
  agent, a reconciler, a bot account).
- **process** — workers, cron jobs, queue consumers, database triggers and defaults, derived
  columns, cascades from other entities, migrations that rewrite the column.
- **external** — webhooks and callbacks from third-party systems.

Do not stop at the first layer. A helper like `markResolved()` is one writer; every caller of it that
represents a distinct trigger is a distinct edge. Follow the call graph up to the entry point and
name that entry point as the trigger.

Also search sibling repositories when the entity crosses services: a Go worker mirroring a
TypeScript API, a data pipeline rewriting statuses, an admin tool. List every repository crawled in
`method` and every one skipped in `caveats`.

## 4. Turn writers into edges

For each writer determine:

- **from** — the state(s) the code allows as the source. Read the guard: an explicit transition map,
  a `WHERE status IN (...)` clause, an `if` on the current value. If the code does not check the
  current state, the source is `*` (any state) — and that is usually worth a `flag`.
- **to** — the value written.
- **trigger** — the entry point and the user-visible or system action that starts it.
- **guard** — the condition that must hold; the function or clause that enforces it. Write `–` when
  there is none, and consider a `flag`.
- **event** — the domain event, message, or audit record emitted; `–` when none.
- **locations** — every `path:line` or `path:start-end` involved: the entry point, the guard, and
  the write. Read at the checked-out commit; never guess line numbers.

One edge per distinct **(trigger, guard, target)** combination. Two callers with the same trigger
semantics and the same guard collapse into one edge with several locations. Two callers with
different guards or different actors are two edges even when they write the same value. Several
sources with the same trigger form one edge with an array `from`.

Self loops are edges: a writer that rewrites the current value while changing other fields.

## 5. Flag what deserves attention

Use `flag` with a short lowercase word on edges that a reader should examine first:

- `undeclared` — the write bypasses the declared transition map or guard.
- `unguarded` — no check on the current state.
- `dead` — the writer is unreachable (no caller, feature flag permanently off).
- `new` — added by the change under review, when the skill runs against a branch or PR.

Flags are findings, not decoration. Every flagged edge carries a `note` saying why.

## 6. Split into machines

A single diagram holds about **8 states and 12 edges** before edges start crossing states. When the
edge count exceeds that, split by the axis that yields the fewest cross-machine edges:

- **by domain** — lifecycle vs. cancellation/refund vs. moderation.
- **by interaction nature** — user-driven edges vs. automated edges.
- **by actor** — one machine per actor when actors rarely share edges.

A state may appear in several machines; each machine lays it out independently. Every edge appears
in exactly one machine. Keys stay globally unique and consecutive (`T1..Tn`) across machines, so a
reader can cite `T9` without naming the diagram.

## 7. Write the summary and method

`summary` (top of the page) names the definition, the sources of truth, the repositories crawled,
how many edges were found, and the single most important thing the reader should notice. `method`
lists the searches you ran. `caveats` list what you did not or could not inspect.
