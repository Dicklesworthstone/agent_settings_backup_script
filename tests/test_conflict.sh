#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

declare -F create_claude_fixture >/dev/null 2>&1 || { echo "create_claude_fixture not loaded" >&2; exit 1; }

assert_output_contains_ctx() {
    local output="$1"
    local needle="$2"
    if ! assert_contains "$output" "$needle"; then
        echo "---- Command output ----" >&2
        echo "$output" >&2
        return 1
    fi
}

assert_output_matches_ctx() {
    local output="$1"
    local pattern="$2"
    if ! assert_output_matches "$output" "$pattern"; then
        echo "---- Command output ----" >&2
        echo "$output" >&2
        return 1
    fi
}

setup_restore_conflict() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local source_dir="${HOME}/.claude"
    printf "changed\n" >> "$source_dir/settings.json"
    # extensions/ is backed up; projects/ is excluded and never restored.
    rm -f "$source_dir/extensions/list.txt"
    printf "current-only\n" > "$source_dir/current_only.txt"
}

test_restore_shows_preview() {
    setup_restore_conflict
    skip_if_missing script "script command not available for TTY tests" || return 2

    run_asb_tty $'n\n' restore claude
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected restore to cancel with 'n' input" >&2
        return 1
    fi
    assert_output_contains_ctx "$ASB_LAST_OUTPUT" "will be DELETED" || return 1
    assert_output_contains_ctx "$ASB_LAST_OUTPUT" "will be ADDED" || return 1
    assert_output_contains_ctx "$ASB_LAST_OUTPUT" "will be REPLACED" || return 1
}

test_restore_requires_confirmation() {
    setup_restore_conflict
    skip_if_missing script "script command not available for TTY tests" || return 2

    local source_dir="${HOME}/.claude"
    local before_checksum
    before_checksum=$(get_dir_checksum "$source_dir")
    local before_copy
    before_copy=$(mktemp -d)
    cp -R "$source_dir/." "$before_copy/" 2>/dev/null || true

    run_asb_tty $'n\n' restore claude
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected restore to cancel with 'n' input" >&2
        return 1
    fi

    assert_dir_unchanged "$source_dir" "$before_checksum"
    if ! diff -ru "$before_copy" "$source_dir" >/dev/null 2>&1; then
        diff -ru "$before_copy" "$source_dir" >&2 || true
        return 1
    fi
}

test_restore_confirm_yes() {
    setup_restore_conflict
    skip_if_missing script "script command not available for TTY tests" || return 2

    run_asb_tty $'y\n' restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local source_dir="${HOME}/.claude"
    local backup_dir="${ASB_BACKUP_ROOT}/.claude"
    # projects/ is excluded from backups, so restore leaves the live one alone.
    if ! diff -rq "$backup_dir" "$source_dir" \
        --exclude='.git' \
        --exclude='.gitignore' \
        --exclude='projects' >/dev/null 2>&1; then
        diff -ru "$backup_dir" "$source_dir" >&2 || true
        return 1
    fi
}

test_restore_enter_cancels() {
    setup_restore_conflict
    skip_if_missing script "script command not available for TTY tests" || return 2

    local source_dir="${HOME}/.claude"
    local before_checksum
    before_checksum=$(get_dir_checksum "$source_dir")
    local before_copy
    before_copy=$(mktemp -d)
    cp -R "$source_dir/." "$before_copy/" 2>/dev/null || true

    run_asb_tty $'\n' restore claude
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected restore to cancel on empty input" >&2
        return 1
    fi

    assert_dir_unchanged "$source_dir" "$before_checksum"
    if ! diff -ru "$before_copy" "$source_dir" >/dev/null 2>&1; then
        diff -ru "$before_copy" "$source_dir" >&2 || true
        return 1
    fi
}

