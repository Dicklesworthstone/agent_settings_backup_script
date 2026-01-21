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

run_test "json_list_output" test_json_list_output || exit 1
run_test "json_history_output" test_json_history_output || exit 1
run_test "json_verify_output" test_json_verify_output || exit 1
run_test "json_schedule_status_output" test_json_schedule_status_output || exit 1

exit 0
