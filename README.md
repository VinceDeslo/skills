# Skills Catalog

A personal catalog of reusable agent skills, shared across coding agents (Claude Code, OpenCode, GitHub Copilot, Hermes, and others). Skills follow the [Agent Skills specification](https://agentskills.io/specification) and are managed with the [`skills` CLI](https://github.com/vercel-labs/skills).

Full usage and authoring conventions live in [AGENTS.md](AGENTS.md) — the single source of truth for agents and humans alike.

## Installing skills

```bash
skills add vincedeslo/skills                                     # interactive
skills add vincedeslo/skills -s <skill-name> -a claude-code -y   # one skill, one agent
```

## Available skills

| Skill | Description |
| --- | --- |
| [brainsync](skills/brainsync/SKILL.md) | Commit and push the personal notes vault at `~/repos/personal/brain` with a dated commit message |
| [new-skill](skills/new-skill/SKILL.md) | Bootstrap a new skill in this catalog — scaffolding, spec-compliant frontmatter, validation, and commit conventions |

## Adding a skill

Use the [new-skill](skills/new-skill/SKILL.md) skill: with this catalog installed, ask your agent to "create a new skill" and it walks through the whole bootstrap (duplicate check, `skills init` scaffold, frontmatter rules, `skills-ref` validation, Conventional Commits).
