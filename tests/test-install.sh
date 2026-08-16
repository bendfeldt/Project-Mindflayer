#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
EXPECTED_SHELLCHECK_VERSION="0.11.0"
EXPECTED_TOOLKIT_VERSION="$(awk -F '\t' '$1 == "install.sh" {print $3; exit}' "$ROOT/manifest.tsv")"
case "$(uname -s)" in
  Darwin) TEST_PLATFORM=macos ;;
  Linux) TEST_PLATFORM=linux ;;
  *) printf 'error: unsupported test platform\n' >&2; exit 1 ;;
esac
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
assert() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
contains() { grep -Fq -- "$2" "$1"; }
not_contains() { ! grep -Fq -- "$2" "$1"; }
checksum() { cksum "$1" | awk '{print $1 ":" $2}'; }
adr_reference_exists() {
  local reference="$1" decision_file
  for decision_file in "$ROOT"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
    grep -Fq "# $reference:" "$decision_file" && return 0
  done
  return 1
}

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

copy_test_bundle() {
  local destination="$1" artifact _type _version _consumers _ownership _platforms
  mkdir -p "$destination"
  while IFS=$'\t' read -r artifact _type _version _consumers _ownership _platforms; do
    case "$artifact" in \#*|'') continue ;; esac
    mkdir -p "$destination/$(dirname "$artifact")"
    cp "$ROOT/$artifact" "$destination/$artifact"
  done < "$ROOT/manifest.tsv"
}

printf '%s\n' '--- static and manifest ---'
assert 'installer version matches manifest' grep -Fqx "VERSION=\"$EXPECTED_TOOLKIT_VERSION\"" "$ROOT/install.sh"
assert 'installer has no mutable-main fetch path' sh -c "! grep -Eq 'raw\.githubusercontent\.com/.*/main|curl .*manifest' '$ROOT/install.sh'"
assert 'Bash help advertises Windows runtime' sh -c "bash '$ROOT/install.sh' --help | grep -Fq 'PowerShell 7.4+'"
assert 'PowerShell installer distributed' grep -Fq $'install.ps1\tscript\t3.6.0' "$ROOT/manifest.tsv"
# shellcheck disable=SC2016
assert 'manifest uses six-field schema' awk -F '\t' '$1 !~ /^#/ && NF != 6 {exit 1}' "$ROOT/manifest.tsv"
# shellcheck disable=SC2016
assert 'manifest platform declarations are valid' awk -F '\t' '$1 !~ /^#/ {delete seen; count=split($6, values, ","); for (i=1; i<=count; i++) if (values[i] !~ /^(linux|macos|windows)$/ || seen[values[i]]++) exit 1}' "$ROOT/manifest.tsv"
# shellcheck disable=SC2016
assert 'Bash artifacts are Unix scoped' awk -F '\t' '$1 ~ /(^install\.sh$|^tools\/.*\.sh$)/ && $6 != "linux,macos" {exit 1}' "$ROOT/manifest.tsv"
# shellcheck disable=SC2016
assert 'PowerShell artifacts are Windows scoped' awk -F '\t' '$1 ~ /(^install\.ps1$|^tools\/.*\.ps1$)/ && $6 != "windows" {exit 1}' "$ROOT/manifest.tsv"
assert 'AppleScript helper is macOS scoped' grep -Fqx $'skills/release-notes/scripts/make_outlook_draft.applescript\tskill-resource\t2.2.0\tglobal,project:skills\tmanaged-tree\tmacos' "$ROOT/manifest.tsv"
assert 'email helper is Linux and Windows scoped' grep -Fqx $'skills/release-notes/scripts/make_email_draft.py\tskill-resource\t2.2.0\tglobal,project:skills\tmanaged-tree\tlinux,windows' "$ROOT/manifest.tsv"
assert 'repository tests are not distributable' sh -c "! grep -Eq 'skills/.*/test_[^[:space:]]+\\.py' '$ROOT/manifest.tsv'"
assert 'system requirements distributed' grep -Fq $'docs/system-requirements.md\tdocument\t1.2.0' "$ROOT/manifest.tsv"
assert 'local mode hidden from public help' sh -c "! bash '$ROOT/install.sh' --help | grep -Fq -- '--local'"
for public_install_file in "$ROOT/README.md" "$ROOT/how-to-guide.md" "$ROOT/skills/setup-repo/SKILL.md"; do
  assert "no public local mode: ${public_install_file##*/}" not_contains "$public_install_file" '--local'
