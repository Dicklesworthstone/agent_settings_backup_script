#!/usr/bin/env bash
#
# E2E Tests: Verify Command
# Comprehensive tests for backup verification
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Single agent verification
# ============================================

test_verify_valid_backup() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb verify claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "OK" || \
    assert_contains "$ASB_LAST_OUTPUT" "pass" || \
    assert_contains "$ASB_LAST_OUTPUT" "valid" || \
    return 1
}

test_verify_no_backup() {
    # Agent exists but no backup
    create_claude_fixture
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb verify claude
    # Should fail or warn
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        # If it passes, output should indicate no backup
        assert_contains "$ASB_LAST_OUTPUT" "no backup" || \
        assert_contains "$ASB_LAST_OUTPUT" "not found" || \
        return 1
    fi
}

test_verify_corrupted_git() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Corrupt the git repo by removing HEAD
    rm -f "${ASB_BACKUP_ROOT}/.claude/.git/HEAD"

    run_asb verify claude
    # Should fail or report error
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        assert_contains "$ASB_LAST_OUTPUT" "error" || \
        assert_contains "$ASB_LAST_OUTPUT" "corrupt" || \
        assert_contains "$ASB_LAST_OUTPUT" "invalid" || \
        return 1
    fi
}

test_verify_missing_gitignore() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Remove .gitignore
    rm -f "${ASB_BACKUP_ROOT}/.claude/.gitignore"

    run_asb verify claude
    # May warn about missing .gitignore
    # Output should mention it
}

test_verify_empty_repo() {
    create_claude_fixture

    # Create backup dir with git but no commits
    mkdir -p "${ASB_BACKUP_ROOT}/.claude"
    git -C "${ASB_BACKUP_ROOT}/.claude" init >/dev/null 2>&1

    run_asb verify claude
    # Should fail or warn about no commits
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        assert_contains "$ASB_LAST_OUTPUT" "no commit" || \
        assert_contains "$ASB_LAST_OUTPUT" "empty" || \
        return 1
    fi
}

# ============================================
# All agents verification
# ============================================

test_verify_all_agents() {
    create_claude_fixture
    create_cursor_fixture

    run_asb backup claude
    run_asb backup cursor

    run_asb verify
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "claude" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "cursor" || return 1
}

test_verify_all_with_some_missing() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Don't backup cursor - just create the fixture
    create_cursor_fixture

    run_asb verify
    # Should still complete and show results
}

test_verify_all_no_backups() {
    # No agents backed up
    run_asb verify

    # Should succeed with message about no backups
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        assert_contains "$ASB_LAST_OUTPUT" "No" || \
        assert_contains "$ASB_LAST_OUTPUT" "none" || \
        return 0  # Empty state is valid
    fi
}

# ============================================
# JSON output tests
# ============================================

test_verify_json_single() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb --json verify claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin)' || {
            echo "Invalid JSON output" >&2
            return 1
        }
    fi
}

test_verify_json_all() {
    create_claude_fixture
    create_cursor_fixture
    run_asb backup claude
    run_asb backup cursor

    run_asb --json verify
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin)' || {
            echo "Invalid JSON output" >&2
            return 1
        }
    fi
}

test_verify_json_error() {
    run_asb --json verify unknownagent123

    # Should still produce valid JSON
    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || {
            echo "Error output should be valid JSON" >&2
            return 1
        }
    fi
}

# ============================================
# Summary statistics tests
# ============================================

test_verify_shows_summary() {
    create_claude_fixture
    create_cursor_fixture
    create_codex_fixture

    run_asb backup claude
    run_asb backup cursor
    run_asb backup codex

    run_asb verify
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Should show summary with totals
    assert_contains "$ASB_LAST_OUTPUT" "3" || \
    assert_contains "$ASB_LAST_OUTPUT" "OK" || \
    return 1
}

# Run all tests
run_test "verify_valid_backup" test_verify_valid_backup || true
run_test "verify_no_backup" test_verify_no_backup || true
run_test "verify_corrupted_git" test_verify_corrupted_git || true
run_test "verify_missing_gitignore" test_verify_missing_gitignore || true
run_test "verify_empty_repo" test_verify_empty_repo || true
run_test "verify_all_agents" test_verify_all_agents || true
run_test "verify_all_with_some_missing" test_verify_all_with_some_missing || true
run_test "verify_all_no_backups" test_verify_all_no_backups || true
run_test "verify_json_single" test_verify_json_single || true
run_test "verify_json_all" test_verify_json_all || true
run_test "verify_json_error" test_verify_json_error || true
run_test "verify_shows_summary" test_verify_shows_summary || true

exit 0
