#!/usr/bin/env bash
# Symlink every skill in this repo into a Claude config dir's skills/ folder.
# Usage: ./install.sh [-f] [config_dir ...]   (default: $CLAUDE_CONFIG_DIR or ~/.claude)
#   -f  replace existing real directories (moved to <name>.bak)
set -euo pipefail

force=0
while getopts "f" opt; do
  case "${opt}" in
    f) force=1 ;;
    *) echo "usage: $0 [-f] [config_dir ...]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
targets=("$@")
[[ ${#targets[@]} -gt 0 ]] || targets=("${CLAUDE_CONFIG_DIR:-${HOME}/.claude}")

for cfg in "${targets[@]}"; do
  mkdir -p -- "${cfg}/skills"
  for src in "${repo}"/skills/*/; do
    name="$(basename "${src}")"
    dest="${cfg}/skills/${name}"
    if [[ -L "${dest}" ]]; then
      ln -sfn "${src%/}" "${dest}"
    elif [[ -e "${dest}" ]]; then
      if (( ! force )); then
        echo "skip ${dest} (exists; rerun with -f to replace)" >&2
        continue
      fi
      if [[ -e "${dest}.bak" ]]; then
        echo "skip ${dest} (${dest}.bak already exists; remove it first)" >&2
        continue
      fi
      mv -- "${dest}" "${dest}.bak"
      ln -s "${src%/}" "${dest}"
    else
      ln -s "${src%/}" "${dest}"
    fi
    echo "linked ${dest}"
  done
done