done
assert 'legacy local flag retained as no-op' grep -Fq -- '--local) :' "$ROOT/install.sh"
for script in "$ROOT/install.sh" "$ROOT"/tools/*.sh "$ROOT"/tests/*.sh; do assert "bash syntax: ${script##*/}" bash -n "$script"; done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck_version="$(shellcheck --version | awk '$1 == "version:" {print $2}')"
  assert 'shellcheck version' test "$shellcheck_version" = "$EXPECTED_SHELLCHECK_VERSION"
  assert 'shellcheck' shellcheck -x "$ROOT/install.sh" "$ROOT"/tools/*.sh "$ROOT"/tests/*.sh
else
  fail "shellcheck $EXPECTED_SHELLCHECK_VERSION available"
fi
assert 'python syntax' python3 -c 'import ast, pathlib, sys; [ast.parse(pathlib.Path(p).read_text()) for p in sys.argv[1:]]' "$ROOT"/skills/*/scripts/*.py

manifest_count=0
while IFS=$'\t' read -r artifact artifact_type artifact_version consumers ownership platforms; do
  case "$artifact" in \#*|'') continue ;; esac
  manifest_count=$((manifest_count + 1))
  assert "manifest file: $artifact" test -f "$ROOT/$artifact"
  if [ -n "$artifact_type" ] && [ -n "$artifact_version" ] && [ -n "$consumers" ] && [ -n "$ownership" ] && [ -n "$platforms" ]; then
    pass "complete manifest row: $artifact"
  else
    fail "complete manifest row: $artifact"
  fi
  case "$artifact_type" in
    skill|skill-resource)
      assert "skill capability consumers: $artifact" test "$consumers" = 'global,project:skills'
      ;;
  esac
done < "$ROOT/manifest.tsv"
assert 'manifest has artifacts' test "$manifest_count" -gt 40

skill_count="$(awk -F '\t' '$2 == "skill" {count++} END {print count+0}' "$ROOT/manifest.tsv")"
assert 'eleven public skills' test "$skill_count" -eq 11
for skill_file in "$ROOT"/skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$skill_file")")"
  keys="$(awk '/^---$/{block++; next} block==1 && /^[a-z_]+:/ {sub(/:.*/, ""); print}' "$skill_file")"
  assert "$skill frontmatter" test "$keys" = $'name\ndescription'
  assert "$skill openai metadata" test -f "$ROOT/skills/$skill/agents/openai.yaml"
  assert "$skill metadata interface" contains "$ROOT/skills/$skill/agents/openai.yaml" 'interface:'
done
for decision_file in "$ROOT"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
  filename_id="$(basename "$decision_file")"
  filename_id="${filename_id%%-*}"
  heading_id="$(sed -n 's/^# ADR-\([0-9][0-9][0-9][0-9]\):.*/\1/p' "$decision_file" | head -1)"
  assert "decision filename matches heading: $filename_id" test "$filename_id" = "$heading_id"
done
while IFS= read -r adr_reference; do
  assert "resolved decision reference: $adr_reference" adr_reference_exists "$adr_reference"
done < <(rg -o --no-filename 'ADR-[0-9]{4}' "$ROOT" --glob '!.git/**' --glob '!plan.md' | sort -u)
assert 'retired platform decision tree absent' test ! -e "$ROOT/docs/decisions/platform"
assert 'retired decision templates absent' test ! -e "$ROOT/docs/decisions/templates"
assert 'no skill lifecycle in frontmatter' sh -c "! rg -n '^(version|updated):' '$ROOT/skills' -g 'SKILL.md'"

assert 'Claude repository shim exact import' grep -Fqx '@AGENTS.md' "$ROOT/CLAUDE.md"
assert 'Gemini repository shim exact import' grep -Fqx '@AGENTS.md' "$ROOT/GEMINI.md"
assert 'shim canonical target exists' test -f "$ROOT/AGENTS.md"
assert 'Claude repository shim is one line' test "$(wc -l < "$ROOT/CLAUDE.md" | tr -d ' ')" -eq 1
assert 'Gemini repository shim is one line' test "$(wc -l < "$ROOT/GEMINI.md" | tr -d ' ')" -eq 1
assert 'repository instructions do not import compatibility shims' sh -c "! rg -n '^@(CLAUDE|GEMINI)\\.md$' '$ROOT/AGENTS.md'"
assert 'duplicate Claude template absent' test ! -e "$ROOT/templates/CLAUDE.md"
assert 'duplicate Gemini template absent' test ! -e "$ROOT/templates/GEMINI.md"
assert 'Cursor project shim source absent' test ! -e "$ROOT/settings/cursor/cursor.md"
assert 'Copilot project shim source absent' test ! -e "$ROOT/settings/copilot/copilot-instructions.md"
assert 'Cursor project shim not distributed' sh -c "! grep -Fq 'settings/cursor/cursor.md' '$ROOT/manifest.tsv'"
assert 'Copilot project shim not distributed' sh -c "! grep -Fq 'settings/copilot/copilot-instructions.md' '$ROOT/manifest.tsv'"
for instruction_file in "$ROOT/global/AGENTS.md" "$ROOT/AGENTS.md" "$ROOT/templates/AGENTS.md"; do
  assert "instruction line budget: ${instruction_file##*/}" test "$(wc -l < "$instruction_file")" -lt 200
