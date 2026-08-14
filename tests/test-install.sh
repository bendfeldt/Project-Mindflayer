#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
assert() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
contains() { grep -Fq -- "$2" "$1"; }
not_contains() { ! grep -Fq -- "$2" "$1"; }

sandbox=""
original_home="$HOME"
setup() {
  sandbox="$(mktemp -d)"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/project"
}
teardown() { export HOME="$original_home"; [ -z "$sandbox" ] || rm -rf "$sandbox"; }
trap teardown EXIT

run_install() { bash "$ROOT/install.sh" "$@" </dev/null; }

printf '%s\n' '--- static and manifest ---'
for script in "$ROOT/install.sh" "$ROOT"/tools/*.sh; do assert "bash syntax: ${script##*/}" bash -n "$script"; done
if command -v shellcheck >/dev/null 2>&1; then assert 'shellcheck' shellcheck -x "$ROOT/install.sh" "$ROOT"/tools/*.sh; fi
assert 'python syntax' python3 -c 'import ast, pathlib, sys; [ast.parse(pathlib.Path(p).read_text()) for p in sys.argv[1:]]' "$ROOT"/skills/release-notes/scripts/*.py

manifest_count=0
while IFS=$'\t' read -r artifact artifact_type artifact_version consumers ownership; do
  case "$artifact" in \#*|'') continue ;; esac
  manifest_count=$((manifest_count + 1))
  assert "manifest file: $artifact" test -f "$ROOT/$artifact"
  [ -n "$artifact_type" ] && [ -n "$artifact_version" ] && [ -n "$consumers" ] && [ -n "$ownership" ] || fail "complete manifest row: $artifact"
  case "$artifact_type" in
    skill|skill-resource)
      assert "skill capability consumers: $artifact" test "$consumers" = 'global,project:skills'
      ;;
  esac
done < "$ROOT/manifest.tsv"
assert 'manifest has artifacts' test "$manifest_count" -gt 40

skill_count="$(awk -F '\t' '$2 == "skill" {count++} END {print count+0}' "$ROOT/manifest.tsv")"
assert 'ten public skills' test "$skill_count" -eq 10
for skill_file in "$ROOT"/skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$skill_file")")"
  keys="$(awk '/^---$/{block++; next} block==1 && /^[a-z_]+:/ {sub(/:.*/, ""); print}' "$skill_file")"
  assert "$skill frontmatter" test "$keys" = $'name\ndescription'
  assert "$skill openai metadata" test -f "$ROOT/skills/$skill/agents/openai.yaml"
  assert "$skill metadata interface" contains "$ROOT/skills/$skill/agents/openai.yaml" 'interface:'
done
assert 'no stale ADR IDs' sh -c "! rg -n 'ADR-00(0[4-9]|1[0-9]|2[0-9]|3[0-9])|docs/decisions/(platform|templates)' '$ROOT' --glob '!.git/**' --glob '!plan.md'"
assert 'Copilot repository guidance is a compatibility shim' test "$(wc -l < "$ROOT/.github/copilot-instructions.md" | tr -d ' ')" -le 5
assert 'no skill lifecycle in frontmatter' sh -c "! rg -n '^(version|updated):' '$ROOT/skills' -g 'SKILL.md'"

printf '%s\n' '--- argument validation ---'
rc=0; run_install --global --project --tools claude --local >/dev/null 2>&1 || rc=$?; assert 'conflicting modes rejected' test "$rc" -ne 0
rc=0; run_install --global --tools unknown --local >/dev/null 2>&1 || rc=$?; assert 'unknown tool rejected' test "$rc" -ne 0
rc=0; run_install --global --tools claude,claude --local >/dev/null 2>&1 || rc=$?; assert 'duplicate tool rejected' test "$rc" -ne 0
rc=0; (cd "$ROOT" && run_install --project --tools claude --profile terraform --client X --prefix x --local) >/dev/null 2>&1 || rc=$?; assert 'root project exemption' test "$rc" -ne 0

