# Spec format

`scripts/render.py` reads one JSON document and writes the whole HTML page: header, states table,
one diagram plus one transition table per machine, and a methodology fold. Everything visible comes
from this file; there is no hand-written HTML.

```bash
python3 scripts/render.py spec.json --check                  # validate and report layout warnings
python3 scripts/render.py spec.json --out /path/report.html  # render
```

Inline code in any text field uses backticks: `` "trigger": "`POST /orders/{id}/submit`" ``. The
renderer turns them into `<code>` and escapes everything else.

## Top level

```json
{
  "entity": "Order",
  "repo": "acme/shop",
  "definition": "internal/order/order.go:18",
  "commit": "3f9c2ab",
  "summary": "One paragraph: sources of truth, repos crawled, edge count, the main thing to notice.",
  "actors": {
    "user": "What a user edge means in this codebase",
    "agent": "…",
    "process": "…",
    "external": "…"
  },
  "states": [ … ],
  "machines": [ … ],
  "method": "The searches run and the layers followed.",
  "caveats": ["What was not inspected."]
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `entity` | yes | Type name as it appears in code. |
| `repo`, `definition`, `commit` | no | Shown in the meta line. |
| `summary` | yes | Rendered under the title. |
| `actors` | yes | Only the four keys `user`, `agent`, `process`, `external`; include only the ones used, each with the legend text. |
| `states` | yes | Every state of the entity, in a sensible reading order. |
| `machines` | yes | One or more diagrams. |
| `method`, `caveats` | no | Fill the methodology fold; omit both to drop it. |

## States

```json
{"id": "paid", "meaning": "Payment captured; eligible for fulfilment.", "initial": false, "terminal": false, "declared": "internal/order/order.go:22"}
```

`id` is the literal value used in code. `meaning` is one sentence on what the state represents.
Exactly one state should be `initial`; it gets the start marker. `terminal` states get a double
border. `declared` is the `path:line` of the enum member.

Every state must be used by at least one edge somewhere; the validator rejects orphans. A declared
but unreachable state still needs a `dead`-flagged edge or must be dropped with a caveat.

## Machines

```json
{
  "title": "Lifecycle",
  "summary": "What this diagram covers and why it is its own diagram.",
  "layout": {"draft": [0, 0], "placed": [1, 0], "paid": [2, 0], "cancelled": [1, 1], "*": [0, 1]},
  "note": "Optional caption under the diagram.",
  "edges": [ … ]
}
```

`layout` places each state used by this machine's edges on an integer grid `[col, row]`. Columns run
left to right, rows top to bottom. The pseudo-state `"*"` (any state) is placed like any other and
drawn as a dashed pill; it must be in the layout when an edge uses `"from": "*"`.

Layout rules that keep the diagram legible:

- Put the main path on one row, left to right, initial state first.
- Put terminal states on a second row under the state they most often come from.
- Never place a third state on the straight line between two states joined by an edge; the checker
  warns when an edge passes through a state. Move the state or set `bend`.
- Leave an empty cell above a state that carries a self loop; the loop is drawn above it.
- Keep a machine to about 8 states and 12 edges. Beyond that, split (see crawl-method.md §6).

## Edges

```json
{
  "key": "T7",
  "from": ["draft", "placed"],
  "to": "cancelled",
  "actor": "user",
  "trigger": "`POST /orders/{id}/cancel`",
  "guard": "`AllowedTransitions[status]` contains `cancelled`",
  "event": "`order.cancelled`",
  "locations": ["internal/api/orders.go:190-214", "internal/order/transitions.go:12-30"],
  "flag": "undeclared",
  "note": "Why the flag, or anything the table cell cannot hold.",
  "bend": 90,
  "labelAt": 0.35
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `key` | yes | `T` plus a number. Unique across all machines, consecutive from `T1`. |
| `from` | yes | One state, an array of states, or `"*"`. Each source is drawn as its own arrow sharing the key. |
| `to` | yes | One state. Equal to `from` for a self loop. |
| `actor` | yes | `user` solid, `agent` dashed, `process` dotted, `external` dash-dot. |
| `trigger` | yes | Entry point and action that starts the transition. |
| `guard` | no | Condition enforced; `–` when none. |
| `event` | yes | Event, message, or audit record emitted; `–` when none. |
| `locations` | yes | One or more `path`, `path:line`, or `path:start-end`. Never empty. |
| `flag` | no | Short lowercase word rendered orange on the edge and in the table. |
| `note` | no | Shown under the trigger cell. |
| `bend` | no | Curve offset in px, positive or negative, overriding the automatic spread. Use it when the checker reports a pass-through. |
| `labelAt` | no | Position of the key pill along the curve, 0.15–0.85, default 0.5. Use it when two labels overlap. |

Edges between the same pair of states are spread automatically: a lone edge is straight, opposite
directions bow to opposite sides, extra parallel edges bow further out. Every arrow carries its own
key pill, so two-way traffic is two arrows and two pills, never a shared label.

## Checker output

`--check` runs the structural validation (missing fields, unknown states, key gaps, orphan states,
edges without locations) and the layout checks (label over a state, edge through a state, label over
label). Errors stop the render; warnings do not, but each names the edge and the fix. Resolve every
warning before delivering.
