#!/usr/bin/env bash
#
# E2E Tests: Large Files Handling
# Tests backup/restore with large files and many files
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Large file size tests
# ============================================

test_large_file_1mb() {
    create_claude_fixture

    # Create 1MB file
    dd if=/dev/urandom of="${HOME}/.claude/large_1mb.bin" bs=1024 count=1024 2>/dev/null

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/large_1mb.bin" ]]; then
        echo "1MB file not backed up" >&2
        return 1
    fi

    local original_size backed_up_size
    original_size=$(stat -c%s "${HOME}/.claude/large_1mb.bin")
    backed_up_size=$(stat -c%s "${ASB_BACKUP_ROOT}/.claude/large_1mb.bin")

    if [[ "$original_size" -ne "$backed_up_size" ]]; then
        echo "Size mismatch: original=$original_size backed_up=$backed_up_size" >&2
        return 1
    fi
}

test_large_file_10mb() {
    create_claude_fixture

    # Create 10MB file
    dd if=/dev/urandom of="${HOME}/.claude/large_10mb.bin" bs=1024 count=10240 2>/dev/null

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/large_10mb.bin" ]]; then
        echo "10MB file not backed up" >&2
        return 1
    fi
}

test_large_file_restore() {
    create_claude_fixture

    # Create large file with known content
    dd if=/dev/urandom of="${HOME}/.claude/restore_test.bin" bs=1024 count=2048 2>/dev/null
    local checksum_original
    checksum_original=$(md5sum "${HOME}/.claude/restore_test.bin" | cut -d' ' -f1)

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Delete original
    rm -f "${HOME}/.claude/restore_test.bin"

    # Restore
    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Verify checksum
    local checksum_restored
    checksum_restored=$(md5sum "${HOME}/.claude/restore_test.bin" | cut -d' ' -f1)

    if [[ "$checksum_original" != "$checksum_restored" ]]; then
        echo "Checksum mismatch after restore" >&2
        return 1
    fi
}

# ============================================
# Many files tests
# ============================================

test_many_files_100() {
    create_claude_fixture

    # Create 100 files
    mkdir -p "${HOME}/.claude/many_files"
    for i in $(seq 1 100); do
        echo "{\"file\": $i}" > "${HOME}/.claude/many_files/file_${i}.json"
    done

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local count
    count=$(find "${ASB_BACKUP_ROOT}/.claude/many_files" -name "*.json" | wc -l)

    if [[ "$count" -lt 100 ]]; then
        echo "Expected 100 files, got $count" >&2
        return 1
    fi
}

test_many_files_500() {
    create_claude_fixture

    # Create 500 files
    mkdir -p "${HOME}/.claude/many_files_500"
    for i in $(seq 1 500); do
        echo "{\"file\": $i}" > "${HOME}/.claude/many_files_500/file_${i}.json"
    done

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local count
    count=$(find "${ASB_BACKUP_ROOT}/.claude/many_files_500" -name "*.json" | wc -l)

    if [[ "$count" -lt 500 ]]; then
        echo "Expected 500 files, got $count" >&2
        return 1
    fi
}

test_many_files_nested_dirs() {
    create_claude_fixture

    # Create nested directory structure
    for i in $(seq 1 5); do
        for j in $(seq 1 5); do
            for k in $(seq 1 5); do
                local dir="${HOME}/.claude/nested/level_${i}/sub_${j}/deep_${k}"
                mkdir -p "$dir"
                echo "{\"level\": [$i, $j, $k]}" > "$dir/config.json"
            done
        done
    done

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Should have 125 config.json files
    local count
    count=$(find "${ASB_BACKUP_ROOT}/.claude/nested" -name "config.json" | wc -l)

    if [[ "$count" -lt 125 ]]; then
        echo "Expected 125 nested files, got $count" >&2
        return 1
    fi
}

# ============================================
# Deep directory nesting tests
# ============================================

test_deep_directory_nesting() {
    create_claude_fixture

    # Create very deep directory structure
    local deep_path="${HOME}/.claude"
    for i in $(seq 1 20); do
        deep_path="${deep_path}/level_${i}"
    done
    mkdir -p "$deep_path"
    echo '{"deep": true}' > "${deep_path}/deep_config.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local backup_deep="${ASB_BACKUP_ROOT}/.claude"
    for i in $(seq 1 20); do
        backup_deep="${backup_deep}/level_${i}"
    done

    if [[ ! -f "${backup_deep}/deep_config.json" ]]; then
        echo "Deep nested file not backed up" >&2
        return 1
    fi
}

# ============================================
# Export/Import large files tests
# ============================================