printf '%s\n' '--- remote-style installation and completion stamp ---'
setup
fakebin="$sandbox/bin"; mkdir -p "$fakebin"
# The single-quoted lines are the literal body of the fake curl executable.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'url=""; output=""' \
  'while [ $# -gt 0 ]; do case "$1" in -o) shift; output="$1" ;; http*) url="$1" ;; esac; shift; done' \
  'relative="${url#*Project-Mindflayer/main/}"' \
  '[ -z "${FAKE_FETCH_LOG:-}" ] || printf "%s\n" "$relative" >> "$FAKE_FETCH_LOG"' \
  '[ "${FAIL_ARTIFACT:-}" != "$relative" ] || exit 22' \
  'cp "$FAKE_REPO/$relative" "$output"' > "$fakebin/curl"
chmod +x "$fakebin/curl"
export FAKE_REPO="$ROOT" FAIL_ARTIFACT="docs/architecture.md"
rc=0; PATH="$fakebin:$PATH" run_install --global --tools codex >/dev/null 2>&1 || rc=$?
assert 'incomplete remote install fails' test "$rc" -ne 0
assert 'incomplete install has no version stamp' test ! -f "$HOME/.ai-toolkit/version"
unset FAIL_ARTIFACT
assert 'remote-style install succeeds' env PATH="$fakebin:$PATH" FAKE_REPO="$ROOT" HOME="$HOME" bash "$ROOT/install.sh" --global --tools codex
assert 'remote completion stamp written last' test "$(cat "$HOME/.ai-toolkit/version")" = 3.0.2
assert 'Codex-only global skill symlink' test "$(readlink "$HOME/.agents/skills/adr")" = "$HOME/.ai-toolkit/skills/adr"
assert 'Codex-only global install omits Claude skills' test ! -d "$HOME/.claude/skills"
export FAKE_FETCH_LOG="$sandbox/fetch.log"
: > "$FAKE_FETCH_LOG"
assert 'mixed project remote install succeeds' sh -c "cd '$sandbox/project' && PATH='$fakebin:$PATH' HOME='$HOME' bash '$ROOT/install.sh' --project --tools claude,codex --profile terraform --client Client --prefix cl >/dev/null"
assert 'project skill artifact fetched once' test "$(grep -Fc 'skills/adr/SKILL.md' "$FAKE_FETCH_LOG")" -eq 1
unset FAKE_FETCH_LOG
unset FAKE_REPO
teardown

printf '%s\n' '--- global install and ownership ---'
setup
assert 'global install all tools' run_install --global --tools claude,codex,gemini,cursor,copilot --local
assert 'version written' test "$(cat "$HOME/.ai-toolkit/version")" = 3.0.2
assert 'manifest installed' test -f "$HOME/.ai-toolkit/manifest.tsv"
assert 'installer installed' test -f "$HOME/.ai-toolkit/install.sh"
assert 'shared skill lifecycle installed' test -f "$HOME/.ai-toolkit/skill-lifecycle.sh"
assert 'ownership state' test -f "$HOME/.ai-toolkit/managed.tsv"
assert 'nested release script' test -f "$HOME/.ai-toolkit/skills/release-notes/scripts/config.py"
assert 'nested skill metadata' test -f "$HOME/.ai-toolkit/skills/adr/agents/openai.yaml"
for skill_root in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.copilot/skills"; do
  assert "skill symlink target: $skill_root" test "$(readlink "$skill_root/adr")" = "$HOME/.ai-toolkit/skills/adr"
done
assert 'Codex nested skill resource visible' test -f "$HOME/.agents/skills/release-notes/scripts/config.py"

printf 'user config\n' > "$HOME/.codex/AGENTS.md"
run_install --global --tools codex --local >/dev/null
assert 'existing config preserved by default' contains "$HOME/.codex/AGENTS.md" 'user config'
run_install --global --tools codex --force --local >/dev/null
assert 'authorized replacement applied' contains "$HOME/.codex/AGENTS.md" 'Portable Data-Consulting'
backup_count="$(find "$HOME/.codex" -name 'AGENTS.md.bak.*' | wc -l | tr -d ' ')"
assert 'authorized replacement backed up' test "$backup_count" -ge 1

