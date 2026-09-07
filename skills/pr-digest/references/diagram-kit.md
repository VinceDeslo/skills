# Diagram kit

The digest carries at most one diagram, built from plain HTML elements styled by the CSS already in
`assets/review-template.html`. There is no diagram library and no external script: the report is a
single self-contained file, and the diagram is readable at body text size without zooming or
scrolling sideways.

The diagram is always a **before / after pair**: two `.panel`s inside one `.compare`, the left
showing the shape at the base branch and the right the shape at the PR head. Author the markup by
hand. Pick **one** body pattern below and use it in **both** panels, delete the rest of the figure,
and keep the legend rows for the states the panels actually use.

The same kit also supplies the `.trace` block every major and minor finding carries — a call stack
from the entry point down to the line the finding is about. See the end of this file.

## Before / after

```html
<div class="compare">
  <div class="panel before">
    <h4>Before <code>main</code></h4>
    <div class="flow">
      <div class="node"><span class="kind">http</span>Request</div>
      <div class="edge"><span class="label">resolve tenant</span><span class="line"></span></div>
      <div class="node is-gone"><span class="kind">inline</span><code>SELECT … FROM tenants</code><span class="tag">gone</span></div>
    </div>
  </div>
  <div class="panel after">
    <h4>After <code>feat/tenant-cache</code></h4>
    <div class="flow">
      <div class="node"><span class="kind">http</span>Request</div>
      <div class="edge"><span class="label">resolve tenant</span><span class="line"></span></div>
      <div class="node is-new"><span class="kind">lru</span><code>tenantCache</code><span class="tag">new</span></div>
      <div class="edge is-new"><span class="label">miss</span><span class="line"></span></div>
      <div class="node"><span class="kind">postgres</span><code>tenants</code></div>
    </div>
  </div>
</div>
```

Rules for the pair:

- **Same pattern on both sides.** A `.flow` before and a `.stack` after cannot be compared. If the
  PR changes *where* things live, both sides are `.stack`; if it changes *what calls what*, both are
  `.flow` or `.steps`.
- **Same node order.** Nodes that exist on both sides sit in the same position, so the eye reads
  the difference and not a rearrangement.
- **States split by side.** The before panel is neutral, with `is-gone` on what the PR deletes or
  bypasses. The after panel carries `is-new` and `is-changed`. Never put `is-new` on the before side
  or `is-gone` on the after side.
- **Purely additive PR:** the before panel still exists and shows the existing path the new code
  plugs into, so the reader sees the attachment point. It is the after panel minus the new nodes.
- **Flows run top-to-bottom inside a panel.** The CSS turns `.flow` vertical there, so a node in
  position three on the left sits level with position three on the right. Write the markup exactly
  as for a horizontal flow; the direction is automatic.
- **Eight nodes per panel maximum.** Two panels share the width, so each carries less than a single
  diagram would. The `.compare` grid stacks vertically below about 640px, so nothing is lost on a
  narrow window — but a panel that only reads when stacked is too wide.
- The panel heading names the branch or ref in `<code>`; the caption says what moved and why.

## The three states

| Class | Colour | Panel | Means |
| --- | --- | --- | --- |
| `is-new` | green | after | The PR introduces this. It did not exist before. |
| `is-changed` | blue | after | The PR modifies this. It existed and behaves differently now. |
| `is-gone` | grey, dashed | before | The PR removes or bypasses this. |
| *(none)* | neutral | both | Untouched context. Most nodes should be this — the colours only mean something if they are rare. |

Colour never carries meaning alone. A coloured node also gets a `<span class="tag">new</span>`,
`<span class="tag">mod</span>`, or `<span class="tag">gone</span>`, so the state survives greyscale
printing and colour blindness.

Drop any legend row whose state is unused. A legend listing three states when the diagram shows one
is noise.

## Sizing rules

- **Eight nodes per panel maximum**, and fewer is better. This is a digest, not an architecture
  poster.
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

## Finding trace: `.trace`

Every major and minor finding carries a call stack that places it in the flow: where execution
enters, which layers it passes through, and the line the finding is about. It sits between the
detail paragraph and the failure/fix paragraphs, so a reader who opens the finding sees the path
before the prose.

```html
<ol class="trace">
  <li>
    <span class="frame"><code>.github/workflows/vuln-check.yml</code> · <code class="fn">scan</code></span>
    <code class="excerpt">uses: ./.github/actions/vuln-check</code>
  </li>
  <li>
    <span class="frame"><code>.github/actions/vuln-check/action.yml</code> · <code class="fn">reachable</code></span>
    <code class="excerpt">run: bun scripts/reachable.ts "$BASE" "$HEAD"</code>
  </li>
  <li>
    <span class="frame"><code>scripts/reachable.ts</code> · <code class="fn">main</code></span>
    <code class="excerpt">const findings = collectFindings(await readScan(headPath))</code>
  </li>
  <li class="hit">
    <span class="frame"><code>.github/actions/lib/osv.ts:42</code> · <code class="fn">collectFindings</code></span>
    <code class="excerpt">for (const result of scan.results) {</code>
    <span class="why"><code>results</code> is absent when the scanner exits 0 with no findings; this throws.</span>
  </li>
</ol>
```

Rules:

- **Entry point first, finding site last** (or nearly last — one frame *after* the `.hit` is
  allowed when the wrong value flows somewhere and that is the point). Three to six frames.
- **One frame per layer**, not per line. A frame is a file plus the function, step, job, handler,
  or rule name within it. Skip layers that only forward the call unchanged.
- **Every excerpt is real.** Each `.excerpt` is a line read at the PR head — `git show
  refs/remotes/pr/<n>:<path>` — trimmed of leading whitespace and cut to one line. Do not paraphrase
  code and do not invent a plausible call. If a frame's excerpt cannot be read, the frame is not
  written.
- **The `.hit` frame is the finding's location.** Its `.frame` carries `path:line`, identical to the
  finding's `.loc`, and its `.why` is one clause saying what is wrong on that line — the excerpt
  shows the code, the `.why` shows the fault.
- **Escape first.** `<`, `>`, and `&` in excerpts become entities before the `<code>` wrapping.
- Nits carry no trace. A `likely` finding still carries one — the frames you could read are what
  make it likely rather than a guess.
- Indentation is automatic (each frame steps in by depth). Do not add your own.
