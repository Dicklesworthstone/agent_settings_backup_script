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
    watch_credential_copies

    run_asb backup claude codex gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_credentials_left_out || return 1
    assert_equals "" "$(cat "$ASB_TEST_COPIED_CREDENTIALS")" || return 1
}

test_backup_without_rsync_excludes_credentials() {
    setup_agents_with_credentials
    use_missing_rsync
    watch_credential_copies

    if command -v rsync >/dev/null 2>&1; then
        return 1
    fi
    run_asb backup claude codex gemini
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_credentials_left_out || return 1
    assert_equals "" "$(cat "$ASB_TEST_COPIED_CREDENTIALS")" || return 1
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

test_cp_fallback_keeps_legacy_excluded_backup_files() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude" legacy_head
    commit_legacy_file "$mirror" "profiles/work/.credentials.json"
    legacy_head=$(git -C "$mirror" rev-parse HEAD)
    printf 'changed settings\n' > "${HOME}/.claude/profiles/work/settings.json"
    use_failing_rsync

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "legacy profiles/work/.credentials.json" "$(cat "${mirror}/profiles/work/.credentials.json")" || return 1
    assert_equals "legacy profiles/work/.credentials.json" "$(git -C "$mirror" show HEAD:profiles/work/.credentials.json)" || return 1
    assert_equals "changed settings" "$(cat "${mirror}/profiles/work/settings.json")" || return 1
    git -C "$mirror" merge-base --is-ancestor "$legacy_head" HEAD || return 1
}

test_git_staging_ignores_new_excluded_files() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude"
    mkdir -p "${mirror}/profiles/work"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/auth.json"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/profiles/work/.credentials.json"
    git -C "$mirror" add -f -- auth.json profiles/work/.credentials.json
    printf 'allowed settings change\n' > "${HOME}/.claude/settings.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- auth.json profiles/work/.credentials.json)" || return 1
    assert_equals "" "$(git -C "$mirror" grep -l "$FAKE_TOKEN" HEAD -- . 2>/dev/null || true)" || return 1
    assert_equals "allowed settings change" "$(git -C "$mirror" show HEAD:settings.json)" || return 1
    assert_equals "$FAKE_TOKEN" "$(cat "${mirror}/auth.json")" || return 1
    assert_equals "$FAKE_TOKEN" "$(cat "${mirror}/profiles/work/.credentials.json")" || return 1
}

test_git_staging_keeps_legacy_credential_version() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude"
    commit_legacy_file "$mirror" "auth.json"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/auth.json"
    git -C "$mirror" add -f -- auth.json
    printf 'allowed settings change\n' > "${HOME}/.claude/settings.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "legacy auth.json" "$(git -C "$mirror" show HEAD:auth.json)" || return 1
    assert_equals "legacy auth.json" "$(git -C "$mirror" show :auth.json)" || return 1
    assert_equals "$FAKE_TOKEN" "$(cat "${mirror}/auth.json")" || return 1
    assert_equals "allowed settings change" "$(git -C "$mirror" show HEAD:settings.json)" || return 1
}

test_excluded_only_changes_create_no_commit() {
    create_codex_fixture
    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.codex" before
    commit_legacy_file "$mirror" "auth.json"
    before=$(git -C "$mirror" rev-parse HEAD)
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/auth.json"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/.credentials.json"
    git -C "$mirror" add -f -- auth.json .credentials.json

    run_asb backup codex
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "$before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
    assert_equals "legacy auth.json" "$(git -C "$mirror" show :auth.json)" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- .credentials.json)" || return 1
    assert_equals "$FAKE_TOKEN" "$(cat "${mirror}/auth.json")" || return 1
}

