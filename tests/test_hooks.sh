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

make_hook_script() {
    local path="$1"
    local body="$2"
    cat > "$path" <<EOF
#!/usr/bin/env bash
set -uo pipefail
$body
EOF
    chmod +x "$path"
}

test_backup_hooks_run_in_order() {
    create_claude_fixture
    run_asb config init
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local hooks_root="${XDG_CONFIG_HOME}/asb/hooks"
    local log_file="${TEST_ENV_ROOT}/hook.log"

    make_hook_script "${hooks_root}/pre-backup.d/01-pre.sh" \
        "if [[ \"\$ASB_OPERATION\" != \"backup\" ]]; then exit 1; fi
if [[ \"\$ASB_AGENT\" != \"claude\" ]]; then exit 1; fi
if [[ \"\$ASB_SOURCE\" != \"${HOME}/.claude\" ]]; then exit 1; fi
if [[ \"\$ASB_BACKUP_DIR\" != \"${ASB_BACKUP_ROOT}/.claude\" ]]; then exit 1; fi
echo \"pre-01\" >> \"${log_file}\""

    make_hook_script "${hooks_root}/pre-backup.d/02-pre.sh" \
        "echo \"pre-02\" >> \"${log_file}\""

    make_hook_script "${hooks_root}/post-backup.d/01-post.sh" \
        "if [[ -z \"\${ASB_COMMIT}\" ]]; then exit 1; fi
echo \"post-01\" >> \"${log_file}\""

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_file_exists "$log_file"
    local content
    content=$(cat "$log_file")
    assert_contains "$content" "pre-01"
    assert_contains "$content" "pre-02"
    assert_contains "$content" "post-01"
    if [[ "$content" != $'pre-01\npre-02\npost-01' ]]; then
        echo "Hooks did not run in expected order" >&2
        return 1
    fi
}

test_pre_backup_hook_failure_aborts() {
    create_claude_fixture
    run_asb config init
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local hooks_root="${XDG_CONFIG_HOME}/asb/hooks"
    make_hook_script "${hooks_root}/pre-backup.d/01-fail.sh" "exit 1"

    run_asb backup claude
    if [[ "$ASB_LAST_STATUS" -eq 0 ]]; then
        echo "Expected backup to fail due to pre-hook error" >&2
        return 1
    fi
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/.claude"
}

test_post_backup_hook_failure_continues() {
    create_claude_fixture
    run_asb config init
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local hooks_root="${XDG_CONFIG_HOME}/asb/hooks"
    make_hook_script "${hooks_root}/post-backup.d/01-fail.sh" "exit 1"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
    assert_dir_exists "${ASB_BACKUP_ROOT}/.claude"
}

test_restore_hooks_run() {
    create_claude_fixture
    run_asb config init
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local hooks_root="${XDG_CONFIG_HOME}/asb/hooks"
    local log_file="${TEST_ENV_ROOT}/restore.log"

    make_hook_script "${hooks_root}/pre-restore.d/01-pre.sh" \
        "if [[ \"\$ASB_OPERATION\" != \"restore\" ]]; then exit 1; fi
echo \"pre-restore\" >> \"${log_file}\""

    make_hook_script "${hooks_root}/post-restore.d/01-post.sh" \
        "echo \"post-restore\" >> \"${log_file}\""

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    printf "MODIFIED\n" >> "${HOME}/.claude/settings.json"

    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_file_exists "$log_file"
    local content
    content=$(cat "$log_file")
    assert_contains "$content" "pre-restore"
    assert_contains "$content" "post-restore"
}

run_test "backup_hooks_run_in_order" test_backup_hooks_run_in_order || exit 1
run_test "pre_backup_hook_failure_aborts" test_pre_backup_hook_failure_aborts || exit 1
run_test "post_backup_hook_failure_continues" test_post_backup_hook_failure_continues || exit 1
run_test "restore_hooks_run" test_restore_hooks_run || exit 1

exit 0
