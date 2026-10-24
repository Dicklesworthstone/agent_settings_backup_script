#!/usr/bin/env bash
#
# E2E Tests: credential files stay out of backups unless ASB_INCLUDE_CREDENTIALS=true
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# Stand-in token text; tests check it never appears in asb's output.
FAKE_TOKEN="fake-token-not-a-secret"

# Login files where Claude Code, Codex and Gemini CLI keep them, plus one in a
# nested profile directory (account managers keep per-account homes there).
add_credentials() {
    printf '{"claudeAiOauth":"%s"}\n' "$FAKE_TOKEN" > "${HOME}/.claude/.credentials.json"
    mkdir -p "${HOME}/.claude/profiles/work"
    printf '{"claudeAiOauth":"%s"}\n' "$FAKE_TOKEN" > "${HOME}/.claude/profiles/work/.credentials.json"
    printf '{"model":"work"}\n' > "${HOME}/.claude/profiles/work/settings.json"
    printf 'keychain\n' > "${HOME}/.claude/profiles/work/login.keychain-db"
    printf '{"tokens":"%s"}\n' "$FAKE_TOKEN" > "${HOME}/.codex/auth.json"
    printf '{"refresh_token":"%s"}\n' "$FAKE_TOKEN" > "${HOME}/.gemini/oauth_creds.json"
    printf '{"server":"%s"}\n' "$FAKE_TOKEN" > "${HOME}/.gemini/mcp-oauth-tokens.json"
    printf 'GEMINI_API_KEY=%s\n' "$FAKE_TOKEN" > "${HOME}/.gemini/.env"
}

setup_agents_with_credentials() {
    create_claude_fixture
    create_codex_fixture
    create_mock_agent "gemini"
    add_credentials
}

# Every credential file is absent from the backups and from their git index,
# while the settings next to them are backed up.
assert_credentials_left_out() {
    local root="$ASB_BACKUP_ROOT"
    assert_file_exists "${root}/.claude/settings.json" || return 1
    assert_file_exists "${root}/.claude/profiles/work/settings.json" || return 1
    assert_file_exists "${root}/.codex/settings.json" || return 1
    assert_file_exists "${root}/.gemini/settings.json" || return 1
    assert_file_not_exists "${root}/.claude/.credentials.json" || return 1
    assert_file_not_exists "${root}/.claude/profiles/work/.credentials.json" || return 1
    assert_file_not_exists "${root}/.claude/profiles/work/login.keychain-db" || return 1
    assert_file_not_exists "${root}/.codex/auth.json" || return 1
    assert_file_not_exists "${root}/.gemini/oauth_creds.json" || return 1
    assert_file_not_exists "${root}/.gemini/mcp-oauth-tokens.json" || return 1
    assert_file_not_exists "${root}/.gemini/.env" || return 1
    local agent tracked
    for agent in .claude .codex .gemini; do
        tracked=$(git -C "${root}/${agent}" grep -l "$FAKE_TOKEN" HEAD -- . 2>/dev/null || true)
        assert_equals "" "$tracked" || return 1
    done
}

test_backup_leaves_out_credentials() {
    setup_agents_with_credentials

    run_asb backup claude codex gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_credentials_left_out || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "$FAKE_TOKEN" || return 1
}

test_cp_fallback_backup_leaves_out_credentials() {
    setup_agents_with_credentials
    use_failing_rsync

    run_asb backup claude codex gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_credentials_left_out || return 1
}

test_dry_run_lists_left_out_credentials() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    printf '{"changed":true}\n' > "${HOME}/.claude/settings.json"

    run_asb --dry-run backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "Credential files left out" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "ASB_INCLUDE_CREDENTIALS=true" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "  .credentials.json" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "  profiles/work/.credentials.json" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "  profiles/work/login.keychain-db" || return 1
    # The rsync change list names settings.json but no credential file.
    assert_contains "$ASB_LAST_OUTPUT" "settings.json" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "f+++++++++ .credentials.json" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "$FAKE_TOKEN" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/.claude/.credentials.json" || return 1
}

test_include_credentials_env_opt_in() {
    setup_agents_with_credentials
    export ASB_INCLUDE_CREDENTIALS=true

    run_asb backup claude codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/.claude/.credentials.json" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/.claude/profiles/work/.credentials.json" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/.codex/auth.json" || return 1

    run_asb --dry-run backup claude
    assert_not_contains "$ASB_LAST_OUTPUT" "Credential files left out" || return 1
}

test_include_credentials_config_opt_in() {
    setup_agents_with_credentials
    mkdir -p "${XDG_CONFIG_HOME}/asb"
    printf 'ASB_INCLUDE_CREDENTIALS=true\n' > "${XDG_CONFIG_HOME}/asb/config"

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/.codex/auth.json" || return 1

    run_asb config show
    assert_contains "$ASB_LAST_OUTPUT" "ASB_INCLUDE_CREDENTIALS: true" || return 1
}

test_restore_keeps_live_credentials() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # The live token rotated after the backup, and a settings change makes
    # the restore actually run.
    printf 'rotated\n' > "${HOME}/.claude/.credentials.json"
    printf '{"changed":true}\n' > "${HOME}/.claude/settings.json"

    run_asb restore claude --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_files_identical "${ASB_BACKUP_ROOT}/.claude/settings.json" "${HOME}/.claude/settings.json" || return 1
    assert_equals "rotated" "$(cat "${HOME}/.claude/.credentials.json")" || return 1
    assert_file_exists "${HOME}/.claude/profiles/work/.credentials.json" || return 1
}

