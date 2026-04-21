#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Test suite for install.sh
# Pure bash — no external test frameworks required
# Run: bash tests/test-install.sh
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/install.sh"
SH_FILES=(
    "$INSTALL_SCRIPT"
    "$REPO_ROOT/tools/check-template-update.sh"
    "$REPO_ROOT/tools/check-stores.sh"
    "$REPO_ROOT/tools/sync-global.sh"
    "$REPO_ROOT/tools/check-update.sh"
    "$REPO_ROOT/tools/uninstall.sh"
)

# --- Harness -----------------------------------------------------------------

PASS=0
FAIL=0
SKIP=0
CURRENT_GROUP=""
FAILURES=()

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "  \033[32mPASS\033[0m %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("[$CURRENT_GROUP] $description (expected='$expected', actual='$actual')")
        printf "  \033[31mFAIL\033[0m %s (expected='%s', got='%s')\n" "$description" "$expected" "$actual"
    fi
}

assert_contains() {
    local description="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        PASS=$((PASS + 1))
        printf "  \033[32mPASS\033[0m %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("[$CURRENT_GROUP] $description (needle='$needle' not found)")
        printf "  \033[31mFAIL\033[0m %s (needle='%s' not found)\n" "$description" "$needle"
    fi
}

assert_not_contains() {
    local description="$1" haystack="$2" needle="$3"
    if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
        PASS=$((PASS + 1))
        printf "  \033[32mPASS\033[0m %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("[$CURRENT_GROUP] $description (unwanted needle='$needle' found)")
        printf "  \033[31mFAIL\033[0m %s\n" "$description"
    fi
}

