#!/usr/bin/env bash
#
# E2E Tests: session-data exclusions and `asb prune`
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# Codex keeps transcripts and logs in databases next to its settings.
add_codex_session_databases() {
    local codex="${HOME}/.codex"
    printf 'threads\n' > "${codex}/thread_history_1.sqlite"
    printf 'logs\n' > "${codex}/logs_2.sqlite"
    printf 'wal\n' > "${codex}/state_5.sqlite-wal"
    printf 'state\n' > "${codex}/state_5.sqlite"
    mkdir -p "${codex}/db-backups/sqlite-1"
    printf 'old\n' > "${codex}/db-backups/sqlite-1/logs_2.sqlite"
}

# Antigravity keeps conversations under ~/.gemini/antigravity-cli.
add_antigravity_tree() {
    local agy="${HOME}/.gemini/antigravity-cli"
    mkdir -p "${agy}/conversations" "${agy}/brain/abc/logs"
    printf '{"model":"x"}\n' > "${agy}/settings.json"
    printf 'conversation\n' > "${agy}/conversations/abc.db"
    printf 'transcript\n' > "${agy}/brain/abc/logs/transcript.jsonl"
}

# Simulate a backup made before an exclusion existed: commit an excluded file.
commit_legacy_file() {
    local mirror="$1" rel="$2"
    mkdir -p "$(dirname "${mirror}/${rel}")"
    printf 'legacy %s\n' "$rel" > "${mirror}/${rel}"
    git -C "$mirror" add -f -- "$rel" >/dev/null 2>&1
    git -C "$mirror" commit -q -m "legacy backup with ${rel}" >/dev/null 2>&1
}

test_backup_excludes_codex_session_databases() {
    create_codex_fixture
    add_codex_session_databases

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local mirror="${ASB_BACKUP_ROOT}/.codex"
    assert_file_exists "${mirror}/state_5.sqlite" || return 1
    assert_file_not_exists "${mirror}/thread_history_1.sqlite" || return 1
    assert_file_not_exists "${mirror}/logs_2.sqlite" || return 1
    assert_file_not_exists "${mirror}/state_5.sqlite-wal" || return 1
    assert_dir_not_exists "${mirror}/db-backups" || return 1
}

test_backup_excludes_antigravity_transcripts() {
    create_mock_agent "gemini"
    add_antigravity_tree

    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local mirror="${ASB_BACKUP_ROOT}/.gemini"
    assert_file_exists "${mirror}/antigravity-cli/settings.json" || return 1
    assert_dir_not_exists "${mirror}/antigravity-cli/conversations" || return 1
    assert_dir_not_exists "${mirror}/antigravity-cli/brain" || return 1
}

test_restore_keeps_live_antigravity_transcripts() {
    create_mock_agent "gemini"
    add_antigravity_tree
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # A real settings difference, so the restore actually runs.
    printf '{"model":"changed"}\n' > "${HOME}/.gemini/antigravity-cli/settings.json"

    run_asb restore gemini --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    assert_equals '{"model":"x"}' "$(cat "${HOME}/.gemini/antigravity-cli/settings.json")" || return 1
    assert_file_exists "${HOME}/.gemini/antigravity-cli/conversations/abc.db" || return 1
    assert_file_exists "${HOME}/.gemini/antigravity-cli/brain/abc/logs/transcript.jsonl" || return 1
}

test_prune_dry_run_changes_nothing() {
    create_codex_fixture
    run_asb backup codex
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    commit_legacy_file "$mirror" "thread_history_1.sqlite"
    local head_before
    head_before=$(git -C "$mirror" rev-parse HEAD)

    run_asb prune codex --dry-run
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "thread_history_1.sqlite" || return 1
    assert_equals "$head_before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
    assert_file_exists "${mirror}/thread_history_1.sqlite" || return 1
}

test_prune_removes_legacy_excluded_files() {
    create_codex_fixture
    run_asb backup codex
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    commit_legacy_file "$mirror" "thread_history_1.sqlite"
    commit_legacy_file "$mirror" "sub/sessions/old.jsonl"
    local commits_before
    commits_before=$(git -C "$mirror" rev-list --count HEAD)

    run_asb prune codex --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    assert_file_not_exists "${mirror}/thread_history_1.sqlite" || return 1
    assert_dir_not_exists "${mirror}/sub/sessions" || return 1
    assert_file_exists "${mirror}/settings.json" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- thread_history_1.sqlite sub/sessions)" || return 1
    # A plain prune adds one commit and keeps history.
    assert_equals "$((commits_before + 1))" "$(git -C "$mirror" rev-list --count HEAD)" || return 1

    # The next backup must not bring the pruned files back.
    run_asb backup codex
    assert_file_not_exists "${mirror}/thread_history_1.sqlite" || return 1
}