test_manual_backup_sanitizes_excluded_staging_without_committing() {
    create_claude_fixture
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude" before saved_settings
    commit_legacy_file "$mirror" 'auth.json'
    before=$(git -C "$mirror" rev-parse HEAD)
    saved_settings=$(git -C "$mirror" show HEAD:settings.json)
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/auth.json"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/.credentials.json"
    git -C "$mirror" add -f -- auth.json .credentials.json
    printf 'allowed settings staged for review\n' > "${HOME}/.claude/settings.json"
    export ASB_AUTO_COMMIT=false

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "$before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
    assert_equals "$saved_settings" "$(git -C "$mirror" show HEAD:settings.json)" || return 1
    assert_equals 'allowed settings staged for review' "$(git -C "$mirror" show :settings.json)" || return 1
    assert_equals 'legacy auth.json' "$(git -C "$mirror" show :auth.json)" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- .credentials.json)" || return 1
    assert_equals "$FAKE_TOKEN" "$(cat "${mirror}/auth.json")" || return 1
    assert_equals "$FAKE_TOKEN" "$(cat "${mirror}/.credentials.json")" || return 1
}

test_init_does_not_commit_preexisting_excluded_files() {
    create_claude_fixture
    local mirror="${ASB_BACKUP_ROOT}/.claude"
    mkdir -p "${mirror}/profiles/work"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/auth.json"
    printf '%s\n' "$FAKE_TOKEN" > "${mirror}/profiles/work/.credentials.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_exists "${mirror}/settings.json" || return 1
    assert_equals "" "$(git -C "$mirror" log --format=%H -- auth.json profiles/work/.credentials.json)" || return 1
    assert_equals "" "$(git -C "$mirror" ls-files -- auth.json profiles/work/.credentials.json)" || return 1
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

configure_literal_exclusions() {
    create_claude_fixture
    mkdir -p "${HOME}/.claude/profiles/work/private store" "${HOME}/.claude/profiles/personal" "${HOME}/.claude/private"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/private.token"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/profiles/work/private store/token.json"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/profiles/work/token[1]?.json"
    printf 'ordinary settings\n' > "${HOME}/.claude/profiles/work/settings.json"
    printf 'literal sibling\n' > "${HOME}/.claude/profiles/work/token1x.json"
    printf 'other profile\n' > "${HOME}/.claude/profiles/personal/private.token"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/private/token\store"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/private/token\[1]?.txt"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/private/token]store"
    printf 'plain sibling\n' > "${HOME}/.claude/private/tokenstore"
    printf 'glob sibling\n' > "${HOME}/.claude/private/token\1x.txt"
    printf 'bracket sibling\n' > "${HOME}/.claude/private/token[1]?.txt"
    printf 'closing bracket sibling\n' > "${HOME}/.claude/private/token]]store"
    export ASB_EXCLUDE_PATHS=$'private.token\nprofiles/work/private store/\nprofiles/work/token[1]?.json\nprivate/token\\store\nprivate/token\\[1]?.txt\nprivate/token]store'
}

assert_literal_exclusions() {
    local mirror="${ASB_BACKUP_ROOT}/.claude"
    assert_file_not_exists "${mirror}/private.token" || return 1
    assert_dir_not_exists "${mirror}/profiles/work/private store" || return 1
    assert_file_not_exists "${mirror}/profiles/work/token[1]?.json" || return 1
    assert_equals "ordinary settings" "$(cat "${mirror}/profiles/work/settings.json")" || return 1
    assert_equals "literal sibling" "$(cat "${mirror}/profiles/work/token1x.json")" || return 1
    assert_equals "other profile" "$(cat "${mirror}/profiles/personal/private.token")" || return 1
    assert_file_not_exists "${mirror}/private/token\store" || return 1
    assert_file_not_exists "${mirror}/private/token\[1]?.txt" || return 1
    assert_file_not_exists "${mirror}/private/token]store" || return 1
    assert_equals "plain sibling" "$(cat "${mirror}/private/tokenstore")" || return 1
    assert_equals "glob sibling" "$(cat "${mirror}/private/token\1x.txt")" || return 1
    assert_equals "bracket sibling" "$(cat "${mirror}/private/token[1]?.txt")" || return 1
    assert_equals "closing bracket sibling" "$(cat "${mirror}/private/token]]store")" || return 1
    assert_equals "" "$(git -C "$mirror" grep -l "$FAKE_TOKEN" HEAD -- . 2>/dev/null || true)" || return 1
}

test_configured_paths_are_literal_and_root_relative() {
    skip_if_missing rsync "rsync is required to verify the rsync exclusion path" || return 2
    configure_literal_exclusions
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "falling back to cp" || return 1
    assert_literal_exclusions || return 1
}

