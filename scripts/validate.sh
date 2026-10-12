#!/usr/bin/env bash
# Validate skill frontmatter and guard against leaking hostnames/secrets (repo is public).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

for dir in skills/*/; do
  name="$(basename "$dir")"
  f="${dir}SKILL.md"
  [[ -f "$f" ]] || { err "$dir has no SKILL.md"; continue; }
  fm="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$f")"
  [[ -n "$fm" ]] || { err "$f: missing frontmatter"; continue; }
  grep -qx "name: $name" <<<"$fm" || err "$f: 'name:' must be '$name'"
  grep -q '^description:' <<<"$fm" || err "$f: missing description"
  ! grep -q '^user-invokable:' <<<"$fm" || err "$f: use 'user-invocable', not 'user-invokable'"
done

# Public repo: no public-domain hostnames or secret-looking assignments.
if grep -rnE '\.net\b|(password|token|secret)[[:space:]]*=[[:space:]]*"[A-Za-z0-9+/]{16,}"' \
  skills install.sh README.md; then
  err "possible leaked hostname or secret (see matches above)"
fi

exit "$fail"