assert_file_exists() {
    local description="$1" filepath="$2"
    if [ -e "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  \033[32mPASS\033[0m %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("[$CURRENT_GROUP] $description ($filepath missing)")
        printf "  \033[31mFAIL\033[0m %s (%s)\n" "$description" "$filepath"
    fi
}

assert_not_exists() {
    local description="$1" filepath="$2"
    if [ ! -e "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  \033[32mPASS\033[0m %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("[$CURRENT_GROUP] $description ($filepath unexpectedly exists)")
        printf "  \033[31mFAIL\033[0m %s (%s unexpectedly exists)\n" "$description" "$filepath"
    fi
}

assert_executable() {
    local description="$1" filepath="$2"
    if [ -x "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  \033[32mPASS\033[0m %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("[$CURRENT_GROUP] $description ($filepath not executable)")
        printf "  \033[31mFAIL\033[0m %s\n" "$description"
    fi
}

assert_rc() {
    local description="$1" expected="$2" actual="$3"
    assert_eq "$description" "$expected" "$actual"
}

skip_test() {
    local description="$1" reason="$2"
    SKIP=$((SKIP + 1))
    printf "  \033[33mSKIP\033[0m %s (%s)\n" "$description" "$reason"
}

group() {
    CURRENT_GROUP="$1"
    printf "\n--- %s ---\n" "$1"
}

# --- Sandbox -----------------------------------------------------------------

SANDBOX=""
SANDBOX_HOME=""
SANDBOX_PROJECT=""
ORIGINAL_HOME="$HOME"

setup_sandbox() {
    SANDBOX="$(mktemp -d)"
    SANDBOX_HOME="$SANDBOX/home"
    SANDBOX_PROJECT="$SANDBOX/project"
    mkdir -p "$SANDBOX_HOME" "$SANDBOX_PROJECT"
    export HOME="$SANDBOX_HOME"
}

teardown_sandbox() {
    export HOME="$ORIGINAL_HOME"
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=""
}

# Run install.sh non-interactively (stdin from /dev/null)
run_installer() {
    bash "$INSTALL_SCRIPT" "$@" </dev/null 2>&1
}

# =============================================================================
# Category 1: Syntax & Static Analysis
# =============================================================================

test_syntax() {
    group "1. Syntax & Static Analysis"

    for f in "${SH_FILES[@]}"; do
        local name
        name="$(basename "$f")"
        local output
        output="$(bash -n "$f" 2>&1)"
        assert_eq "bash -n $name" "" "$output"
    done

    if command -v shellcheck >/dev/null 2>&1; then
        for f in "${SH_FILES[@]}"; do
            local name
            name="$(basename "$f")"
            local rc=0
            shellcheck -s bash -S warning -e SC2034,SC2088,SC2155 "$f" >/dev/null 2>&1 || rc=$?
            assert_eq "shellcheck $name" "0" "$rc"
        done
    else
        skip_test "shellcheck linting" "shellcheck not installed"
    fi

    for f in "${SH_FILES[@]}"; do
        local name
        name="$(basename "$f")"
        local shebang
        shebang="$(head -1 "$f")"
        assert_eq "shebang $name" "#!/usr/bin/env bash" "$shebang"
    done
}

# =============================================================================
# Category 2: File Manifest Integrity
# =============================================================================

test_manifests() {
    group "2. File Manifest Integrity"

    # Extract all quoted paths from manifest arrays in install.sh
    local manifest_files=()
    local in_array=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Z_]+_FILES=\( ]]; then
            in_array=1
            continue
        fi
        if [ "$in_array" = "1" ]; then
            if [[ "$line" =~ ^\) ]]; then
                in_array=0
                continue
            fi
            if [[ "$line" =~ \"([^\"]+)\" ]]; then
                manifest_files+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "$INSTALL_SCRIPT"

    for f in "${manifest_files[@]}"; do
        assert_file_exists "manifest: $f" "$REPO_ROOT/$f"
    done

    assert_file_exists "global/AGENTS.md" "$REPO_ROOT/global/AGENTS.md"
    assert_file_exists "repo-root AGENTS.md (ADR-0001)" "$REPO_ROOT/AGENTS.md"
    assert_file_exists "repo-root CLAUDE.md pointer" "$REPO_ROOT/CLAUDE.md"
    local claude_pointer
    claude_pointer="$(grep -c "@AGENTS.md" "$REPO_ROOT/CLAUDE.md" || true)"
    [ "$claude_pointer" -ge 1 ] && claude_pointer=1 || claude_pointer=0
    assert_eq "CLAUDE.md contains @AGENTS.md pointer" "1" "$claude_pointer"

    # Orphan check: skills
    while IFS= read -r f; do
        local rel="${f#"$REPO_ROOT"/}"
        local found=0
        for m in "${manifest_files[@]}"; do
            [ "$m" = "$rel" ] && found=1 && break
        done
        assert_eq "skill in manifest: $rel" "1" "$found"
    done < <(find "$REPO_ROOT/skills" -name "SKILL.md" 2>/dev/null)

    # Orphan check: templates
    while IFS= read -r f; do
        local rel="${f#"$REPO_ROOT"/}"
        local found=0
        for m in "${manifest_files[@]}"; do
            [ "$m" = "$rel" ] && found=1 && break
        done
        assert_eq "template in manifest: $rel" "1" "$found"
    done < <(find "$REPO_ROOT/templates" -name "AGENTS*.md" 2>/dev/null)
}

# =============================================================================
# Category 3: Flag Parsing
# =============================================================================

test_flags() {
    group "3. Flag Parsing"

    local rc

    # --help exits 0
    rc=0; run_installer --help >/dev/null 2>&1 || rc=$?
    assert_rc "--help exits 0" "0" "$rc"

    # Value flags without value exit 1
    for flag in --tools --profile --client --prefix; do
        rc=0; run_installer "$flag" >/dev/null 2>&1 || rc=$?
        assert_rc "$flag without value exits 1" "1" "$rc"
    done

    # Unknown flag exits 1
    rc=0; run_installer --nonexistent >/dev/null 2>&1 || rc=$?
    assert_rc "unknown flag exits 1" "1" "$rc"

    # Invalid profile name exits 1
    rc=0; run_installer --project --tools claude --profile bogus --client X --prefix x --force --local >/dev/null 2>&1 || rc=$?
    assert_rc "--profile bogus exits 1" "1" "$rc"
}

# =============================================================================
# Category 4: Non-Interactive Mode
# =============================================================================

test_non_interactive() {
    group "4. Non-Interactive Mode"

    local rc output

    # Full global command succeeds
    setup_sandbox
    rc=0; run_installer --global --tools claude --force --local >/dev/null 2>&1 || rc=$?
    assert_rc "global + tools + force + local succeeds" "0" "$rc"
    teardown_sandbox

    # Full project command succeeds
    setup_sandbox
    rc=0; (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1 || rc=$?
    assert_rc "project full flags succeeds" "0" "$rc"
    teardown_sandbox

    # Missing --tools
    setup_sandbox
    rc=0; output="$(run_installer --global --force --local 2>&1)" || rc=$?
    assert_rc "missing --tools exits non-zero" "1" "$rc"
    assert_contains "missing --tools mentions flag" "$output" "--tools"
    teardown_sandbox

    # Missing --global/--project
    setup_sandbox
    rc=0; output="$(run_installer --tools claude --force --local 2>&1)" || rc=$?
    assert_rc "missing mode exits non-zero" "1" "$rc"
    assert_contains "missing mode mentions --global" "$output" "--global"
    teardown_sandbox

    # Missing --client in project mode
    setup_sandbox
    rc=0; run_installer --project --tools claude --profile terraform --prefix x --force --local >/dev/null 2>&1 || rc=$?
    assert_rc "missing --client exits non-zero" "1" "$rc"
    teardown_sandbox
}

# =============================================================================
# Category 5: Global Install Verification
# =============================================================================

test_global_install() {
    group "5. Global Install Verification"

    setup_sandbox
    run_installer --global --tools claude,codex,gemini,cursor,copilot --force --local >/dev/null 2>&1

    # Skills in ~/.ai-toolkit/ (agent-neutral)
    assert_file_exists "skill (toolkit): adr" "$SANDBOX_HOME/.ai-toolkit/skills/adr/SKILL.md"
    assert_file_exists "skill (toolkit): kimball-model" "$SANDBOX_HOME/.ai-toolkit/skills/kimball-model/SKILL.md"
    assert_file_exists "skill (toolkit): setup-repo" "$SANDBOX_HOME/.ai-toolkit/skills/setup-repo/SKILL.md"
    assert_file_exists "skill (toolkit): terraform-scaffold" "$SANDBOX_HOME/.ai-toolkit/skills/terraform-scaffold/SKILL.md"
    assert_file_exists "skill ref (toolkit): azure-devops" "$SANDBOX_HOME/.ai-toolkit/skills/terraform-scaffold/references/azure-devops-pipelines.md"
    assert_file_exists "skill ref (toolkit): fabric" "$SANDBOX_HOME/.ai-toolkit/skills/terraform-scaffold/references/fabric-modules.md"

    # Skills also in ~/.claude/skills/ for Claude auto-discovery (claude was selected)
    assert_file_exists "skill (claude): adr" "$SANDBOX_HOME/.claude/skills/adr/SKILL.md"
    assert_file_exists "skill (claude): kimball-model" "$SANDBOX_HOME/.claude/skills/kimball-model/SKILL.md"

    # Smart skills installed
    assert_file_exists "skill (toolkit): smart-commit" "$SANDBOX_HOME/.ai-toolkit/skills/smart-commit/SKILL.md"
    assert_file_exists "skill (toolkit): smart-pr" "$SANDBOX_HOME/.ai-toolkit/skills/smart-pr/SKILL.md"
    assert_file_exists "skill (toolkit): branch-cleanup" "$SANDBOX_HOME/.ai-toolkit/skills/branch-cleanup/SKILL.md"
    assert_file_exists "skill (toolkit): promote-adr" "$SANDBOX_HOME/.ai-toolkit/skills/promote-adr/SKILL.md"

    # Skills content validation — verify YAML frontmatter and correct skill identity
    local adr_content kimball_content
    adr_content="$(head -3 "$SANDBOX_HOME/.ai-toolkit/skills/adr/SKILL.md")"
    assert_contains "skill content: adr has frontmatter" "$adr_content" "name: adr"
    kimball_content="$(head -3 "$SANDBOX_HOME/.ai-toolkit/skills/kimball-model/SKILL.md")"
    assert_contains "skill content: kimball has frontmatter" "$kimball_content" "name: kimball-model"
    local cleanup_content
    cleanup_content="$(head -3 "$SANDBOX_HOME/.ai-toolkit/skills/branch-cleanup/SKILL.md")"
    assert_contains "skill content: branch-cleanup has frontmatter" "$cleanup_content" "name: branch-cleanup"

    # Regression: protected-branch list and multi-remote fetch
    local cleanup_full
    cleanup_full="$(cat "$SANDBOX_HOME/.ai-toolkit/skills/branch-cleanup/SKILL.md")"
    assert_contains "skill: branch-cleanup protects develop" "$cleanup_full" "\`develop\`"
    assert_contains "skill: branch-cleanup fetches all remotes" "$cleanup_full" "git fetch --all --prune"
    local promote_content
    promote_content="$(head -3 "$SANDBOX_HOME/.ai-toolkit/skills/promote-adr/SKILL.md")"
    assert_contains "skill content: promote-adr has frontmatter" "$promote_content" "name: promote-adr"

    # Skills are distinct (not clobbered by basename collision)
    local adr_first kimball_first
    adr_first="$(head -3 "$SANDBOX_HOME/.ai-toolkit/skills/adr/SKILL.md")"
    kimball_first="$(head -3 "$SANDBOX_HOME/.ai-toolkit/skills/kimball-model/SKILL.md")"
    if [ "$adr_first" != "$kimball_first" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m skills are distinct (no basename collision)\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] skills are identical (basename collision bug)")
        printf "  \033[31mFAIL\033[0m skills are identical (basename collision bug)\n"
    fi

    # Docs (in ~/.ai-toolkit/)
    assert_file_exists "doc: architecture" "$SANDBOX_HOME/.ai-toolkit/docs/architecture.md"
    assert_file_exists "doc: terraform-patterns" "$SANDBOX_HOME/.ai-toolkit/docs/terraform-patterns.md"
    assert_file_exists "doc: kimball-reference" "$SANDBOX_HOME/.ai-toolkit/docs/kimball-reference.md"

    # Templates (in ~/.ai-toolkit/) — v2.0.0: one universal template
    assert_file_exists "template: universal AGENTS.md" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS.md"
    assert_not_exists "template: no legacy AGENTS-terraform.md" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS-terraform.md"
    assert_not_exists "template: no legacy AGENTS-databricks.md" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS-databricks.md"
    assert_not_exists "template: no legacy AGENTS-fabric.md" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS-fabric.md"

    # Platform ADRs (in ~/.ai-toolkit/docs/decisions/platform/)
    assert_file_exists "platform ADR: 0011 safety" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/platform/0011-safety-rules-for-all-agents.md"
    assert_file_exists "platform ADR: 0012 fabric medallion" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/platform/0012-fabric-medallion-layers.md"
    assert_file_exists "platform ADR: 0016 databricks uc" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/platform/0016-databricks-unity-catalog-structure.md"
    assert_file_exists "platform ADR: 0019 terraform modules" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/platform/0019-terraform-module-structure.md"

    # Toolkit meta-ADR for the refactor
    assert_file_exists "toolkit ADR: 0011 tech-stack as ADRs" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0011-tech-stack-conventions-as-adrs.md"

    # Settings templates (in ~/.ai-toolkit/)
    assert_file_exists "settings tmpl: terraform" "$SANDBOX_HOME/.ai-toolkit/templates/settings/settings-terraform.json"
    assert_file_exists "settings tmpl: databricks" "$SANDBOX_HOME/.ai-toolkit/templates/settings/settings-databricks.json"
    assert_file_exists "settings tmpl: fabric" "$SANDBOX_HOME/.ai-toolkit/templates/settings/settings-fabric.json"

    # Global settings.json (Claude-specific)
    assert_file_exists "settings.json" "$SANDBOX_HOME/.claude/settings.json"

    # Settings content validation — verify it's valid JSON with permissions
    if python3 -c "import json; json.load(open('$SANDBOX_HOME/.claude/settings.json'))" 2>/dev/null; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m settings.json is valid JSON\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] settings.json is not valid JSON")
        printf "  \033[31mFAIL\033[0m settings.json is not valid JSON\n"
    fi

    # Scripts (in ~/.ai-toolkit/)
    assert_file_exists "script: check-template-update" "$SANDBOX_HOME/.ai-toolkit/check-template-update.sh"
    assert_file_exists "script: check-stores" "$SANDBOX_HOME/.ai-toolkit/check-stores.sh"
    assert_file_exists "script: sync-global" "$SANDBOX_HOME/.ai-toolkit/sync-global.sh"
    assert_file_exists "script: check-update" "$SANDBOX_HOME/.ai-toolkit/check-update.sh"
    assert_file_exists "script: uninstall" "$SANDBOX_HOME/.ai-toolkit/uninstall.sh"
    assert_executable "check-template-update.sh +x" "$SANDBOX_HOME/.ai-toolkit/check-template-update.sh"
    assert_executable "check-stores.sh +x" "$SANDBOX_HOME/.ai-toolkit/check-stores.sh"
    assert_executable "sync-global.sh +x" "$SANDBOX_HOME/.ai-toolkit/sync-global.sh"
    assert_executable "check-update.sh +x" "$SANDBOX_HOME/.ai-toolkit/check-update.sh"
    assert_executable "uninstall.sh +x" "$SANDBOX_HOME/.ai-toolkit/uninstall.sh"

    # Stores registry (in ~/.ai-toolkit/)
    assert_file_exists "stores.yml" "$SANDBOX_HOME/.ai-toolkit/stores.yml"

    # Version stamp (in ~/.ai-toolkit/)
    assert_file_exists "version stamp" "$SANDBOX_HOME/.ai-toolkit/version"
    local installed_version
    installed_version="$(cat "$SANDBOX_HOME/.ai-toolkit/version")"
    assert_eq "version matches installer VERSION" "1.0.0" "$installed_version"

    # Decision log (spot-check first, middle, last — in ~/.ai-toolkit/)
    assert_file_exists "decision: 0001" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0001-agents-md-as-universal-repo-instruction-file.md"
    assert_file_exists "decision: 0009" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0009-five-layer-data-architecture.md"
    assert_file_exists "decision: 0010" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0010-lowercase-snake-case-naming.md"

    # Agent-specific global configs
    assert_file_exists "claude: CLAUDE.md" "$SANDBOX_HOME/.claude/CLAUDE.md"
    assert_file_exists "codex: AGENTS.md" "$SANDBOX_HOME/.codex/AGENTS.md"
    assert_file_exists "gemini: GEMINI.md" "$SANDBOX_HOME/.gemini/GEMINI.md"
    assert_file_exists "cursor: rules.md" "$SANDBOX_HOME/.cursor/rules.md"
    assert_file_exists "copilot: global copilot-instructions.md" "$SANDBOX_HOME/.copilot/copilot-instructions.md"

    # Global config content validation — all agents get the same source content
    local claude_heading codex_heading
    claude_heading="$(head -1 "$SANDBOX_HOME/.claude/CLAUDE.md")"
    assert_eq "claude CLAUDE.md has correct heading" "# Global Instructions" "$claude_heading"
    codex_heading="$(head -1 "$SANDBOX_HOME/.codex/AGENTS.md")"
    assert_eq "codex AGENTS.md has correct heading" "# Global Instructions" "$codex_heading"
    local copilot_heading
    copilot_heading="$(head -1 "$SANDBOX_HOME/.copilot/copilot-instructions.md")"
    assert_eq "copilot global instructions has correct heading" "# Global Instructions" "$copilot_heading"

    # Hard Rules section enforced in global config
    local claude_body
    claude_body="$(cat "$SANDBOX_HOME/.claude/CLAUDE.md")"
    assert_contains "global config: Hard Rules section" "$claude_body" "Hard Rules"
    assert_contains "global config: Always Plan First rule" "$claude_body" "Always Plan First"
    assert_contains "global config: Wait for the User rule" "$claude_body" "Wait for the User"

    # Codex + copilot templates (in ~/.ai-toolkit/)
    assert_file_exists "codex: config.toml" "$SANDBOX_HOME/.ai-toolkit/templates/codex/config.toml"
    assert_file_exists "codex: codex.md" "$SANDBOX_HOME/.ai-toolkit/templates/codex/codex.md"
    assert_file_exists "copilot: instructions" "$SANDBOX_HOME/.ai-toolkit/templates/copilot/copilot-instructions.md"
    assert_file_exists "gemini: settings.json" "$SANDBOX_HOME/.ai-toolkit/templates/gemini/settings.json"
    assert_file_exists "gemini: gemini.md" "$SANDBOX_HOME/.ai-toolkit/templates/gemini/gemini.md"
    assert_file_exists "cursor: cursor.md" "$SANDBOX_HOME/.ai-toolkit/templates/cursor/cursor.md"

    # Codex-only install must NOT create ~/.claude/
    teardown_sandbox
    setup_sandbox
    run_installer --global --tools codex --force --local >/dev/null 2>&1
    if [ ! -d "$SANDBOX_HOME/.claude" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m codex-only: ~/.claude not created\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] codex-only install created ~/.claude/")
        printf "  \033[31mFAIL\033[0m codex-only install created ~/.claude/\n"
    fi

    teardown_sandbox
}

# =============================================================================
# Category 6: Project Install Verification
# =============================================================================

test_project_install() {
    group "6. Project Install Verification"

    for profile in terraform databricks fabric; do
        setup_sandbox

        (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude,codex,copilot,gemini,cursor --profile "$profile" --client "TestCorp" --prefix "tc" --force --local) >/dev/null 2>&1

        assert_file_exists "[$profile] AGENTS.md" "$SANDBOX_PROJECT/AGENTS.md"

        if [ -f "$SANDBOX_PROJECT/AGENTS.md" ]; then
            local content
            content="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
            assert_contains "[$profile] CLIENT_NAME substituted" "$content" "TestCorp"
            assert_not_contains "[$profile] no raw {CLIENT_NAME}" "$content" "{CLIENT_NAME}"
            assert_not_contains "[$profile] no raw {prefix}" "$content" "{prefix}"
        fi

        assert_file_exists "[$profile] .claude/settings.json" "$SANDBOX_PROJECT/.claude/settings.json"
        assert_file_exists "[$profile] docs/adr/" "$SANDBOX_PROJECT/docs/adr"

        if [ -f "$SANDBOX_PROJECT/.gitignore" ]; then
            local gi
            gi="$(cat "$SANDBOX_PROJECT/.gitignore")"
            assert_contains "[$profile] .gitignore: settings.local" "$gi" ".claude/settings.local.json"
            assert_contains "[$profile] .gitignore: CLAUDE.local" "$gi" "CLAUDE.local.md"
        fi

        if [ -L "$SANDBOX_PROJECT/.github/copilot-instructions.md" ]; then
            PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m [$profile] copilot symlink\n"
        else
            FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] [$profile] copilot symlink missing")
            printf "  \033[31mFAIL\033[0m [$profile] copilot symlink\n"
        fi

        assert_file_exists "[$profile] codex.md" "$SANDBOX_PROJECT/codex.md"
        assert_file_exists "[$profile] gemini.md" "$SANDBOX_PROJECT/gemini.md"
        assert_file_exists "[$profile] .cursor/rules/project.md" "$SANDBOX_PROJECT/.cursor/rules/project.md"

        teardown_sandbox
    done

    # .gitignore idempotency
    setup_sandbox
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1

    if [ -f "$SANDBOX_PROJECT/.gitignore" ]; then
        local count
        count="$(grep -c ".claude/settings.local.json" "$SANDBOX_PROJECT/.gitignore")"
        assert_eq ".gitignore not duplicated on re-run" "1" "$count"
    fi

    teardown_sandbox
}

# =============================================================================
# Category 7: Safety & Overwrite Protection
# =============================================================================

test_safety() {
    group "7. Safety & Overwrite Protection"

    # AGENTS.md preserved without --force
    setup_sandbox
    echo "ORIGINAL" > "$SANDBOX_PROJECT/AGENTS.md"
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --local) >/dev/null 2>&1
    local content
    content="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
    assert_eq "AGENTS.md preserved without --force" "ORIGINAL" "$content"
    teardown_sandbox

    # AGENTS.md overwritten with --force
    setup_sandbox
    echo "ORIGINAL" > "$SANDBOX_PROJECT/AGENTS.md"
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1
    content="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
    if [ "$content" != "ORIGINAL" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m AGENTS.md overwritten with --force\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] AGENTS.md not overwritten with --force")
        printf "  \033[31mFAIL\033[0m AGENTS.md not overwritten with --force\n"
    fi
    teardown_sandbox

    # Backup created on global --force
    setup_sandbox
    mkdir -p "$SANDBOX_HOME/.claude"
    echo "OLD" > "$SANDBOX_HOME/.claude/CLAUDE.md"
    run_installer --global --tools claude --force --local >/dev/null 2>&1
    local backup_count
    backup_count="$(find "$SANDBOX_HOME/.claude" -name "CLAUDE.md.bak.*" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$backup_count" -ge 1 ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m backup created on global --force\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] no backup created on global --force")
        printf "  \033[31mFAIL\033[0m no backup created on global --force\n"
    fi
    teardown_sandbox

    # Settings.json backup on --force when it differs
    setup_sandbox
    mkdir -p "$SANDBOX_HOME/.claude"
    echo '{"old": true}' > "$SANDBOX_HOME/.claude/settings.json"
    run_installer --global --tools claude --force --local >/dev/null 2>&1
    local settings_backup
    settings_backup="$(find "$SANDBOX_HOME/.claude" -name "settings.json.bak.*" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$settings_backup" -ge 1 ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m settings.json backup on --force\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] no settings.json backup on --force")
        printf "  \033[31mFAIL\033[0m no settings.json backup on --force\n"
    fi
    teardown_sandbox

    # Idempotency: global install twice
    setup_sandbox
    run_installer --global --tools claude --force --local >/dev/null 2>&1
    local first_md
    first_md="$(cat "$SANDBOX_HOME/.claude/CLAUDE.md")"
    run_installer --global --tools claude --force --local >/dev/null 2>&1
    local second_md
    second_md="$(cat "$SANDBOX_HOME/.claude/CLAUDE.md")"
    assert_eq "idempotent global install" "$first_md" "$second_md"
    teardown_sandbox

    # Join mode: existing Mindflayer-managed AGENTS.md is preserved without --force
    setup_sandbox
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client OriginalCorp --prefix oc --force --local) >/dev/null 2>&1
    # Simulate a new teammate running setup again (no --force) on the same repo
    local before_agents
    before_agents="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude,cursor --profile terraform --client NewTeammate --prefix nt --local) >/dev/null 2>&1
    local after_agents
    after_agents="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
    assert_eq "join mode: AGENTS.md preserved (teammate re-run)" "$before_agents" "$after_agents"
    assert_contains "join mode: original client preserved" "$after_agents" "OriginalCorp"
    assert_not_contains "join mode: new teammate's client NOT injected" "$after_agents" "NewTeammate"
    teardown_sandbox

    # Join mode: additive — adds missing agent-specific file for new teammate
    setup_sandbox
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client OriginalCorp --prefix oc --force --local) >/dev/null 2>&1
    # New teammate uses Cursor too — the cursor file wasn't in the initial commit
    [ ! -f "$SANDBOX_PROJECT/.cursor/rules/project.md" ] || rm -f "$SANDBOX_PROJECT/.cursor/rules/project.md"
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude,cursor --profile terraform --client Ignored --prefix x --local) >/dev/null 2>&1
    assert_file_exists "join mode: cursor file added for new teammate" "$SANDBOX_PROJECT/.cursor/rules/project.md"
    teardown_sandbox

    # Join mode: legacy v1 header fallback — old repo with AGENTS-fabric header
    # should still have its platform inferred (backwards compatibility).
    setup_sandbox
    cat > "$SANDBOX_PROJECT/AGENTS.md" <<'LEGACY_AGENTS'
