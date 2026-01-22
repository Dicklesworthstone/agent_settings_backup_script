#!/usr/bin/env bash
#
# Unit Tests: agent_exists Function
# Tests agent validation logic
#

# Test known agents return success
test_known_agent_claude() {
    assert_function_succeeds agent_exists "claude" || return 1
}

test_known_agent_codex() {
    assert_function_succeeds agent_exists "codex" || return 1
}

test_known_agent_cursor() {
    assert_function_succeeds agent_exists "cursor" || return 1
}

test_known_agent_gemini() {
    assert_function_succeeds agent_exists "gemini" || return 1
}

test_known_agent_aider() {
    assert_function_succeeds agent_exists "aider" || return 1
}

# Test unknown agents return failure
test_unknown_agent() {
    assert_function_fails agent_exists "unknownagent123" || return 1
}

test_unknown_agent_similar_name() {
    # Similar to claude but not exact
    assert_function_fails agent_exists "claudecode" || return 1
}

# Test case sensitivity
test_case_sensitivity_uppercase() {
    # Should fail - agent names are lowercase
    assert_function_fails agent_exists "Claude" || return 1
}

test_case_sensitivity_mixed() {
    assert_function_fails agent_exists "CURSOR" || return 1
}

# Test empty string - should not match any agent
test_empty_string() {
    # Use set +e to prevent script exit on command failure
    set +e
    agent_exists ""
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]]; then
        echo "Empty string should not match a real agent (got exit code 0)" >&2
        return 1
    fi
    return 0
}

# Test special characters
test_special_characters() {
    assert_function_fails agent_exists "claude!" || return 1
    assert_function_fails agent_exists "agent@name" || return 1
    assert_function_fails agent_exists "agent name" || return 1
}

# Test custom agents loaded from config
test_custom_agent_loaded() {
    local custom_file="${XDG_CONFIG_HOME}/asb/custom_agents"
    mkdir -p "${XDG_CONFIG_HOME}/asb"
    echo "myagent=.myagent" > "$custom_file"

    load_custom_agents

    assert_function_succeeds agent_exists "myagent" || return 1
}

# Test all primary agents exist
test_all_primary_agents() {
    local agents=("claude" "codex" "cursor" "gemini" "cline" "amp" "aider" "opencode" "factory" "windsurf" "plandex" "qwencode" "amazonq")
    local failed=()

    for agent in "${agents[@]}"; do
        if ! agent_exists "$agent" 2>/dev/null; then
            failed+=("$agent")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "These agents should exist but don't: ${failed[*]}" >&2
        return 1
    fi
}

# Run all tests
run_unit_test "known_agent_claude" test_known_agent_claude
run_unit_test "known_agent_codex" test_known_agent_codex
run_unit_test "known_agent_cursor" test_known_agent_cursor
run_unit_test "known_agent_gemini" test_known_agent_gemini
run_unit_test "known_agent_aider" test_known_agent_aider
run_unit_test "unknown_agent" test_unknown_agent
run_unit_test "unknown_agent_similar_name" test_unknown_agent_similar_name
run_unit_test "case_sensitivity_uppercase" test_case_sensitivity_uppercase
run_unit_test "case_sensitivity_mixed" test_case_sensitivity_mixed
run_unit_test "empty_string" test_empty_string
run_unit_test "special_characters" test_special_characters
run_unit_test "custom_agent_loaded" test_custom_agent_loaded
run_unit_test "all_primary_agents" test_all_primary_agents
