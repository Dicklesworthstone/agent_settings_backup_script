#!/usr/bin/env bash
#
# E2E Test Suite: Complete workflow tests with logging
# Tests full workflows across all features
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

declare -F create_claude_fixture >/dev/null 2>&1 || { echo "create_claude_fixture not loaded" >&2; exit 1; }

# E2E-specific utilities
E2E_START_TIME=""
E2E_PASSED=0
E2E_FAILED=0
E2E_SKIPPED=0
E2E_FAILED_TESTS=()

e2e_start() {
    E2E_START_TIME=$(date +%s)
    log_section "E2E Test Suite"
}

e2e_summary() {
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - E2E_START_TIME))
    local total=$((E2E_PASSED + E2E_FAILED + E2E_SKIPPED))

    echo ""
    echo "===================================="
    echo "E2E Test Suite Results"
    echo "===================================="
    echo "Total:    $total"
    echo "Passed:   $E2E_PASSED"
    echo "Failed:   $E2E_FAILED"
    echo "Skipped:  $E2E_SKIPPED"
    echo "Duration: ${duration}s"
    echo "===================================="

    if [[ ${#E2E_FAILED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo "Failed Tests:"
        for test in "${E2E_FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi
}

run_e2e_test() {
    local test_name="$1"
    local func="$2"
    local start_time

    set_current_test "$test_name"
    start_time=$(date +%s)
    log_info "Starting test"

    setup_test_env
    local result=0
    if ( set -euo pipefail; "$func" ); then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_pass "$test_name (${duration}s)"
        ((E2E_PASSED++))
    else
        result=$?
        if [[ $result -eq 2 ]]; then
            log_skip "$test_name"
            ((E2E_SKIPPED++))
        else
            local end_time duration
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_fail "$test_name (${duration}s)"
            E2E_FAILED_TESTS+=("$test_name")
            ((E2E_FAILED++))
            preserve_artifacts "$test_name"
        fi
    fi
    teardown_test_env
    clear_current_test
    return $result
}

# Helper to run asb with logging
run_asb_logged() {
    local description="${1:-command}"
    shift
    log_debug "Running: asb $*"
    # Capture output and status separately (|| true was incorrectly resetting $?)
    ASB_LAST_OUTPUT=$("$ASB_BIN" "$@" 2>&1)
    ASB_LAST_STATUS=$?
    log_debug "Exit code: $ASB_LAST_STATUS"
    if [[ $ASB_LAST_STATUS -ne 0 ]] && [[ -n "$ASB_LAST_OUTPUT" ]]; then
        log_debug "Output: $ASB_LAST_OUTPUT"
    fi
    return $ASB_LAST_STATUS
}

# ============================================
# E2E Workflow Tests
# ============================================

test_first_backup_workflow() {
    log_info "Creating mock agent config"
    create_claude_fixture
    assert_dir_exists "$HOME/.claude" || { log_error "Mock agent not created"; return 1; }

    log_info "Running initial backup"
    run_asb_logged "backup" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_dir_exists "$ASB_BACKUP_ROOT/.claude" || { log_error "Backup not created"; return 1; }

    log_info "Verifying git history"
    assert_dir_exists "$ASB_BACKUP_ROOT/.claude/.git" || { log_error "Git not initialized"; return 1; }
    local commit_count
    commit_count=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-list --count HEAD 2>/dev/null || echo 0)
    [[ $commit_count -ge 1 ]] || { log_error "No commits found"; return 1; }

    log_info "Running list command"
    run_asb_logged "list" list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "claude" || { log_error "Agent not listed"; return 1; }

    log_info "Workflow completed successfully"
}

test_modify_and_backup_workflow() {
    log_info "Setting up initial backup"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local initial_commit
    initial_commit=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)
    log_debug "Initial commit: $initial_commit"

    log_info "Modifying agent config"
    printf "modified\n" >> "$HOME/.claude/settings.json"

    log_info "Running second backup"
    run_asb_logged "backup" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Verifying new commit created"
    local new_commit
    new_commit=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)
    log_debug "New commit: $new_commit"
    assert_not_equals "$initial_commit" "$new_commit" || { log_error "No new commit"; return 1; }

    log_info "Running log command"
    run_asb_logged "log" log claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Backup" || { log_error "Log missing backup entry"; return 1; }

    log_info "Running diff command (should be empty after backup)"
    run_asb_logged "diff" diff claude
    # diff should succeed with no output when no changes
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Workflow completed successfully"
}