# Project Instructions

<!-- template: AGENTS-fabric | version: 1.0.0 | updated: 2026-03-24 -->

## Repo Identity
- **client:** LegacyCorp
- **platform:** microsoft-fabric

LEGACY_AGENTS
    # No --profile passed on purpose — installer must infer it from header
    local legacy_out
    legacy_out="$(cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --client LegacyCorp --prefix lc --local 2>&1)"
    assert_contains "join mode: legacy v1 header inferred as fabric" "$legacy_out" "fabric"
    # AGENTS.md must still be preserved (join mode)
    assert_contains "join mode: legacy AGENTS.md preserved" "$(cat "$SANDBOX_PROJECT/AGENTS.md")" "template: AGENTS-fabric"
    teardown_sandbox

    # Join mode: v2 body **platform:** inference
    setup_sandbox
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile fabric --client FabricCorp --prefix fc --force --local) >/dev/null 2>&1
    # Re-run without --profile — installer must infer from body **platform:** line
    local v2_out
    v2_out="$(cd "$SANDBOX_PROJECT" && run_installer --project --tools claude,cursor --client Ignored --prefix x --local 2>&1)"
    assert_contains "join mode: v2 body platform inferred as fabric" "$v2_out" "fabric"
    teardown_sandbox
}

# =============================================================================
# Category 8: Edge Cases
# =============================================================================

