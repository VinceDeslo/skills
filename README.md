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
| [brain-sync](skills/brain-sync/SKILL.md) | Commit and push the personal notes vault at `~/repos/personal/brain` with a dated commit message |
| [design-doc](skills/design-doc/SKILL.md) | Write a design doc for a software idea and publish it into the Obsidian vault with the Obsidian CLI, filed under the source repository's path |
| [feature](skills/feature/SKILL.md) | Start a feature from a Linear ticket — create a ticket-prefixed worktree, scaffold the implementation, and stop at a reviewable state without committing or pushing |
| [new-skill](skills/new-skill/SKILL.md) | Bootstrap a new skill in this catalog — scaffolding, spec-compliant frontmatter, validation, and commit conventions |
| [pr-assignments](skills/pr-assignments/SKILL.md) | Crawl every open GitHub PR whose review was requested from you in the last two weeks, summarize each in a line with its comment conversation, CI state, and review status, and rank them by review-SLA expiry — direct requests first, then team requests — into a self-contained HTML report |
| [pr-digest](skills/pr-digest/SKILL.md) | Review a PR from its link in four in-session passes — orient, correctness, fit, verify — and emit a short HTML digest of at most five major, five minor, and five nits into a reboot-cleared `temp_reviews` directory, without touching the PR |
| [prune-trees](skills/prune-trees/SKILL.md) | Remove worktrees already merged into the default branch across every repository under `~/repos/personal` and `~/repos/work`, previewed as one table for approval before anything is removed |
| [refresh-repos](skills/refresh-repos/SKILL.md) | Fast-forward the default branch of every repository under `~/repos/personal` and `~/repos/work`, discovering them with worktrunk |
| [service-scorecard](skills/service-scorecard/SKILL.md) | Audit a service repo and produce a shareable HTML report card grading it A–F across 23 facets, each with the top 3 paths to improvement |
| [simplify-comments](skills/simplify-comments/SKILL.md) | Condense and de-duplicate the comments added by the current worktree diff, following the repository's own comment guidelines when it has any |
| [stage-split](skills/stage-split/SKILL.md) | Split the currently staged changes into focused Conventional Commits, proposed as a table for approval before anything is committed |

## Adding a skill

Use the [new-skill](skills/new-skill/SKILL.md) skill: with this catalog installed, ask your agent to "create a new skill" and it walks through the whole bootstrap (duplicate check, `skills init` scaffold, frontmatter rules, `skills-ref` validation, Conventional Commits).
