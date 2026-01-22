#!/usr/bin/env bash
#
# Unit Tests: Logging Functions
# Tests log_info, log_warn, log_error, log_success, log_step, log_debug
#

# Test log_info outputs to stderr with correct prefix
test_log_info_output() {
    local output
    output=$(log_info "test message" 2>&1)

    assert_contains "$output" "test message" || return 1
    # Should have some indicator (color codes or INFO text depending on terminal)
}

# Test log_warn outputs warning message
test_log_warn_output() {
    local output
    output=$(log_warn "warning message" 2>&1)

    assert_contains "$output" "warning message" || return 1
}

# Test log_error outputs error message
test_log_error_output() {
    local output
    output=$(log_error "error message" 2>&1)

    assert_contains "$output" "error message" || return 1
}

# Test log_success outputs with checkmark or success indicator
test_log_success_output() {
    local output
    output=$(log_success "success message" 2>&1)

    assert_contains "$output" "success message" || return 1
}

# Test log_step outputs step message
test_log_step_output() {
    local output
    output=$(log_step "step message" 2>&1)

    assert_contains "$output" "step message" || return 1
}

# Test log_debug only outputs when ASB_VERBOSE=true
test_log_debug_silent_by_default() {
    local output
    unset ASB_VERBOSE
    output=$(log_debug "debug message" 2>&1)

    # Should be empty or not contain the message
    if [[ "$output" == *"debug message"* ]]; then
        echo "log_debug should not output when ASB_VERBOSE is unset" >&2
        return 1
    fi
}

# Test log_debug outputs when ASB_VERBOSE=true
test_log_debug_verbose_mode() {
    local output
    ASB_VERBOSE=true
    output=$(log_debug "debug message" 2>&1)
    unset ASB_VERBOSE

    assert_contains "$output" "debug message" || return 1
}

# Test NO_COLOR disables colors
test_no_color_mode() {
    local output
    export NO_COLOR=1
    output=$(log_info "test" 2>&1)
    unset NO_COLOR

    # Should not contain ANSI escape codes
    if [[ "$output" == *$'\033'* ]] || [[ "$output" == *$'\e'* ]]; then
        echo "NO_COLOR should disable ANSI color codes" >&2
        return 1
    fi
}

# Test logging doesn't crash on empty message
test_log_empty_message() {
    log_info "" 2>/dev/null || true
    log_warn "" 2>/dev/null || true
    log_error "" 2>/dev/null || true
    # If we get here without crashing, test passes
}

# Test logging handles special characters
test_log_special_characters() {
    local output
    output=$(log_info 'Message with "quotes" and $variables and `backticks`' 2>&1)
    assert_contains "$output" "quotes" || return 1
}

# Test log functions write only to stderr
test_log_info_stderr_only() {
    local stdout stderr
    stdout=$(capture_stdout log_info "stderr test")
    stderr=$(capture_stderr log_info "stderr test")

    assert_equals "" "$stdout" || return 1
    assert_contains "$stderr" "stderr test" || return 1
}

test_log_warn_stderr_only() {
    local stdout stderr
    stdout=$(capture_stdout log_warn "stderr test")
    stderr=$(capture_stderr log_warn "stderr test")

    assert_equals "" "$stdout" || return 1
    assert_contains "$stderr" "stderr test" || return 1
}

test_log_error_stderr_only() {
    local stdout stderr
    stdout=$(capture_stdout log_error "stderr test")
    stderr=$(capture_stderr log_error "stderr test")

    assert_equals "" "$stdout" || return 1
    assert_contains "$stderr" "stderr test" || return 1
}

test_log_success_stderr_only() {
    local stdout stderr
    stdout=$(capture_stdout log_success "stderr test")
    stderr=$(capture_stderr log_success "stderr test")

    assert_equals "" "$stdout" || return 1
    assert_contains "$stderr" "stderr test" || return 1
}

test_log_step_stderr_only() {
    local stdout stderr
    stdout=$(capture_stdout log_step "stderr test")
    stderr=$(capture_stderr log_step "stderr test")

    assert_equals "" "$stdout" || return 1
    assert_contains "$stderr" "stderr test" || return 1
}

# Test non-TTY output does not include ANSI codes
test_no_color_non_tty() {
    local output
    output=$(bash -c 'ASB_SOURCED=true source "'"$REPO_ROOT"'/asb"; log_info "test"' 2>&1)

    if [[ "$output" == *$'\033'* ]] || [[ "$output" == *$'\e'* ]]; then
        echo "Non-TTY output should not include ANSI color codes" >&2
        return 1
    fi
}

# Run all tests
run_unit_test "log_info_output" test_log_info_output
run_unit_test "log_warn_output" test_log_warn_output
run_unit_test "log_error_output" test_log_error_output
run_unit_test "log_success_output" test_log_success_output
run_unit_test "log_step_output" test_log_step_output
run_unit_test "log_debug_silent_by_default" test_log_debug_silent_by_default
run_unit_test "log_debug_verbose_mode" test_log_debug_verbose_mode
run_unit_test "no_color_mode" test_no_color_mode
run_unit_test "log_empty_message" test_log_empty_message
run_unit_test "log_special_characters" test_log_special_characters
run_unit_test "log_info_stderr_only" test_log_info_stderr_only
run_unit_test "log_warn_stderr_only" test_log_warn_stderr_only
run_unit_test "log_error_stderr_only" test_log_error_stderr_only
run_unit_test "log_success_stderr_only" test_log_success_stderr_only
run_unit_test "log_step_stderr_only" test_log_step_stderr_only
run_unit_test "no_color_non_tty" test_no_color_non_tty