test_cp_fallback_respects_configured_paths() {
    configure_literal_exclusions
    use_failing_rsync
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_literal_exclusions || return 1
}

test_configured_paths_apply_to_builtin_and_custom_agents() {
    create_claude_fixture
    create_codex_fixture
    local profile=".local/share/accounts/work"
    mkdir -p "${HOME}/${profile}/private vault" "${XDG_CONFIG_HOME}/asb"
    printf 'work settings\n' > "${HOME}/${profile}/settings.json"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/${profile}/private vault/token.json"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/${profile}/shared.private"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/claude.private"
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/shared.private"
    printf 'ordinary codex value\n' > "${HOME}/.codex/claude.private"
    printf 'work=%s\n' "$profile" > "${XDG_CONFIG_HOME}/asb/custom_agents"
    cat > "${XDG_CONFIG_HOME}/asb/config" <<'EOF'
ASB_EXCLUDE_PATHS='shared.private'
ASB_AGENT_EXCLUDE_PATHS[claude]='claude.private'
ASB_AGENT_EXCLUDE_PATHS[work]='private vault/'
EOF

    run_asb backup claude codex work
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/.claude/shared.private" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/.claude/claude.private" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/${profile}/shared.private" || return 1
    assert_dir_not_exists "${ASB_BACKUP_ROOT}/${profile}/private vault" || return 1
    assert_equals 'ordinary codex value' "$(cat "${ASB_BACKUP_ROOT}/.codex/claude.private")" || return 1
    assert_equals 'work settings' "$(cat "${ASB_BACKUP_ROOT}/${profile}/settings.json")" || return 1
}

test_configured_paths_survive_credentials_opt_in() {
    setup_agents_with_credentials
    export ASB_INCLUDE_CREDENTIALS=true
    export ASB_EXCLUDE_PATHS='.credentials.json'

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_file_not_exists "${ASB_BACKUP_ROOT}/.claude/.credentials.json" || return 1
    assert_file_exists "${ASB_BACKUP_ROOT}/.claude/profiles/work/.credentials.json" || return 1
}

test_invalid_exclusions_fail_before_backup_changes() {
    create_claude_fixture
    local invalid
    for invalid in /absolute ../escape ./private.token secrets/../token secrets//token secrets/./token .git/config profiles/.git/token .gitignore; do
        export ASB_EXCLUDE_PATHS="$invalid"
        run_asb backup claude || true
        assert_not_equals 0 "$ASB_LAST_STATUS" || return 1
        assert_dir_not_exists "${ASB_BACKUP_ROOT}/.claude" || return 1
    done
}

test_diff_never_copies_excluded_credentials() {
    setup_agents_with_credentials
    printf '%s\n' "$FAKE_TOKEN" > "${HOME}/.claude/profiles/work/private.token"
    export ASB_EXCLUDE_PATHS='profiles/work/private.token'
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    printf 'changed settings\n' > "${HOME}/.claude/settings.json"
    watch_credential_copies

    run_asb diff claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "" "$(cat "$ASB_TEST_COPIED_CREDENTIALS")" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "$FAKE_TOKEN" || return 1
}

test_dry_run_with_configured_paths_is_read_only() {
    configure_literal_exclusions
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude" before
    before=$(git -C "$mirror" rev-parse HEAD)
    printf 'changed settings\n' > "${HOME}/.claude/settings.json"
    use_failing_rsync

    run_asb --dry-run backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_not_contains "$ASB_LAST_OUTPUT" "$FAKE_TOKEN" || return 1
    assert_equals "$before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
    assert_equals "" "$(git -C "$mirror" status --porcelain)" || return 1
    assert_literal_exclusions || return 1
}

test_dry_run_restore_never_extracts_legacy_credentials() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude" before
    commit_legacy_file "$mirror" "profiles/work/.credentials.json"
    before=$(git -C "$mirror" rev-parse HEAD)
    printf 'changed settings\n' > "${HOME}/.claude/settings.json"
    watch_credential_archives

    run_asb --dry-run restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "" "$(cat "$ASB_TEST_EXTRACTED_CREDENTIALS")" || return 1
    assert_equals "$before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
    assert_equals "" "$(git -C "$mirror" status --porcelain)" || return 1
    assert_equals "changed settings" "$(cat "${HOME}/.claude/settings.json")" || return 1
}