test_restore_workflow() {
    log_info "Setting up backup and modifications"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local original_content
    original_content=$(cat "$HOME/.claude/settings.json")
    log_debug "Original content saved"

    log_info "Modifying agent config"
    printf "MODIFIED_LINE\n" >> "$HOME/.claude/settings.json"
    local modified_content
    modified_content=$(cat "$HOME/.claude/settings.json")
    assert_not_equals "$original_content" "$modified_content" || { log_error "File not modified"; return 1; }

    log_info "Running restore with --force"
    run_asb_logged "restore" --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Verifying changes reverted"
    local restored_content
    restored_content=$(cat "$HOME/.claude/settings.json")
    assert_equals "$original_content" "$restored_content" || { log_error "Restore failed"; return 1; }

    log_info "Workflow completed successfully"
}

test_export_import_workflow() {
    log_info "Setting up backup with history"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    printf "change1\n" >> "$HOME/.claude/settings.json"
    run_asb backup claude
    printf "change2\n" >> "$HOME/.claude/settings.json"
    run_asb backup claude

    local commit_count_before
    commit_count_before=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-list --count HEAD)
    log_debug "Commits before export: $commit_count_before"

    log_info "Exporting backup"
    local archive="${TEST_ENV_ROOT}/claude-export.tar.gz"
    run_asb_logged "export" export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "$archive" || { log_error "Archive not created"; return 1; }

    log_info "Deleting backup directory"
    rm -rf "$ASB_BACKUP_ROOT/.claude"
    assert_dir_not_exists "$ASB_BACKUP_ROOT/.claude" || { log_error "Backup not deleted"; return 1; }

    log_info "Importing backup"
    run_asb_logged "import" import "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Verifying history preserved"
    assert_dir_exists "$ASB_BACKUP_ROOT/.claude/.git" || { log_error "Git not restored"; return 1; }
    local commit_count_after
    commit_count_after=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-list --count HEAD)
    log_debug "Commits after import: $commit_count_after"
    assert_equals "$commit_count_before" "$commit_count_after" || { log_error "History not preserved"; return 1; }

    log_info "Workflow completed successfully"
}