done
combined_instruction_bytes="$(wc -c < "$ROOT/global/AGENTS.md")"
combined_instruction_bytes=$((combined_instruction_bytes + $(wc -c < "$ROOT/templates/AGENTS.md")))
assert 'combined instruction byte budget' test "$combined_instruction_bytes" -lt 32768
assert 'no runtime discovery scaffolds in manifest' sh -c "! grep -Fq 'settings/claude/scaffold/' '$ROOT/manifest.tsv'"
assert 'composable template inventoried' contains "$ROOT/manifest.tsv" $'templates/AGENTS-composable.md\ttemplate\t5.0.0'
assert 'technology catalog inventoried' contains "$ROOT/manifest.tsv" $'config/technology-catalog.tsv\tregistry\t1.0.0'
assert 'technology policy inventoried' contains "$ROOT/manifest.tsv" $'settings/claude/technology-permissions.tsv\tsetting\t1.0.0'
assert 'all three project types cataloged' sh -c "test \"\$(awk -F '\t' '\$2 == \"project-type\" {count++} END {print count+0}' '$ROOT/config/technology-catalog.tsv')\" -eq 3"
assert 'ambiguous dlt alias absent' sh -c "! awk -F '\t' '\$4 == \"dlt\" {found=1} END {exit found ? 0 : 1}' '$ROOT/config/technology-catalog.tsv'"

printf '%s\n' '--- argument validation ---'
rc=0; run_install --global --project --tools claude --local >/dev/null 2>&1 || rc=$?; assert 'conflicting modes rejected' test "$rc" -ne 0
rc=0; run_install --global --tools unknown --local >/dev/null 2>&1 || rc=$?; assert 'unknown tool rejected' test "$rc" -ne 0
rc=0; run_install --global --tools claude,claude --local >/dev/null 2>&1 || rc=$?; assert 'duplicate tool rejected' test "$rc" -ne 0
rc=0; (cd "$ROOT" && run_install --project --tools claude --profile terraform --client X --prefix x --local) >/dev/null 2>&1 || rc=$?; assert 'root project exemption' test "$rc" -ne 0

setup
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --project-types infrastructure --client Client --local) >/dev/null 2>&1 || rc=$?; assert 'technologies required for composable install' test "$rc" -ne 0
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --technologies sql --client Client --local) >/dev/null 2>&1 || rc=$?; assert 'project types required for composable install' test "$rc" -ne 0
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --profile terraform --project-types infrastructure --technologies terraform --client Client --prefix cl --local) >/dev/null 2>&1 || rc=$?; assert 'legacy and composable flags conflict' test "$rc" -ne 0
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --project-types Infrastructure --technologies sql --client Client --local) >/dev/null 2>&1 || rc=$?; assert 'uppercase project type rejected' test "$rc" -ne 0
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --project-types infrastructure --technologies postgresql,postgres --client Client --local) >/dev/null 2>&1 || rc=$?; assert 'alias duplicate rejected' test "$rc" -ne 0
teardown

printf '%s\n' '--- local bundle preflight ---'
setup
bundle="$sandbox/bundle"
copy_test_bundle "$bundle"
printf '%s\n' $'../outside\tdocument\t1.0.0\tglobal\tmanaged-file\tlinux,macos' >> "$bundle/manifest.tsv"
rc=0; HOME="$HOME" bash "$bundle/install.sh" --global --tools codex >/dev/null 2>&1 || rc=$?
assert 'malicious manifest path rejected' test "$rc" -ne 0
assert 'manifest failure precedes target writes' test ! -e "$HOME/.ai-toolkit"
teardown

printf '%s\n' '--- global install and ownership ---'
setup
assert 'global install all tools' run_install --global --tools claude,codex,gemini,cursor,copilot --local
assert 'version written' test "$(cat "$HOME/.ai-toolkit/version")" = "$EXPECTED_TOOLKIT_VERSION"
assert 'manifest installed' test -f "$HOME/.ai-toolkit/manifest.tsv"
assert 'installer installed' test -f "$HOME/.ai-toolkit/install.sh"
assert 'PowerShell installer excluded on macOS' test ! -e "$HOME/.ai-toolkit/install.ps1"
assert 'shared skill lifecycle installed' test -f "$HOME/.ai-toolkit/skill-lifecycle.sh"
assert 'PowerShell lifecycle excluded on macOS' test ! -e "$HOME/.ai-toolkit/uninstall.ps1"
assert 'ownership state' test -f "$HOME/.ai-toolkit/managed.tsv"
assert 'nested release script' test -f "$HOME/.ai-toolkit/skills/release-notes/scripts/config.py"
if [ "$TEST_PLATFORM" = macos ]; then
  assert 'macOS helper installed' test -f "$HOME/.ai-toolkit/skills/release-notes/scripts/make_outlook_draft.applescript"
  assert 'Linux Windows helper excluded on macOS' test ! -e "$HOME/.ai-toolkit/skills/release-notes/scripts/make_email_draft.py"