test_prune_reinit_drops_history() {
    create_codex_fixture
    run_asb backup codex
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    commit_legacy_file "$mirror" "logs_2.sqlite"
    git -C "$mirror" tag before-prune >/dev/null 2>&1

    run_asb prune codex --reinit --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    assert_equals "1" "$(git -C "$mirror" rev-list --count HEAD)" || return 1
    assert_equals "" "$(git -C "$mirror" tag -l)" || return 1
    assert_equals "" "$(git -C "$mirror" rev-list --all --objects | grep logs_2.sqlite || true)" || return 1
    assert_file_exists "${mirror}/settings.json" || return 1
}

test_prune_clean_backup_is_noop() {
    create_codex_fixture
    run_asb backup codex
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    local head_before
    head_before=$(git -C "$mirror" rev-parse HEAD)

    run_asb prune codex --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "nothing to prune" || return 1
    assert_equals "$head_before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
}

test_prune_requires_confirmation_without_tty() {
    create_codex_fixture
    run_asb backup codex
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    commit_legacy_file "$mirror" "thread_history_1.sqlite"

    run_asb prune codex </dev/null
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "requires confirmation" || return 1
    assert_file_exists "${mirror}/thread_history_1.sqlite" || return 1
}

# Put a failing rsync first on PATH so asb takes its cp fallback.
use_failing_rsync() {
    local bin="${TEST_ENV_ROOT}/fakebin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexit 1\n' > "${bin}/rsync"
    chmod +x "${bin}/rsync"
    export PATH="${bin}:${PATH}"
}

test_cp_fallback_backup_applies_policy() {
    create_codex_fixture
    add_codex_session_databases
    create_mock_agent "gemini"
    add_antigravity_tree
    use_failing_rsync

    run_asb backup codex gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    assert_file_exists "${ASB_BACKUP_ROOT}/.codex/state_5.sqlite" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/.codex/thread_history_1.sqlite" || return 1
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/.codex/db-backups" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/.gemini/antigravity-cli/settings.json" || return 1
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/.gemini/antigravity-cli/conversations" || return 1
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/.gemini/antigravity-cli/brain" || return 1
}

test_cp_fallback_restore_keeps_live_transcripts() {
    create_mock_agent "gemini"
    add_antigravity_tree
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    # A conversation that exists only live, never in any backup.
    printf 'new\n' > "${HOME}/.gemini/antigravity-cli/conversations/new.db"
    use_failing_rsync

    run_asb restore gemini --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "${HOME}/.gemini/antigravity-cli/conversations/new.db" || return 1
    assert_file_exists "${HOME}/.gemini/antigravity-cli/settings.json" || return 1
}

test_cp_fallback_restore_ignores_legacy_excluded_copies() {
    create_mock_agent "gemini"
    add_antigravity_tree
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # A legacy backup still holding an old copy of a live conversation.
    commit_legacy_file "${ASB_BACKUP_ROOT}/.gemini" "antigravity-cli/conversations/abc.db"
    printf 'live newer\n' > "${HOME}/.gemini/antigravity-cli/conversations/abc.db"
    # A real settings difference, so the restore actually runs.
    printf '{"model":"changed"}\n' > "${HOME}/.gemini/antigravity-cli/settings.json"
    use_failing_rsync

    run_asb restore gemini --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals '{"model":"x"}' "$(cat "${HOME}/.gemini/antigravity-cli/settings.json")" || return 1
    assert_equals "live newer" "$(cat "${HOME}/.gemini/antigravity-cli/conversations/abc.db")" || return 1
}

# ~/.gemini/antigravity-cli as a link to data kept outside the agent's folder.
# GNU cp -r copies the link itself, so the cp fallbacks see a symlink there.
add_symlinked_antigravity_tree() {
    local outside="${TEST_ENV_ROOT}/outside-agy"
    mkdir -p "${outside}/conversations" "${outside}/brain/abc"
    printf '{"model":"x"}\n' > "${outside}/settings.json"
    printf 'conversation\n' > "${outside}/conversations/abc.db"
    printf 'transcript\n' > "${outside}/brain/abc/t.jsonl"
    printf 'sentinel\n' > "${outside}/sentinel"
    ln -s "$outside" "${HOME}/.gemini/antigravity-cli"
}

