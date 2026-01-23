#!/usr/bin/env bash
# Master test runner

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

LOG_LEVEL=1
FILTER=""
KEEP_TEST_ARTIFACTS=false
PARALLEL=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            LOG_LEVEL=0
            shift
            ;;
        --filter)
            FILTER="${2:-}"
            shift 2
            ;;
        --parallel)
            PARALLEL="${2:-1}"
            shift 2
            ;;
        --keep-artifacts)
            KEEP_TEST_ARTIFACTS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

export LOG_LEVEL
export KEEP_TEST_ARTIFACTS
if [[ -n "${TMPDIR:-}" ]] && [[ -d "${TMPDIR}" ]]; then
    : # Use existing TMPDIR
else
    export TMPDIR="${TMPDIR:-/tmp}"
    mkdir -p "$TMPDIR" 2>/dev/null || export TMPDIR="/tmp"
fi

source "${SCRIPT_DIR}/lib/logging.sh"

log_section "ASB Test Suite"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

tests=()
while IFS= read -r -d '' file; do
    tests+=("$file")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'test_*.sh' -print0 | sort -z)

if [[ -n "$FILTER" ]]; then
    filtered=()
    for t in "${tests[@]}"; do
        if [[ "$t" == *"$FILTER"* ]]; then
            filtered+=("$t")
        fi
    done
    tests=("${filtered[@]}")
fi

if [[ ${#tests[@]} -eq 0 ]]; then
    log_warn "No tests found"
    exit 2
fi

passed=0
failed=0
skipped=0

if [[ "$PARALLEL" -gt 1 ]]; then
    log_info "Running tests in parallel (jobs=${PARALLEL})"
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t asb-test-run.XXXXXXXX)
    idx=0
    status_files=()

    for test_file in "${tests[@]}"; do
        while (( $(jobs -rp | wc -l) >= PARALLEL )); do
            sleep 0.1
        done

        status_file="${tmp_dir}/${idx}.status"
        status_files+=("$status_file")

        (
            if [[ ! -x "$test_file" ]]; then
                chmod +x "$test_file" 2>/dev/null || true
            fi
            "$test_file"
            echo "$?" > "$status_file"
        ) &

        idx=$((idx + 1))
    done

    wait

    for status_file in "${status_files[@]}"; do
        status=$(cat "$status_file" 2>/dev/null || echo 1)
        if [[ $status -eq 0 ]]; then
            ((passed++))
        elif [[ $status -eq 2 ]]; then
            ((skipped++))
        else
            ((failed++))
        fi
    done
else
    for test_file in "${tests[@]}"; do
        if [[ ! -x "$test_file" ]]; then
            chmod +x "$test_file" 2>/dev/null || true
        fi

        if "$test_file"; then
            ((passed++))
        else
            status=$?
            if [[ $status -eq 2 ]]; then
                ((skipped++))
            else
                ((failed++))
            fi
        fi
        echo "" >&2
        sleep 0.1
        clear_current_test
    done
fi

log_section "Results"
log_info "Total:    $((passed + failed + skipped))"
log_info "Passed:   ${passed}"
log_info "Failed:   ${failed}"
log_info "Skipped:  ${skipped}"

if [[ $failed -ne 0 ]]; then
    exit 1
fi

exit 0
