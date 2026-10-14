#!/usr/bin/env bash
#
# Unit Tests: backup exclusion policy helpers
# asb_is_excluded_name, asb_holds_nested_exclusion, asb_excluded_pathspecs,
# asb_strip_excluded and the derived ASB_RSYNC_EXCLUDES / ASB_DIFF_EXCLUDES
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

test_diff_excludes_use_base_names() {
    local joined=" ${ASB_DIFF_EXCLUDES[*]} "
    assert_contains "$joined" " --exclude=sessions " || return 1
    assert_contains "$joined" " --exclude=conversations " || return 1
    assert_contains "$joined" " --exclude=logs_*.sqlite " || return 1
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

run_unit_test "excluded_name_matches_dirs_and_globs" test_excluded_name_matches_dirs_and_globs
run_unit_test "excluded_name_keeps_settings" test_excluded_name_keeps_settings
run_unit_test "holds_nested_exclusion" test_holds_nested_exclusion
run_unit_test "rsync_excludes_derived_from_policy" test_rsync_excludes_derived_from_policy
run_unit_test "diff_excludes_use_base_names" test_diff_excludes_use_base_names
run_unit_test "pathspecs_select_excluded_tracked_files" test_pathspecs_select_excluded_tracked_files
run_unit_test "strip_excluded_matches_rsync_policy" test_strip_excluded_matches_rsync_policy