else
  assert 'macOS helper excluded on Linux' test ! -e "$HOME/.ai-toolkit/skills/release-notes/scripts/make_outlook_draft.applescript"
  assert 'Linux helper installed' test -f "$HOME/.ai-toolkit/skills/release-notes/scripts/make_email_draft.py"
fi
assert 'repository test modules excluded' sh -c "! find '$HOME/.ai-toolkit/skills' -type f -name 'test_*.py' | grep -q ."
cp "$ROOT/install.ps1" "$HOME/.ai-toolkit/install.ps1"
printf '%s\tfile\t%s\n' "$HOME/.ai-toolkit/install.ps1" "$(checksum "$HOME/.ai-toolkit/install.ps1")" >> "$HOME/.ai-toolkit/managed.tsv"
mkdir -p "$HOME/.ai-toolkit/skills/release-notes/scripts"
cp "$ROOT/skills/release-notes/scripts/test_tasks.py" "$HOME/.ai-toolkit/skills/release-notes/scripts/test_tasks.py"
printf '%s\tfile\t%s\n' "$HOME/.ai-toolkit/skills/release-notes/scripts/test_tasks.py" "$(checksum "$HOME/.ai-toolkit/skills/release-notes/scripts/test_tasks.py")" >> "$HOME/.ai-toolkit/managed.tsv"
run_install --global --tools claude,codex,copilot --local >/dev/null
assert 'verified wrong-platform artifact removed' test ! -e "$HOME/.ai-toolkit/install.ps1"
assert 'verified retired test artifact removed' test ! -e "$HOME/.ai-toolkit/skills/release-notes/scripts/test_tasks.py"
mkdir -p "$HOME/.ai-toolkit/docs"
printf 'retired managed document\n' > "$HOME/.ai-toolkit/docs/retired.md"
printf '%s\tfile\t%s\n' "$HOME/.ai-toolkit/docs/retired.md" "$(checksum "$HOME/.ai-toolkit/docs/retired.md")" >> "$HOME/.ai-toolkit/managed.tsv"
printf 'unowned cache\n' > "$HOME/.ai-toolkit/docs/local.cache"
run_install --global --tools codex --local >/dev/null
assert 'verified retired global artifact removed' test ! -e "$HOME/.ai-toolkit/docs/retired.md"
assert 'unowned global noise preserved' test -f "$HOME/.ai-toolkit/docs/local.cache"
cp "$ROOT/install.ps1" "$HOME/.ai-toolkit/install.ps1"
printf '%s\tfile\t%s\n' "$HOME/.ai-toolkit/install.ps1" "$(checksum "$HOME/.ai-toolkit/install.ps1")" >> "$HOME/.ai-toolkit/managed.tsv"
printf '\nuser modification\n' >> "$HOME/.ai-toolkit/install.ps1"
run_install --global --tools claude,codex,copilot --local >/dev/null 2>&1
assert 'modified wrong-platform artifact preserved' test -f "$HOME/.ai-toolkit/install.ps1"
assert 'nested skill metadata' test -f "$HOME/.ai-toolkit/skills/adr/agents/openai.yaml"
assert 'nested auditor reference' test -f "$HOME/.ai-toolkit/skills/engineering-auditor/references/output-format.md"
assert 'nested auditor script' test -f "$HOME/.ai-toolkit/skills/engineering-auditor/scripts/validate_audit_report.py"
for skill_root in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.copilot/skills"; do
  assert "skill symlink target: $skill_root" test "$(readlink "$skill_root/adr")" = "$HOME/.ai-toolkit/skills/adr"
  assert "auditor symlink target: $skill_root" test "$(readlink "$skill_root/engineering-auditor")" = "$HOME/.ai-toolkit/skills/engineering-auditor"
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
        assert "nested auditor: $tools -> $skill_root" test -f "$sandbox/project/$skill_root/engineering-auditor/scripts/repository_inventory.py"
        assert "project tests excluded: $tools -> $skill_root" sh -c "! find '$sandbox/project/$skill_root' -type f -name 'test_*.py' | grep -q ."
        if [ "$TEST_PLATFORM" = macos ]; then
          assert "project macOS helper: $tools -> $skill_root" test -f "$sandbox/project/$skill_root/release-notes/scripts/make_outlook_draft.applescript"
          assert "project email helper excluded on macOS: $tools -> $skill_root" test ! -e "$sandbox/project/$skill_root/release-notes/scripts/make_email_draft.py"
        else
          assert "project AppleScript excluded on Linux: $tools -> $skill_root" test ! -e "$sandbox/project/$skill_root/release-notes/scripts/make_outlook_draft.applescript"
          assert "project Linux email helper: $tools -> $skill_root" test -f "$sandbox/project/$skill_root/release-notes/scripts/make_email_draft.py"
        fi
        ;;
    esac
  done
  if [ "$tools" = codex ]; then
    assert 'Codex-only install omits Claude settings' test ! -e "$sandbox/project/.claude/settings.json"
    assert 'Codex-only install omits Claude skill root' test ! -d "$sandbox/project/.claude/skills"
  fi
  teardown
