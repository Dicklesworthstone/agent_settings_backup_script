#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

declare -F create_claude_fixture >/dev/null 2>&1 || { echo "create_claude_fixture not loaded" >&2; exit 1; }

test_dryrun_backup_no_file_changes() {
    create_claude_fixture
    local backup_dir="${ASB_BACKUP_ROOT}/.claude"
    run_asb --dry-run backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    if [[ -d "$backup_dir" ]]; then
        echo "Backup directory was created during dry-run" >&2
        return 1
    fi
}

test_dryrun_backup_no_git_commits() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local backup_dir="${ASB_BACKUP_ROOT}/.claude"
    local before_count
    before_count=$(git -C "$backup_dir" rev-list --count HEAD 2>/dev/null)

    run_asb --dry-run backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local after_count
    after_count=$(git -C "$backup_dir" rev-list --count HEAD 2>/dev/null)
    assert_equals "$before_count" "$after_count"
}

test_dryrun_backup_shows_preview() {
    create_claude_fixture
    # Debug: show test environment
    echo "DEBUG: HOME=$HOME" >&2
    echo "DEBUG: Fixture exists: $(ls -la "${HOME}/.claude" 2>&1 | head -3)" >&2
    run_asb --dry-run backup claude
    echo "DEBUG: Exit status: $ASB_LAST_STATUS" >&2
    echo "DEBUG: Output length: ${#ASB_LAST_OUTPUT}" >&2
    echo "DEBUG: Output (first 500 chars): ${ASB_LAST_OUTPUT:0:500}" >&2
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "DRY RUN"
    assert_contains "$ASB_LAST_OUTPUT" "Would backup"
}

test_dryrun_short_flag() {
    create_claude_fixture
    run_asb -n backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "DRY RUN"
}

test_dryrun_restore_no_changes() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local source_dir="${HOME}/.claude"
    printf "changed\n" >> "$source_dir/config.toml"
    local before_checksum
    before_checksum=$(get_dir_checksum "$source_dir")

    run_asb --dry-run restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_dir_unchanged "$source_dir" "$before_checksum"
}

test_dryrun_all_agents() {
    create_claude_fixture
    create_codex_fixture
    create_cursor_fixture

    run_asb --dry-run backup
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Claude Code"
    assert_contains "$ASB_LAST_OUTPUT" "OpenAI Codex CLI"
    assert_contains "$ASB_LAST_OUTPUT" "Cursor"
}

test_dryrun_output_format() {
    create_claude_fixture
    run_asb --dry-run backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "[DRY RUN]"
}

run_test "dryrun_backup_no_file_changes" test_dryrun_backup_no_file_changes || exit 1
run_test "dryrun_backup_no_git_commits" test_dryrun_backup_no_git_commits || exit 1
run_test "dryrun_backup_shows_preview" test_dryrun_backup_shows_preview || exit 1
run_test "dryrun_short_flag" test_dryrun_short_flag || exit 1
run_test "dryrun_restore_no_changes" test_dryrun_restore_no_changes || exit 1
run_test "dryrun_all_agents" test_dryrun_all_agents || exit 1
run_test "dryrun_output_format" test_dryrun_output_format || exit 1

exit 0
