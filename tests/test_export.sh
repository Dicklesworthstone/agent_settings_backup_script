#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

declare -F create_claude_fixture >/dev/null 2>&1 || { echo "create_claude_fixture not loaded" >&2; exit 1; }

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
    # Not `tar | grep -q`: under pipefail, grep exiting at the first match can
    # kill tar with SIGPIPE and fail the check at random.
    local listing
    listing=$(tar -tzf "$archive" 2>/dev/null) || return 1
    [[ "$listing" == *".git/objects"* ]]
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

test_import_from_stdin_roundtrip_and_conflict() {
    make_backup_with_history
    local expected_head
    expected_head=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)

    local archive="${TEST_ENV_ROOT}/stdin-export.tar.gz"
    "$ASB_BIN" export claude - > "$archive" 2>/dev/null || {
        echo "Export to stdout failed" >&2
        return 1
    }

    # Stdin dry-run must inspect the spooled archive and detect overwrite
    local dry_out
    dry_out=$("$ASB_BIN" --json --dry-run import - < "$archive" 2>&1) || {
        echo "Stdin dry-run failed: $dry_out" >&2
        return 1
    }
    assert_contains "$dry_out" '"status":"dry_run"' || return 1
    assert_contains "$dry_out" '"agent_folder":".claude"' || return 1
    assert_contains "$dry_out" '"would_overwrite":true' || return 1

    # Stdin without --force must detect existing backup and refuse
    printf "incumbent-marker\n" > "$ASB_BACKUP_ROOT/.claude/incumbent.txt"
    local conflict_out conflict_rc=0
    conflict_out=$("$ASB_BIN" --json import - < "$archive" 2>&1) || conflict_rc=$?
    if [[ $conflict_rc -eq 0 ]]; then
        echo "Expected stdin import without --force to refuse existing backup" >&2
        return 1
    fi
    assert_contains "$conflict_out" '"error":"backup_exists"' || return 1
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/incumbent.txt" || return 1

    # Stdin with --force replaces cleanly and preserves Git history
    local force_out
    force_out=$("$ASB_BIN" --json --force import - < "$archive" 2>&1) || {
        echo "Forced stdin import failed: $force_out" >&2
        return 1
    }
    assert_contains "$force_out" '"status":"success"' || return 1
    assert_contains "$force_out" '"agent_folder":".claude"' || return 1
    assert_file_not_exists "$ASB_BACKUP_ROOT/.claude/incumbent.txt" || return 1
    assert_equals "$expected_head" "$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)" || return 1
}

test_import_rejects_multi_root_and_preserves_incumbent() {
    make_backup_with_history
    create_codex_fixture
    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1

    local claude_head codex_head
    claude_head=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)
    codex_head=$(git -C "$ASB_BACKUP_ROOT/.codex" rev-parse HEAD)
    printf "claude-incumbent\n" > "$ASB_BACKUP_ROOT/.claude/keep.txt"
    printf "codex-incumbent\n" > "$ASB_BACKUP_ROOT/.codex/keep.txt"

    local multi_archive="${TEST_ENV_ROOT}/multi-root.tar.gz"
    tar -czf "$multi_archive" -C "$ASB_BACKUP_ROOT" .claude .codex || return 1

    run_asb --json --force import "$multi_archive"
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected multi-root archive to be rejected" >&2
        return 1
    fi
    assert_contains "$ASB_LAST_OUTPUT" '"error":"multiple_archive_roots"' || return 1
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/keep.txt" || return 1
    assert_file_exists "$ASB_BACKUP_ROOT/.codex/keep.txt" || return 1
    assert_equals "$claude_head" "$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)" || return 1
    assert_equals "$codex_head" "$(git -C "$ASB_BACKUP_ROOT/.codex" rev-parse HEAD)" || return 1
}

test_import_rejects_unsafe_paths_links_and_unrecognized_root() {
    make_backup_with_history
    local claude_head
    claude_head=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)
    printf "incumbent-safe\n" > "$ASB_BACKUP_ROOT/.claude/safe.txt"

    local traversal_archive="${TEST_ENV_ROOT}/traversal.tar.gz"
    local symlink_archive="${TEST_ENV_ROOT}/escaping-symlink.tar.gz"
    local unknown_archive="${TEST_ENV_ROOT}/unknown-root.tar.gz"

    python3 - "$traversal_archive" "$symlink_archive" "$unknown_archive" <<'PY' || return 1
import io, sys, tarfile

def add_dir(tf, name):
    ti = tarfile.TarInfo(name)
    ti.type = tarfile.DIRTYPE
    ti.mode = 0o755
    tf.addfile(ti)

def add_file(tf, name, data=b"x\n"):
    ti = tarfile.TarInfo(name)
    ti.size = len(data)
    ti.mode = 0o644
    tf.addfile(ti, io.BytesIO(data))

with tarfile.open(sys.argv[1], "w:gz") as tf:
    add_dir(tf, ".claude")
    add_file(tf, ".claude/../escaped.txt")

with tarfile.open(sys.argv[2], "w:gz") as tf:
    add_dir(tf, ".claude")
    ti = tarfile.TarInfo(".claude/escape_link")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "../../outside.txt"
    tf.addfile(ti)