done

printf '%s\n' '--- composable project classification ---'
setup
all_types='infrastructure,data-platform,data-engineering'
mixed_technologies='databricks,dabs,microsoft-fabric,snowflake,postgres,terraform,dbt,dlthub,podman,py,sql'
(cd "$sandbox/project" && run_install --project --tools claude,codex,gemini,cursor,copilot \
  --project-types data-engineering,infrastructure,data-platform \
  --technologies "$mixed_technologies" --client Client --local) >/dev/null
assert 'all project types canonicalized' contains "$sandbox/project/AGENTS.md" '**project types:** infrastructure, data-platform, data-engineering'
assert 'technologies canonicalized' contains "$sandbox/project/AGENTS.md" '**technologies:** databricks, databricks:asset-bundles, fabric, snowflake, postgresql, terraform, dbt, dlthub, podman, python, sql'
assert 'optional prefix omitted' not_contains "$sandbox/project/AGENTS.md" '**resource prefix:**'
assert 'composed settings valid JSON' sh -c "python3 -m json.tool '$sandbox/project/.claude/settings.json' >/dev/null"
assert 'composed settings deduplicated and deny-disjoint' python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["permissions"]; assert len(p["allow"]) == len(set(p["allow"])); assert len(p["deny"]) == len(set(p["deny"])); assert not set(p["allow"]) & set(p["deny"])' "$sandbox/project/.claude/settings.json"
assert 'Databricks allows require profile' python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["permissions"]["allow"]; assert all("--profile " in rule for rule in a if "databricks " in rule)' "$sandbox/project/.claude/settings.json"
assert 'Snowflake allows require connection when present' python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["permissions"]["allow"]; assert all("--connection " in rule or " -c " in rule for rule in a if "snow " in rule)' "$sandbox/project/.claude/settings.json"

mkdir -p "$sandbox/project-reordered"
(cd "$sandbox/project-reordered" && run_install --project --tools claude \
  --project-types "$all_types" \
  --technologies sql,python,podman,dlthub,dbt,terraform,postgresql,snowflake,fabric,databricks:asset-bundles,databricks \
  --client Client --local) >/dev/null
assert 'project metadata input-order invariant' cmp "$sandbox/project/AGENTS.md" "$sandbox/project-reordered/AGENTS.md"
assert 'composed settings input-order invariant' cmp "$sandbox/project/.claude/settings.json" "$sandbox/project-reordered/.claude/settings.json"

agents_checksum_before="$(checksum "$sandbox/project/AGENTS.md")"
(cd "$sandbox/project" && run_install --project --tools claude --local) >/dev/null
assert 'composable join preserves AGENTS' test "$(checksum "$sandbox/project/AGENTS.md")" = "$agents_checksum_before"
rc=0; (cd "$sandbox/project" && run_install --project --tools claude --project-types infrastructure --technologies "$mixed_technologies" --local) >/dev/null 2>&1 || rc=$?; assert 'composable join rejects mismatched project types' test "$rc" -ne 0
teardown

printf '%s\n' '--- all project type combinations ---'
setup
for project_types in \
  infrastructure data-platform data-engineering \
  infrastructure,data-platform infrastructure,data-engineering data-platform,data-engineering \
  infrastructure,data-platform,data-engineering; do
  project_path="$sandbox/project-${project_types//,/-}"
  mkdir -p "$project_path"
  assert "project types: $project_types" sh -c "cd '$project_path' && HOME='$HOME' bash '$ROOT/install.sh' --project --tools cursor --project-types '$project_types' --technologies sql --client Client --local >/dev/null"
done
assert 'non-Claude composable install omits settings' test ! -e "$sandbox/project-infrastructure/.claude/settings.json"
teardown

printf '%s\n' '--- component permissions and composable ownership ---'
setup
(cd "$sandbox/project" && run_install --project --tools claude \
  --project-types data-platform --technologies databricks:asset-bundles \
  --client Client --local) >/dev/null
assert 'component permission included' contains "$sandbox/project/.claude/settings.json" 'Bash(databricks bundle validate *--profile *)'
assert 'component does not inherit parent permission' not_contains "$sandbox/project/.claude/settings.json" 'Bash(databricks * list *--profile *)'
printf '\n{"user":"change"}\n' >> "$sandbox/project/.claude/settings.json"
(cd "$sandbox/project" && run_install --project --tools claude --local) >/dev/null
assert 'modified composed settings preserved by default' contains "$sandbox/project/.claude/settings.json" '"user":"change"'
(cd "$sandbox/project" && run_install --project --tools claude --force --local) >/dev/null
assert 'composed settings restored with force' sh -c "python3 -m json.tool '$sandbox/project/.claude/settings.json' >/dev/null"
assert 'composed settings replacement backed up' sh -c "find '$sandbox/project/.claude' -name 'settings.json.bak.*' -type f | grep -q ."
(cd "$sandbox/project" && bash "$ROOT/tools/uninstall.sh" --project --confirm) >/dev/null
assert 'verified composed settings removed' test ! -e "$sandbox/project/.claude/settings.json"
assert 'verified composable AGENTS removed' test ! -e "$sandbox/project/AGENTS.md"
teardown

