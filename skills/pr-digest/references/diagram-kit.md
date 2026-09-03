# Diagram kit

The digest carries at most one diagram, built from plain HTML elements styled by the CSS already in
`assets/review-template.html`. There is no diagram library and no external script: the report is a
single self-contained file, and the diagram is readable at body text size without zooming or
scrolling sideways.

Author the markup by hand. Pick **one** body pattern below, delete the rest of the figure, and keep
the legend rows for the states the diagram actually uses.

## The three states

| Class | Colour | Means |
| --- | --- | --- |
| `is-new` | green | The PR introduces this. It did not exist before. |
| `is-changed` | blue | The PR modifies this. It existed and behaves differently now. |
| `is-gone` | grey, dashed | The PR removes or bypasses this. Include only when its absence is the point. |
| *(none)* | neutral | Untouched context. Most nodes should be this — the colours only mean something if they are rare. |

Colour never carries meaning alone. A coloured node also gets a `<span class="tag">new</span>` or
`<span class="tag">mod</span>`, so the state survives greyscale printing and colour blindness.

Drop any legend row whose state is unused. A legend listing three states when the diagram shows one
is noise.

## Sizing rules

- **Twelve nodes maximum**, and fewer is better. This is a digest, not an architecture poster.
- **Node labels under ~28 characters.** Long identifiers go in the `kind` line or the caption.
- **Identifiers are `<code>`.** A node naming a real symbol, table, queue, or file wraps it in
  `<code>`; a node naming a concept ("Request", "Retry") does not. Same for `.what` and edge labels.
- **Edge labels under ~40 characters.** They wrap, but a wrapped three-line edge label means the
  diagram is carrying an explanation that belongs in the caption.
- Everything wraps by design. Never add `overflow-x` or a fixed width to make something fit — if it
  does not fit, it is too big.

## Pattern: `.flow`

A path through components. The default choice, and right for most PRs.

```html
<div class="flow">
  <div class="node"><span class="kind">http</span>Request</div>
  <div class="edge"><span class="label">resolve tenant</span><span class="line"></span></div>
  <div class="node is-new"><span class="kind">lru</span><code>tenantCache</code><span class="tag">new</span></div>
  <div class="edge is-new"><span class="label">miss</span><span class="line"></span></div>
  <div class="node"><span class="kind">postgres</span><code>tenants</code></div>
</div>
```

`.edge` also takes `dashed` for a path that no longer fires, and `is-new` / `is-changed` to colour
the connector itself when the *edge* is what changed rather than the node.

For a fan-out, wrap the destinations in `.branch` lanes:

```html
<div class="flow">
  <div class="node">Queue</div>
  <div class="branch">
    <div class="lane">
      <div class="edge"><span class="label">receives &lt; 3</span><span class="line"></span></div>
      <div class="node">Handler</div>
    </div>
    <div class="lane">
      <div class="edge is-changed"><span class="label">receives = 3</span><span class="line"></span></div>
      <div class="node is-changed"><code>action-dlq</code><span class="tag">mod</span></div>
    </div>
  </div>
</div>
```

## Pattern: `.steps`

Ordered interactions between participants — the replacement for a sequence diagram, and easier to
read at this size because it is a numbered list, not a grid of lifelines.

```html
<ol class="steps">
  <li>
    <div>
      <div class="hop"><span class="actor">Handler</span><span class="arrow">→</span><span class="actor is-new"><code>tenantCache</code></span></div>
      <div class="what">Looks up the tenant before touching <code>tenants</code>.</div>
    </div>
  </li>
</ol>
```

Each `<li>` holds one wrapper `<div>` containing the `.hop` and its `.what`. Keep to six steps.

## Pattern: `.stack`

Grouped layers or subsystems, when the change is about *where* something now lives rather than the
order things happen in.

```html
<div class="stack">
  <div class="layer">
    <h4>Transport</h4>
    <div class="nodes">
      <span class="node"><code>router</code></span>
      <span class="node is-changed"><code>requireAuth</code><span class="tag">mod</span></span>
    </div>
  </div>
  <div class="layer">
    <h4>Domain</h4>
    <div class="nodes"><span class="node is-new"><code>TenantResolver</code><span class="tag">new</span></span></div>
  </div>
</div>
```

## Pattern: `table.fields`

A schema, payload, or config shape change — the replacement for an ER diagram.

```html
<table class="fields">
  <thead><tr><th>Field</th><th>Type</th><th>Note</th></tr></thead>
  <tbody>
    <tr class="is-new"><td>region</td><td>text not null</td><td>New; part of the cache key.</td></tr>
    <tr class="is-changed"><td>tenant_id</td><td>uuid</td><td>Was text; backfilled in the same migration.</td></tr>
    <tr class="is-gone"><td>legacy_shard</td><td>int</td><td>Dropped.</td></tr>
  </tbody>
</table>
```

## When not to draw one

A diagram that restates the file list is worse than no diagram. Delete the whole
`<figure class="card diagram">` block when the change is a bug fix inside one function, a dependency
bump, a copy or config tweak, or anything else with no structure to show.

The test: if the caption would say "the code, and the thing it calls", there is no diagram to draw.
