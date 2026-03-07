#!/usr/bin/env bash
# Install skills from .claude/skills/ into ~/.claude/skills/ via symlinks.
# Usage: bash scripts/install.sh <skills_source_dir>
set -euo pipefail

skills_src="${1:?Usage: install.sh <skills_source_dir>}"

if [[ ! -d "$skills_src" ]]; then
    echo "error: skills source not found: $skills_src" >&2
    exit 1
fi

skills_dst="$HOME/.claude/skills"
mkdir -p "$skills_dst"

installed=0
for skill_dir in "$skills_src"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="$(basename "$skill_dir")"
    target="$skills_dst/$skill_name"
    if [[ -d "$target" && ! -L "$target" ]]; then
        echo "skip: $target exists as a real directory (not a symlink)" >&2
        continue
    fi
    ln -sfn "$skill_dir" "$target"
    echo "linked: $target -> $skill_dir"
    installed=$((installed + 1))
done

if [[ $installed -eq 0 ]]; then
    echo "warning: no skills installed" >&2
    exit 1
fi
echo "done: $installed skill(s) installed"