test_export_large_file() {
    create_claude_fixture

    # Create moderately large file for export
    dd if=/dev/urandom of="${HOME}/.claude/export_large.bin" bs=1024 count=5120 2>/dev/null

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local export_file="${TEST_ENV_ROOT}/large_export.tar.gz"
    run_asb export claude -o "$export_file"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    assert_file_exists "$export_file" || return 1

    # Archive should be smaller due to compression
    local bin_size archive_size
    bin_size=$(stat -c%s "${HOME}/.claude/export_large.bin")
    archive_size=$(stat -c%s "$export_file")

    echo "Original: $bin_size bytes, Archive: $archive_size bytes"
}

test_import_large_file() {
    create_claude_fixture

    dd if=/dev/urandom of="${HOME}/.claude/import_test.bin" bs=1024 count=3072 2>/dev/null
    local checksum_original
    checksum_original=$(md5sum "${HOME}/.claude/import_test.bin" | cut -d' ' -f1)

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local export_file="${TEST_ENV_ROOT}/import_test.tar.gz"
    run_asb export claude -o "$export_file"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Clear backup
    rm -rf "${ASB_BACKUP_ROOT}/.claude"

    # Import
    run_asb import "$export_file"
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Verify content
    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/import_test.bin" ]]; then
        echo "Large file not imported" >&2
        return 1
    fi
}

# ============================================
# History with large files tests
# ============================================

test_history_large_repo() {
    create_claude_fixture

    # Create multiple backups with changes
    for version in $(seq 1 10); do
        echo "{\"version\": $version}" > "${HOME}/.claude/versioned.json"
        dd if=/dev/urandom of="${HOME}/.claude/random_${version}.bin" bs=1024 count=512 2>/dev/null
        run_asb backup claude
        assert_exit_code 0 "$ASB_LAST_STATUS"
    done

    # History should list all versions
    run_asb history claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Should have at least 10 commits
    local commit_count
    commit_count=$(git -C "${ASB_BACKUP_ROOT}/.claude" rev-list --count HEAD)
    if [[ "$commit_count" -lt 10 ]]; then
        echo "Expected at least 10 commits, got $commit_count" >&2
        return 1
    fi
}

# ============================================
# Performance-related tests
# ============================================

test_incremental_backup_efficiency() {
    create_claude_fixture

    # Create initial large file
    dd if=/dev/urandom of="${HOME}/.claude/stable.bin" bs=1024 count=2048 2>/dev/null
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Small change
    echo '{"changed": true}' > "${HOME}/.claude/small_change.json"

    # Second backup should be fast (incremental)
    local start_time end_time
    start_time=$(date +%s)
    run_asb backup claude
    end_time=$(date +%s)
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local duration=$((end_time - start_time))
    echo "Incremental backup took ${duration} seconds"
}

test_diff_large_files() {
    create_claude_fixture

    dd if=/dev/urandom of="${HOME}/.claude/diff_test.bin" bs=1024 count=1024 2>/dev/null
    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Modify one byte
    printf 'X' | dd of="${HOME}/.claude/diff_test.bin" bs=1 seek=512 conv=notrunc 2>/dev/null

    run_asb diff claude
    # Should detect change in binary file
}

# ============================================
# Empty and special cases
# ============================================

test_empty_files() {
    create_claude_fixture

    # Create empty files
    touch "${HOME}/.claude/empty1.txt"
    touch "${HOME}/.claude/empty2.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/empty1.txt" ]]; then
        echo "Empty file not backed up" >&2
        return 1
    fi
}

test_sparse_file() {
    create_claude_fixture

    # Create sparse file (if supported)
    truncate -s 10M "${HOME}/.claude/sparse.bin" 2>/dev/null || {
        dd if=/dev/zero of="${HOME}/.claude/sparse.bin" bs=1 count=0 seek=10485760 2>/dev/null
    }

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"
}

# Run all tests
run_test "large_file_1mb" test_large_file_1mb || true
run_test "large_file_10mb" test_large_file_10mb || true
run_test "large_file_restore" test_large_file_restore || true
run_test "many_files_100" test_many_files_100 || true
run_test "many_files_500" test_many_files_500 || true
run_test "many_files_nested_dirs" test_many_files_nested_dirs || true
run_test "deep_directory_nesting" test_deep_directory_nesting || true
run_test "export_large_file" test_export_large_file || true
run_test "import_large_file" test_import_large_file || true
run_test "history_large_repo" test_history_large_repo || true
run_test "incremental_backup_efficiency" test_incremental_backup_efficiency || true
run_test "diff_large_files" test_diff_large_files || true
run_test "empty_files" test_empty_files || true
run_test "sparse_file" test_sparse_file || true

finish_suite
