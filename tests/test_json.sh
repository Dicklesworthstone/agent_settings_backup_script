#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"
if [[ "$SCRIPT_DIR" == */lib ]]; then
    LIB_DIR="$SCRIPT_DIR"
fi

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

declare -F create_claude_fixture >/dev/null 2>&1 || { echo "create_claude_fixture not loaded" >&2; exit 1; }

assert_json_valid() {
    local input="$1"
    skip_if_missing python3 "python3 required for JSON tests" || return $?
    echo "$input" | python3 -c 'import json, sys; json.load(sys.stdin)'
}

# Run asb capturing only stdout for JSON validation (stderr goes to /dev/null)
run_asb_json() {
    ASB_LAST_OUTPUT="$($ASB_BIN "$@" 2>/dev/null)"
    ASB_LAST_STATUS=$?
    return $ASB_LAST_STATUS
}

test_json_list_output() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb --json list
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"agent\":\"claude\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_history_output() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb --json history claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"commits\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_verify_output() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb --json verify claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"agent\":\"claude\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_schedule_status_output() {
    run_asb --json schedule --status
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"cron\""
    assert_contains "$ASB_LAST_OUTPUT" "\"systemd\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_backup_output() {
    create_claude_fixture
    run_asb_json --json backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"results\""
    assert_contains "$ASB_LAST_OUTPUT" "\"summary\""
    assert_contains "$ASB_LAST_OUTPUT" "\"backed_up\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_backup_single_agent() {
    create_claude_fixture
    run_asb_json --json backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"agent\":\"claude\""
    assert_contains "$ASB_LAST_OUTPUT" "\"status\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_restore_dry_run() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb_json --json --dry-run restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"agent\":\"claude\""
    # Either dry_run status or no_changes (if already up to date)
    if [[ "$ASB_LAST_OUTPUT" == *"dry_run"* ]] || [[ "$ASB_LAST_OUTPUT" == *"no_changes"* ]]; then
        assert_json_valid "$ASB_LAST_OUTPUT"
    else
        fail "Expected dry_run or no_changes status"
    fi
}

test_json_restore_force() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Modify source to create a change
    echo "modified" >> "${HOME}/.claude/settings.json"

    run_asb_json --json --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"agent\":\"claude\""
    assert_contains "$ASB_LAST_OUTPUT" "\"status\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_export_output() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local tmp_dir
    tmp_dir=$(get_test_tmp_dir)
    run_asb_json --json export claude "${tmp_dir}/claude-backup.tar.gz"
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"status\":\"success\""
    assert_contains "$ASB_LAST_OUTPUT" "\"size\""
    assert_contains "$ASB_LAST_OUTPUT" "\"size_bytes\""
    assert_contains "$ASB_LAST_OUTPUT" "\"commits\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_export_dry_run() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb_json --json --dry-run export claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"status\":\"dry_run\""
    assert_contains "$ASB_LAST_OUTPUT" "\"size_estimate\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_import_output() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local tmp_dir
    tmp_dir=$(get_test_tmp_dir)
    run_asb export claude "${tmp_dir}/claude-backup.tar.gz"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Remove existing backup to test import (safe - only removing test directory)
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb_json --json import "${tmp_dir}/claude-backup.tar.gz"
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"status\":\"success\""
    assert_contains "$ASB_LAST_OUTPUT" "\"destination\""
    assert_contains "$ASB_LAST_OUTPUT" "\"agent_folder\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_import_dry_run() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local tmp_dir
    tmp_dir=$(get_test_tmp_dir)
    run_asb export claude "${tmp_dir}/claude-backup.tar.gz"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb_json --json --dry-run import "${tmp_dir}/claude-backup.tar.gz"
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"status\":\"dry_run\""
    assert_contains "$ASB_LAST_OUTPUT" "\"destination\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_diff_output() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb_json --json diff claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"agent\":\"claude\""
    assert_contains "$ASB_LAST_OUTPUT" "\"has_changes\""
    assert_contains "$ASB_LAST_OUTPUT" "\"added\""
    assert_contains "$ASB_LAST_OUTPUT" "\"removed\""
    assert_contains "$ASB_LAST_OUTPUT" "\"modified\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

test_json_diff_with_changes() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Create a change
    echo "new file content" > "${HOME}/.claude/new_file.txt"

    run_asb_json --json diff claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "\"has_changes\":true"
    assert_contains "$ASB_LAST_OUTPUT" "\"added\""
    assert_json_valid "$ASB_LAST_OUTPUT"
}

run_test "json_list_output" test_json_list_output || exit 1
run_test "json_history_output" test_json_history_output || exit 1
run_test "json_verify_output" test_json_verify_output || exit 1
run_test "json_schedule_status_output" test_json_schedule_status_output || exit 1
run_test "json_backup_output" test_json_backup_output || exit 1
run_test "json_backup_single_agent" test_json_backup_single_agent || exit 1
run_test "json_restore_dry_run" test_json_restore_dry_run || exit 1
run_test "json_restore_force" test_json_restore_force || exit 1
run_test "json_export_output" test_json_export_output || exit 1
run_test "json_export_dry_run" test_json_export_dry_run || exit 1
run_test "json_import_output" test_json_import_output || exit 1
run_test "json_import_dry_run" test_json_import_dry_run || exit 1
run_test "json_diff_output" test_json_diff_output || exit 1
run_test "json_diff_with_changes" test_json_diff_with_changes || exit 1

exit 0
