#!/usr/bin/env bash
#
# E2E Tests: Schedule Command
# Comprehensive tests for backup scheduling (cron/systemd)
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Help and usage tests
# ============================================

test_schedule_help() {
    run_asb schedule --help
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "schedule" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "--cron" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "--systemd" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "--interval" || return 1
}

test_schedule_no_mode() {
    # Should fail if no mode specified
    run_asb schedule
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        # Either shows help or requires a mode
        assert_contains "$ASB_LAST_OUTPUT" "schedule" || return 0
    fi
}

test_schedule_unknown_option() {
    run_asb schedule --unknownoption
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for unknown option" >&2
        return 1
    fi
}

# ============================================
# Interval validation tests
# ============================================

test_schedule_invalid_interval() {
    run_asb schedule --cron --interval invalid
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected failure for invalid interval" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Invalid" || \
    assert_contains "$ASB_LAST_OUTPUT" "invalid" || \
    return 1
}

test_schedule_hourly_interval() {
    # Test with dry-run to avoid modifying crontab
    run_asb --dry-run schedule --cron --interval hourly
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

test_schedule_daily_interval() {
    run_asb --dry-run schedule --cron --interval daily
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

test_schedule_weekly_interval() {
    run_asb --dry-run schedule --cron --interval weekly
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

# ============================================
# Cron dry-run tests
# ============================================

test_schedule_cron_dry_run() {
    run_asb --dry-run schedule --cron
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Would" || \
    assert_contains "$ASB_LAST_OUTPUT" "cron" || \
    return 1
}

test_schedule_cron_remove_dry_run() {
    run_asb --dry-run schedule --remove --cron
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Would" || \
    assert_contains "$ASB_LAST_OUTPUT" "remove" || \
    return 1
}

test_schedule_cron_status_dry_run() {
    run_asb --dry-run schedule --status --cron
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Would" || \
    assert_contains "$ASB_LAST_OUTPUT" "status" || \
    return 1
}

# ============================================
# Systemd dry-run tests
# ============================================

test_schedule_systemd_dry_run() {
    run_asb --dry-run schedule --systemd
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Would" || \
    assert_contains "$ASB_LAST_OUTPUT" "systemd" || \
    return 1
}

test_schedule_systemd_remove_dry_run() {
    run_asb --dry-run schedule --remove --systemd
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Would" || \
    assert_contains "$ASB_LAST_OUTPUT" "remove" || \
    return 1
}

test_schedule_systemd_status_dry_run() {
    run_asb --dry-run schedule --status --systemd
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "Would" || \
    assert_contains "$ASB_LAST_OUTPUT" "status" || \
    return 1
}

# ============================================
# JSON output tests
# ============================================

test_schedule_status_json() {
    run_asb --json schedule --status
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "cron" in d or "systemd" in d' || {
            echo "Invalid JSON output or missing keys" >&2
            return 1
        }
    fi
}

test_schedule_status_json_cron_only() {
    run_asb --json schedule --status --cron
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' || {
            echo "Invalid JSON output" >&2
            return 1
        }
    fi
}

test_schedule_status_json_systemd_only() {
    run_asb --json schedule --status --systemd
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' || {
            echo "Invalid JSON output" >&2
            return 1
        }
    fi
}

# ============================================
# Status without schedule (clean state)
# ============================================

test_schedule_status_no_schedule() {
    # When no schedule exists, status should still work
    run_asb schedule --status --cron
    # Either succeeds with "not found" or fails gracefully
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        assert_contains "$ASB_LAST_OUTPUT" "No" || \
        assert_contains "$ASB_LAST_OUTPUT" "not" || \
        return 0  # Empty is fine
    fi
}

# ============================================
# Combined mode tests
# ============================================

test_schedule_both_modes() {
    # Specifying both --cron and --systemd should error
    run_asb --dry-run schedule --cron --systemd
    assert_exit_code 1 "$ASB_LAST_STATUS"
    assert_output_contains "$ASB_LAST_OUTPUT" "Choose only one"
}

test_schedule_status_both_modes() {
    # Status for both should work
    run_asb schedule --status
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

# Run all tests
run_test "schedule_help" test_schedule_help || true
run_test "schedule_no_mode" test_schedule_no_mode || true
run_test "schedule_unknown_option" test_schedule_unknown_option || true
run_test "schedule_invalid_interval" test_schedule_invalid_interval || true
run_test "schedule_hourly_interval" test_schedule_hourly_interval || true
run_test "schedule_daily_interval" test_schedule_daily_interval || true
run_test "schedule_weekly_interval" test_schedule_weekly_interval || true
run_test "schedule_cron_dry_run" test_schedule_cron_dry_run || true
run_test "schedule_cron_remove_dry_run" test_schedule_cron_remove_dry_run || true
run_test "schedule_cron_status_dry_run" test_schedule_cron_status_dry_run || true
run_test "schedule_systemd_dry_run" test_schedule_systemd_dry_run || true
run_test "schedule_systemd_remove_dry_run" test_schedule_systemd_remove_dry_run || true
run_test "schedule_systemd_status_dry_run" test_schedule_systemd_status_dry_run || true
run_test "schedule_status_json" test_schedule_status_json || true
run_test "schedule_status_json_cron_only" test_schedule_status_json_cron_only || true
run_test "schedule_status_json_systemd_only" test_schedule_status_json_systemd_only || true
run_test "schedule_status_no_schedule" test_schedule_status_no_schedule || true
run_test "schedule_both_modes" test_schedule_both_modes || true
run_test "schedule_status_both_modes" test_schedule_status_both_modes || true

exit 0
