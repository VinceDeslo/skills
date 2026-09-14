---
name: generate-artifact
description: Build a self-contained HTML artifact on any subject the user asks for — a report, digest, comparison, diagram, dashboard, cheat sheet, or explainer — and save it into ~/.artifacts, then serve that directory locally with a generated index page that lists every artifact and updates as new files land. Use when asked to generate, build, produce, or render an artifact or HTML page about something, to save output to the artifacts directory, to open, list, browse, or serve the artifacts, or when the user says "generate-artifact".
compatibility: Requires shell access and `python3` (standard library only). Optional — a browser opener (`open`, `xdg-open`, or `start`) to display the page.
---

# generate-artifact

Turn a subject into one self-contained HTML file under `~/.artifacts`, and keep a local server
running that lists every file in that directory from a single index page.

Three properties define the output:

- **Self-contained.** One `.html` file. Inline CSS, inline SVG, inline data, no network requests.
  The file must render correctly when opened from disk with no server at all.
- **Discoverable.** Every artifact carries a `<title>` and a `<meta name="description">` in its
  head. The index page is built from those two tags, so they are the artifact's card.
- **Grounded.** The page states where its content came from — files read, commands run, sources
  consulted — in a closing Method section. Nothing on the page is asserted from memory when it
  could be read.

## When to use

The user asks for an artifact, an HTML page, a report, a one-pager, a visual summary, a diagram, or
a dashboard about some subject and wants it kept locally; asks to open, list, browse, or serve the
artifacts; or says "generate-artifact".

Not for artifacts that must be published to a hosted link. If the host agent has a publishing
capability and the user asks for a link, build the file with this skill first, then publish the
same file unchanged.

## Instructions

### 1. Resolve the subject and the sources

Take the subject from the request. Decide what the page must answer before writing any HTML: the
one question a reader opens it for, and the two or three sections that answer it. Gather the
material — read the code, run the commands, fetch the documents — and keep the paths, commands,
and commit hashes you used for the Method section.

If the subject is a chart or data visualization and the host agent has a data visualization skill,
load it before writing chart markup.

### 2. Pick the file name

Slugify the subject: lowercase, digits and hyphens only, no leading or trailing hyphen, at most
about 60 characters. Append a timestamp so repeated runs never overwrite each other:

```bash
mkdir -p ~/.artifacts
out="$HOME/.artifacts/<slug>-$(date +%Y%m%d-%H%M%S).html"
```

Only overwrite an existing file when the user asks to update that specific artifact.

### 3. Write the page

Start from [assets/artifact-template.html](assets/artifact-template.html). Replace every
`{{PLACEHOLDER}}`, keep the `<head>` block, and keep the CSS token approach so the page renders in
both light and dark themes. Fill the head first:

- `<title>` — a short noun phrase naming the subject, two to five words, unique enough to pick out
  of a long list.
- `<meta name="description">` — one sentence stating what the page shows and for what scope
  (repository, date range, version).

Then the body:

- **Summary** at the top: the answer to the question from step 1 in three sentences at most.
- **Content sections**: one `<section>` per topic. Prefer tables for parallel facts, `<pre>` for
  commands and snippets, inline SVG for diagrams. Wrap wide tables in `<div class="table-wrap">`.
- **Method** at the end: repositories and commits read, commands run, documents fetched, and any
  caveat about what was not checked.

Rules for the markup:

- No `<script src>`, `<link href>`, `<img src>`, `@import`, or `url()` pointing at a network host.
  Embed images as `data:` URIs if they are essential; otherwise leave them out.
- Keep the file under 16 MB. Move bulk data into a compact inline table rather than a dump.
- Text and controls must stay readable at a 400px wide viewport; the template CSS handles this if
  layout stays in the provided classes.

### 4. Check

```bash
python3 <skill-dir>/scripts/check_artifact.py "$out"
```

The checker reports a missing title, description, charset, or viewport, any external resource
reference, and files over the size limit. Fix every problem before delivering.

### 5. Serve and open

```bash
python3 <skill-dir>/scripts/serve.py --open
```

The server binds `127.0.0.1:8642`, detaches into the background, and writes its pid to
`~/.artifacts/.serve.pid`. Running the command again while it is up prints the URL and does
nothing else. The index at `/` is generated on every request by scanning `~/.artifacts` for
`*.html`, newest first, so a freshly saved artifact appears on the next reload with no extra step.
`/index.json` returns the same listing as JSON.

Other server commands:

```bash
python3 <skill-dir>/scripts/serve.py --status          # running or stopped
python3 <skill-dir>/scripts/serve.py --stop            # stop the background server
python3 <skill-dir>/scripts/serve.py --port 9000       # different port
python3 <skill-dir>/scripts/serve.py --dir <path>      # different directory
python3 <skill-dir>/scripts/serve.py --write-index     # static ~/.artifacts/index.html, no server
python3 <skill-dir>/scripts/serve.py --foreground      # run attached, for debugging
```

If the user only asked to open one artifact and does not need the list, opening the file directly
is enough:

```bash
open "$out"        # macOS
xdg-open "$out"    # Linux
start "" "$out"    # Windows
```

### 6. Report

Summarize in chat in **three lines at most**: the artifact path, the index URL, and the single most
important finding on the page. Everything else is on the page.

## Edge cases

- **Subject already has an artifact:** list matching slugs in `~/.artifacts` and say so. Create a
  new timestamped file unless the user asked to update the existing one.
- **Port in use by something else:** the script treats an open port as an already running server.
  Confirm with `--status`; if the pid is missing, pass a different `--port`.
- **Directory holds non-artifact HTML** (a saved web page, a template): the index lists any
  `*.html` except `index.html` and files in dot-directories. Move stray files into a dot-directory
  such as `~/.artifacts/.archive/` to hide them.
- **Content needs a chart library or web font:** do not load it from a CDN. Draw the chart as inline
  SVG and use the system font stack in the template.
- **Very large data set:** summarize it in the page and cite the source path; do not embed the raw
  data when it would push the file past a few megabytes.
- **Another skill already produces HTML** (`entity-machine`, `pr-digest`, `service-scorecard`,
  `pr-assignments`): let that skill build the page, then copy or save its output into `~/.artifacts`
  so the index picks it up.
