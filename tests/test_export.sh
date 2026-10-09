#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

declare -F create_claude_fixture >/dev/null 2>&1 || { echo "create_claude_fixture not loaded" >&2; exit 1; }

run_asb_tty() {
    local input="$1"
    shift

    skip_if_missing script "script command not available for TTY tests" || return 2

    if script -q -e -c true /dev/null >/dev/null 2>&1; then
        ASB_LAST_OUTPUT=$(printf '%b' "$input" | script -q -e -c "$ASB_BIN $*" /dev/null 2>&1)
        ASB_LAST_STATUS=$?
    else
        ASB_LAST_OUTPUT=$(printf '%b' "$input" | script -q -c "$ASB_BIN $*" /dev/null 2>&1)
        ASB_LAST_STATUS=$?
        if [[ $ASB_LAST_STATUS -eq 0 ]] && [[ "$ASB_LAST_OUTPUT" == *"Import cancelled"* ]]; then
            ASB_LAST_STATUS=1
        fi
    fi
    return $ASB_LAST_STATUS
}

make_backup_with_history() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    printf "change\n" >> "$HOME/.claude/settings.json"
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

assert_archive_contains_git() {
    local archive="$1"
    tar -tzf "$archive" 2>/dev/null | grep -q "\.git/objects"
}

test_export_creates_archive() {
    make_backup_with_history

    run_asb export claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local archive
    archive=$(echo "$ASB_LAST_OUTPUT" | awk '/File:/ {print $2}' | tr -d '\r')
    assert_file_exists "$archive"

    if [[ "$archive" != *"claude-backup-"*".tar.gz" ]]; then
        echo "Expected timestamped archive filename" >&2
        return 1
    fi
}

test_export_custom_filename() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/custom-backup.tar.gz"
    run_asb export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_file_exists "$archive"
    if ls "${TEST_ENV_ROOT}"/claude-backup-*.tar.gz >/dev/null 2>&1; then
        echo "Did not expect timestamped archive when custom filename used" >&2
        return 1
    fi
}

test_export_rejects_partial_archive() {
    create_claude_fixture || return 1
    run_asb backup claude || return 1
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local good_archive="${TEST_ENV_ROOT}/complete-export.tar.gz"
    run_asb export claude "$good_archive" || return 1
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_archive_contains_git "$good_archive" || return 1

    local partial_archive="${TEST_ENV_ROOT}/partial-export.tar.gz"
    # The real kernel limit makes real tar leave a file but fail to write it.
    # Keep the completed positive archive and the failed output for inspection.
    if ASB_LAST_OUTPUT=$(
        ulimit -f 0 || exit 125
        trap '' XFSZ || exit 125
        "$ASB_BIN" export claude "$partial_archive" 2>&1
    ); then
        ASB_LAST_STATUS=0
    else
        ASB_LAST_STATUS=$?
    fi

    if [[ $ASB_LAST_STATUS -eq 125 ]]; then
        echo "Kernel file-limit case unavailable; no export failure proof" >&2
        return 1
    fi
    assert_file_exists "$partial_archive" || return 1
    if [[ -s "$partial_archive" || $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected a retained empty archive and a failed export" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Failed to create archive" || return 1
    assert_archive_contains_git "$good_archive" || return 1
}

test_export_includes_git() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/claude-export.tar.gz"
    run_asb export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_archive_contains_git "$archive"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar -xzf "$archive" -C "$tmp_dir"
    if ! git -C "$tmp_dir/.claude" log -1 --oneline >/dev/null 2>&1; then
        echo "Expected git history in exported archive" >&2
        return 1
    fi
}

test_export_to_stdout() {
    make_backup_with_history

    if ! command_exists tar; then
        skip_test "tar not available"
        return 2
    fi

    if ! "$ASB_BIN" export claude - 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
        echo "Expected valid tar stream from export stdout" >&2
        return 1
    fi

    local output
    output=$("$ASB_BIN" export claude - 2>/dev/null | tar -tzf - 2>/dev/null | head -20 || true)
    echo "$output" | grep -q "\.claude/" || {
        echo "Expected .claude path in archive" >&2
        return 1
    }
}

test_import_restores_backup() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/claude-export.tar.gz"
    run_asb export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    rm -rf "$ASB_BACKUP_ROOT/.claude"

    run_asb import "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_dir_exists "$ASB_BACKUP_ROOT/.claude/.git"
    git -C "$ASB_BACKUP_ROOT/.claude" log -1 --oneline >/dev/null 2>&1
}

test_import_detects_existing() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/claude-export.tar.gz"
    run_asb export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    printf "sentinel\n" > "$ASB_BACKUP_ROOT/.claude/extra.txt"

    run_asb_tty $'n\n' import "$archive"
    assert_contains "$ASB_LAST_OUTPUT" "Import cancelled"
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/extra.txt"
}

test_import_force_overwrites() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/claude-export.tar.gz"
    run_asb export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    printf "extra\n" > "$ASB_BACKUP_ROOT/.claude/extra.txt"

    run_asb --force import "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ -f "$ASB_BACKUP_ROOT/.claude/extra.txt" ]]; then
        echo "Expected import to overwrite existing backup" >&2
        return 1
    fi
}

test_export_dryrun() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/dryrun.tar.gz"
    run_asb --dry-run export claude "$archive"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_file_not_exists "$archive"
    assert_contains "$ASB_LAST_OUTPUT" "[DRY RUN]"
}

test_import_invalid_archive() {
    make_backup_with_history

    local archive="${TEST_ENV_ROOT}/invalid.tar.gz"
    printf "not a tar" > "$archive"

    run_asb import "$archive"
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected import to fail for invalid archive" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Failed to read archive"
}

test_export_nonexistent_agent() {
    run_asb export nonexistent
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected export to fail for unknown agent" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" "Unknown agent"
    assert_contains "$ASB_LAST_OUTPUT" "Run 'asb list'"
}

run_test "export_creates_archive" test_export_creates_archive || exit 1
run_test "export_custom_filename" test_export_custom_filename || exit 1
run_test "export_rejects_partial_archive" test_export_rejects_partial_archive || exit 1
run_test "export_includes_git" test_export_includes_git || exit 1
run_test "export_to_stdout" test_export_to_stdout || exit 1
run_test "import_restores_backup" test_import_restores_backup || exit 1
run_test "import_detects_existing" test_import_detects_existing || exit 1
run_test "import_force_overwrites" test_import_force_overwrites || exit 1
run_test "export_dryrun" test_export_dryrun || exit 1
run_test "import_invalid_archive" test_import_invalid_archive || exit 1
run_test "export_nonexistent_agent" test_export_nonexistent_agent || exit 1

exit 0