printf 'changed\n' >> "$HOME/.codex/AGENTS.md"
bash "$ROOT/tools/uninstall.sh" --global --confirm >/dev/null
assert 'modified managed file preserved' test -f "$HOME/.codex/AGENTS.md"
assert 'ownership retained for modified file' test -f "$HOME/.ai-toolkit/managed.tsv"
assert 'verified skill symlink removed' test ! -L "$HOME/.claude/skills/adr"
assert 'verified Codex skill symlink removed' test ! -L "$HOME/.agents/skills/adr"
teardown

printf '%s\n' '--- Codex global symlink replacement safety ---'
setup
mkdir -p "$HOME/.agents/skills" "$sandbox/wrong-target"
ln -s "$sandbox/wrong-target" "$HOME/.agents/skills/adr"
run_install --global --tools codex --local >/dev/null
assert 'wrong Codex symlink preserved by default' test "$(readlink "$HOME/.agents/skills/adr")" = "$sandbox/wrong-target"
run_install --global --tools codex --force --local >/dev/null
assert 'wrong Codex symlink replaced with verified target' test "$(readlink "$HOME/.agents/skills/adr")" = "$HOME/.ai-toolkit/skills/adr"
assert 'wrong Codex symlink backed up' sh -c "find '$HOME/.agents/skills' -name 'adr.bak.*' -type l | grep -q ."
teardown

printf '%s\n' '--- project combinations and nested drift ---'
for tools in claude codex gemini cursor copilot claude,codex,gemini,cursor,copilot; do
  setup
  assert "project install: $tools" sh -c "cd '$sandbox/project' && HOME='$HOME' bash '$ROOT/install.sh' --project --tools '$tools' --profile terraform --client Client --prefix cl --local >/dev/null"
  assert "project agents: $tools" test -f "$sandbox/project/AGENTS.md"
  for skill_mapping in 'claude:.claude/skills' 'codex:.agents/skills' 'copilot:.claude/skills'; do
    skill_tool="${skill_mapping%%:*}"
    skill_root="${skill_mapping#*:}"
    case ",$tools," in
      *",$skill_tool,"*)
        assert "nested skill: $tools -> $skill_root" test -f "$sandbox/project/$skill_root/release-notes/scripts/config.py"
        ;;
    esac
  done
  if [ "$tools" = codex ]; then
    assert 'Codex-only install omits Claude settings' test ! -e "$sandbox/project/.claude/settings.json"
    assert 'Codex-only install omits Claude skill root' test ! -d "$sandbox/project/.claude/skills"
  fi
  teardown
done

setup
(cd "$sandbox/project" && run_install --project --tools claude,codex --profile databricks --client Client --prefix cl --local) >/dev/null
assert 'shared project root recorded once' test "$(grep -Fc $'.claude/skills/adr/SKILL.md\t' "$sandbox/project/.mindflayer-managed.tsv")" -eq 1
export MINDFlAYER_HOME="$ROOT"
assert 'full directory initially synced' sh -c "cd '$sandbox/project' && '$ROOT/tools/check-skills-update.sh' >/dev/null"
printf 'drift\n' >> "$sandbox/project/.agents/skills/adr/agents/openai.yaml"
rc=0; (cd "$sandbox/project" && "$ROOT/tools/check-skills-update.sh" >/dev/null) || rc=$?
assert 'Codex nested drift detected' test "$rc" -ne 0
(cd "$sandbox/project" && "$ROOT/tools/sync-skills.sh" --force >/dev/null)
assert 'Codex nested drift repaired' sh -c "cd '$sandbox/project' && '$ROOT/tools/check-skills-update.sh' >/dev/null"
printf 'drift\n' >> "$sandbox/project/.claude/skills/adr/agents/openai.yaml"
rc=0; (cd "$sandbox/project" && "$ROOT/tools/check-skills-update.sh" >/dev/null) || rc=$?
assert 'Claude nested drift detected' test "$rc" -ne 0
(cd "$sandbox/project" && "$ROOT/tools/sync-skills.sh" --force >/dev/null)
assert 'all managed roots repaired' sh -c "cd '$sandbox/project' && '$ROOT/tools/check-skills-update.sh' >/dev/null"
unset MINDFlAYER_HOME
teardown

