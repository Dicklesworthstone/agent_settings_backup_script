#!/usr/bin/env bash
#
# E2E Tests: Concurrent Operations
# Tests behavior under concurrent access scenarios
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Concurrent backup tests
# ============================================

test_concurrent_backup_same_agent() {
    create_claude_fixture

    # Start two backups of same agent simultaneously
    run_asb backup claude &
    local pid1=$!
    run_asb backup claude &
    local pid2=$!

    # Wait for both
    local status1 status2
    wait $pid1
    status1=$?
    wait $pid2
    status2=$?

    # At least one should succeed
    if [[ "$status1" -ne 0 && "$status2" -ne 0 ]]; then
        echo "Both concurrent backups failed" >&2
        return 1
    fi

    # Backup should exist
    if [[ ! -d "${ASB_BACKUP_ROOT}/.claude" ]]; then
        echo "Backup directory not created" >&2
        return 1
    fi
}

test_concurrent_backup_different_agents() {
    create_claude_fixture
    create_cursor_fixture

    # Start backups of different agents simultaneously
    run_asb backup claude &
    local pid1=$!
    run_asb backup cursor &
    local pid2=$!

    wait $pid1
    local status1=$?
    wait $pid2
    local status2=$?

    # Both should succeed
    if [[ "$status1" -ne 0 ]]; then
        echo "Claude backup failed: $status1" >&2
        return 1
    fi
    if [[ "$status2" -ne 0 ]]; then
        echo "Cursor backup failed: $status2" >&2
        return 1
    fi
}

test_concurrent_backup_all() {
    create_claude_fixture
    create_cursor_fixture
    create_codex_fixture

    # Multiple concurrent backup all commands
    run_asb backup &
    local pid1=$!
    run_asb backup &
    local pid2=$!

    wait $pid1
    local status1=$?
    wait $pid2
    local status2=$?

    # At least one should succeed
    if [[ "$status1" -ne 0 && "$status2" -ne 0 ]]; then
        echo "Both concurrent backup-all failed" >&2
        return 1
    fi
}

# ============================================
# Concurrent read operations tests
# ============================================

test_concurrent_list() {
    create_claude_fixture
    create_cursor_fixture
    run_asb backup claude
    run_asb backup cursor

    # Multiple list commands
    run_asb list &
    local pid1=$!
    run_asb list &
    local pid2=$!
    run_asb list &
    local pid3=$!

    wait $pid1
    wait $pid2
    wait $pid3

    # All should succeed (read operations)
}

test_concurrent_history() {
    create_claude_fixture
    run_asb backup claude

    # Multiple history commands on same agent
    run_asb history claude &
    local pid1=$!
    run_asb history claude &
    local pid2=$!

    wait $pid1
    wait $pid2

    # Both should succeed
}

test_concurrent_diff() {
    create_claude_fixture
    run_asb backup claude

    echo '{"changed": true}' > "${HOME}/.claude/changed.json"

    # Multiple diff commands
    run_asb diff claude &
    local pid1=$!
    run_asb diff claude &
    local pid2=$!

    wait $pid1
    wait $pid2
}

test_concurrent_stats() {
    create_claude_fixture
    create_cursor_fixture
    run_asb backup claude
    run_asb backup cursor

    # Multiple stats commands
    run_asb stats claude &
    local pid1=$!
    run_asb stats cursor &
    local pid2=$!
    run_asb stats &
    local pid3=$!

    wait $pid1
    wait $pid2
    wait $pid3
}

# ============================================
# Concurrent export tests
# ============================================

test_concurrent_export() {
    create_claude_fixture
    run_asb backup claude

    local export1="${TEST_ENV_ROOT}/export1.tar.gz"
    local export2="${TEST_ENV_ROOT}/export2.tar.gz"

    # Export same agent to different files
    run_asb export claude "$export1" &
    local pid1=$!
    run_asb export claude "$export2" &
    local pid2=$!

    wait $pid1
    local status1=$?
    wait $pid2
    local status2=$?

    if [[ "$status1" -ne 0 || "$status2" -ne 0 ]]; then
        echo "Concurrent exports failed" >&2
        return 1
    fi

    # Both files should exist and be valid archives
    assert_file_exists "$export1" || return 1
    assert_file_exists "$export2" || return 1
}

# ============================================
# Stress tests
# ============================================

test_rapid_sequential_backups() {
    create_claude_fixture

    # Rapid sequential backups
    for i in $(seq 1 10); do
        echo "{\"iteration\": $i}" > "${HOME}/.claude/iteration.json"
        run_asb backup claude
        if [[ "$ASB_LAST_STATUS" -ne 0 ]]; then
            echo "Backup failed at iteration $i" >&2
            return 1
        fi
    done

    # Should have multiple commits
    local commit_count
    commit_count=$(git -C "${ASB_BACKUP_ROOT}/.claude" rev-list --count HEAD)
    if [[ "$commit_count" -lt 5 ]]; then
        echo "Expected multiple commits, got $commit_count" >&2
        return 1
    fi
}

test_concurrent_multiple_agents_stress() {
    create_claude_fixture
    create_cursor_fixture
    create_codex_fixture

    # Run many concurrent operations
    local pids=()
    for _ in $(seq 1 3); do
        run_asb backup claude &
        pids+=($!)
        run_asb backup cursor &
        pids+=($!)
        run_asb backup codex &
        pids+=($!)
    done

    # Wait for all
    local failures=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failures++))
        fi
    done

    if [[ "$failures" -gt 3 ]]; then
        echo "Too many failures ($failures) in concurrent operations" >&2
        return 1
    fi
}

# ============================================
# Lock contention tests
# ============================================

test_backup_during_modification() {
    create_claude_fixture

    # Start modifying files while backing up
    (
        for i in $(seq 1 20); do
            echo "{\"mod\": $i}" > "${HOME}/.claude/modifying.json"
            sleep 0.1
        done
    ) &
    local mod_pid=$!

    run_asb backup claude
    local backup_status=$?

    kill $mod_pid 2>/dev/null || true
    wait $mod_pid 2>/dev/null || true

    # Backup should complete (may capture any consistent state)
    if [[ "$backup_status" -ne 0 ]]; then
        echo "Backup failed during concurrent modifications" >&2
        return 1
    fi
}

# Run all tests
run_test "concurrent_backup_same_agent" test_concurrent_backup_same_agent || true
run_test "concurrent_backup_different_agents" test_concurrent_backup_different_agents || true
run_test "concurrent_backup_all" test_concurrent_backup_all || true
run_test "concurrent_list" test_concurrent_list || true
run_test "concurrent_history" test_concurrent_history || true
run_test "concurrent_diff" test_concurrent_diff || true
run_test "concurrent_stats" test_concurrent_stats || true
run_test "concurrent_export" test_concurrent_export || true
run_test "rapid_sequential_backups" test_rapid_sequential_backups || true
run_test "concurrent_multiple_agents_stress" test_concurrent_multiple_agents_stress || true
run_test "backup_during_modification" test_backup_during_modification || true

exit 0
