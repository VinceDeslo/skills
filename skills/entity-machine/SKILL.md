---
name: entity-machine
description: Crawl one or more codebases for a named entity (struct, class, type, model, enum) and produce a self-contained HTML page with its full state machine — a list of every state and what it represents, one or more state diagrams where every individual transition edge is keyed T1..Tn and coloured by actor, and a table per diagram giving each edge's trigger, guard, emitted event, and code location. Splits into several diagrams per domain or interaction nature when the edges do not fit one. Use when asked to map, diagram, enumerate, or audit the states, statuses, lifecycle, or transitions of an entity, when asked "who can move X from A to B", or when the user says "entity-machine".
compatibility: Requires shell access, `python3` (standard library only), and a code search tool (`rg` or `grep`) over a local checkout of the repositories to crawl. Optional — a browser opener (`open`, `xdg-open`, or `start`) to display the page, and the `generate-artifact` skill when the user wants the page saved and served as an artifact.
---

# entity-machine

Take an entity name, find every state it can be in and every piece of code that moves it between
states, and hand back one HTML page: the states with their meaning at the top, then one or more
state machine diagrams where **every individual edge is identified**, each followed by a table that
names the actor, trigger, guard, event, and `path:line` of that edge.

Three properties define the output:

- **Exhaustive.** Every writer of the state field in every crawled repository becomes an edge. A
  transition that exists only in a raw SQL statement, a cascade from another entity, or a mirror
  service counts as much as one behind the declared transition map.
- **Cited.** Every edge points at the lines that perform it, read at the checked-out commit. No
  edge is drawn from memory or from documentation.
- **Legible.** A diagram stops at about 8 states and 12 edges. Past that the edges are split into
  several diagrams by domain or by interaction nature, each with its own table, and the keys stay
  globally unique so `T9` means one thing across the page.

## When to use

The user names an entity — `Task`, `Order`, `Subscription`, `Deployment` — and asks for its state
machine, lifecycle, statuses, or transitions; asks which code can move it from one state to another;
wants to audit whether a transition map is honoured; or says "entity-machine".

Not for generic architecture diagrams or data flows. If the entity has no state-like field, say so
and stop.

## Instructions

### 1. Resolve the entity and the scope

Take the entity name from the request. Resolve the codebases to crawl in this order: the paths the
user named, the current repository, then sibling repositories that reference the same entity or
table name (search `~/repos/*/*` for the type name, the table name, and the enum values). Say which
repositories are in scope before crawling; the user may narrow it.

Capture the commit of each repository for the meta line:

```bash
git -C <repo> rev-parse --short HEAD
```

### 2. Crawl

Follow [references/crawl-method.md](references/crawl-method.md) end to end: locate the definition,
enumerate the states from every source of truth, find every writer, turn writers into edges, flag
what deserves attention, and decide the split into machines. Do the crawl yourself in this session;
it is one entity and the steps depend on each other.

Open every search hit. A grep match is a lead, not an edge — an edge exists once you have read the
write, its guard, and the entry point that triggers it, and can cite all three.

### 3. Write the spec

Author one JSON file following [references/spec-format.md](references/spec-format.md) in a working
directory under the system temp root:

```bash
work="${TMPDIR:-/tmp}/temp_machines"
mkdir -p "$work"
spec="$work/<entity>.json"
```

Fill it in this order — states first, then edges, then layout, then prose:

1. **states** — every state with a one-sentence `meaning`, `initial`, `terminal`, and `declared`.
2. **edges** — grouped into machines, keyed `T1..Tn` in the order a reader meets them: happy path
   first, then returns, then closures, then anything flagged. Each edge cites at least one location.
3. **layout** — main path on one row left to right, terminal states on a row below, `"*"` placed
   when used. Keep straight lines clear of third states.
4. **summary, actors, method, caveats** — the summary names the definition, the repositories
   crawled, the edge count, and the one thing the reader should look at first.

### 4. Check and fix

```bash
python3 <skill-dir>/scripts/render.py "$spec" --check
```

Errors are structural (missing fields, key gaps, orphan states, edges without locations) and must be
fixed in the spec. Warnings are layout collisions and each names the fix: move a state, set `bend`,
or set `labelAt` on the edge. Iterate until the checker prints zero warnings. Do not deliver a page
with a known overlap.

### 5. Render and deliver

```bash
out="$work/<entity>-$(date +%Y%m%d-%H%M%S).html"
python3 <skill-dir>/scripts/render.py "$spec" --out "$out"
open "$out"        # macOS
xdg-open "$out"    # Linux
start "" "$out"    # Windows
```

The page is fully self-contained: inline CSS, inline SVG, one small inline script for hover linking
between a diagram edge and its table row, no network requests. It renders in light and dark themes.

If the user asked for the page as an artifact or for a shareable link, hand the rendered file to
the `generate-artifact` skill: save the same file unchanged into `~/.artifacts` and serve it from
that skill's index. Give the served URL as well as the local path.

Then summarize in chat in **four lines at most**: state count and edge count, number of diagrams,
the most important flagged edge if any, and the file path. Everything else is on the page.

## Edge cases

- **Entity mirrored in several languages or services:** crawl every mirror, list each in `method`,
  and add a caveat wherever the value sets disagree. A state present in one mirror and absent in
  another is a finding worth a flagged edge or a note on the state.
- **No declared transition map:** every edge is effectively unguarded. Do not flag them all; say so
  once in the summary and flag only the writes that skip a check the rest of the code performs.
- **State stored outside the entity** (a status table, an event log folded into a view): the
  writers are inserts into that table or the view definition. Cite the migration or the view.
- **Too many edges for one page** (50+): split by domain first, then by actor inside a domain, and
  put the diagram the user asked about first. Never drop an edge to make a diagram fit.
- **Running against a branch or PR:** flag edges the change adds as `new` and mention the base ref
  in the summary, the way the adversarial-review format does.
- **Entity found but no state field:** stop and say the entity has no state machine; offer the
  closest state-bearing entity found while searching.
- **No local checkout:** stop and ask for the path. This skill does not crawl through a remote API
  because line-accurate citations need the files on disk.