test_restore_ignores_credentials_an_earlier_backup_holds() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    # A backup written before credentials were excluded holds an old token.
    commit_legacy_file "${ASB_BACKUP_ROOT}/.claude" ".credentials.json"
    printf 'rotated\n' > "${HOME}/.claude/.credentials.json"
    printf '{"changed":true}\n' > "${HOME}/.claude/settings.json"

    run_asb restore claude --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "rotated" "$(cat "${HOME}/.claude/.credentials.json")" || return 1
}

test_cp_fallback_restore_keeps_live_credentials() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    commit_legacy_file "${ASB_BACKUP_ROOT}/.claude" ".credentials.json"
    printf 'rotated\n' > "${HOME}/.claude/.credentials.json"
    printf 'rotated work\n' > "${HOME}/.claude/profiles/work/.credentials.json"
    printf '{"changed":true}\n' > "${HOME}/.claude/settings.json"
    printf '{"model":"changed"}\n' > "${HOME}/.claude/profiles/work/settings.json"
    use_failing_rsync

    run_asb restore claude --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_files_identical "${ASB_BACKUP_ROOT}/.claude/settings.json" "${HOME}/.claude/settings.json" || return 1
    # The profile directory is merged over, not replaced: its live
    # credentials survive and its settings come back from the backup.
    assert_equals '{"model":"work"}' "$(cat "${HOME}/.claude/profiles/work/settings.json")" || return 1
    assert_equals "rotated work" "$(cat "${HOME}/.claude/profiles/work/.credentials.json")" || return 1
    assert_equals "rotated" "$(cat "${HOME}/.claude/.credentials.json")" || return 1
}

test_backup_warns_about_tracked_credentials_and_prune_removes_them() {
    setup_agents_with_credentials
    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.codex"
    commit_legacy_file "$mirror" "auth.json"
    commit_legacy_file "$mirror" "profiles/old/.env"
    printf '{"changed":true}\n' > "${HOME}/.codex/settings.json"

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "still holds 2 credential file(s)" || return 1
    assert_contains "$ASB_LAST_OUTPUT" "asb prune codex" || return 1
    # Left tracked as it was: the live token is not copied over it.
    assert_equals "legacy auth.json" "$(cat "${mirror}/auth.json")" || return 1

    run_asb prune codex --force
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- auth.json profiles/old/.env)" || return 1
    assert_file_exists "${mirror}/settings.json" || return 1
    # History is not rewritten without --reinit.
    assert_not_equals "" "$(git -C "$mirror" log --format=%H -- auth.json)" || return 1

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "credential file(s)" || return 1
    assert_file_not_exists "${mirror}/auth.json" || return 1
}

test_custom_agent_leaves_out_credentials() {
    local profile=".local/share/accounts/claude/work"
    mkdir -p "${HOME}/${profile}" "${XDG_CONFIG_HOME}/asb"
    printf '{"model":"x"}\n' > "${HOME}/${profile}/settings.json"
    printf '{"claudeAiOauth":"%s"}\n' "$FAKE_TOKEN" > "${HOME}/${profile}/.credentials.json"
    printf 'work=%s\n' "$profile" > "${XDG_CONFIG_HOME}/asb/custom_agents"

    run_asb backup work
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/${profile}/settings.json" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/${profile}/.credentials.json" || return 1
}

use_failing_rsync() {
    local bin="${TEST_ENV_ROOT}/fakebin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexit 1\n' > "${bin}/rsync"
    chmod +x "${bin}/rsync"
    export PATH="${bin}:${PATH}"
}

# Simulate a backup made before credentials were excluded.
commit_legacy_file() {
    local mirror="$1" rel="$2"
    mkdir -p "$(dirname "${mirror}/${rel}")"
    printf 'legacy %s\n' "$rel" > "${mirror}/${rel}"
    git -C "$mirror" add -f -- "$rel" >/dev/null 2>&1
    git -C "$mirror" commit -q -m "legacy backup with ${rel}" >/dev/null 2>&1
}

run_test "backup_leaves_out_credentials" test_backup_leaves_out_credentials
run_test "cp_fallback_backup_leaves_out_credentials" test_cp_fallback_backup_leaves_out_credentials
run_test "dry_run_lists_left_out_credentials" test_dry_run_lists_left_out_credentials
run_test "include_credentials_env_opt_in" test_include_credentials_env_opt_in
run_test "include_credentials_config_opt_in" test_include_credentials_config_opt_in
run_test "restore_keeps_live_credentials" test_restore_keeps_live_credentials
run_test "restore_ignores_credentials_an_earlier_backup_holds" test_restore_ignores_credentials_an_earlier_backup_holds
run_test "cp_fallback_restore_keeps_live_credentials" test_cp_fallback_restore_keeps_live_credentials
run_test "backup_warns_about_tracked_credentials_and_prune_removes_them" test_backup_warns_about_tracked_credentials_and_prune_removes_them
run_test "custom_agent_leaves_out_credentials" test_custom_agent_leaves_out_credentials

finish_suite