printf '%s\n' '--- partial composable join metadata ---'
setup
printf '%s\n' '# Project Instructions' '<!-- template: AGENTS | version: 5.0.0 -->' '- **project types:** data-engineering' > "$sandbox/project/AGENTS.md"
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --local) >/dev/null 2>&1 || rc=$?; assert 'partial composable metadata rejected' test "$rc" -ne 0
teardown

printf '%s\n' '--- legacy profile equivalence and join ---'
for legacy_profile in terraform databricks fabric; do
  setup
  (cd "$sandbox/project" && run_install --project --tools claude --profile "$legacy_profile" --client Client --prefix cl --local) >/dev/null
  assert "legacy settings unchanged: $legacy_profile" cmp "$sandbox/project/.claude/settings.json" "$ROOT/settings/claude/settings-$legacy_profile.json"
  legacy_agents_checksum="$(checksum "$sandbox/project/AGENTS.md")"
  (cd "$sandbox/project" && run_install --project --tools claude --local) >/dev/null
  assert "legacy join preserves AGENTS: $legacy_profile" test "$(checksum "$sandbox/project/AGENTS.md")" = "$legacy_agents_checksum"
  teardown
done

setup
(cd "$sandbox/project" && run_install --project --tools claude,codex,gemini,cursor,copilot --profile databricks --client Client --prefix cl --local) >/dev/null
assert 'Claude project shim installed' grep -Fqx '@AGENTS.md' "$sandbox/project/CLAUDE.md"
assert 'Gemini project shim installed' grep -Fqx '@AGENTS.md' "$sandbox/project/GEMINI.md"
assert 'Codex uses native AGENTS without shim' test ! -e "$sandbox/project/codex.md"
assert 'Cursor uses native AGENTS without shim' test ! -e "$sandbox/project/.cursor/rules/project.md"
assert 'Copilot uses native AGENTS without shim' test ! -e "$sandbox/project/.github/copilot-instructions.md"
assert 'Claude runtime scaffold README absent' test ! -e "$sandbox/project/.claude/rules/README.md"
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

printf '%s\n' '--- lifecycle ignores unmanifested runtime artifacts ---'
setup
(cd "$sandbox/project" && run_install --project --tools codex --profile databricks --client Client --prefix cl --local) >/dev/null
toolkit_fixture="$sandbox/toolkit"
mkdir -p "$toolkit_fixture" "$toolkit_fixture/skills/adr/__pycache__" "$sandbox/project/.agents/skills/adr/__pycache__"
cp "$ROOT/manifest.tsv" "$toolkit_fixture/manifest.tsv"
cp -R "$ROOT/skills/." "$toolkit_fixture/skills/"
printf 'source cache\n' > "$toolkit_fixture/skills/adr/__pycache__/source.pyc"
printf 'target cache\n' > "$sandbox/project/.agents/skills/adr/__pycache__/target.pyc"
export MINDFlAYER_HOME="$toolkit_fixture"
assert 'unmanifested caches do not report drift' sh -c "cd '$sandbox/project' && '$ROOT/tools/check-skills-update.sh' >/dev/null"
printf 'retired owned file\n' > "$sandbox/project/.agents/skills/adr/retired.md"
printf '%s\tfile\t%s\n' '.agents/skills/adr/retired.md' "$(checksum "$sandbox/project/.agents/skills/adr/retired.md")" >> "$sandbox/project/.mindflayer-managed.tsv"
rc=0; (cd "$sandbox/project" && "$ROOT/tools/check-skills-update.sh" >/dev/null 2>&1) || rc=$?
assert 'owned obsolete skill file reports drift' test "$rc" -ne 0
(cd "$sandbox/project" && "$ROOT/tools/sync-skills.sh" >/dev/null)
assert 'owned obsolete skill file removed' test ! -e "$sandbox/project/.agents/skills/adr/retired.md"
assert 'unowned cache survives obsolete reconciliation' test -f "$sandbox/project/.agents/skills/adr/__pycache__/target.pyc"
printf 'drift\n' >> "$sandbox/project/.agents/skills/adr/agents/openai.yaml"
(cd "$sandbox/project" && "$ROOT/tools/sync-skills.sh" --force >/dev/null)
assert 'sync does not copy source cache' test ! -e "$sandbox/project/.agents/skills/adr/__pycache__/source.pyc"
assert 'sync preserves unmanifested target cache' test -f "$sandbox/project/.agents/skills/adr/__pycache__/target.pyc"
assert 'manifested drift repaired with caches present' sh -c "cd '$sandbox/project' && '$ROOT/tools/check-skills-update.sh' >/dev/null"
unset MINDFlAYER_HOME
teardown