exercise_restore_configured_paths() {
    local fallback="$1"
    configure_literal_exclusions
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude"
    commit_legacy_file "$mirror" 'profiles/work/private store/token.json'
    commit_legacy_file "$mirror" 'profiles/work/token[1]?.json'
    printf 'rotated private token\n' > "${HOME}/.claude/profiles/work/private store/token.json"
    printf 'rotated literal token\n' > "${HOME}/.claude/profiles/work/token[1]?.json"
    printf 'changed settings\n' > "${HOME}/.claude/profiles/work/settings.json"
    printf 'obsolete setting\n' > "${HOME}/.claude/profiles/work/stale.json"
    [[ "$fallback" == true ]] && use_failing_rsync

    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "ordinary settings" "$(cat "${HOME}/.claude/profiles/work/settings.json")" || return 1
    assert_equals "rotated private token" "$(cat "${HOME}/.claude/profiles/work/private store/token.json")" || return 1
    assert_equals "rotated literal token" "$(cat "${HOME}/.claude/profiles/work/token[1]?.json")" || return 1
    assert_file_not_exists "${HOME}/.claude/profiles/work/stale.json" || return 1
}

test_restore_respects_configured_paths() {
    exercise_restore_configured_paths false
}

test_cp_restore_respects_configured_paths() {
    exercise_restore_configured_paths true
}

test_cp_restore_does_not_follow_nested_destination_symlink() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local outside="${TEST_ENV_ROOT}/outside-settings"
    printf 'outside must survive\n' > "$outside"
    mv "${HOME}/.claude/profiles/work/settings.json" "${TEST_ENV_ROOT}/saved-settings"
    ln -s "$outside" "${HOME}/.claude/profiles/work/settings.json"
    printf 'changed settings\n' > "${HOME}/.claude/settings.json"
    use_failing_rsync

    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals 'outside must survive' "$(cat "$outside")" || return 1
    [[ ! -L "${HOME}/.claude/profiles/work/settings.json" ]] || return 1
    assert_equals '{"model":"work"}' "$(cat "${HOME}/.claude/profiles/work/settings.json")" || return 1
    assert_file_exists "${HOME}/.claude/profiles/work/.credentials.json" || return 1
}

test_cp_backup_failure_preserves_previous_snapshot() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    local mirror="${ASB_BACKUP_ROOT}/.claude" before saved_settings
    before=$(git -C "$mirror" rev-parse HEAD)
    saved_settings=$(cat "${mirror}/settings.json")
    printf 'new live settings\n' > "${HOME}/.claude/settings.json"
    use_failing_rsync
    use_failing_copy

    run_asb backup claude || true
    assert_not_equals 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "$before" "$(git -C "$mirror" rev-parse HEAD)" || return 1
    assert_equals "$saved_settings" "$(cat "${mirror}/settings.json")" || return 1
    assert_equals "" "$(git -C "$mirror" status --porcelain)" || return 1
}

test_cp_restore_failure_preserves_live_settings() {
    setup_agents_with_credentials
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    printf 'new live settings\n' > "${HOME}/.claude/settings.json"
    printf 'rotated live credential\n' > "${HOME}/.claude/.credentials.json"
    use_failing_rsync
    use_failing_copy

    run_asb --force restore claude || true
    assert_not_equals 0 "$ASB_LAST_STATUS" || return 1
    assert_equals 'new live settings' "$(cat "${HOME}/.claude/settings.json")" || return 1
    assert_equals 'rotated live credential' "$(cat "${HOME}/.claude/.credentials.json")" || return 1
}