printf '%s\n' '--- lifecycle ownership boundaries ---'
setup
mkdir -p "$sandbox/project/.agents/skills/adr"
printf 'user skill\n' > "$sandbox/project/.agents/skills/adr/SKILL.md"
export MINDFLAYER_HOME="$ROOT"
rc=0; (cd "$sandbox/project" && "$ROOT/tools/check-skills-update.sh" >/dev/null 2>&1) || rc=$?
assert 'check rejects unmanaged skill root' test "$rc" -ne 0
rc=0; (cd "$sandbox/project" && "$ROOT/tools/sync-skills.sh" --force >/dev/null 2>&1) || rc=$?
assert 'sync rejects unmanaged skill root' test "$rc" -ne 0
assert 'unmanaged skill remains unchanged' contains "$sandbox/project/.agents/skills/adr/SKILL.md" 'user skill'
unset MINDFLAYER_HOME
teardown

setup
printf '%s\tfile\tproof\n' \
  '/tmp/outside/skills/adr/SKILL.md' \
  '../outside/skills/adr/SKILL.md' > "$sandbox/project/.mindflayer-managed.tsv"
export MINDFLAYER_HOME="$ROOT"
rc=0; (cd "$sandbox/project" && "$ROOT/tools/check-skills-update.sh" >/dev/null 2>&1) || rc=$?
assert 'check rejects unsafe ownership paths' test "$rc" -ne 0
rc=0; (cd "$sandbox/project" && "$ROOT/tools/sync-skills.sh" --force >/dev/null 2>&1) || rc=$?
assert 'sync rejects unsafe ownership paths' test "$rc" -ne 0
unset MINDFLAYER_HOME
teardown

setup
printf '%s\n' '# user rules' '.claude/settings.local.json' > "$sandbox/project/.gitignore"
mkdir -p "$sandbox/project/docs/adr"
(cd "$sandbox/project" && run_install --project --tools codex --profile terraform --client Client --prefix cl --local) >/dev/null
(cd "$sandbox/project" && bash "$ROOT/tools/uninstall.sh" --project --confirm) >/dev/null
assert 'Codex project skills removed' test ! -e "$sandbox/project/.agents/skills/adr/SKILL.md"
assert 'empty Codex managed directories removed' test ! -d "$sandbox/project/.agents"
assert 'Codex project shim removed' test ! -e "$sandbox/project/codex.md"
assert 'pre-existing gitignore line preserved' contains "$sandbox/project/.gitignore" '.claude/settings.local.json'
assert 'toolkit gitignore line removed' not_contains "$sandbox/project/.gitignore" 'CLAUDE.local.md'
assert 'pre-existing docs/adr preserved' test -d "$sandbox/project/docs/adr"
teardown

printf '%s\n' '--- stores and release notes fixtures ---'
setup
mkdir -p "$HOME/.ai-toolkit"
printf 'stores:\n' > "$HOME/.ai-toolkit/stores.yml"
cp "$ROOT/stores.yml" "$sandbox/project/stores.yml"
fakebin="$sandbox/bin"; mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nprintf '\''{"tag_name":"v0.0.0"}'\''\n' > "$fakebin/curl"; chmod +x "$fakebin/curl"
output="$(cd "$sandbox/project" && PATH="$fakebin:$PATH" bash "$ROOT/tools/check-stores.sh" 2>&1 || true)"
assert 'store check prefers checkout' sh -c "printf '%s' '$output' | grep -Fq 'Registry: ./stores.yml'"
assert 'release remote fixtures' sh -c "cd '$ROOT/skills/release-notes/scripts' && python3 test_remote.py >/dev/null"
teardown

printf '\nPASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
