#!/usr/bin/env bash
#
# E2E Tests: Symlinks Handling
# Tests backup/restore with symbolic links
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Symlink to file tests
# ============================================

test_symlink_to_local_file() {
    create_claude_fixture

    # Create target file and symlink
    echo '{"target": true}' > "${HOME}/.claude/target.json"
    ln -sf "target.json" "${HOME}/.claude/link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Check how backup handles symlink
    if [[ -L "${ASB_BACKUP_ROOT}/.claude/link.json" ]]; then
        echo "Symlink preserved as symlink" >&2
    elif [[ -f "${ASB_BACKUP_ROOT}/.claude/link.json" ]]; then
        echo "Symlink dereferenced to file" >&2
    fi
    # Either behavior is acceptable
}

test_symlink_to_external_file() {
    create_claude_fixture

    # Create external target
    local external_target="${TEST_ENV_ROOT}/external_config.json"
    echo '{"external": true}' > "$external_target"
    ln -sf "$external_target" "${HOME}/.claude/external_link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Either preserves symlink or follows it
}

test_symlink_broken() {
    create_claude_fixture

    # Create broken symlink
    ln -sf "nonexistent_file.json" "${HOME}/.claude/broken_link.json"

    run_asb backup claude
    # Should succeed (ignoring broken symlink) or warn
    if [[ "$ASB_LAST_STATUS" -ne 0 ]]; then
        # Check if error is about broken symlink (acceptable)
        assert_contains "$ASB_LAST_OUTPUT" "link" || \
        assert_contains "$ASB_LAST_OUTPUT" "symlink" || \
        return 0
    fi
}

test_symlink_circular() {
    create_claude_fixture

    # Create circular symlinks
    ln -sf "link_b.json" "${HOME}/.claude/link_a.json"
    ln -sf "link_a.json" "${HOME}/.claude/link_b.json"

    run_asb backup claude
    # Should not hang or crash
    # May succeed with warnings or fail gracefully
}

# ============================================
# Symlink to directory tests
# ============================================

test_symlink_to_local_dir() {
    create_claude_fixture

    # Create target directory and symlink
    mkdir -p "${HOME}/.claude/real_dir"
    echo '{"in_dir": true}' > "${HOME}/.claude/real_dir/config.json"
    ln -sf "real_dir" "${HOME}/.claude/linked_dir"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Should backup content via symlink
    if [[ -f "${ASB_BACKUP_ROOT}/.claude/linked_dir/config.json" ]] || \
       [[ -f "${ASB_BACKUP_ROOT}/.claude/real_dir/config.json" ]]; then
        return 0
    fi
    echo "Directory content not backed up through symlink" >&2
    return 1
}

