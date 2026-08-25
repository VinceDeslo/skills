# List all available recipes
default:
    @just --list

# Install all skills globally from this working copy
link:
    skills add {{justfile_directory()}} -g --all

# Install all skills globally from the published GitHub repo
remote:
    skills add vincedeslo/skills -g --all

# Pull the latest version of every globally installed skill
update:
    skills update -g -y

# Show the globally installed skills
list:
    skills list -g

# Validate every skill in this repo against the Agent Skills spec
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for skill in skills/*/; do
        npx skills-ref validate "${skill%/}"
    done
