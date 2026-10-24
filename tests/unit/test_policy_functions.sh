#!/usr/bin/env bash
#
# Unit Tests: backup exclusion policy helpers
# asb_is_excluded_name, asb_holds_nested_exclusion, asb_excluded_pathspecs,
# asb_strip_excluded, the credential rules (asb_build_shared_policy,
# asb_holds_credentials, asb_list_skipped_credentials) and the derived
# ASB_RSYNC_EXCLUDES / ASB_DIFF_EXCLUDES
#

test_excluded_name_matches_dirs_and_globs() {
    assert_function_succeeds asb_is_excluded_name "sessions" || return 1
    assert_function_succeeds asb_is_excluded_name "db-backups" || return 1
    assert_function_succeeds asb_is_excluded_name "thread_history_1.sqlite" || return 1
    assert_function_succeeds asb_is_excluded_name "logs_2.sqlite" || return 1
    assert_function_succeeds asb_is_excluded_name "state_5.sqlite-wal" || return 1
    assert_function_succeeds asb_is_excluded_name "debug.log" || return 1
}

test_excluded_name_keeps_settings() {
    assert_function_fails asb_is_excluded_name "settings.json" || return 1
    assert_function_fails asb_is_excluded_name "state_5.sqlite" || return 1
    assert_function_fails asb_is_excluded_name "memories_1.sqlite" || return 1
    assert_function_fails asb_is_excluded_name "antigravity-cli" || return 1
}

test_holds_nested_exclusion() {
    assert_function_succeeds asb_holds_nested_exclusion "antigravity-cli" || return 1
    assert_function_fails asb_holds_nested_exclusion "skills" || return 1
    assert_function_fails asb_holds_nested_exclusion "conversations" || return 1
}

test_rsync_excludes_derived_from_policy() {
    local joined=" ${ASB_RSYNC_EXCLUDES[*]} "
    assert_contains "$joined" " --exclude=.git " || return 1
    assert_contains "$joined" " --exclude=sessions/ " || return 1
    assert_contains "$joined" " --exclude=thread_history_*.sqlite " || return 1
    assert_contains "$joined" " --exclude=*.sqlite-wal " || return 1
    assert_contains "$joined" " --exclude=/antigravity-cli/conversations/ " || return 1
}

test_diff_excludes_skip_nested_rules() {
    local joined=" ${ASB_DIFF_EXCLUDES[*]} "
    assert_contains "$joined" " --exclude=sessions " || return 1
    assert_contains "$joined" " --exclude=logs_*.sqlite " || return 1
    # Nested rules are anchored; diff would apply a base name everywhere.
    assert_not_contains "$joined" " --exclude=conversations " || return 1
    assert_not_contains "$joined" " --exclude=brain " || return 1
}

test_pathspecs_select_excluded_tracked_files() {
    local repo="${TEST_ENV_ROOT}/pathspec_repo"
    mkdir -p "$repo/sub/sessions" "$repo/antigravity-cli/brain/x" "$repo/antigravity-cli/skills"
    git -C "$repo" init -q
    printf 'a\n' > "$repo/settings.json"
    printf 'a\n' > "$repo/thread_history_1.sqlite"
    printf 'a\n' > "$repo/sub/sessions/s.jsonl"
    printf 'a\n' > "$repo/antigravity-cli/brain/x/t.jsonl"
    printf 'a\n' > "$repo/antigravity-cli/skills/k.md"
    git -C "$repo" add -A >/dev/null 2>&1

    asb_excluded_pathspecs
    local got
    got=$(git -C "$repo" ls-files -- "${ASB_PRUNE_PATHSPECS[@]}" | sort | tr '\n' ' ')
    assert_equals "antigravity-cli/brain/x/t.jsonl sub/sessions/s.jsonl thread_history_1.sqlite " "$got" || return 1
}

test_strip_excluded_matches_rsync_policy() {
    local dir="${TEST_ENV_ROOT}/strip_test"
    mkdir -p "$dir/.git/logs" "$dir/a/cache" "$dir/antigravity-cli/conversations" "$dir/keep"
    printf 'x\n' > "$dir/.git/logs/HEAD.log"
    printf 'x\n' > "$dir/a/cache/blob"
    printf 'x\n' > "$dir/a/run.log"
    printf 'x\n' > "$dir/antigravity-cli/conversations/c.db"
    printf 'x\n' > "$dir/antigravity-cli/settings.json"
    printf 'x\n' > "$dir/keep/config.toml"

    asb_strip_excluded "$dir"

    assert_file_exists "$dir/.git/logs/HEAD.log" || return 1
    assert_dir_not_exists "$dir/a/cache" || return 1
    assert_file_not_exists "$dir/a/run.log" || return 1
    assert_dir_not_exists "$dir/antigravity-cli/conversations" || return 1
    assert_file_exists "$dir/antigravity-cli/settings.json" || return 1
    assert_file_exists "$dir/keep/config.toml" || return 1
}

test_strip_excluded_does_not_follow_symlinks() {
    local dir="${TEST_ENV_ROOT}/strip_link" outside="${TEST_ENV_ROOT}/strip_outside"
    mkdir -p "$dir" "${outside}/conversations" "${outside}/brain"
    printf 'live\n' > "${outside}/conversations/c.db"
    printf 'live\n' > "${outside}/brain/t.jsonl"
    ln -s "$outside" "$dir/antigravity-cli"

    asb_strip_excluded "$dir"

    assert_file_exists "${outside}/conversations/c.db" || return 1
    assert_file_exists "${outside}/brain/t.jsonl" || return 1
    [[ -L "$dir/antigravity-cli" ]] || return 1
}