printf '%s\n' '--- project compatibility migration ---'
setup
mkdir -p \
  "$sandbox/project/.claude/rules" \
  "$sandbox/project/.claude/commands" \
  "$sandbox/project/.claude/agents" \
  "$sandbox/project/.claude/hooks" \
  "$sandbox/project/.cursor/rules" \
  "$sandbox/project/.github"
ownership_file="$sandbox/project/.mindflayer-managed.tsv"
for legacy_path in \
  codex.md \
  gemini.md \
  .claude/rules/README.md \
  .claude/commands/README.md \
  .claude/agents/README.md \
  .claude/hooks/README.md \
  .cursor/rules/project.md; do
  printf 'legacy managed artifact\n' > "$sandbox/project/$legacy_path"
  printf '%s\tfile\t%s\n' "$legacy_path" "$(checksum "$sandbox/project/$legacy_path")" >> "$ownership_file"
done
printf 'user modification\n' >> "$sandbox/project/.claude/rules/README.md"
ln -s ../AGENTS.md "$sandbox/project/.github/copilot-instructions.md"
printf '%s\tsymlink\t%s\n' '.github/copilot-instructions.md' '../AGENTS.md' >> "$ownership_file"
(cd "$sandbox/project" && run_install --project --tools claude,codex,gemini,cursor,copilot --profile terraform --client Client --prefix cl --local) >/dev/null
assert 'legacy Codex shim removed' test ! -e "$sandbox/project/codex.md"
assert 'legacy Gemini shim replaced with native casing' test "$(find "$sandbox/project" -maxdepth 1 -name 'GEMINI.md' -print | wc -l | tr -d ' ')" -eq 1
assert 'legacy lowercase Gemini entry removed' test "$(find "$sandbox/project" -maxdepth 1 -name 'gemini.md' -print | wc -l | tr -d ' ')" -eq 0
assert 'unchanged Claude command scaffold removed' test ! -e "$sandbox/project/.claude/commands/README.md"
assert 'unchanged Claude agent scaffold removed' test ! -e "$sandbox/project/.claude/agents/README.md"
assert 'unchanged Claude hook scaffold removed' test ! -e "$sandbox/project/.claude/hooks/README.md"
assert 'modified Claude rule scaffold preserved' contains "$sandbox/project/.claude/rules/README.md" 'user modification'
assert 'unchanged Cursor shim removed' test ! -e "$sandbox/project/.cursor/rules/project.md"
assert 'unchanged Copilot symlink removed' test ! -e "$sandbox/project/.github/copilot-instructions.md"
assert 'Cursor ownership record removed' not_contains "$ownership_file" '.cursor/rules/project.md'
assert 'Copilot ownership record removed' not_contains "$ownership_file" '.github/copilot-instructions.md'
teardown

printf '%s\n' '--- modified legacy shim preservation ---'
setup
mkdir -p "$sandbox/project/.cursor/rules" "$sandbox/project/.github"
ownership_file="$sandbox/project/.mindflayer-managed.tsv"
printf 'legacy managed Cursor shim\n' > "$sandbox/project/.cursor/rules/project.md"
printf '%s\tfile\t%s\n' '.cursor/rules/project.md' "$(checksum "$sandbox/project/.cursor/rules/project.md")" >> "$ownership_file"
printf 'user modification\n' >> "$sandbox/project/.cursor/rules/project.md"
ln -s ../AGENTS.md "$sandbox/project/.github/copilot-instructions.md"
printf '%s\tsymlink\t%s\n' '.github/copilot-instructions.md' '../AGENTS.md' >> "$ownership_file"
ln -sfn ../OTHER.md "$sandbox/project/.github/copilot-instructions.md"
(cd "$sandbox/project" && run_install --project --tools cursor,copilot --profile terraform --client Client --prefix cl --local) >/dev/null
assert 'modified Cursor shim preserved' contains "$sandbox/project/.cursor/rules/project.md" 'user modification'
assert 'modified Cursor ownership retained' contains "$ownership_file" '.cursor/rules/project.md'
assert 'changed Copilot symlink preserved' test "$(readlink "$sandbox/project/.github/copilot-instructions.md")" = '../OTHER.md'
assert 'changed Copilot ownership retained' contains "$ownership_file" '.github/copilot-instructions.md'
teardown

printf '%s\n' '--- missing legacy ownership cleanup ---'
setup
ownership_file="$sandbox/project/.mindflayer-managed.tsv"
printf '%s\tfile\t%s\n' '.cursor/rules/project.md' 'missing-proof' > "$ownership_file"
printf '%s\tsymlink\t%s\n' '.github/copilot-instructions.md' '../AGENTS.md' >> "$ownership_file"
(cd "$sandbox/project" && run_install --project --tools cursor,copilot --profile terraform --client Client --prefix cl --local) >/dev/null
assert 'missing Cursor ownership forgotten' not_contains "$ownership_file" '.cursor/rules/project.md'
assert 'missing Copilot ownership forgotten' not_contains "$ownership_file" '.github/copilot-instructions.md'
teardown

