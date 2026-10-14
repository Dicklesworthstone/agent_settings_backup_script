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
    # Rotated logs and the app-server daemon Codex downloads for itself.
    mkdir -p "${codex}/log" "${codex}/packages/app-server-daemon/releases/1.0/bin"
    printf 'rotated\n' > "${codex}/log/codex-tui.log.2.gz"
    printf 'rotated\n' > "${codex}/log/codex-tui.log.1"
    printf 'binary\n' > "${codex}/packages/app-server-daemon/releases/1.0/bin/codex"
    printf 'keep\n' > "${codex}/packages/notes.txt"
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
    assert_file_not_exists "${mirror}/log/codex-tui.log.2.gz" || return 1
    assert_file_not_exists "${mirror}/log/codex-tui.log.1" || return 1
    assert_dir_not_exists "${mirror}/packages/app-server-daemon" || return 1
    assert_file_exists "${mirror}/packages/notes.txt" || return 1
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
    commit_legacy_file "$mirror" "log/codex-tui.log.2.gz"
    commit_legacy_file "$mirror" "packages/app-server-daemon/releases/1.0/bin/codex"
    local commits_before
    commits_before=$(git -C "$mirror" rev-list --count HEAD)

    run_asb prune codex --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    assert_file_not_exists "${mirror}/thread_history_1.sqlite" || return 1
    assert_dir_not_exists "${mirror}/sub/sessions" || return 1
    assert_file_exists "${mirror}/settings.json" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- thread_history_1.sqlite sub/sessions log packages/app-server-daemon)" || return 1
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

# Hold the codex backup lock from another process for $1 seconds.
# Sets LOCK_HOLDER_PID; returns once the lock is held.
hold_codex_lock() {
    local lock="${ASB_BACKUP_ROOT}/.asb-locks/codex.flock" ready="${TEST_ENV_ROOT}/lock-ready.$RANDOM"
    mkdir -p "${lock%/*}"
    perl -e 'use Fcntl qw(:flock); open(my $f, ">>", $ARGV[0]) or die; flock($f, LOCK_EX) or die;
             open(my $r, ">", $ARGV[1]) or die; close $r; sleep $ARGV[2]' "$lock" "$ready" "$1" &
    LOCK_HOLDER_PID=$!
    local i
    for i in $(seq 1 100); do
        [[ -e "$ready" ]] && return 0
        sleep 0.1
    done
    return 1
}

test_write_commands_refuse_while_locked() {
    create_codex_fixture
    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    hold_codex_lock 60 || return 1
    export ASB_LOCK_WAIT=0

    run_asb backup codex
    assert_exit_code 1 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Another asb operation is still writing" || return 1
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
    kill "$LOCK_HOLDER_PID" 2>/dev/null
    wait "$LOCK_HOLDER_PID" 2>/dev/null || true
}

test_writer_waits_for_lock_holder() {
    create_codex_fixture
    hold_codex_lock 2 || return 1
    export ASB_LOCK_WAIT=30

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Waiting for another asb" || return 1
}

test_lock_dies_with_its_holder() {
    create_codex_fixture
    hold_codex_lock 60 || return 1
    kill -9 "$LOCK_HOLDER_PID"
    wait "$LOCK_HOLDER_PID" 2>/dev/null || true
    export ASB_LOCK_WAIT=0

    # The lock file is still there, but nobody holds it: no takeover needed.
    assert_file_exists "${ASB_BACKUP_ROOT}/.asb-locks/codex.flock" || return 1
    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
}