test_edge_cases() {
    group "8. Edge Cases"

    # sed injection: special characters in client name/prefix
    setup_sandbox
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client 'Foo/Bar&Baz\Qux' --prefix 'f/b' --force --local) >/dev/null 2>&1

    if [ -f "$SANDBOX_PROJECT/AGENTS.md" ]; then
        local content
        content="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
        assert_contains "sed injection: / and & in name" "$content" 'Foo/Bar&Baz\Qux'
        assert_contains "sed injection: / in prefix" "$content" "f/b"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] AGENTS.md not created for sed test")
        printf "  \033[31mFAIL\033[0m AGENTS.md not created for sed injection test\n"
    fi
    teardown_sandbox

    # Template version header parsing (v2.0.0: universal template, no platform suffix)
    setup_sandbox
    mkdir -p "$SANDBOX_HOME/.claude/docs/repo-templates"
    cp "$REPO_ROOT/templates/AGENTS.md" "$SANDBOX_HOME/.claude/docs/repo-templates/AGENTS.md"
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1

    if [ -f "$SANDBOX_PROJECT/AGENTS.md" ]; then
        local tmpl_name
        tmpl_name="$(sed -n 's/.*template: \([^ |]*\).*/\1/p' "$SANDBOX_PROJECT/AGENTS.md" | head -1)"
        assert_eq "version header: template name (v2)" "AGENTS" "$tmpl_name"

        local tmpl_version
        tmpl_version="$(sed -n 's/.*version: \([^ |]*\).*/\1/p' "$SANDBOX_PROJECT/AGENTS.md" | head -1)"
        assert_eq "version header: version is 2.0.0" "2.0.0" "$tmpl_version"

        # v2: platform is in the **platform:** body line (not the header suffix)
        local platform_line
        platform_line="$(sed -n 's/^[[:space:]]*-[[:space:]]*\*\*platform:\*\*[[:space:]]*\([a-z0-9-]*\).*/\1/p' "$SANDBOX_PROJECT/AGENTS.md" | head -1)"
        assert_eq "v2: platform in body" "terraform" "$platform_line"

        # v2: ADR list injected for profile
        local content
        content="$(cat "$SANDBOX_PROJECT/AGENTS.md")"
        assert_contains "v2: terraform ADRs injected" "$content" "ADR-0019"
        assert_contains "v2: safety ADR referenced" "$content" "ADR-0011"
    fi
    teardown_sandbox
}

