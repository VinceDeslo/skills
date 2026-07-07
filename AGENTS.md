# Skills Catalog

This repository is the single source of truth for reusable agent skills, shared across coding agents (Claude Code, OpenCode, GitHub Copilot, Hermes, Codex, Cursor, and others). Skills follow the [Agent Skills specification](https://agentskills.io/specification) and are managed with the [`skills` CLI](https://github.com/vercel-labs/skills), which is installed on this host.

## Repository layout

```
skills/                  # All skills live here (the CLI's default container directory)
  <skill-name>/
    SKILL.md             # Required: YAML frontmatter + instructions
    scripts/             # Optional: executable code the agent can run
    references/          # Optional: docs loaded on demand
    assets/              # Optional: templates, images, data files
AGENTS.md                # This file
CLAUDE.md                # Imports this file for Claude Code
README.md                # Human-facing landing page; lists available skills
```

One skill per directory. Keep the layout flat: `skills/<skill-name>/SKILL.md`. Do not nest skills inside each other.

## Creating a skill

Follow the [new-skill](skills/new-skill/SKILL.md) skill — it covers the full workflow: duplicate check, scaffolding with `skills init`, spec-compliant frontmatter, progressive-disclosure body structure, validation, README update, and commit format.

## Installing skills from this repo into an agent

Consumers (including you, when working in another project) install with the `skills` CLI:

```bash
# Interactive: pick skills and target agents
skills add vincedeslo/skills                                  # or the full GitHub URL, or a local path

# Non-interactive examples
skills add vincedeslo/skills -s <skill-name> -a claude-code -y   # one skill, one agent
skills add vincedeslo/skills --all                               # all skills, all agents
skills add vincedeslo/skills -g -s <skill-name> -a '*' -y        # globally, all agents
```

The CLI symlinks by default so installed skills stay in sync with this repo; pass `--copy` only when a symlink won't work. Use `skills list` to see what's installed, `skills update` to pull newer versions, and `skills remove` to uninstall.

## Working conventions (creating *and* modifying skills)

- **Keep skills agent-agnostic.** They are shared across many agents, so avoid instructions that only work in one tool; declare genuine environment requirements in `compatibility`.
- **A skill's `name` and its directory name must always match** — rename them together.
- **Validate** every new or modified skill with `npx skills-ref validate skills/<skill-name>` before committing.
- **Keep the README's "Available skills" table in sync** when a skill is added, renamed, or removed.
- **Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)**, e.g. `feat(terraform-plan-review): add skill`, `fix(pdf-processing): correct merge script`, `docs: update AGENTS.md`.
