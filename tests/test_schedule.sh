#!/usr/bin/env bash
#
# Schedule command tests (dry-run only)
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"
if [[ "$SCRIPT_DIR" == */lib ]]; then
    LIB_DIR="$SCRIPT_DIR"
fi

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"

test_schedule_help() {
    run_asb schedule --help
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "asb schedule"
}

test_schedule_dryrun_cron() {
    run_asb --dry-run schedule --cron --interval daily
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "DRY RUN"
    assert_contains "$ASB_LAST_OUTPUT" "cron"
}

test_schedule_dryrun_systemd() {
    run_asb --dry-run schedule --systemd --interval weekly
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_contains "$ASB_LAST_OUTPUT" "DRY RUN"
    assert_contains "$ASB_LAST_OUTPUT" "systemd"
}

test_schedule_invalid_interval() {
    run_asb schedule --cron --interval monthly
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected non-zero exit for invalid interval" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Invalid interval"
}

run_test "schedule_help" test_schedule_help || exit 1
run_test "schedule_dryrun_cron" test_schedule_dryrun_cron || exit 1
run_test "schedule_dryrun_systemd" test_schedule_dryrun_systemd || exit 1
run_test "schedule_invalid_interval" test_schedule_invalid_interval || exit 1

exit 0
