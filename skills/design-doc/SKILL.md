---
name: design-doc
description: Write a design doc for a software idea and publish it into the Obsidian vault with the Obsidian CLI, filed under the repo's location (personal/<repo-name>/<Title>.md). Use when asked to write, draft, record, capture, or publish a design doc, RFC, technical spec, or architecture note for an idea, feature, or project.
compatibility: Requires the `obsidian` CLI on PATH with the Obsidian app running and the `brain` vault available, plus git for repository detection. The CLI is the only supported write path into the vault; syncing to the remote is a separate step.
---

# design-doc

Turn an idea into a design doc and publish it into the Obsidian vault through the Obsidian CLI, filed under the same path the source repository lives at.

## When to use

The user asks to write, draft, record, capture, or publish a design doc, RFC, spec, or architecture note — typically for personal software they are building or thinking about.

## Hard requirement: publish through the Obsidian CLI

Every read and write inside the vault goes through the `obsidian` CLI. Never create, edit, or move a vault note with file-write tools, shell redirection, `mkdir`, `cp`, or an editor — even though the vault is a plain git checkout on disk. The CLI keeps the running app's index, properties, links, and sync state correct; a raw write leaves the vault stale.

Drafting is the exception: compose the doc in a scratch file outside the vault, then hand it to the CLI.

## Destination path

The vault mirrors the repository layout under `~/repos`:

| Repository | Vault path (`path=`) |
| --- | --- |
| `~/repos/personal/pocketbase-sync` | `personal/pocketbase-sync/<Title>.md` |
| `~/repos/work/infra` | `work/infra/<Title>.md` |

Two path segments: the group (`personal` or `work`) and the repository directory name. `obsidian create` creates missing folders on its own — do not pre-create them.

## Instructions

1. **Confirm the CLI and the vault.** Stop and report if either is missing; do not fall back to a direct file write.

   ```bash
   command -v obsidian || echo "obsidian CLI missing"
   obsidian vaults
   obsidian vault info=path
   ```

   If more than one vault is listed, add `vault=brain` to every later command.

2. **Resolve the repository.** From the working directory:

   ```bash
   git rev-parse --show-toplevel
   ```

   Take the last two path segments — group and repository name. Strip any worktree suffix from the repository name (`skills.my-branch` → `skills`) so every doc for a repo lands in one folder. If the command fails, or the path is not under `~/repos/personal` or `~/repos/work`, ask the user which repository the doc belongs to instead of guessing.

3. **Pick a title.** A short noun phrase naming the thing being designed, in Title Case — it becomes both the filename and the `title` property, and is what wikilinks display. Example: `Offline Sync Queue.md`, not `offline-sync-queue.md`.

4. **Gather context before writing.** Read the repository's `README.md`, `AGENTS.md`, and the code the design touches. A design doc that restates the prompt is not useful; ground every section in what the codebase actually does today.

5. **Ask only what blocks the draft.** If the idea is stated in one line, draft the doc with explicit assumptions in the "Open questions" section rather than interviewing the user first. Ask only when different readings would produce materially different designs.

6. **Draft outside the vault.** Write the doc from [assets/design-doc-template.md](assets/design-doc-template.md) into a scratch file (for example `/tmp/design-doc-draft.md`). Fill every section; delete a section only when it genuinely does not apply, and say so in the doc.

7. **Check whether the note already exists:**

   ```bash
   obsidian file path="<group>/<repo-name>/<Title>.md"
   ```

   `not found` means it is new. Anything else means it exists — read it before touching it, and keep its original `created` date:

   ```bash
   obsidian read path="<group>/<repo-name>/<Title>.md"
   ```

8. **Publish.** New note:

   ```bash
   obsidian create path="<group>/<repo-name>/<Title>.md" content="$(cat /tmp/design-doc-draft.md)"
   ```

   Existing note — `overwrite` is required, and only after step 7:

   ```bash
   obsidian create path="<group>/<repo-name>/<Title>.md" content="$(cat /tmp/design-doc-draft.md)" overwrite
   ```

   Add `open` to either command to surface the note in Obsidian after writing.

9. **Verify and report.** Read the note back, then report its vault path plus the absolute path (`obsidian vault info=path` + the vault path). Do not commit or push the vault; tell the user to run `brain-sync` when they want it saved to the remote.

## Obsidian CLI notes

- **Exit status is always 0.** Failures are reported as `Error: ...` on stdout. Check the output text, never `$?`.
- **`create` without `overwrite` never fails on a collision** — it silently writes `<Title> 1.md` next to the original. Always run the step 7 existence check first, or a duplicate doc appears.
- **`content=` accepts real newlines**, so `content="$(cat draft.md)"` publishes a multi-line doc as-is. `\n` and `\t` escapes also work for short one-line additions.
- **Quote every value containing spaces**: `path="personal/skills/My Note.md"`.
- **`path=` is exact** (`folder/note.md`); `file=` resolves by note name like a wikilink. Use `path=` for publishing, `file=` only for lookups.
- Useful follow-ups: `obsidian append` / `obsidian prepend` to add a section to an existing doc, `obsidian property:set` to change one property (for example `status`) without rewriting the note, `obsidian files folder="personal/<repo-name>"` to list a repo's docs, and `obsidian move` to relocate or rename one.

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

- `status`: `draft`, `proposed`, `accepted`, `implemented`, or `abandoned`. New docs start at `draft`. Later status changes are one command: `obsidian property:set name=status value=accepted path="<group>/<repo-name>/<Title>.md"`.
- `tags`: always include `design-doc` plus the `<group>/<repo-name>` tag, so the vault can list every doc for a repo.
- Dates in `YYYY-MM-DD`, from `date +%F`.

## Notes

- Obsidian renders wikilinks: link related notes as `[[Other Design Doc]]`, and use standard Markdown links for URLs and repository files.
- Mermaid fences render natively in Obsidian. Use one when the design has a flow or a state machine worth drawing; skip it for prose-only docs.
- Keep the doc decision-shaped, not tutorial-shaped: what is being built, why this way, what was rejected, what is still unknown.

## Edge cases

- **Obsidian not running.** The CLI drives the live app, so commands fail while it is closed. Report that Obsidian must be open and stop — do not write the note to disk directly.
- **No repository yet** — the idea has no code. File it under `personal/<intended-repo-name>/` and note in the doc that the repository does not exist yet.
- **Idea spans several repos.** Publish one doc in the repo that owns the change, and link it from the others with wikilinks rather than duplicating the content.
- **Duplicate `<Title> 1.md` created by mistake.** Delete it with `obsidian delete path="<group>/<repo-name>/<Title> 1.md"` (it goes to trash; add `permanent` only if the user asks), then republish with `overwrite`.
- **Vault has uncommitted changes.** Irrelevant to publishing — publish anyway; `brain-sync` handles the commit.