# =============================================================================
# Category 9: Cross-Platform Compatibility
# =============================================================================

test_cross_platform() {
    group "9. Cross-Platform Compatibility"

    for f in "${SH_FILES[@]}"; do
        local name
        name="$(basename "$f")"

        # No grep -oP in executable lines (exclude comments)
        local count
        count="$(grep -v '^\s*#' "$f" | grep -c 'grep.*-[a-zA-Z]*P' || true)"
        assert_eq "no grep -P in $name" "0" "$count"

        # No sed -i in executable lines (exclude comments)
        count="$(grep -v '^\s*#' "$f" | grep -c 'sed -i' || true)"
        assert_eq "no sed -i in $name" "0" "$count"

        # Shebang
        local shebang
        shebang="$(head -1 "$f")"
        assert_eq "portable shebang: $name" "#!/usr/bin/env bash" "$shebang"
    done
}

# =============================================================================
# Category 10: Uninstaller
# =============================================================================

test_uninstall() {
    group "10. Uninstaller"

    local UNINSTALL_SCRIPT="$REPO_ROOT/tools/uninstall.sh"

    # --- Dry-run produces no deletions ---
    setup_sandbox
    run_installer --global --tools claude,codex,gemini,cursor --force --local >/dev/null 2>&1

    local pre_count
    pre_count="$(find "$SANDBOX_HOME/.ai-toolkit" -type f 2>/dev/null | wc -l | tr -d ' ')"

    bash "$UNINSTALL_SCRIPT" --global >/dev/null 2>&1
    local post_count
    post_count="$(find "$SANDBOX_HOME/.ai-toolkit" -type f 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "dry-run: no files deleted" "$pre_count" "$post_count"
    teardown_sandbox

    # --- Global --confirm removes ~/.ai-toolkit/ ---
    setup_sandbox
    run_installer --global --tools claude,codex,gemini,cursor --force --local >/dev/null 2>&1
    assert_file_exists "pre-uninstall: toolkit exists" "$SANDBOX_HOME/.ai-toolkit/version"

    bash "$UNINSTALL_SCRIPT" --global --confirm >/dev/null 2>&1
    if [ ! -d "$SANDBOX_HOME/.ai-toolkit" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m global --confirm: ~/.ai-toolkit/ removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] ~/.ai-toolkit/ still exists after --confirm")
        printf "  \033[31mFAIL\033[0m global --confirm: ~/.ai-toolkit/ still exists\n"
    fi

    # Codex/Gemini/Cursor agent files removed
    if [ ! -f "$SANDBOX_HOME/.codex/AGENTS.md" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m global --confirm: codex AGENTS.md removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] codex AGENTS.md still exists")
        printf "  \033[31mFAIL\033[0m global --confirm: codex AGENTS.md still exists\n"
    fi

    # Claude CLAUDE.md preserved without --force (user-modified)
    assert_file_exists "global --confirm: CLAUDE.md preserved (user-modified)" "$SANDBOX_HOME/.claude/CLAUDE.md"

    # Claude skills removed
    if [ ! -d "$SANDBOX_HOME/.claude/skills/adr" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m global --confirm: claude skill adr removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] claude skill adr still exists")
        printf "  \033[31mFAIL\033[0m global --confirm: claude skill adr still exists\n"
    fi
    teardown_sandbox

    # --- Global --confirm --force removes user-modified files ---
    setup_sandbox
    run_installer --global --tools claude --force --local >/dev/null 2>&1
    bash "$UNINSTALL_SCRIPT" --global --confirm --force >/dev/null 2>&1

    if [ ! -f "$SANDBOX_HOME/.claude/CLAUDE.md" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m global --force: CLAUDE.md removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] CLAUDE.md still exists with --force")
        printf "  \033[31mFAIL\033[0m global --force: CLAUDE.md still exists\n"
    fi

    # Backup created for user-modified files
    local backup_count
    backup_count="$(find "$SANDBOX_HOME/.claude" -name "CLAUDE.md.bak" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$backup_count" -ge 1 ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m global --force: CLAUDE.md backup created\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] no CLAUDE.md backup on --force")
        printf "  \033[31mFAIL\033[0m global --force: no CLAUDE.md backup\n"
    fi
    teardown_sandbox

    # --- Project --confirm removes project files ---
    setup_sandbox
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude,codex,gemini,cursor,copilot --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1

    (cd "$SANDBOX_PROJECT" && bash "$UNINSTALL_SCRIPT" --project --confirm) >/dev/null 2>&1

    # Generated files removed
    if [ ! -f "$SANDBOX_PROJECT/.claude/settings.json" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m project --confirm: .claude/settings.json removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] .claude/settings.json still exists")
        printf "  \033[31mFAIL\033[0m project --confirm: .claude/settings.json still exists\n"
    fi

    if [ ! -f "$SANDBOX_PROJECT/codex.md" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m project --confirm: codex.md removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] codex.md still exists")
        printf "  \033[31mFAIL\033[0m project --confirm: codex.md still exists\n"
    fi

    # Copilot symlink removed
    if [ ! -L "$SANDBOX_PROJECT/.github/copilot-instructions.md" ]; then
        PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m project --confirm: copilot symlink removed\n"
    else
        FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] copilot symlink still exists")
        printf "  \033[31mFAIL\033[0m project --confirm: copilot symlink still exists\n"
    fi

    # AGENTS.md preserved (user-modified) without --force
    assert_file_exists "project --confirm: AGENTS.md preserved (user-modified)" "$SANDBOX_PROJECT/AGENTS.md"

    # docs/adr/ preserved (user content)
    assert_file_exists "project --confirm: docs/adr/ preserved" "$SANDBOX_PROJECT/docs/adr"
    teardown_sandbox

    # --- Must specify --global or --project ---
    local rc=0
    bash "$UNINSTALL_SCRIPT" >/dev/null 2>&1 || rc=$?
    assert_rc "no mode flag exits 1" "1" "$rc"

    # --- --global and --project are mutually exclusive ---
    rc=0
    bash "$UNINSTALL_SCRIPT" --global --project >/dev/null 2>&1 || rc=$?
    assert_rc "mutual exclusion exits 1" "1" "$rc"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    printf "=== install.sh Test Suite ===\n"
    printf "Repo: %s\n\n" "$REPO_ROOT"

    test_syntax
    test_manifests
    test_flags
    test_non_interactive
    test_global_install
    test_project_install
    test_safety
    test_edge_cases
    test_cross_platform
    test_uninstall

    printf "\n=== Summary ===\n"
    printf "  PASS: %d\n" "$PASS"
    printf "  FAIL: %d\n" "$FAIL"
    printf "  SKIP: %d\n" "$SKIP"
    printf "  TOTAL: %d\n" "$((PASS + FAIL + SKIP))"

    if [ "$FAIL" -gt 0 ]; then
        printf "\nFailures:\n"
        for f in "${FAILURES[@]}"; do
            printf "  - %s\n" "$f"
        done
        exit 1
    fi

    printf "\nAll tests passed.\n"
    exit 0
}

main "$@"
