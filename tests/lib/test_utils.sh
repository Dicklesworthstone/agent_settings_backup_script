#!/usr/bin/env bash
# Common test utilities

set -uo pipefail

TEST_UTILS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${TEST_UTILS_DIR}/../.." && pwd)
ASB_BIN="${REPO_ROOT}/asb"

TEST_ENV_ROOT=""
KEEP_TEST_ARTIFACTS=${KEEP_TEST_ARTIFACTS:-false}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

skip_if_missing() {
    local cmd="$1"
    local reason="${2:-}"
    if ! command_exists "$cmd"; then
        if [[ -n "$reason" ]]; then
            skip_test "$reason"
        else
            skip_test "Missing dependency: ${cmd}"
        fi
        return 2
    fi
    return 0
}

setup_test_env() {
    export TMPDIR="${TMPDIR:-/data/tmp}"
    mkdir -p "$TMPDIR"
    TEST_ENV_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t asb-test)
    export HOME="${TEST_ENV_ROOT}/home"
    export XDG_CONFIG_HOME="${TEST_ENV_ROOT}/xdg"
    export ASB_BACKUP_ROOT="${TEST_ENV_ROOT}/backups"
    export PATH="${REPO_ROOT}:$PATH"
    export GIT_AUTHOR_NAME="ASB Test"
    export GIT_AUTHOR_EMAIL="asb-test@example.com"
    export GIT_COMMITTER_NAME="ASB Test"
    export GIT_COMMITTER_EMAIL="asb-test@example.com"
    export GIT_AUTHOR_NAME="ASB Test"
    export GIT_AUTHOR_EMAIL="asb-test@example.com"
    export GIT_COMMITTER_NAME="ASB Test"
    export GIT_COMMITTER_EMAIL="asb-test@example.com"

    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$ASB_BACKUP_ROOT"
}

teardown_test_env() {
    if [[ "$KEEP_TEST_ARTIFACTS" == "true" ]]; then
        return 0
    fi

    if [[ -n "$TEST_ENV_ROOT" ]] && [[ -d "$TEST_ENV_ROOT" ]]; then
        rm -rf "$TEST_ENV_ROOT"
    fi
}

get_test_tmp_dir() {
    local dir="${TEST_ENV_ROOT}/tmp"
    mkdir -p "$dir"
    echo "$dir"
}

preserve_artifacts() {
    local test_name="$1"
    if [[ -z "$TEST_ENV_ROOT" ]] || [[ ! -d "$TEST_ENV_ROOT" ]]; then
        return 0
    fi

    local dest_root="${TEST_ARTIFACTS_ROOT:-/data/tmp/asb-test-artifacts}"
    mkdir -p "$dest_root"
    local dest="${dest_root}/${test_name}-$(date +%Y%m%d-%H%M%S)"
    cp -r "$TEST_ENV_ROOT" "$dest" 2>/dev/null || true
    log_info "Artifacts preserved at ${dest}"
}

skip_test() {
    local reason="$1"
    log_skip "$reason"
    return 2
}

run_test() {
    local test_name="$1"
    local func="$2"

    set_current_test "$test_name"
    local start
    start=$(date +%s)

    setup_test_env
    if ( set -euo pipefail; "$func" ); then
        log_pass "$test_name"
        teardown_test_env
        clear_current_test
        return 0
    else
        local status=$?
        if [[ $status -eq 2 ]]; then
            teardown_test_env
            clear_current_test
            return 0
        fi
        log_fail "$test_name"
        preserve_artifacts "$test_name"
        teardown_test_env
        clear_current_test
        return 1
    fi
}

run_asb() {
    ASB_LAST_OUTPUT="$($ASB_BIN "$@" 2>&1)"
    ASB_LAST_STATUS=$?
    return $ASB_LAST_STATUS
}

get_dir_checksum() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo ""
        return 0
    fi

    (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}')
}

get_agent_folder() {
    local agent="$1"
    case "$agent" in
        claude)
            echo ".claude"
            ;;
        codex)
            echo ".codex"
            ;;
        cursor)
            echo ".cursor"
            ;;
        *)
            echo ".${agent}"
            ;;
    esac
}

create_mock_agent() {
    local agent="$1"
    local folder
    folder=$(get_agent_folder "$agent")
    local dest="${HOME}/${folder}"

    local fixtures_root="${TEST_UTILS_DIR}/../fixtures"
    local fixture_dir="${fixtures_root}/sample_${agent}"

    if [[ -d "$fixture_dir" ]] && find "$fixture_dir" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        mkdir -p "$dest"
        cp -R "$fixture_dir/." "$dest/" 2>/dev/null || true
        return 0
    fi

    mkdir -p "$dest/projects" "$dest/extensions"
    printf '{"agent":"%s","setting":true}\n' "$agent" > "$dest/settings.json"
    printf '{"agent":"%s","backup":true}\n' "$agent" > "$dest/config.json"
    printf "# ${agent} config\nvalue=true\n" > "$dest/config.toml"
    printf '{"recent":["alpha","beta"]}\n' > "$dest/projects/recent.json"
    printf "extension_one\n" > "$dest/extensions/list.txt"
}