printf '%s\n' '--- unowned legacy shim preservation ---'
setup
mkdir -p "$sandbox/project/.cursor/rules" "$sandbox/project/.github"
printf 'unowned Cursor guidance\n' > "$sandbox/project/.cursor/rules/project.md"
printf 'unowned Copilot guidance\n' > "$sandbox/project/.github/copilot-instructions.md"
(cd "$sandbox/project" && run_install --project --tools cursor,copilot --profile terraform --client Client --prefix cl --local) >/dev/null
assert 'unowned Cursor shim preserved' contains "$sandbox/project/.cursor/rules/project.md" 'unowned Cursor guidance'
assert 'unowned Copilot shim preserved' contains "$sandbox/project/.github/copilot-instructions.md" 'unowned Copilot guidance'
teardown

printf '%s\n' '--- project entrypoint uninstall ---'
setup
(cd "$sandbox/project" && run_install --project --tools claude,codex,gemini,cursor,copilot --profile fabric --client Client --prefix cl --local) >/dev/null
(cd "$sandbox/project" && bash "$ROOT/tools/uninstall.sh" --project --confirm) >/dev/null
assert 'Claude project shim removed' test ! -e "$sandbox/project/CLAUDE.md"
assert 'Gemini project shim removed' test ! -e "$sandbox/project/GEMINI.md"
assert 'Cursor project shim remains absent' test ! -e "$sandbox/project/.cursor/rules/project.md"
assert 'Copilot project shim remains absent' test ! -e "$sandbox/project/.github/copilot-instructions.md"
teardown

printf '%s\n' '--- ownership ledger containment ---'
setup
printf 'outside data\n' > "$sandbox/outside.txt"
printf '%s\tfile\t%s\n' '../outside.txt' "$(checksum "$sandbox/outside.txt")" > "$sandbox/project/.mindflayer-managed.tsv"
rc=0; (cd "$sandbox/project" && bash "$ROOT/tools/uninstall.sh" --project --confirm >/dev/null 2>&1) || rc=$?
assert 'uninstall rejects relative ledger escape' test "$rc" -ne 0
assert 'relative ledger escape target preserved' test -f "$sandbox/outside.txt"
mkdir -p "$sandbox/outside-directory"
printf 'symlink escape data\n' > "$sandbox/outside-directory/victim.txt"
ln -s "$sandbox/outside-directory" "$sandbox/project/escape"
printf '%s\tfile\t%s\n' 'escape/victim.txt' "$(checksum "$sandbox/outside-directory/victim.txt")" > "$sandbox/project/.mindflayer-managed.tsv"
rc=0; (cd "$sandbox/project" && bash "$ROOT/tools/uninstall.sh" --project --confirm >/dev/null 2>&1) || rc=$?
assert 'uninstall rejects symlinked parent escape' test "$rc" -ne 0
assert 'symlinked parent escape target preserved' test -f "$sandbox/outside-directory/victim.txt"
teardown

setup
printf 'AGENTS.md\tfile\tproof\n' > "$sandbox/external-state.tsv"
ln -s "$sandbox/external-state.tsv" "$sandbox/project/.mindflayer-managed.tsv"
rc=0; (cd "$sandbox/project" && bash "$ROOT/tools/uninstall.sh" --project --confirm >/dev/null 2>&1) || rc=$?
assert 'uninstall rejects symlink ownership state' test "$rc" -ne 0
assert 'symlink ownership state target preserved' test -f "$sandbox/external-state.tsv"
teardown

setup
printf 'outside data\n' > "$sandbox/outside.txt"
printf '%s\tfile\t%s\n' '../outside.txt' "$(checksum "$sandbox/outside.txt")" > "$sandbox/project/.mindflayer-managed.tsv"
rc=0; (cd "$sandbox/project" && run_install --project --tools cursor --profile terraform --client Client --prefix cl --local >/dev/null 2>&1) || rc=$?
assert 'installer rejects unsafe existing ledger' test "$rc" -ne 0
assert 'unsafe ledger rejected before project writes' test ! -e "$sandbox/project/AGENTS.md"
assert 'installer preserves escaped ledger target' test -f "$sandbox/outside.txt"
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
assert 'Codex project shim remains absent' test ! -e "$sandbox/project/codex.md"
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
assert 'release task planning' sh -c "cd '$ROOT/skills/release-notes/scripts' && python3 test_tasks.py >/dev/null"
assert 'release email drafts' sh -c "cd '$ROOT/skills/release-notes/scripts' && python3 test_email_draft.py >/dev/null"
teardown

printf '\nPASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
