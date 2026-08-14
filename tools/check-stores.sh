#!/usr/bin/env bash
set -euo pipefail

STORES_FILE=""
if [ "${1:-}" = --file ]; then
  [ -n "${2:-}" ] || { printf 'error: --file requires a path\n' >&2; exit 1; }
  STORES_FILE="$2"; shift 2
elif [ -f ./stores.yml ]; then
  STORES_FILE=./stores.yml
elif [ -f "$HOME/.ai-toolkit/stores.yml" ]; then
  STORES_FILE="$HOME/.ai-toolkit/stores.yml"
else
  printf 'error: stores.yml not found\n' >&2; exit 1
fi
[ $# -eq 0 ] || { printf 'error: unknown option: %s\n' "$1" >&2; exit 1; }
[ -f "$STORES_FILE" ] || { printf 'error: file not found: %s\n' "$STORES_FILE" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'error: curl is required\n' >&2; exit 1; }

parse_stores() {
  awk '
    /^  - id:/ {if (id) print id "|" repo "|" type "|" known; id=$NF; repo=""; type=""; known=""}
    /^    repo:/ {repo=$NF}
    /^    type:/ {type=$NF}
    /^    known_version:/ {known=$NF}
    END {if (id) print id "|" repo "|" type "|" known}
  ' "$STORES_FILE"
}

latest_release() {
  local repository="$1" response
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    response="$(printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" | curl -fsSL --proto '=https' --config - "https://api.github.com/repos/$repository/releases/latest" 2>/dev/null || true)"
  else
    response="$(curl -fsSL --proto '=https' "https://api.github.com/repos/$repository/releases/latest" 2>/dev/null || true)"
  fi
  printf '%s' "$response" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

errors=0 updates=0
printf 'Registry: %s\n' "$STORES_FILE"
while IFS='|' read -r id repository type known; do
  [ -n "$id" ] || continue
  if [ "$type" != releases ]; then printf '%s: unsupported type %s\n' "$id" "$type"; errors=$((errors + 1)); continue; fi
  latest="$(latest_release "$repository")"
  if [ -z "$latest" ]; then printf '%s: lookup failed\n' "$id"; errors=$((errors + 1))
  elif [ "$latest" = "$known" ]; then printf '%s: current (%s)\n' "$id" "$known"
  else printf '%s: update %s -> %s\n' "$id" "$known" "$latest"; updates=$((updates + 1))
  fi
done < <(parse_stores)
printf 'Updates: %d; errors: %d\n' "$updates" "$errors"
[ "$errors" -eq 0 ]