test_force_skips_confirmation() {
    setup_restore_conflict
    run_asb --force restore claude </dev/null
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local source_dir="${HOME}/.claude"
    local backup_dir="${ASB_BACKUP_ROOT}/.claude"
    # projects/ is excluded from backups, so restore leaves the live one alone.
    if ! diff -rq "$backup_dir" "$source_dir" \
        --exclude='.git' \
        --exclude='.gitignore' \
        --exclude='projects' >/dev/null 2>&1; then
        diff -ru "$backup_dir" "$source_dir" >&2 || true
        return 1
    fi
}

test_preview_formatting() {
    setup_restore_conflict
    skip_if_missing script "script command not available for TTY tests" || return 2

    run_asb_tty $'n\n' restore claude
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected restore to cancel with 'n' input" >&2
        return 1
    fi

    # Colors (red/green/yellow) should be present in TTY output when available
    # The script command may output escape codes in different formats depending on platform,
    # so we check for the core ANSI sequences in multiple ways
    if echo "$ASB_LAST_OUTPUT" | grep -qE $'\x1b\\[|\\[0;3[123]m'; then
        # Check for red (31), green (32), yellow (33) color codes
        # Match both ESC[ and raw [0;3Xm patterns since script output varies by platform
        if ! echo "$ASB_LAST_OUTPUT" | grep -qE '(\x1b)?\[0;31m'; then
            echo "Expected red color code in output" >&2
            return 1
        fi
        if ! echo "$ASB_LAST_OUTPUT" | grep -qE '(\x1b)?\[0;32m'; then
            echo "Expected green color code in output" >&2
            return 1
        fi
        if ! echo "$ASB_LAST_OUTPUT" | grep -qE '(\x1b)?\[0;33m'; then
            echo "Expected yellow color code in output" >&2
            return 1
        fi
    fi

    # Summary with counts
    assert_output_contains_ctx "$ASB_LAST_OUTPUT" "Summary:"
    assert_output_matches_ctx "$ASB_LAST_OUTPUT" "Summary: [0-9]+ added, [0-9]+ replaced, [0-9]+ deleted"

    # Ensure entries are sorted by path
    local paths=()
    while IFS= read -r line; do
        case "$line" in
            *"(will be DELETED)"*|*"(will be ADDED)"*|*"(will be REPLACED)"*)
                local cleaned
                cleaned=$(echo "$line" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
                cleaned=${cleaned%%(will be *}
                cleaned=$(echo "$cleaned" | tr -d '\r' | xargs)
                [[ -n "$cleaned" ]] && paths+=("$cleaned")
                ;;
        esac
    done <<< "$ASB_LAST_OUTPUT"

    local sorted
    sorted=$(printf '%s\n' "${paths[@]}" | sort)
    if [[ "$(printf '%s\n' "${paths[@]}")" != "$sorted" ]]; then
        echo "Preview output is not sorted by path" >&2
        echo "---- Parsed order ----" >&2
        printf '%s\n' "${paths[@]}" >&2
        echo "---- Sorted order ----" >&2
        printf '%s\n' $sorted >&2
        return 1
    fi
}

test_no_changes_scenario() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    run_asb restore claude </dev/null
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_output_contains_ctx "$ASB_LAST_OUTPUT" "Already up to date"
}

test_non_tty_without_force_error() {
    setup_restore_conflict
    run_asb restore claude </dev/null
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected restore to fail without TTY and without --force" >&2
        return 1
    fi
    assert_output_contains_ctx "$ASB_LAST_OUTPUT" "Use --force"
}

run_test "restore_shows_preview" test_restore_shows_preview || exit 1
run_test "restore_requires_confirmation" test_restore_requires_confirmation || exit 1
run_test "restore_confirm_yes" test_restore_confirm_yes || exit 1
run_test "restore_enter_cancels" test_restore_enter_cancels || exit 1
run_test "force_skips_confirmation" test_force_skips_confirmation || exit 1
run_test "non_tty_without_force_error" test_non_tty_without_force_error || exit 1
run_test "preview_formatting" test_preview_formatting || exit 1
run_test "no_changes_scenario" test_no_changes_scenario || exit 1

exit 0
