#!/usr/bin/env sh
set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

current_hooks_path="$(git config core.hooksPath || true)"
if [ "$current_hooks_path" = "githooks" ]; then
  git config --unset core.hooksPath
  printf '%s\n' "Removed core.hooksPath=githooks"
else
  printf '%s\n' "core.hooksPath is not githooks; current value: $current_hooks_path"
fi

printf '%s\n' "Local files were kept:"
printf '%s\n' "  githooks/"
printf '%s\n' "  .ai-review.env"
printf '%s\n' "Remove them manually if you no longer need this tool."
