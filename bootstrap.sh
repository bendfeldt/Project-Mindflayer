#!/usr/bin/env bash
set -euo pipefail

VERSION="3.7.0"
COSIGN_VERSION="2.4.1"
REPOSITORY="bendfeldt/Project-Mindflayer"
STAGING_DIRECTORY=""

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [ -n "$STAGING_DIRECTORY" ] && [ -d "$STAGING_DIRECTORY" ]; then
    rm -rf "$STAGING_DIRECTORY"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print tolower($1)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print tolower($1)}'
  else
    fail "required command not found: shasum or sha256sum"
  fi
}

verify_sha256() {
  local expected_hash="$1" verified_file="$2" actual_hash
  [ "${#expected_hash}" -eq 64 ] || fail "invalid checksum for: $(basename "$verified_file")"
  case "$expected_hash" in *[!0-9a-fA-F]*) fail "invalid checksum for: $(basename "$verified_file")" ;; esac
  actual_hash="$(sha256_file "$verified_file")"
  expected_hash="$(printf '%s' "$expected_hash" | tr '[:upper:]' '[:lower:]')"
  [ "$actual_hash" = "$expected_hash" ] || fail "checksum verification failed: $(basename "$verified_file")"
}

require_command curl
require_command tar
require_command awk
require_command mktemp

case "$(uname -s)" in
  Linux) PLATFORM="linux"; COSIGN_OS="linux" ;;
  Darwin) PLATFORM="macos"; COSIGN_OS="darwin" ;;
  *) fail "supported platforms are Linux and macOS" ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCHITECTURE="amd64" ;;
  arm64|aarch64) ARCHITECTURE="arm64" ;;
  *) fail "supported architectures are amd64 and arm64" ;;
esac

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/project-mindflayer.XXXXXX")"

if command -v cosign >/dev/null 2>&1; then
  COSIGN_COMMAND="$(command -v cosign)"
else
  COSIGN_ASSET="cosign-${COSIGN_OS}-${ARCHITECTURE}"
  case "$COSIGN_ASSET" in
    cosign-darwin-amd64) COSIGN_HASH="666032ca283da92b6f7953965688fd51200fdc891a86c19e05c98b898ea0af4e" ;;
    cosign-darwin-arm64) COSIGN_HASH="13343856b69f70388c4fe0b986a31dde5958e444b41be22d785d3dc5e1a9cc62" ;;
    cosign-linux-amd64) COSIGN_HASH="8b24b946dd5809c6bd93de08033bcf6bc0ed7d336b7785787c080f574b89249b" ;;
    cosign-linux-arm64) COSIGN_HASH="3b2e2e3854d0356c45fe6607047526ccd04742d20bd44afb5be91fa2a6e7cb4a" ;;
    *) fail "no pinned Cosign binary for ${COSIGN_OS}/${ARCHITECTURE}" ;;
  esac
  COSIGN_COMMAND="$STAGING_DIRECTORY/cosign"
  curl -fsSL --proto '=https' --proto-redir '=https' --output "$COSIGN_COMMAND" \
    "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/${COSIGN_ASSET}"
  verify_sha256 "$COSIGN_HASH" "$COSIGN_COMMAND"
  chmod 0700 "$COSIGN_COMMAND"
fi

ASSET="project-mindflayer-${VERSION}-${PLATFORM}.tar.gz"
RELEASE_BASE="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"
ARCHIVE="$STAGING_DIRECTORY/$ASSET"
CHECKSUM="$ARCHIVE.sha256"
SIGNATURE_BUNDLE="$ARCHIVE.sigstore.json"

curl -fsSL --proto '=https' --proto-redir '=https' --output "$ARCHIVE" "$RELEASE_BASE/$ASSET"
curl -fsSL --proto '=https' --proto-redir '=https' --output "$CHECKSUM" "$RELEASE_BASE/$ASSET.sha256"
curl -fsSL --proto '=https' --proto-redir '=https' --output "$SIGNATURE_BUNDLE" "$RELEASE_BASE/$ASSET.sigstore.json"

EXPECTED_HASH="$(awk 'NR == 1 {print $1; exit}' "$CHECKSUM")"
verify_sha256 "$EXPECTED_HASH" "$ARCHIVE"
"$COSIGN_COMMAND" verify-blob --bundle "$SIGNATURE_BUNDLE" \
  --certificate-identity "https://github.com/${REPOSITORY}/.github/workflows/release.yml@refs/tags/v${VERSION}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$ARCHIVE"

tar -xzf "$ARCHIVE" -C "$STAGING_DIRECTORY"
INSTALLER="$STAGING_DIRECTORY/project-mindflayer-${VERSION}-${PLATFORM}/install.sh"
[ -f "$INSTALLER" ] || fail "verified release does not contain install.sh"
bash "$INSTALLER" "$@"
