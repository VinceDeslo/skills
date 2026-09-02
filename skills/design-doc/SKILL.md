---
name: design-doc
description: Write a design doc for a software idea and publish it as a note in the Obsidian vault at ~/repos/personal/brain, mirroring the repo's location (personal/<repo-name>/<Title>.md). Use when asked to write, draft, record, capture, or publish a design doc, RFC, technical spec, or architecture note for an idea, feature, or project.
compatibility: Requires a local Obsidian vault at ~/repos/personal/brain and git for repository detection. Publishing is a local file write; syncing to the remote is a separate step.
---

# design-doc

Turn an idea into a design doc and publish it into the Obsidian vault, filed under the same path the source repository lives at.

## When to use

The user asks to write, draft, record, capture, or publish a design doc, RFC, spec, or architecture note — typically for personal software they are building or thinking about.

## Destination path

The vault mirrors the repository layout under `~/repos`:

| Repository | Vault note |
| --- | --- |
| `~/repos/personal/pocketbase-sync` | `~/repos/personal/brain/personal/pocketbase-sync/<Title>.md` |
| `~/repos/work/infra` | `~/repos/personal/brain/work/infra/<Title>.md` |

Two path segments: the group (`personal` or `work`) and the repository directory name.

## Instructions

1. **Confirm the vault exists.** Stop and report if it is missing:

   ```bash
   test -d ~/repos/personal/brain/.git || echo "vault missing"
   ```

2. **Resolve the repository.** From the working directory:

   ```bash
   git rev-parse --show-toplevel
   ```

   Take the last two path segments — group and repository name. Strip any worktree suffix from the repository name (`skills.my-branch` → `skills`) so every doc for a repo lands in one folder. If the command fails, or the path is not under `~/repos/personal` or `~/repos/work`, ask the user which repository the doc belongs to instead of guessing.

3. **Pick a title.** A short noun phrase naming the thing being designed, in Title Case — it becomes both the filename and the `title` frontmatter field, and is what wikilinks display. Example: `Offline Sync Queue.md`, not `offline-sync-queue.md`.

4. **Gather context before writing.** Read the repository's `README.md`, `AGENTS.md`, and the code the design touches. A design doc that restates the prompt is not useful; ground every section in what the codebase actually does today.

5. **Ask only what blocks the draft.** If the idea is stated in one line, draft the doc with explicit assumptions in the "Open questions" section rather than interviewing the user first. Ask only when different readings would produce materially different designs.

6. **Write the doc** from [assets/design-doc-template.md](assets/design-doc-template.md). Fill every section; delete a section only when it genuinely does not apply, and say so in the doc.

7. **Publish** to the vault:

   ```bash
   mkdir -p ~/repos/personal/brain/<group>/<repo-name>
   ```

   Write the file there. If a note with that title already exists, read it first and update it in place — never silently overwrite. Bump `updated` in the frontmatter and keep the original `created` date.

8. **Report** the absolute path of the published note. Do not commit or push the vault; tell the user to run `brain-sync` when they want it saved to the remote.

## Frontmatter

Every published doc starts with Obsidian-readable YAML:

```yaml
---
title: Offline Sync Queue
type: design-doc
status: draft
repo: personal/pocketbase-sync
created: 2026-09-02
updated: 2026-09-02
tags:
  - design-doc
  - personal/pocketbase-sync
---
```

- `status`: `draft`, `proposed`, `accepted`, `implemented`, or `abandoned`. New docs start at `draft`.
- `tags`: always include `design-doc` plus the `<group>/<repo-name>` tag, so the vault can list every doc for a repo.
- Dates in `YYYY-MM-DD`, from `date +%F`.

## Notes

- Obsidian renders wikilinks: link related notes as `[[Other Design Doc]]`, and use standard Markdown links for URLs and repository files.
- Mermaid fences render natively in Obsidian. Use one when the design has a flow or a state machine worth drawing; skip it for prose-only docs.
- Keep the doc decision-shaped, not tutorial-shaped: what is being built, why this way, what was rejected, what is still unknown.

## Edge cases

- **No repository yet** — the idea has no code. File it under `personal/<intended-repo-name>/` and note in the doc that the repository does not exist yet.
- **Idea spans several repos.** Publish one doc in the repo that owns the change, and link it from the others with wikilinks rather than duplicating the content.
- **Vault has uncommitted changes.** Irrelevant to publishing — write the note anyway; `brain-sync` handles the commit.