test_restore_ignores_export_attributes_and_preserves_backup_index() {
    create_claude_fixture
    # shellcheck disable=SC2016 # Git's archive placeholder must remain literal.
    local marker='literal $Format:%H$' saved_settings mirror before
    saved_settings=$(cat "${HOME}/.claude/settings.json")
    printf '%s\n' "$marker" > "${HOME}/.claude/config.json"
    cat > "${HOME}/.claude/.gitattributes" <<'EOF'
settings.json export-ignore
config.json export-subst
EOF
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    mirror="${ASB_BACKUP_ROOT}/.claude"
    # Existing staged work in the mirror belongs to the operator. Restore
    # must read the requested commit without checking it out over that work.
    printf 'staged backup edit\n' > "${mirror}/config.json"
    git -C "$mirror" add -- config.json
    before=$(git -C "$mirror" status --porcelain)
    printf 'changed live settings\n' > "${HOME}/.claude/settings.json"
    printf 'changed live config\n' > "${HOME}/.claude/config.json"

    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS" || return 1
    assert_equals "$saved_settings" "$(cat "${HOME}/.claude/settings.json")" || return 1
    assert_equals "$marker" "$(cat "${HOME}/.claude/config.json")" || return 1
    assert_equals "$before" "$(git -C "$mirror" status --porcelain)" || return 1
    assert_equals 'staged backup edit' "$(cat "${mirror}/config.json")" || return 1
    assert_equals 'staged backup edit' "$(git -C "$mirror" show :config.json)" || return 1
}

use_failing_rsync() {
    local bin="${TEST_ENV_ROOT}/fakebin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexit 1\n' > "${bin}/rsync"
    chmod +x "${bin}/rsync"
    export PATH="${bin}:${PATH}"
}

use_missing_rsync() {
    local bin="${TEST_ENV_ROOT}/without-rsync-bin" cmd executable
    mkdir -p "$bin"
    # Keep the commands used by asb, Git, and these assertions; deliberately
    # provide no rsync entry, so command discovery takes the absent-tool path.
    for cmd in awk bash basename cat chmod cmp cp cut date dirname du env find \
        flock git grep head id ln mkdir mktemp mv perl readlink realpath rm \
        rmdir sed sh sleep sort tail tar tr uname wc; do
        executable=$(command -v "$cmd") || continue
        ln -s "$executable" "${bin}/${cmd}"
    done
    export PATH="$bin"
}

use_failing_copy() {
    local bin="${TEST_ENV_ROOT}/failing-copy-bin"
    mkdir -p "$bin"
    ASB_TEST_REAL_CP=$(command -v cp)
    export ASB_TEST_REAL_CP
    cat > "${bin}/cp" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
for path in "$@"; do
    [[ "${path##*/}" == settings.json ]] && exit 47
done
exec "$ASB_TEST_REAL_CP" "$@"
EOF
    chmod +x "${bin}/cp"
    export PATH="${bin}:${PATH}"
}