assert_outside_agy_intact() {
    local outside="${TEST_ENV_ROOT}/outside-agy"
    assert_equals "conversation" "$(cat "${outside}/conversations/abc.db" 2>/dev/null)" || return 1
    assert_equals "transcript" "$(cat "${outside}/brain/abc/t.jsonl" 2>/dev/null)" || return 1
    assert_equals "sentinel" "$(cat "${outside}/sentinel" 2>/dev/null)" || return 1
}

test_cp_fallback_backup_does_not_follow_symlinks() {
    create_mock_agent "gemini"
    add_symlinked_antigravity_tree
    use_failing_rsync

    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_outside_agy_intact || return 1
    assert_equals "" "$(git -C "${ASB_BACKUP_ROOT}/.gemini" ls-files | grep -E 'conversations|brain' || true)" || return 1
}

test_cp_fallback_restore_does_not_follow_symlinks() {
    create_mock_agent "gemini"
    add_symlinked_antigravity_tree
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # A real difference outside the link, so the restore actually runs.
    printf '{"changed":true}\n' > "${HOME}/.gemini/settings.json"
    use_failing_rsync

    run_asb restore gemini --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_outside_agy_intact || return 1
    assert_contains "$(cat "${HOME}/.gemini/settings.json")" '"agent":"gemini"' || return 1
}

test_cp_fallback_restore_refuses_when_staging_fails() {
    create_mock_agent "gemini"
    add_antigravity_tree
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    printf '{"model":"changed"}\n' > "${HOME}/.gemini/antigravity-cli/settings.json"
    printf 'live only\n' > "${HOME}/.gemini/antigravity-cli/conversations/new.db"
    local before
    before=$(cd "${HOME}/.gemini" && find . -type f -exec cksum {} + | sort)
    # Every copy out of the backup fails, so the staging copy does too.
    local real_cp
    real_cp=$(command -v cp)
    use_failing_rsync
    printf '#!/bin/sh\ncase "$*" in *"%s/"*) exit 1 ;; esac\nexec "%s" "$@"\n' \
        "$ASB_BACKUP_ROOT" "$real_cp" > "${TEST_ENV_ROOT}/fakebin/cp"
    chmod +x "${TEST_ENV_ROOT}/fakebin/cp"

    run_asb restore gemini --force
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "nothing was restored" || return 1
    assert_equals "$before" "$(cd "${HOME}/.gemini" && find . -type f -exec cksum {} + | sort)" || return 1
}

test_diff_shows_same_named_dirs_outside_antigravity() {
    create_mock_agent "gemini"
    add_antigravity_tree
    mkdir -p "${HOME}/.gemini/tools/conversations"
    printf 'v1\n' > "${HOME}/.gemini/tools/conversations/prompt.md"
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    printf 'v2\n' > "${HOME}/.gemini/tools/conversations/prompt.md"
    printf 'live only\n' > "${HOME}/.gemini/antigravity-cli/conversations/new.db"

    run_asb diff gemini
    assert_contains "$ASB_LAST_OUTPUT" "tools/conversations/prompt.md" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "new.db" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "antigravity-cli/conversations" || return 1
}

test_restore_preview_shows_same_named_dirs_outside_antigravity() {
    create_mock_agent "gemini"
    add_antigravity_tree
    mkdir -p "${HOME}/.gemini/tools/brain"
    printf 'v1\n' > "${HOME}/.gemini/tools/brain/notes.md"
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # Only the same-named directory differs: an anchored filter still sees a
    # change, so the restore runs and puts v1 back.
    printf 'v2\n' > "${HOME}/.gemini/tools/brain/notes.md"

    run_asb restore gemini --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "v1" "$(cat "${HOME}/.gemini/tools/brain/notes.md")" || return 1
}

test_prune_reinit_refuses_when_branch_moved() {
    create_codex_fixture
    run_asb backup codex
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    commit_legacy_file "$mirror" "thread_history_1.sqlite"
    # Another git writer commits after prune inspected the backup: a git
    # wrapper adds one just as prune builds the replacement root commit.
    local real_git
    real_git=$(command -v git)
    local bin="${TEST_ENV_ROOT}/racebin"
    mkdir -p "$bin"
    cat > "${bin}/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
    if [[ "\$a" == "commit-tree" ]]; then
        printf 'late\n' > "${mirror}/late.txt"
        "${real_git}" -C "${mirror}" add late.txt >/dev/null 2>&1
        "${real_git}" -C "${mirror}" commit -q -m "late backup" >/dev/null 2>&1
        break
    fi
done
exec "${real_git}" "\$@"
EOF
    chmod +x "${bin}/git"
    export PATH="${bin}:${PATH}"
    local late_count
    run_asb --force prune codex --reinit
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    late_count=$(git -C "$mirror" log --format=%s | grep -c '^late backup$' || true)
    assert_equals "1" "$late_count" || return 1
    assert_contains "$(git -C "$mirror" show HEAD:late.txt 2>/dev/null)" "late" || return 1
    # Recovery history survives: the pre-prune commits are still reachable.
    assert_contains "$(git -C "$mirror" log --format=%s)" "legacy backup with thread_history_1.sqlite" || return 1
}