test_multi_agent_workflow() {
    log_info "Creating multiple mock agents"
    create_claude_fixture
    create_cursor_fixture
    create_codex_fixture

    assert_dir_exists "$HOME/.claude" || { log_error "Claude not created"; return 1; }
    assert_dir_exists "$HOME/.cursor" || { log_error "Cursor not created"; return 1; }
    assert_dir_exists "$HOME/.codex" || { log_error "Codex not created"; return 1; }

    log_info "Running backup for all agents"
    run_asb_logged "backup claude" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb_logged "backup cursor" backup cursor
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb_logged "backup codex" backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Modifying each agent"
    printf "claude_mod\n" >> "$HOME/.claude/settings.json"
    printf "cursor_mod\n" >> "$HOME/.cursor/settings.json"
    printf "codex_mod\n" >> "$HOME/.codex/settings.json"

    log_info "Running backup again for all"
    run_asb backup claude
    run_asb backup cursor
    run_asb backup codex

    log_info "Running list command"
    run_asb_logged "list" list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "claude" || { log_error "Claude not listed"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "cursor" || { log_error "Cursor not listed"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "codex" || { log_error "Codex not listed"; return 1; }

    log_info "Workflow completed successfully"
}

test_dryrun_safety_workflow() {
    log_info "Creating mock agent"
    create_claude_fixture
    local original_checksum
    original_checksum=$(get_dir_checksum "$HOME/.claude")

    log_info "Running dry-run backup"
    run_asb_logged "dry-run backup" --dry-run backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "DRY RUN" || { log_error "Missing DRY RUN indicator"; return 1; }

    log_info "Verifying no backup created"
    assert_dir_not_exists "$ASB_BACKUP_ROOT/.claude" || { log_error "Dry-run created backup"; return 1; }

    log_info "Running actual backup"
    run_asb_logged "real backup" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_dir_exists "$ASB_BACKUP_ROOT/.claude" || { log_error "Real backup not created"; return 1; }

    log_info "Modifying agent and testing dry-run restore"
    printf "modification\n" >> "$HOME/.claude/settings.json"
    local modified_checksum
    modified_checksum=$(get_dir_checksum "$HOME/.claude")

    run_asb_logged "dry-run restore" --dry-run restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "DRY RUN" || { log_error "Missing DRY RUN indicator"; return 1; }

    log_info "Verifying no changes made"
    local after_dryrun_checksum
    after_dryrun_checksum=$(get_dir_checksum "$HOME/.claude")
    assert_equals "$modified_checksum" "$after_dryrun_checksum" || { log_error "Dry-run modified files"; return 1; }

    log_info "Workflow completed successfully"
}

test_disaster_recovery_workflow() {
    log_info "Setting up full environment"
    create_claude_fixture
    create_cursor_fixture

    run_asb backup claude
    run_asb backup cursor

    log_info "Exporting all agents"
    local claude_archive="${TEST_ENV_ROOT}/claude-disaster.tar.gz"
    local cursor_archive="${TEST_ENV_ROOT}/cursor-disaster.tar.gz"
    run_asb export claude "$claude_archive"
    run_asb export cursor "$cursor_archive"

    assert_file_exists "$claude_archive" || { log_error "Claude archive not created"; return 1; }
    assert_file_exists "$cursor_archive" || { log_error "Cursor archive not created"; return 1; }

    log_info "DISASTER: Deleting all backups"
    rm -rf "$ASB_BACKUP_ROOT/.claude" "$ASB_BACKUP_ROOT/.cursor"
    assert_dir_not_exists "$ASB_BACKUP_ROOT/.claude" || { log_error "Claude not deleted"; return 1; }
    assert_dir_not_exists "$ASB_BACKUP_ROOT/.cursor" || { log_error "Cursor not deleted"; return 1; }

    log_info "Importing archives"
    run_asb_logged "import claude" import "$claude_archive"
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb_logged "import cursor" import "$cursor_archive"
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Verifying full restoration"
    assert_dir_exists "$ASB_BACKUP_ROOT/.claude/.git" || { log_error "Claude not restored"; return 1; }
    assert_dir_exists "$ASB_BACKUP_ROOT/.cursor/.git" || { log_error "Cursor not restored"; return 1; }

    log_info "Verifying restore works after import"
    rm -rf "$HOME/.claude"
    run_asb_logged "restore claude" --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_dir_exists "$HOME/.claude" || { log_error "Restore after import failed"; return 1; }

    log_info "Workflow completed successfully"
}

test_config_workflow() {
    log_info "Running config init"
    run_asb_logged "config init" config init
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local config_file="${XDG_CONFIG_HOME}/asb/config"
    assert_file_exists "$config_file" || { log_error "Config file not created"; return 1; }

    log_info "Running config show"
    run_asb_logged "config show" config show
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "ASB_BACKUP_ROOT" || { log_error "Config not showing backup root"; return 1; }

    log_info "Testing config file is sourced"
    printf 'ASB_VERBOSE=true\n' >> "$config_file"
    run_asb_logged "config show" config show
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "ASB_VERBOSE" || { log_error "Config not loaded"; return 1; }

    log_info "Workflow completed successfully"
}

test_completion_workflow() {
    log_info "Testing bash completion generation"
    run_asb_logged "completion bash" completion bash
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "complete" || { log_error "Bash completion invalid"; return 1; }

    log_info "Testing zsh completion generation"
    run_asb_logged "completion zsh" completion zsh
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "compdef" || { log_error "Zsh completion invalid"; return 1; }

    log_info "Testing fish completion generation"
    run_asb_logged "completion fish" completion fish
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "complete" || { log_error "Fish completion invalid"; return 1; }

    log_info "Workflow completed successfully"
}

test_version_and_help_workflow() {
    log_info "Testing version command"
    run_asb_logged "version" --version
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "asb" || { log_error "Version missing asb"; return 1; }

    log_info "Testing help command"
    run_asb_logged "help" --help
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "backup" || { log_error "Help missing backup command"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "restore" || { log_error "Help missing restore command"; return 1; }

    log_info "Workflow completed successfully"
}

# ============================================
# v0.3 Feature Workflows
# ============================================

test_tags_workflow() {
    log_info "Setting up backup for tagging"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Creating tag v1.0"
    run_asb_logged "tag create" tag claude v1.0
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Tagged" || { log_error "Tag not created"; return 1; }

    log_info "Modifying agent and creating second backup"
    printf "modified_for_v2\n" >> "$HOME/.claude/settings.json"
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Creating tag v2.0"
    run_asb_logged "tag create" tag claude v2.0
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Listing tags"
    run_asb_logged "tag list" tag claude --list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "v1.0" || { log_error "v1.0 not listed"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "v2.0" || { log_error "v2.0 not listed"; return 1; }

    log_info "Restoring from tag v1.0"
    run_asb_logged "restore from tag" --force restore claude v1.0
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Verifying restored content (should not have v2 modification)"
    if grep -q "modified_for_v2" "$HOME/.claude/settings.json" 2>/dev/null; then
        log_error "Restore from tag failed - v2 content still present"
        return 1
    fi

    log_info "Workflow completed successfully"
}

test_stats_workflow() {
    log_info "Setting up multiple backups for stats"
    create_claude_fixture
    create_cursor_fixture

    run_asb backup claude
    run_asb backup cursor

    printf "change1\n" >> "$HOME/.claude/settings.json"
    run_asb backup claude
    printf "change2\n" >> "$HOME/.claude/settings.json"
    run_asb backup claude

    log_info "Running stats overview"
    run_asb_logged "stats overview" stats
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "claude" || { log_error "Claude not in stats"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "cursor" || { log_error "Cursor not in stats"; return 1; }

    log_info "Running stats for single agent"
    run_asb_logged "stats single" stats claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Claude" || { log_error "Claude name not shown"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "backups" || { log_error "Backup count not shown"; return 1; }

    log_info "Testing JSON stats output"
    run_asb_logged "stats json" --json stats claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || { log_error "Invalid JSON"; return 1; }

    log_info "Workflow completed successfully"
}

test_discover_workflow() {
    log_info "Creating discoverable agent"
    mkdir -p "$HOME/.kodu"
    printf '{"mock": true}\n' > "$HOME/.kodu/settings.json"

    log_info "Running discover --list"
    run_asb_logged "discover list" discover --list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" ".kodu" || { log_error "Kodu not discovered"; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" "Kodu" || { log_error "Kodu name not shown"; return 1; }

    log_info "Running discover --auto"
    run_asb_logged "discover auto" discover --auto
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Added" || { log_error "Agent not added"; return 1; }

    log_info "Verifying agent appears in list"
    run_asb_logged "list" list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "kodu" || { log_error "Kodu not in agent list"; return 1; }

    log_info "Running backup for newly discovered agent"
    run_asb_logged "backup kodu" backup kodu
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_dir_exists "$ASB_BACKUP_ROOT/.kodu" || { log_error "Kodu backup not created"; return 1; }

    log_info "Verifying agent not rediscovered"
    run_asb_logged "discover list again" discover --list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "No new agents" || { log_error "Agent was rediscovered"; return 1; }

    log_info "Workflow completed successfully"
}

test_json_output_workflow() {
    log_info "Setting up backup"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Testing JSON list"
    run_asb_logged "json list" --json list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, list) and len(d) > 0' 2>/dev/null || { log_error "Invalid JSON list"; return 1; }

    log_info "Testing JSON history"
    run_asb_logged "json history" --json history claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "commits" in d' 2>/dev/null || { log_error "Invalid JSON history"; return 1; }

    log_info "Testing JSON tag list"
    run_asb tag claude test-tag
    run_asb_logged "json tag list" --json tag claude --list
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "tags" in d' 2>/dev/null || { log_error "Invalid JSON tag list"; return 1; }

    log_info "Testing JSON stats"
    run_asb_logged "json stats" --json stats
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "agents" in d' 2>/dev/null || { log_error "Invalid JSON stats"; return 1; }

    log_info "Workflow completed successfully"
}

# ============================================
# Enhanced E2E Coverage
# ============================================

test_error_paths_workflow() {
    log_info "Testing backup with unknown agent"
    run_asb_logged "backup unknown" backup unknownagent123
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        log_error "Expected failure for unknown agent"
        return 1
    fi

    log_info "Testing restore with invalid commit"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb_logged "restore invalid commit" --force restore claude deadbeef
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        log_error "Expected failure for invalid commit"
        return 1
    fi

    log_info "Workflow completed successfully"
}

test_unicode_and_special_files_workflow() {
    log_info "Creating mock agent config with unicode filenames"
    create_claude_fixture
    local unicode_file="${HOME}/.claude/ünîçødé.txt"
    local special_file="${HOME}/.claude/space and #!.txt"
    printf "unicode\n" > "$unicode_file"
    printf "special\n" > "$special_file"

    log_info "Backing up with unicode files"
    run_asb_logged "backup unicode" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    rm -f "$unicode_file" "$special_file"

    log_info "Restoring and verifying unicode files"
    run_asb_logged "restore unicode" --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "$unicode_file" || return 1
    assert_file_exists "$special_file" || return 1

    log_info "Workflow completed successfully"
}

test_symlink_workflow() {
    log_info "Creating mock agent config with symlink"
    create_claude_fixture
    local target="${HOME}/.claude/target.txt"
    local link="${HOME}/.claude/linked.txt"
    printf "target\n" > "$target"
    ln -s "$target" "$link"

    log_info "Backing up symlink"
    run_asb_logged "backup symlink" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    rm -f "$link"

    log_info "Restoring and verifying symlink"
    run_asb_logged "restore symlink" --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    if [[ ! -L "$link" ]]; then
        log_error "Expected symlink after restore"
        return 1
    fi

    log_info "Workflow completed successfully"
}

test_large_file_workflow() {
    log_info "Creating large file fixture"
    create_claude_fixture
    local large_file="${HOME}/.claude/large.bin"
    if command -v dd >/dev/null 2>&1; then
        dd if=/dev/zero of="$large_file" bs=1m count=5 >/dev/null 2>&1
    elif command -v python3 >/dev/null 2>&1; then
        LARGE_FILE="$large_file" python3 - <<'PY'
import os
with open(os.environ["LARGE_FILE"], "wb") as f:
    f.write(b"\0" * 5 * 1024 * 1024)
PY
    else
        log_warn "Skipping large file test (missing dd/python3)"
        return 2
    fi

    log_info "Backing up large file"
    run_asb_logged "backup large file" backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local backup_file="${ASB_BACKUP_ROOT}/.claude/large.bin"
    assert_file_exists "$backup_file" || return 1

    log_info "Workflow completed successfully"
}

test_concurrent_backup_workflow() {
    log_info "Creating multiple mock agents for concurrent backups"
    create_claude_fixture
    create_cursor_fixture
    create_codex_fixture

    log_info "Running concurrent backups"
    "$ASB_BIN" backup claude >/dev/null 2>&1 &
    local pid1=$!
    "$ASB_BIN" backup codex >/dev/null 2>&1 &
    local pid2=$!
    wait "$pid1"
    local status1=$?
    wait "$pid2"
    local status2=$?

    if [[ $status1 -ne 0 || $status2 -ne 0 ]]; then
        log_error "Concurrent backups failed"
        return 1
    fi

    assert_dir_exists "$ASB_BACKUP_ROOT/.claude" || return 1
    assert_dir_exists "$ASB_BACKUP_ROOT/.codex" || return 1

    log_info "Workflow completed successfully"
}

test_verify_workflow() {
    log_info "Creating mock agent config for verify"
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Running verify for agent"
    run_asb_logged "verify claude" verify claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    log_info "Workflow completed successfully"
}

# ============================================
# Main test runner
# ============================================

e2e_start

run_e2e_test "first_backup_workflow" test_first_backup_workflow || true
run_e2e_test "modify_and_backup_workflow" test_modify_and_backup_workflow || true
run_e2e_test "restore_workflow" test_restore_workflow || true
run_e2e_test "export_import_workflow" test_export_import_workflow || true
run_e2e_test "multi_agent_workflow" test_multi_agent_workflow || true
run_e2e_test "dryrun_safety_workflow" test_dryrun_safety_workflow || true
run_e2e_test "disaster_recovery_workflow" test_disaster_recovery_workflow || true
run_e2e_test "config_workflow" test_config_workflow || true
run_e2e_test "completion_workflow" test_completion_workflow || true
run_e2e_test "version_and_help_workflow" test_version_and_help_workflow || true

# v0.3 feature tests
run_e2e_test "tags_workflow" test_tags_workflow || true
run_e2e_test "stats_workflow" test_stats_workflow || true
run_e2e_test "discover_workflow" test_discover_workflow || true
run_e2e_test "json_output_workflow" test_json_output_workflow || true
run_e2e_test "error_paths_workflow" test_error_paths_workflow || true
run_e2e_test "unicode_and_special_files_workflow" test_unicode_and_special_files_workflow || true
run_e2e_test "symlink_workflow" test_symlink_workflow || true
run_e2e_test "large_file_workflow" test_large_file_workflow || true
run_e2e_test "concurrent_backup_workflow" test_concurrent_backup_workflow || true
run_e2e_test "verify_workflow" test_verify_workflow || true

e2e_summary

if [[ $E2E_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