with tarfile.open(sys.argv[3], "w:gz") as tf:
    add_dir(tf, ".not_an_agent")
    add_file(tf, ".not_an_agent/settings.json", b"{}\n")
PY

    run_asb --json --force import "$traversal_archive"
    [[ $ASB_LAST_STATUS -ne 0 ]] || { echo "Expected traversal archive refusal" >&2; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" '"error":"unsafe_archive_path"' || return 1

    run_asb --json --force import "$symlink_archive"
    [[ $ASB_LAST_STATUS -ne 0 ]] || { echo "Expected escaping symlink archive refusal" >&2; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" '"error":"unsafe_archive_link"' || return 1

    run_asb --json --force import "$unknown_archive"
    [[ $ASB_LAST_STATUS -ne 0 ]] || { echo "Expected unrecognized root refusal" >&2; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" '"error":"unrecognized_agent_root"' || return 1

    assert_file_not_exists "$ASB_BACKUP_ROOT/escaped.txt" || return 1
    assert_dir_not_exists "$ASB_BACKUP_ROOT/.not_an_agent" || return 1
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/safe.txt" || return 1
    assert_equals "$claude_head" "$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)" || return 1
}

test_import_preserves_incumbent_on_truncated_archive_with_force() {
    make_backup_with_history
    local claude_head
    claude_head=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)
    printf "must-survive\n" > "$ASB_BACKUP_ROOT/.claude/must-survive.txt"

    local good_archive="${TEST_ENV_ROOT}/good.tar.gz"
    local trunc_archive="${TEST_ENV_ROOT}/truncated.tar.gz"
    run_asb export claude "$good_archive"
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    head -c 64 "$good_archive" > "$trunc_archive"

    run_asb --force import "$trunc_archive"
    if [[ $ASB_LAST_STATUS -eq 0 ]]; then
        echo "Expected truncated archive import to fail" >&2
        return 1
    fi
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/must-survive.txt" || return 1
    assert_equals "$claude_head" "$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)" || return 1
}

test_import_rejects_untrusted_git_hooks_and_config() {
    make_backup_with_history
    local claude_head
    claude_head=$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)
    printf "trusted-incumbent\n" > "$ASB_BACKUP_ROOT/.claude/trusted.txt"

    local canary_file="${TEST_ENV_ROOT}/canary-executed"
    local stage_copy="${TEST_ENV_ROOT}/malicious-stage"
    mkdir -p "$stage_copy"

    # Case 1: Archive containing an active Git hook
    cp -a "$ASB_BACKUP_ROOT/.claude" "$stage_copy/.claude"
    mkdir -p "$stage_copy/.claude/.git/hooks"
    printf '#!/bin/sh\necho pwned > "%s"\n' "$canary_file" > "$stage_copy/.claude/.git/hooks/pre-commit"
    chmod +x "$stage_copy/.claude/.git/hooks/pre-commit"
    local hook_archive="${TEST_ENV_ROOT}/with-hook.tar.gz"
    tar -czf "$hook_archive" -C "$stage_copy" .claude || return 1

    run_asb --json --force import "$hook_archive"
    [[ $ASB_LAST_STATUS -ne 0 ]] || { echo "Expected hook archive to be rejected" >&2; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" '"error":"untrusted_git_metadata"' || return 1
    assert_file_not_exists "$canary_file" || return 1
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/trusted.txt" || return 1

    # Case 2: Archive containing untrusted core.fsmonitor directive in .git/config
    rm -f "$stage_copy/.claude/.git/hooks/pre-commit"
    git -C "$stage_copy/.claude" config core.fsmonitor "echo pwned > '$canary_file'"
    local cfg_archive="${TEST_ENV_ROOT}/with-fsmonitor.tar.gz"
    tar -czf "$cfg_archive" -C "$stage_copy" .claude || return 1

    run_asb --json --force import "$cfg_archive"
    [[ $ASB_LAST_STATUS -ne 0 ]] || { echo "Expected core.fsmonitor archive to be rejected" >&2; return 1; }
    assert_contains "$ASB_LAST_OUTPUT" '"error":"untrusted_git_metadata"' || return 1
    assert_file_not_exists "$canary_file" || return 1
    assert_file_exists "$ASB_BACKUP_ROOT/.claude/trusted.txt" || return 1
    assert_equals "$claude_head" "$(git -C "$ASB_BACKUP_ROOT/.claude" rev-parse HEAD)" || return 1
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
run_test "import_from_stdin_roundtrip_and_conflict" test_import_from_stdin_roundtrip_and_conflict || exit 1
run_test "import_rejects_multi_root_and_preserves_incumbent" test_import_rejects_multi_root_and_preserves_incumbent || exit 1
run_test "import_rejects_unsafe_paths_links_and_unrecognized_root" test_import_rejects_unsafe_paths_links_and_unrecognized_root || exit 1
run_test "import_preserves_incumbent_on_truncated_archive_with_force" test_import_preserves_incumbent_on_truncated_archive_with_force || exit 1
run_test "import_rejects_untrusted_git_hooks_and_config" test_import_rejects_untrusted_git_hooks_and_config || exit 1

exit 0
