#!/usr/bin/env bash
# Symlink every skill in this repo into a Claude config dir's skills/ folder.
# Usage: ./install.sh [-f] [config_dir ...]   (default: $CLAUDE_CONFIG_DIR or ~/.claude)
#   -f  replace existing real directories (moved to <name>.bak)
set -euo pipefail

force=0
if [[ "${1:-}" == "-f" ]]; then force=1; shift; fi
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
targets=("$@")
[[ ${#targets[@]} -gt 0 ]] || targets=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}")

for cfg in "${targets[@]}"; do
  mkdir -p "$cfg/skills"
  for src in "$repo"/skills/*/; do
    name="$(basename "$src")"
    dest="$cfg/skills/$name"
    if [[ -L "$dest" ]]; then
      ln -sfn "${src%/}" "$dest"
    elif [[ -e "$dest" ]]; then
      if (( force )); then
        mv "$dest" "$dest.bak"
        ln -s "${src%/}" "$dest"
      else
        echo "skip $dest (exists; rerun with -f to replace)" >&2
        continue
      fi
    else
      ln -s "${src%/}" "$dest"
    fi
    echo "linked $dest"
  done
done