# Observe every cp source before it is copied. Checking only the completed
# backup would miss a recursive copy that briefly writes credentials and
# deletes them afterwards. The guard records filenames only.
watch_credential_copies() {
    local bin="${TEST_ENV_ROOT}/copy-watch-bin"
    mkdir -p "$bin"
    ASB_TEST_REAL_CP=$(command -v cp)
    ASB_TEST_COPIED_CREDENTIALS="${TEST_ENV_ROOT}/copied-credentials"
    export ASB_TEST_REAL_CP ASB_TEST_COPIED_CREDENTIALS
    : > "$ASB_TEST_COPIED_CREDENTIALS"
    cat > "${bin}/cp" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
args=("$@")
for ((i = 0; i + 1 < ${#args[@]}; i++)); do
    path="${args[$i]}"
    [[ "$path" == -* ]] && continue
    [[ -L "$path" ]] && continue
    if [[ -d "$path" ]]; then
        find "$path" -type f \( -name .credentials.json -o -name auth.json \
            -o -name oauth_creds.json -o -name mcp-oauth-tokens.json \
            -o -name .env -o -name '*.keychain-db' -o -name private.token \) \
            -print >> "$ASB_TEST_COPIED_CREDENTIALS"
    elif [[ -f "$path" ]]; then
        case "${path##*/}" in
            .credentials.json|auth.json|oauth_creds.json|mcp-oauth-tokens.json|.env|*.keychain-db|private.token)
                printf '%s\n' "$path" >> "$ASB_TEST_COPIED_CREDENTIALS" ;;
        esac
    fi
done
exec "$ASB_TEST_REAL_CP" "$@"
EOF
    chmod +x "${bin}/cp"
    export PATH="${bin}:${PATH}"
}

watch_credential_archives() {
    local bin="${TEST_ENV_ROOT}/archive-watch-bin"
    mkdir -p "$bin"
    ASB_TEST_REAL_TAR=$(command -v tar)
    ASB_TEST_EXTRACTED_CREDENTIALS="${TEST_ENV_ROOT}/extracted-credentials"
    export ASB_TEST_REAL_TAR ASB_TEST_EXTRACTED_CREDENTIALS
    : > "$ASB_TEST_EXTRACTED_CREDENTIALS"
    cat > "${bin}/tar" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
args=("$@")
dest=''
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
        -C|--directory) dest="${args[$((i + 1))]}" ;;
        --directory=*) dest="${args[$i]#--directory=}" ;;
    esac
done
"$ASB_TEST_REAL_TAR" "$@"
status=$?
if [[ -n "$dest" && -d "$dest" ]]; then
    find "$dest" -type f \( -name .credentials.json -o -name auth.json -o -name private.token \) \
        -print >> "$ASB_TEST_EXTRACTED_CREDENTIALS"
fi
exit "$status"
EOF
    chmod +x "${bin}/tar"
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
run_test "backup_without_rsync_excludes_credentials" test_backup_without_rsync_excludes_credentials
run_test "dry_run_lists_left_out_credentials" test_dry_run_lists_left_out_credentials
run_test "include_credentials_env_opt_in" test_include_credentials_env_opt_in
run_test "include_credentials_config_opt_in" test_include_credentials_config_opt_in
run_test "restore_keeps_live_credentials" test_restore_keeps_live_credentials
run_test "restore_ignores_credentials_an_earlier_backup_holds" test_restore_ignores_credentials_an_earlier_backup_holds
run_test "cp_fallback_restore_keeps_live_credentials" test_cp_fallback_restore_keeps_live_credentials
run_test "cp_fallback_keeps_legacy_excluded_backup_files" test_cp_fallback_keeps_legacy_excluded_backup_files
run_test "git_staging_ignores_new_excluded_files" test_git_staging_ignores_new_excluded_files
run_test "git_staging_keeps_legacy_credential_version" test_git_staging_keeps_legacy_credential_version
run_test "excluded_only_changes_create_no_commit" test_excluded_only_changes_create_no_commit
run_test "manual_backup_sanitizes_excluded_staging_without_committing" test_manual_backup_sanitizes_excluded_staging_without_committing
run_test "init_does_not_commit_preexisting_excluded_files" test_init_does_not_commit_preexisting_excluded_files
run_test "backup_warns_about_tracked_credentials_and_prune_removes_them" test_backup_warns_about_tracked_credentials_and_prune_removes_them
run_test "custom_agent_leaves_out_credentials" test_custom_agent_leaves_out_credentials
run_test "configured_paths_are_literal_and_root_relative" test_configured_paths_are_literal_and_root_relative
run_test "cp_fallback_respects_configured_paths" test_cp_fallback_respects_configured_paths
run_test "configured_paths_apply_to_builtin_and_custom_agents" test_configured_paths_apply_to_builtin_and_custom_agents
run_test "configured_paths_survive_credentials_opt_in" test_configured_paths_survive_credentials_opt_in
run_test "invalid_exclusions_fail_before_backup_changes" test_invalid_exclusions_fail_before_backup_changes
run_test "diff_never_copies_excluded_credentials" test_diff_never_copies_excluded_credentials
run_test "dry_run_with_configured_paths_is_read_only" test_dry_run_with_configured_paths_is_read_only
run_test "dry_run_restore_never_extracts_legacy_credentials" test_dry_run_restore_never_extracts_legacy_credentials
run_test "restore_respects_configured_paths" test_restore_respects_configured_paths
run_test "cp_restore_respects_configured_paths" test_cp_restore_respects_configured_paths
run_test "cp_restore_does_not_follow_nested_destination_symlink" test_cp_restore_does_not_follow_nested_destination_symlink
run_test "cp_backup_failure_preserves_previous_snapshot" test_cp_backup_failure_preserves_previous_snapshot
run_test "cp_restore_failure_preserves_live_settings" test_cp_restore_failure_preserves_live_settings
run_test "restore_ignores_export_attributes_and_preserves_backup_index" test_restore_ignores_export_attributes_and_preserves_backup_index

finish_suite
