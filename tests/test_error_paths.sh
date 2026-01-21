#!/usr/bin/env bash
#
# E2E Tests: Error Path Coverage
# Tests all error conditions with proper error messages
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Backup error tests
# ============================================

test_backup_unknown_agent() {
    run_asb backup unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Unknown agent" || \
    assert_contains "$ASB_LAST_OUTPUT" "unknownagent123" || \
    return 1
}

test_backup_invalid_agent_name() {
    run_asb backup "agent with spaces"
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for agent with spaces" >&2
        return 1
    fi
}

# ============================================
# Restore error tests
# ============================================

test_restore_unknown_agent() {
    run_asb restore unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "nknown" || return 1
}

test_restore_no_backup_exists() {
    # Create agent folder but no backup
    create_claude_fixture
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb --force restore claude
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure when no backup exists" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "backup" || \
    assert_contains "$ASB_LAST_OUTPUT" "found" || \
    return 1
}

test_restore_nonexistent_commit() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb --force restore claude "abc1234567890"
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for non-existent commit" >&2
        return 1
    fi
}

test_restore_nonexistent_tag() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb --force restore claude "nonexistent-tag"
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for non-existent tag" >&2
        return 1
    fi
}

# ============================================
# Export error tests
# ============================================

test_export_unknown_agent() {
    run_asb export unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
}

test_export_no_backup_exists() {
    create_claude_fixture
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb export claude
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure when no backup to export" >&2
        return 1
    fi
}

# ============================================
# Import error tests
# ============================================

test_import_nonexistent_file() {
    run_asb import "/nonexistent/path/backup.tar.gz"
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for non-existent file" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "not found" || \
    assert_contains "$ASB_LAST_OUTPUT" "exist" || \
    assert_contains "$ASB_LAST_OUTPUT" "No such" || \
    return 1
}

test_import_invalid_archive() {
    # Create invalid archive
    local bad_archive="${TEST_ENV_ROOT}/bad.tar.gz"
    echo "not a valid archive" > "$bad_archive"

    run_asb import "$bad_archive"
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for invalid archive" >&2
        return 1
    fi
}

# ============================================
# Tag error tests
# ============================================

test_tag_unknown_agent() {
    run_asb tag unknownagent123 v1.0
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
}

test_tag_no_backup_exists() {
    create_claude_fixture
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb tag claude v1.0
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure when no backup exists" >&2
        return 1
    fi
}

test_tag_duplicate_name() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb tag claude v1.0
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Try to create same tag again
    run_asb tag claude v1.0
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for duplicate tag" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "exist" || \
    assert_contains "$ASB_LAST_OUTPUT" "already" || \
    return 1
}

test_tag_invalid_name() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Invalid tag names
    run_asb tag claude "-invalid"
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for tag starting with dash" >&2
        return 1
    fi
}

# ============================================
# History error tests
# ============================================

test_history_unknown_agent() {
    run_asb history unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
}

test_history_no_backup() {
    create_claude_fixture
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb history claude
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure when no backup exists" >&2
        return 1
    fi
}

# ============================================
# Stats error tests
# ============================================

test_stats_unknown_agent() {
    run_asb stats unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
}

# ============================================
# Diff error tests
# ============================================

test_diff_unknown_agent() {
    run_asb diff unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi
}

test_diff_no_backup() {
    create_claude_fixture
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb diff claude
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure when no backup exists" >&2
        return 1
    fi
}

# ============================================
# JSON error format tests
# ============================================

test_json_error_format() {
    run_asb --json backup unknownagent123
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown agent" >&2
        return 1
    fi

    # Should be valid JSON even for errors
    if command -v python3 >/dev/null 2>&1; then
        if ! echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
            echo "Error output should be valid JSON" >&2
            return 1
        fi
    fi
}

# ============================================
# Command validation tests
# ============================================

test_unknown_command() {
    run_asb fakecommand
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown command" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Unknown command" || \
    assert_contains "$ASB_LAST_OUTPUT" "fakecommand" || \
    return 1
}

test_missing_required_args() {
    # restore requires agent name
    run_asb restore
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure when missing required args" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Usage" || \
    assert_contains "$ASB_LAST_OUTPUT" "agent" || \
    return 1
}

# Run all tests
run_test "backup_unknown_agent" test_backup_unknown_agent || true
run_test "backup_invalid_agent_name" test_backup_invalid_agent_name || true
run_test "restore_unknown_agent" test_restore_unknown_agent || true
run_test "restore_no_backup_exists" test_restore_no_backup_exists || true
run_test "restore_nonexistent_commit" test_restore_nonexistent_commit || true
run_test "restore_nonexistent_tag" test_restore_nonexistent_tag || true
run_test "export_unknown_agent" test_export_unknown_agent || true
run_test "export_no_backup_exists" test_export_no_backup_exists || true
run_test "import_nonexistent_file" test_import_nonexistent_file || true
run_test "import_invalid_archive" test_import_invalid_archive || true
run_test "tag_unknown_agent" test_tag_unknown_agent || true
run_test "tag_no_backup_exists" test_tag_no_backup_exists || true
run_test "tag_duplicate_name" test_tag_duplicate_name || true
run_test "tag_invalid_name" test_tag_invalid_name || true
run_test "history_unknown_agent" test_history_unknown_agent || true
run_test "history_no_backup" test_history_no_backup || true
run_test "stats_unknown_agent" test_stats_unknown_agent || true
run_test "diff_unknown_agent" test_diff_unknown_agent || true
run_test "diff_no_backup" test_diff_no_backup || true
run_test "json_error_format" test_json_error_format || true
run_test "unknown_command" test_unknown_command || true
run_test "missing_required_args" test_missing_required_args || true

exit 0
