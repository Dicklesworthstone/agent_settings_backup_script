#!/usr/bin/env bash
# Assertions for tests

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" != "$actual" ]]; then
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        [[ -n "$message" ]] && echo "$message" >&2
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        echo "Did not expect: $actual" >&2
        [[ -n "$message" ]] && echo "$message" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Expected output to contain: $needle" >&2
        [[ -n "$message" ]] && echo "$message" >&2
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "Expected output not to contain: $needle" >&2
        return 1
    fi
}

assert_output_contains() {
    assert_contains "$@"
}

assert_output_matches() {
    local output="$1"
    local pattern="$2"
    local message="${3:-}"

    if ! echo "$output" | grep -Eq "$pattern"; then
        echo "Expected output to match: $pattern" >&2
        [[ -n "$message" ]] && echo "$message" >&2
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    [[ -f "$path" ]]
}

assert_file_not_exists() {
    local path="$1"
    [[ ! -f "$path" ]]
}

assert_dir_exists() {
    local path="$1"
    [[ -d "$path" ]]
}

assert_dir_not_exists() {
    local path="$1"
    [[ ! -d "$path" ]]
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" != "$actual" ]]; then
        echo "Expected exit code: $expected" >&2
        echo "Actual exit code:   $actual" >&2
        [[ -n "$message" ]] && echo "$message" >&2
        return 1
    fi
}

assert_files_identical() {
    local a="$1"
    local b="$2"
    diff -q "$a" "$b" >/dev/null 2>&1
}

assert_dir_unchanged() {
    local dir="$1"
    local before_checksum="$2"
    local after_checksum
    after_checksum=$(get_dir_checksum "$dir")

    if [[ "$before_checksum" != "$after_checksum" ]]; then
        echo "Directory changed: $dir" >&2
        return 1
    fi
}