test_filter_nested_diff_is_anchored() {
    local a="/x/live" b="/x/backup" got
    got=$(printf '%s\n' \
        "Only in ${a}/antigravity-cli: conversations" \
        "Only in ${a}/antigravity-cli/brain: t.jsonl" \
        "Files ${a}/antigravity-cli/conversations/c.db and ${b}/antigravity-cli/conversations/c.db differ" \
        "Files ${a}/tools/conversations/p.md and ${b}/tools/conversations/p.md differ" \
        "Only in ${b}/tools: brain" \
        "Files ${a}/antigravity-cli/settings.json and ${b}/antigravity-cli/settings.json differ" \
        | asb_filter_nested_diff "$a" "$b")
    assert_equals "Files ${a}/tools/conversations/p.md and ${b}/tools/conversations/p.md differ
Only in ${b}/tools: brain
Files ${a}/antigravity-cli/settings.json and ${b}/antigravity-cli/settings.json differ" "$got" || return 1
}

test_excluded_name_matches_credentials() {
    assert_function_succeeds asb_is_excluded_name ".credentials.json" || return 1
    assert_function_succeeds asb_is_excluded_name "auth.json" || return 1
    assert_function_succeeds asb_is_excluded_name "oauth_creds.json" || return 1
    assert_function_succeeds asb_is_excluded_name "mcp-oauth-tokens.json" || return 1
    assert_function_succeeds asb_is_excluded_name ".env" || return 1
    assert_function_succeeds asb_is_excluded_name "login.keychain-db" || return 1
    assert_function_fails asb_is_excluded_name "auth.json.example" || return 1
    assert_function_fails asb_is_excluded_name ".env.example" || return 1
    assert_function_fails asb_is_excluded_name "credentials.md" || return 1
    local joined=" ${ASB_RSYNC_EXCLUDES[*]} ${ASB_DIFF_EXCLUDES[*]} "
    assert_contains "$joined" " --exclude=.credentials.json " || return 1
    assert_contains "$joined" " --exclude=auth.json " || return 1
}

test_include_credentials_opts_out_of_credential_rules_only() {
    ASB_INCLUDE_CREDENTIALS=true
    asb_build_shared_policy
    asb_use_policy
    assert_function_fails asb_is_excluded_name ".credentials.json" || return 1
    assert_function_fails asb_is_excluded_name "auth.json" || return 1
    assert_function_succeeds asb_is_excluded_name "debug.log" || return 1
    assert_function_succeeds asb_is_excluded_name "sessions" || return 1
    local joined=" ${ASB_RSYNC_EXCLUDES[*]} "
    assert_not_contains "$joined" " --exclude=auth.json " || return 1
    assert_contains "$joined" " --exclude=*.log " || return 1
}

test_holds_credentials() {
    local dir="${TEST_ENV_ROOT}/holds" outside="${TEST_ENV_ROOT}/holds_outside"
    mkdir -p "$dir/profiles/work" "$dir/skills" "$outside"
    printf 'x\n' > "$dir/profiles/work/.credentials.json"
    printf 'x\n' > "$dir/skills/SKILL.md"
    printf 'x\n' > "$outside/auth.json"
    ln -s "$outside" "$dir/linked"
    assert_function_succeeds asb_holds_credentials "$dir/profiles" || return 1
    assert_function_fails asb_holds_credentials "$dir/skills" || return 1
    assert_function_fails asb_holds_credentials "$dir/profiles/work/.credentials.json" || return 1
    # Not followed: nothing behind a link is restored over or deleted.
    assert_function_fails asb_holds_credentials "$dir/linked" || return 1
    ASB_INCLUDE_CREDENTIALS=true
    assert_function_fails asb_holds_credentials "$dir/profiles" || return 1
}

test_list_skipped_credentials_skips_excluded_data_dirs() {
    local dir="${TEST_ENV_ROOT}/skipped"
    mkdir -p "$dir/profiles/work" "$dir/sessions/a" "$dir/.git"
    printf 'x\n' > "$dir/.credentials.json"
    printf 'x\n' > "$dir/profiles/work/auth.json"
    printf 'x\n' > "$dir/sessions/a/auth.json"
    printf 'x\n' > "$dir/.git/auth.json"
    printf 'x\n' > "$dir/settings.json"
    assert_equals ".credentials.json
profiles/work/auth.json" "$(asb_list_skipped_credentials "$dir")" || return 1
    ASB_INCLUDE_CREDENTIALS=true
    assert_equals "" "$(asb_list_skipped_credentials "$dir")" || return 1
}

run_unit_test "excluded_name_matches_dirs_and_globs" test_excluded_name_matches_dirs_and_globs
run_unit_test "excluded_name_matches_credentials" test_excluded_name_matches_credentials
run_unit_test "include_credentials_opts_out_of_credential_rules_only" test_include_credentials_opts_out_of_credential_rules_only
run_unit_test "holds_credentials" test_holds_credentials
run_unit_test "list_skipped_credentials_skips_excluded_data_dirs" test_list_skipped_credentials_skips_excluded_data_dirs
run_unit_test "excluded_name_keeps_settings" test_excluded_name_keeps_settings
run_unit_test "holds_nested_exclusion" test_holds_nested_exclusion
run_unit_test "rsync_excludes_derived_from_policy" test_rsync_excludes_derived_from_policy
run_unit_test "diff_excludes_skip_nested_rules" test_diff_excludes_skip_nested_rules
run_unit_test "pathspecs_select_excluded_tracked_files" test_pathspecs_select_excluded_tracked_files
run_unit_test "strip_excluded_matches_rsync_policy" test_strip_excluded_matches_rsync_policy
run_unit_test "strip_excluded_does_not_follow_symlinks" test_strip_excluded_does_not_follow_symlinks
run_unit_test "filter_nested_diff_is_anchored" test_filter_nested_diff_is_anchored