test_write_commands_refuse_while_locked() {
    create_codex_fixture
    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # A live asb (this test shell) is writing the codex backup.
    mkdir -p "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock"
    printf '%s\n' "$$" > "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock/pid"
    export ASB_LOCK_WAIT=0

    run_asb backup codex
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Another asb operation (pid $$)" || return 1
    run_asb --force prune codex --reinit
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    run_asb restore codex --force
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    # Other agents, read-only commands and dry runs are not blocked.
    create_mock_agent "gemini"
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb history codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb --dry-run prune codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
}

test_writer_waits_for_lock_holder() {
    create_codex_fixture
    mkdir -p "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock"
    sleep 2 &
    local holder=$!
    printf '%s\n' "$holder" > "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock/pid"
    export ASB_LOCK_WAIT=30

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Waiting for asb pid ${holder}" || return 1
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock" || return 1
}

test_stale_write_lock_is_taken_over() {
    create_codex_fixture
    mkdir -p "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock"
    # A pid that cannot be running.
    printf '%s\n' "999999999" > "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock/pid"

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/.asb-locks/codex.lock" || return 1
}

test_prune_json() {
    create_codex_fixture
    run_asb backup codex
    commit_legacy_file "${ASB_BACKUP_ROOT}/.codex" "thread_history_1.sqlite"

    ASB_LAST_OUTPUT="$($ASB_BIN --json prune codex --dry-run 2>/dev/null)"
    ASB_LAST_STATUS=$?
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" '"command":"prune"' || return 1
    assert_contains "$ASB_LAST_OUTPUT" '"status":"dry_run"' || return 1
    assert_contains "$ASB_LAST_OUTPUT" '"excluded_paths":1' || return 1
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' || return 1
    fi
}

test_prune_unknown_option() {
    run_asb prune --bogus
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Unknown prune option" || return 1
}

run_test "backup_excludes_codex_session_databases" test_backup_excludes_codex_session_databases
run_test "backup_excludes_antigravity_transcripts" test_backup_excludes_antigravity_transcripts
run_test "restore_keeps_live_antigravity_transcripts" test_restore_keeps_live_antigravity_transcripts
run_test "prune_dry_run_changes_nothing" test_prune_dry_run_changes_nothing
run_test "prune_removes_legacy_excluded_files" test_prune_removes_legacy_excluded_files
run_test "prune_reinit_drops_history" test_prune_reinit_drops_history
run_test "prune_clean_backup_is_noop" test_prune_clean_backup_is_noop
run_test "prune_requires_confirmation_without_tty" test_prune_requires_confirmation_without_tty
run_test "cp_fallback_backup_applies_policy" test_cp_fallback_backup_applies_policy
run_test "cp_fallback_restore_keeps_live_transcripts" test_cp_fallback_restore_keeps_live_transcripts
run_test "cp_fallback_restore_ignores_legacy_excluded_copies" test_cp_fallback_restore_ignores_legacy_excluded_copies
run_test "cp_fallback_backup_does_not_follow_symlinks" test_cp_fallback_backup_does_not_follow_symlinks
run_test "cp_fallback_restore_does_not_follow_symlinks" test_cp_fallback_restore_does_not_follow_symlinks
run_test "cp_fallback_restore_refuses_when_staging_fails" test_cp_fallback_restore_refuses_when_staging_fails
run_test "diff_shows_same_named_dirs_outside_antigravity" test_diff_shows_same_named_dirs_outside_antigravity
run_test "restore_preview_shows_same_named_dirs_outside_antigravity" test_restore_preview_shows_same_named_dirs_outside_antigravity
run_test "prune_reinit_refuses_when_branch_moved" test_prune_reinit_refuses_when_branch_moved
run_test "write_commands_refuse_while_locked" test_write_commands_refuse_while_locked
run_test "writer_waits_for_lock_holder" test_writer_waits_for_lock_holder
run_test "stale_write_lock_is_taken_over" test_stale_write_lock_is_taken_over
run_test "prune_json" test_prune_json
run_test "prune_unknown_option" test_prune_unknown_option

finish_suite
