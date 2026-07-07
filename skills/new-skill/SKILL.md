---
name: new-skill
description: Bootstrap a new agent skill in the skills catalog. Use when asked to create, add, scaffold, or bootstrap a new skill in this repository, or when converting a repeated workflow into a reusable skill.
---

# new-skill

Bootstrap a new skill in this repository, following the [Agent Skills specification](https://agentskills.io/specification).

## Instructions

1. **Check for duplicates.** List `skills/` and read the descriptions of anything similar. If an existing skill covers the task, extend it instead of creating a new one.

2. **Pick a name.** 1–64 characters; lowercase letters, digits, and hyphens only; no leading, trailing, or consecutive hyphens. Name the task, not the tool (e.g. `terraform-plan-review`, not `terraform`).

3. **Scaffold with the CLI** from the repo root — never write `SKILL.md` by hand from scratch:

   ```bash
   cd skills
   skills init <skill-name>
   ```

   This creates `skills/<skill-name>/SKILL.md` with valid frontmatter and a body template.

4. **Write the frontmatter.**
   - `name`: must exactly match the directory name.
   - `description`: state what the skill does **and** when to use it, with keywords an agent can match against a task. Bad: "Helps with PDFs." Good: "Extracts text and tables from PDF files, fills forms, and merges PDFs. Use when working with PDF documents or when the user mentions PDFs, forms, or document extraction."
   - Add `compatibility` only if the skill needs specific tools, network access, or a particular environment.
   - Keep skills agent-agnostic; this catalog is shared across Claude Code, OpenCode, Copilot, Hermes, and others.

5. **Write the body** for progressive disclosure — the body only loads once the skill activates, so the description carries discovery:
   - Step-by-step instructions, concrete input/output examples, known edge cases.
   - Keep `SKILL.md` under 500 lines. Move long reference material to `references/<topic>.md` and link it with relative paths from the skill root, one level deep.
   - Put runnable helpers in `scripts/` (self-contained or with dependencies documented) and static templates or data in `assets/`.

6. **Validate:**

   ```bash
   npx skills-ref validate skills/<skill-name>
   ```

   Fix anything it reports before committing.

7. **Update the README.** Add the new skill to the "Available skills" table in `README.md` at the repo root.

8. **Commit** with a Conventional Commits message:

   ```bash
   git add skills/<skill-name> README.md
   git commit -m "feat(<skill-name>): add skill"
   ```

## Edge cases

- **Renaming a skill:** rename the directory and the `name` field together — they must always match.
- **A skill that grows past 500 lines:** split detail into `references/` files rather than trimming instructions the agent needs.
- **CLI missing:** `skills` is expected on the host (https://github.com/vercel-labs/skills); fall back to `npx skills init <name>` if not on PATH.