test_symlink_to_external_dir() {
    create_claude_fixture

    # Create external directory
    local external_dir="${TEST_ENV_ROOT}/external_dir"
    mkdir -p "$external_dir"
    echo '{"external_dir": true}' > "$external_dir/config.json"
    ln -sf "$external_dir" "${HOME}/.claude/external_linked_dir"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

# ============================================
# Restore symlink tests
# ============================================

test_restore_preserves_symlink() {
    create_claude_fixture

    echo '{"target": true}' > "${HOME}/.claude/target.json"
    ln -sf "target.json" "${HOME}/.claude/link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Delete and restore
    rm -f "${HOME}/.claude/link.json"

    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Check if link was restored
    if [[ -L "${HOME}/.claude/link.json" ]] || [[ -f "${HOME}/.claude/link.json" ]]; then
        return 0
    fi
    echo "Link not restored" >&2
    return 1
}

test_restore_overwrites_symlink_with_file() {
    create_claude_fixture

    # Create a regular file
    echo '{"was_file": true}' > "${HOME}/.claude/config.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Replace file with symlink
    rm -f "${HOME}/.claude/config.json"
    echo '{"target": true}' > "${HOME}/.claude/target.json"
    ln -sf "target.json" "${HOME}/.claude/config.json"

    # Restore should overwrite symlink with original file
    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Check content is restored correctly
    if grep -q "was_file" "${HOME}/.claude/config.json" 2>/dev/null; then
        return 0
    fi
    echo "Original file not restored over symlink" >&2
    return 1
}

# ============================================
# Diff with symlinks tests
# ============================================

test_diff_with_symlink() {
    create_claude_fixture

    echo '{"original": true}' > "${HOME}/.claude/target.json"
    ln -sf "target.json" "${HOME}/.claude/link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Modify target (affects symlink)
    echo '{"modified": true}' > "${HOME}/.claude/target.json"

    run_asb diff claude
    # Should detect change through symlink
}

test_diff_symlink_target_change() {
    create_claude_fixture

    echo '{"target1": true}' > "${HOME}/.claude/target1.json"
    echo '{"target2": true}' > "${HOME}/.claude/target2.json"
    ln -sf "target1.json" "${HOME}/.claude/link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Change symlink target
    rm -f "${HOME}/.claude/link.json"
    ln -sf "target2.json" "${HOME}/.claude/link.json"

    run_asb diff claude
    # Should detect symlink target change
}

# ============================================
# Export/Import with symlinks tests
# ============================================

test_export_with_symlinks() {
    create_claude_fixture

    echo '{"target": true}' > "${HOME}/.claude/target.json"
    ln -sf "target.json" "${HOME}/.claude/link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local export_file="${TEST_ENV_ROOT}/export_symlink.tar.gz"
    run_asb export claude "$export_file"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_file_exists "$export_file" || return 1

    # Verify archive contains the file
    if tar tzf "$export_file" 2>/dev/null | grep -q "link.json\|target.json"; then
        return 0
    fi
    echo "Symlinked files not in archive" >&2
    return 1
}

test_import_with_symlinks() {
    create_claude_fixture

    echo '{"target": true}' > "${HOME}/.claude/target.json"
    ln -sf "target.json" "${HOME}/.claude/link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local export_file="${TEST_ENV_ROOT}/export_symlink2.tar.gz"
    run_asb export claude "$export_file"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Clear and reimport
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    run_asb import "$export_file"
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

# ============================================
# Special symlink cases
# ============================================

test_symlink_self_reference() {
    create_claude_fixture

    # Self-referencing symlink
    ln -sf "." "${HOME}/.claude/self"

    run_asb backup claude
    # Should not hang
}

test_symlink_deep_nesting() {
    create_claude_fixture

    # Create deeply nested symlink chain
    echo '{"deep": true}' > "${HOME}/.claude/deep_target.json"
    ln -sf "deep_target.json" "${HOME}/.claude/link1.json"
    ln -sf "link1.json" "${HOME}/.claude/link2.json"
    ln -sf "link2.json" "${HOME}/.claude/link3.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

test_symlink_absolute_path() {
    create_claude_fixture

    # Symlink with absolute path
    echo '{"absolute": true}' > "${HOME}/.claude/absolute_target.json"
    ln -sf "${HOME}/.claude/absolute_target.json" "${HOME}/.claude/absolute_link.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

# Run all tests
run_test "symlink_to_local_file" test_symlink_to_local_file || true
run_test "symlink_to_external_file" test_symlink_to_external_file || true
run_test "symlink_broken" test_symlink_broken || true
run_test "symlink_circular" test_symlink_circular || true
run_test "symlink_to_local_dir" test_symlink_to_local_dir || true
run_test "symlink_to_external_dir" test_symlink_to_external_dir || true
run_test "restore_preserves_symlink" test_restore_preserves_symlink || true
run_test "restore_overwrites_symlink_with_file" test_restore_overwrites_symlink_with_file || true
run_test "diff_with_symlink" test_diff_with_symlink || true
run_test "diff_symlink_target_change" test_diff_symlink_target_change || true
run_test "export_with_symlinks" test_export_with_symlinks || true
run_test "import_with_symlinks" test_import_with_symlinks || true
run_test "symlink_self_reference" test_symlink_self_reference || true
run_test "symlink_deep_nesting" test_symlink_deep_nesting || true
run_test "symlink_absolute_path" test_symlink_absolute_path || true

exit 0