test_simultaneous_writers_never_overlap() {
    create_codex_fixture
    # Start from a lock file whose holder was killed: the case where
    # stale-lock takeover could let two claimants in together.
    hold_codex_lock 60 || return 1
    kill -9 "$LOCK_HOLDER_PID"
    wait "$LOCK_HOLDER_PID" 2>/dev/null || true

    local log="${TEST_ENV_ROOT}/overlap.log" mark="${TEST_ENV_ROOT}/inside"
    local hook="${XDG_CONFIG_HOME}/asb/hooks/pre-backup.d/10-overlap.sh"
    mkdir -p "${hook%/*}"
    printf '#!/bin/sh\nmkdir "%s" 2>/dev/null || echo overlap >> "%s"\necho enter >> "%s"\nsleep 1\nrmdir "%s" 2>/dev/null\nexit 0\n' \
        "$mark" "$log" "$log" "$mark" > "$hook"
    chmod +x "$hook"
    export ASB_LOCK_WAIT=60

    local -a pids=()
    local i failed=0
    for i in 1 2 3 4; do
        "$ASB_BIN" backup codex >/dev/null 2>&1 &
        pids+=("$!")
    done
    for i in "${pids[@]}"; do
        wait "$i" || failed=$((failed + 1))
    done
    assert_equals "0" "$failed" || return 1
    assert_equals "4" "$(grep -c '^enter$' "$log")" || return 1
    assert_equals "0" "$(grep -c '^overlap$' "$log" || true)" || return 1
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

# Top-level scratch and installer output: Gemini CLI's tmp/ (per-project chats),
# Claude Code's jobs/, OpenCode's bin/. Same-named dirs deeper down, and
# Claude's own bin/ (user scripts), are settings and stay.
add_top_level_scratch() {
    create_mock_agent "gemini"
    mkdir -p "${HOME}/.gemini/tmp/proj/chats" "${HOME}/.gemini/skills/demo/tmp"
    printf 'chat\n' > "${HOME}/.gemini/tmp/proj/chats/session-1.jsonl"
    printf 'keep\n' > "${HOME}/.gemini/skills/demo/tmp/notes.md"
    create_claude_fixture
    mkdir -p "${HOME}/.claude/jobs/abc/tmp" "${HOME}/.claude/bin" "${HOME}/.claude/skills/demo/jobs"
    printf 'state\n' > "${HOME}/.claude/jobs/abc/state.json"
    printf 'binary\n' > "${HOME}/.claude/jobs/abc/tmp/am"
    printf '#!/bin/sh\n' > "${HOME}/.claude/bin/statusline.sh"
    printf 'keep\n' > "${HOME}/.claude/skills/demo/jobs/README.md"
    create_mock_agent "opencode"
    mkdir -p "${HOME}/.opencode/bin"
    printf 'binary\n' > "${HOME}/.opencode/bin/opencode"
}

assert_top_level_scratch_excluded() {
    local b="$ASB_BACKUP_ROOT"
    assert_dir_not_exists "${b}/.gemini/tmp" || return 1
    assert_file_exists "${b}/.gemini/skills/demo/tmp/notes.md" || return 1
    assert_file_exists "${b}/.gemini/settings.json" || return 1
    assert_dir_not_exists "${b}/.claude/jobs" || return 1
    assert_file_exists "${b}/.claude/bin/statusline.sh" || return 1
    assert_file_exists "${b}/.claude/skills/demo/jobs/README.md" || return 1
    assert_dir_not_exists "${b}/.opencode/bin" || return 1
    assert_file_exists "${b}/.opencode/settings.json" || return 1
}

test_backup_excludes_top_level_scratch() {
    add_top_level_scratch
    run_asb backup gemini claude opencode
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_top_level_scratch_excluded
}

test_cp_fallback_backup_excludes_top_level_scratch() {
    add_top_level_scratch
    use_failing_rsync
    run_asb backup gemini claude opencode
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_top_level_scratch_excluded
}

restore_keeps_live_top_level_scratch() {
    local fallback="$1"
    add_top_level_scratch
    run_asb backup gemini opencode
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # Real settings differences, so the restores actually run.
    printf '{"changed":true}\n' > "${HOME}/.gemini/settings.json"
    printf '{"changed":true}\n' > "${HOME}/.opencode/settings.json"
    [[ "$fallback" == "true" ]] && use_failing_rsync

    run_asb restore gemini --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    run_asb restore opencode --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_not_contains "$(cat "${HOME}/.gemini/settings.json")" "changed" || return 1
    assert_not_contains "$(cat "${HOME}/.opencode/settings.json")" "changed" || return 1
    assert_file_exists "${HOME}/.gemini/tmp/proj/chats/session-1.jsonl" || return 1
    assert_file_exists "${HOME}/.opencode/bin/opencode" || return 1
}

test_restore_keeps_live_top_level_scratch() {
    restore_keeps_live_top_level_scratch false
}

test_cp_fallback_restore_keeps_live_top_level_scratch() {
    restore_keeps_live_top_level_scratch true
}

test_diff_ignores_top_level_scratch() {
    add_top_level_scratch
    run_asb backup gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    printf 'v2\n' > "${HOME}/.gemini/skills/demo/tmp/notes.md"
    printf 'live only\n' > "${HOME}/.gemini/tmp/proj/chats/session-2.jsonl"
    mkdir -p "${HOME}/.gemini/tmp/other"

    run_asb diff gemini
    assert_contains "$ASB_LAST_OUTPUT" "skills/demo/tmp/notes.md" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "session-2.jsonl" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "other" || return 1
}

test_prune_removes_legacy_top_level_scratch() {
    add_top_level_scratch
    run_asb backup claude opencode
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    commit_legacy_file "${ASB_BACKUP_ROOT}/.opencode" "bin/opencode"
    commit_legacy_file "${ASB_BACKUP_ROOT}/.claude" "jobs/abc/tmp/am"

    run_asb prune opencode claude --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "" "$(git -C "${ASB_BACKUP_ROOT}/.opencode" ls-files -- bin)" || return 1
    assert_equals "" "$(git -C "${ASB_BACKUP_ROOT}/.claude" ls-files -- jobs)" || return 1
    # Per-agent: Claude's bin/ is not OpenCode's.
    assert_equals "bin/statusline.sh" "$(git -C "${ASB_BACKUP_ROOT}/.claude" ls-files -- bin)" || return 1
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
run_test "lock_dies_with_its_holder" test_lock_dies_with_its_holder
run_test "simultaneous_writers_never_overlap" test_simultaneous_writers_never_overlap
run_test "backup_excludes_top_level_scratch" test_backup_excludes_top_level_scratch
run_test "cp_fallback_backup_excludes_top_level_scratch" test_cp_fallback_backup_excludes_top_level_scratch
run_test "restore_keeps_live_top_level_scratch" test_restore_keeps_live_top_level_scratch
run_test "cp_fallback_restore_keeps_live_top_level_scratch" test_cp_fallback_restore_keeps_live_top_level_scratch
run_test "diff_ignores_top_level_scratch" test_diff_ignores_top_level_scratch
run_test "prune_removes_legacy_top_level_scratch" test_prune_removes_legacy_top_level_scratch
run_test "prune_json" test_prune_json
run_test "prune_unknown_option" test_prune_unknown_option

finish_suite
