# Report template tokens

Fill every token in [../assets/report-template.html](../assets/report-template.html). Three elements are exemplars that get duplicated; the rest are single substitutions.

## Header

| Token | Value |
| --- | --- |
| `{{SERVICE_NAME}}` | Service name — from the manifest or directory, not the repo slug if they differ |
| `{{REPO}}` | `owner/repo`, or the absolute path when there is no remote |
| `{{COMMIT_SHORT}}` | Short SHA of the graded commit |
| `{{STACK}}` | Primary language and framework, e.g. `Go · chi · Postgres` |
| `{{FILE_COUNT}}` / `{{LOC}}` | Tracked source files and lines, generated code excluded |
| `{{GENERATED_DATE}}` | ISO date, in both the header and the footer |

## Overall panel

| Token | Value |
| --- | --- |
| `{{OVERALL_CLASS}}` | `g-a` … `g-f`, matching the overall letter |
| `{{OVERALL_LETTER}}` | The letter |
| `{{VERDICT}}` | One or two sentences: what this service is like to maintain today |
| `{{OVERALL_GPA}}` | Two decimals, e.g. `3.24` |
| `{{OVERALL_MATH}}` | The visible arithmetic, e.g. `Σ(weight × points) 129 ÷ Σ(weight) 40` |

## Summary grid — duplicate the `<a class="chip">` element once per facet, worst grade first

| Token | Value |
| --- | --- |
| `{{CHIP_CLASS}}` | `g-a` … `g-f`, or `g-na` |
| `{{CHIP_LETTER}}` | The letter, or `N/A` |
| `{{CHIP_NAME}}` | Facet name |
| `{{CHIP_WEIGHT}}` | `3`, `2`, or `1` |
| `{{CHIP_ANCHOR}}` | Kebab-case slug, matching the facet section's `id` |

## Facet sections — duplicate the `<section class="card facet">` element once per facet, in the same order as the grid

| Token | Value |
| --- | --- |
| `{{FACET_CLASS}}` / `{{FACET_LETTER}}` / `{{FACET_NAME}}` / `{{FACET_WEIGHT}}` / `{{FACET_ANCHOR}}` | As above |
| `{{FACET_ONE_LINER}}` | Six to ten words naming what the facet measures |
| `{{ON_A}}` … `{{ON_F}}` | `on` for the achieved grade's segment, empty string for the other five. For N/A leave all six empty |
| `{{FACET_ASSESSMENT}}` | Two to four sentences. What was found, why it lands at this grade against the rubric anchors. Duplicate the `<p>` for a second paragraph |
| `{{EVIDENCE_PATH}}` | `path/to/file.go:120` — duplicate the `<li>` per item, two to five items |
| `{{EVIDENCE_NOTE}}` | What that path shows, in a clause |
| `{{FIX_TITLE}}` | Imperative, five to nine words, e.g. `Collapse the DTO mapper tier` |
| `{{FIX_DETAIL}}` | The concrete change, naming the files. Exactly three `<li>` per facet, highest impact first |

Wrap paths and identifiers in `<code>` inside assessments and fixes.

## Methodology

| Token | Value |
| --- | --- |
| `{{SCOPE_NOTE}}` | What was graded — whole repo, or a subdirectory of a monorepo; whether the read was complete or sampled, and what was sampled |
| `{{EXCLUSIONS_NOTE}}` | Generated code, vendored trees, and anything else left out |
| `{{CONFIDENCE_NOTE}}` | Where the grades rest on inference rather than direct evidence, and which facets are N/A and why |

## Rules

- Keep the document self-contained: no external fonts, scripts, stylesheets, or images.
- Do not add a theme toggle; the CSS already follows the reader's system theme and any host `data-theme` attribute.
- Order both lists identically: F → E → D → C → B → A, then N/A, breaking ties on grade by weight, heaviest first.
- Delete an unfilled token rather than shipping `{{...}}` into the report.
