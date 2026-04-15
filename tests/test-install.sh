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
            shellcheck -s bash -S warning -e SC2034,SC2155 "$f" >/dev/null 2>&1 || rc=$?
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
    done < <(find "$REPO_ROOT/templates" -name "AGENTS-*.md" 2>/dev/null)
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
    assert_file_exists "doc: terraform-patterns" "$SANDBOX_HOME/.ai-toolkit/docs/terraform-patterns.md"
    assert_file_exists "doc: kimball-reference" "$SANDBOX_HOME/.ai-toolkit/docs/kimball-reference.md"

    # Templates (in ~/.ai-toolkit/)
    assert_file_exists "template: terraform" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS-terraform.md"
    assert_file_exists "template: databricks" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS-databricks.md"
    assert_file_exists "template: fabric" "$SANDBOX_HOME/.ai-toolkit/templates/AGENTS-fabric.md"

    # Settings templates (in ~/.ai-toolkit/)
    assert_file_exists "settings tmpl: terraform" "$SANDBOX_HOME/.ai-toolkit/templates/settings/settings-terraform.json"
    assert_file_exists "settings tmpl: databricks" "$SANDBOX_HOME/.ai-toolkit/templates/settings/settings-databricks.json"
    assert_file_exists "settings tmpl: fabric" "$SANDBOX_HOME/.ai-toolkit/templates/settings/settings-fabric.json"

    # Global settings.json (Claude-specific)
    assert_file_exists "settings.json" "$SANDBOX_HOME/.claude/settings.json"

    # Scripts (in ~/.ai-toolkit/)
    assert_file_exists "script: check-template-update" "$SANDBOX_HOME/.ai-toolkit/check-template-update.sh"
    assert_file_exists "script: check-stores" "$SANDBOX_HOME/.ai-toolkit/check-stores.sh"
    assert_file_exists "script: sync-global" "$SANDBOX_HOME/.ai-toolkit/sync-global.sh"
    assert_executable "check-template-update.sh +x" "$SANDBOX_HOME/.ai-toolkit/check-template-update.sh"
    assert_executable "check-stores.sh +x" "$SANDBOX_HOME/.ai-toolkit/check-stores.sh"
    assert_executable "sync-global.sh +x" "$SANDBOX_HOME/.ai-toolkit/sync-global.sh"

    # Stores registry (in ~/.ai-toolkit/)
    assert_file_exists "stores.yml" "$SANDBOX_HOME/.ai-toolkit/stores.yml"

    # Decision log (spot-check first, middle, last — in ~/.ai-toolkit/)
    assert_file_exists "decision: 0001" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0001-agents-md-as-universal-repo-instruction-file.md"
    assert_file_exists "decision: 0009" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0009-five-layer-data-architecture.md"
    assert_file_exists "decision: 0010" "$SANDBOX_HOME/.ai-toolkit/docs/decisions/0010-lowercase-snake-case-naming.md"

    # Agent-specific global configs
    assert_file_exists "claude: CLAUDE.md" "$SANDBOX_HOME/.claude/CLAUDE.md"
    assert_file_exists "codex: AGENTS.md" "$SANDBOX_HOME/.codex/AGENTS.md"
    assert_file_exists "gemini: GEMINI.md" "$SANDBOX_HOME/.gemini/GEMINI.md"
    assert_file_exists "cursor: rules.md" "$SANDBOX_HOME/.cursor/rules.md"

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

    # Template version header parsing (same sed as check-template-update.sh)
    setup_sandbox
    mkdir -p "$SANDBOX_HOME/.claude/docs/repo-templates"
    cp "$REPO_ROOT/templates/AGENTS-terraform.md" "$SANDBOX_HOME/.claude/docs/repo-templates/AGENTS-terraform.md"
    (cd "$SANDBOX_PROJECT" && run_installer --project --tools claude --profile terraform --client X --prefix x --force --local) >/dev/null 2>&1

    if [ -f "$SANDBOX_PROJECT/AGENTS.md" ]; then
        local tmpl_name
        tmpl_name="$(sed -n 's/.*template: \([^ |]*\).*/\1/p' "$SANDBOX_PROJECT/AGENTS.md" | head -1)"
        assert_eq "version header: template name" "AGENTS-terraform" "$tmpl_name"

        local tmpl_version
        tmpl_version="$(sed -n 's/.*version: \([^ |]*\).*/\1/p' "$SANDBOX_PROJECT/AGENTS.md" | head -1)"
        if [ -n "$tmpl_version" ]; then
            PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m version header: version non-empty (%s)\n" "$tmpl_version"
        else
            FAIL=$((FAIL + 1)); FAILURES+=("[$CURRENT_GROUP] version header: version is empty")
            printf "  \033[31mFAIL\033[0m version header: version is empty\n"
        fi
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
