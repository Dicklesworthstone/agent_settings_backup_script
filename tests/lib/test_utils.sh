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
    if [[ -n "${TMPDIR:-}" ]] && [[ -d "${TMPDIR}" ]]; then
        : # Use existing TMPDIR
    else
        export TMPDIR="${TMPDIR:-/tmp}"
        mkdir -p "$TMPDIR" 2>/dev/null || export TMPDIR="/tmp"
    fi
    TEST_ENV_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t asb-test.XXXXXXXX)
    export HOME="${TEST_ENV_ROOT}/home"
    export XDG_CONFIG_HOME="${TEST_ENV_ROOT}/xdg"
    export XDG_STATE_HOME="${TEST_ENV_ROOT}/xdg-state"
    export ASB_BACKUP_ROOT="${TEST_ENV_ROOT}/backups"
    ASB_ORIG_PATH="${ASB_ORIG_PATH:-$PATH}"
    export PATH="${TEST_ENV_ROOT}/bin:${REPO_ROOT}:${ASB_ORIG_PATH}"
    install_scheduler_shims
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

# crontab and `systemctl --user` act on the real user's schedule even with
# HOME pointed at the test dir, so a test that schedules would rewrite the
# developer's crontab. Shadow them: crontab keeps a per-test file, and
# systemctl may only query. Shims exist only where the real command does, so
# scheduler auto-detection is unchanged.
install_scheduler_shims() {
    local bin="${TEST_ENV_ROOT}/bin" real
    mkdir -p "$bin"
    if PATH="$ASB_ORIG_PATH" command -v crontab >/dev/null 2>&1; then
        cat > "${bin}/crontab" <<EOF
#!/usr/bin/env bash
# Test shim: this test's crontab lives in ${TEST_ENV_ROOT}/crontab.
tab="${TEST_ENV_ROOT}/crontab"
case "\${1:--}" in
    -l) [[ -f "\$tab" ]] || { echo "crontab: no crontab (test shim)" >&2; exit 1; }
        cat "\$tab" ;;
    -r) rm -f "\$tab" ;;
    -) cat > "\$tab" ;;
    -*) echo "crontab test shim: unsupported option \$1" >&2; exit 1 ;;
    *) cat "\$1" > "\$tab" ;;
esac
EOF
        chmod +x "${bin}/crontab"
    fi
    if real=$(PATH="$ASB_ORIG_PATH" command -v systemctl 2>/dev/null); then
        cat > "${bin}/systemctl" <<EOF
#!/usr/bin/env bash
# Test shim: only queries reach the real service manager.
for arg in "\$@"; do
    case "\$arg" in
        enable|disable|reenable|start|stop|restart|reload|daemon-reload|mask|unmask|link|preset|kill|edit|set-property)
            echo "systemctl test shim: refusing 'systemctl \$*'" >&2
            exit 1 ;;
    esac
done
exec "${real}" "\$@"
EOF
        chmod +x "${bin}/systemctl"
    fi
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

    local dest_root="${TEST_ARTIFACTS_ROOT:-${TMPDIR:-/tmp}/asb-test-artifacts}"
    mkdir -p "$dest_root" 2>/dev/null || return 0
    local dest="${dest_root}/${test_name}-$(date +%Y%m%d-%H%M%S)"
    cp -r "$TEST_ENV_ROOT" "$dest" 2>/dev/null || true
    log_info "Artifacts preserved at ${dest}"
}

skip_test() {
    local reason="$1"
    log_skip "$reason"
    return 2
}

# Failed run_test calls in this suite; finish_suite turns them into its exit status.
ASB_SUITE_FAILURES=0

# End a suite that runs every test regardless of earlier failures.
finish_suite() {
    if (( ASB_SUITE_FAILURES > 0 )); then
        log_error "${ASB_SUITE_FAILURES} test(s) failed"
        exit 1
    fi
    exit 0
}

run_test() {
    local test_name="$1"
    local func="$2"

    set_current_test "$test_name"
    local start
    start=$(date +%s)

    setup_test_env
    # Run inside the test's scratch dir so default-named output (e.g. export's
    # claude-backup-DATE.tar.gz) never lands in the caller's directory.
    if ( set -euo pipefail; cd "$TEST_ENV_ROOT" || exit 1; "$func" ); then
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
        ASB_SUITE_FAILURES=$((ASB_SUITE_FAILURES + 1))
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

# Run asb on a pseudo-terminal, typing $1 (printf %b escapes) as input.
# util-linux and BSD script(1) take different arguments. BSD script sends EOF
# as soon as its input closes, ahead of text the command has not read yet, so
# the input stays open until the command has finished.
run_asb_tty() {
    local input="$1"
    shift

    skip_if_missing script "script command not available for TTY tests" || return 2

    # Probes read /dev/null: BSD script fails when its stdin is a socket.
    if script -q -e -c true /dev/null </dev/null >/dev/null 2>&1; then
        ASB_LAST_OUTPUT=$(printf '%b' "$input" | script -q -e -c "$ASB_BIN $*" /dev/null 2>&1)
        ASB_LAST_STATUS=$?
    elif script -q /dev/null true </dev/null >/dev/null 2>&1; then
        local done_mark="${TEST_ENV_ROOT}/tty-done.$RANDOM"
        ASB_LAST_OUTPUT=$( { printf '%b' "$input"
            for _ in $(seq 1 600); do [[ -e "$done_mark" ]] && break; sleep 0.1; done
        } | { script -q /dev/null "$ASB_BIN" "$@" 2>&1; st=$?; : > "$done_mark"; exit "$st"; } )
        ASB_LAST_STATUS=$?
    else
        # util-linux without -e does not pass the exit status through.
        ASB_LAST_OUTPUT=$(printf '%b' "$input" | script -q -c "$ASB_BIN $*" /dev/null 2>&1)
        ASB_LAST_STATUS=$?
        if [[ $ASB_LAST_STATUS -eq 0 ]] && [[ "$ASB_LAST_OUTPUT" == *"cancelled"* ]]; then
            ASB_LAST_STATUS=1
        fi
    fi
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
