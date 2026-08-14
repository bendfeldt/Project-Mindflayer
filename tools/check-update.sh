#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="$HOME/.ai-toolkit/version"
[ -f "$VERSION_FILE" ] || { printf 'error: version file not found: %s\n' "$VERSION_FILE" >&2; exit 1; }
installed="$(sed -n '1p' "$VERSION_FILE")"
[ -n "$installed" ] || { printf 'error: version file is empty\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'error: curl is required\n' >&2; exit 1; }

if [ -n "${GITHUB_TOKEN:-}" ]; then
  response="$(printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" | curl -fsSL --proto '=https' --config - 'https://api.github.com/repos/bendfeldt/Project-Mindflayer/releases/latest')"
else
  response="$(curl -fsSL --proto '=https' 'https://api.github.com/repos/bendfeldt/Project-Mindflayer/releases/latest')"
fi
latest="$(printf '%s' "$response" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$latest" ] || { printf 'error: release response has no tag_name\n' >&2; exit 1; }

printf 'Installed: %s\nLatest:    %s\n' "${installed#v}" "${latest#v}"
if [ "${installed#v}" != "${latest#v}" ]; then
  printf 'Update with an explicit tool list:\n'
  printf '  ~/.ai-toolkit/install.sh --global --tools <tools> --force\n'
fi
