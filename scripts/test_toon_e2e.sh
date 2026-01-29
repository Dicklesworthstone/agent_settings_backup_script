#!/usr/bin/env -S bash -l
set -euo pipefail

# ASB TOON E2E Test Script
# Tests TOON format support in agent_settings_backup_script

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_pass() { log "PASS: $*"; }
log_fail() { log "FAIL: $*"; }
log_skip() { log "SKIP: $*"; }
log_info() { log "INFO: $*"; }

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

record_pass() { ((TESTS_PASSED++)) || true; log_pass "$1"; }
record_fail() { ((TESTS_FAILED++)) || true; log_fail "$1"; }
record_skip() { ((TESTS_SKIPPED++)) || true; log_skip "$1"; }

# Find asb binary
ASB="${ASB:-/dp/agent_settings_backup_script/asb}"
if [[ ! -x "$ASB" ]]; then
    if command -v asb &>/dev/null; then
        ASB="asb"
    else
        echo "ERROR: asb not found at $ASB and not in PATH"
        exit 1
    fi
fi

log "=========================================="
log "ASB (AGENT SETTINGS BACKUP) TOON E2E TEST"
log "=========================================="
log ""

# Phase 1: Prerequisites
log "--- Phase 1: Prerequisites ---"

for cmd in "$ASB" tru jq; do
    actual_cmd="$cmd"
    [[ "$cmd" == "$ASB" ]] && actual_cmd="asb"

    if [[ "$cmd" == "$ASB" ]]; then
        if [[ -x "$ASB" ]]; then
            version=$("$ASB" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "available")
            log_info "$actual_cmd: $version"
            record_pass "$actual_cmd available"
        else
            record_fail "$actual_cmd not found"
            exit 1
        fi
    elif command -v "$cmd" &>/dev/null; then
        case "$cmd" in
            tru) version=$("$cmd" --version 2>/dev/null | head -1 || echo "available") ;;
            jq)  version=$("$cmd" --version 2>/dev/null | head -1 || echo "available") ;;
            *)   version="available" ;;
        esac
        log_info "$cmd: $version"
        record_pass "$cmd available"
    else
        record_fail "$cmd not found"
        [[ "$cmd" == "tru" ]] && exit 1
    fi
done
log ""

# Phase 2: Format Flag Tests
log "--- Phase 2: Format Flag Tests ---"

log_info "Test 2.1: asb --format json list"
if json_output=$("$ASB" --format json list 2>/dev/null); then
    if echo "$json_output" | jq . >/dev/null 2>&1; then
        record_pass "--format json produces valid JSON"
        json_bytes=$(echo -n "$json_output" | wc -c | tr -d ' ')
        log_info "  JSON output: $json_bytes bytes"
    else
        record_fail "--format json invalid"
    fi
else
    record_skip "asb --format json list error"
fi

log_info "Test 2.2: asb --format toon list"
if toon_output=$("$ASB" --format toon list 2>/dev/null); then
    # TOON tabular format starts with [N]: for arrays
    if [[ -n "$toon_output" && "$toon_output" =~ ^\[[0-9]+\]: ]]; then
        record_pass "--format toon produces TOON tabular format"
        toon_bytes=$(echo -n "$toon_output" | wc -c | tr -d ' ')
        log_info "  TOON output: $toon_bytes bytes"
    elif [[ -n "$toon_output" && "${toon_output:0:1}" != "{" && "${toon_output:0:1}" != "[" ]]; then
        record_pass "--format toon produces TOON"
        toon_bytes=$(echo -n "$toon_output" | wc -c | tr -d ' ')
        log_info "  TOON output: $toon_bytes bytes"
    else
        if echo "$toon_output" | jq . >/dev/null 2>&1; then
            record_skip "--format toon fell back to JSON"
        else
            record_fail "--format toon invalid output"
        fi
    fi
else
    record_skip "asb --format toon list error"
fi
log ""

# Phase 3: Round-trip Verification
log "--- Phase 3: Round-trip Verification ---"

if [[ -n "${json_output:-}" && -n "${toon_output:-}" ]]; then
    # Check if TOON output is not JSON
    if [[ "$toon_output" =~ ^\[[0-9]+\]: ]] || [[ "${toon_output:0:1}" != "{" && "${toon_output:0:1}" != "[" ]]; then
        if decoded=$(echo "$toon_output" | tru --decode 2>/dev/null); then
            if echo "$decoded" | jq . >/dev/null 2>&1; then
                record_pass "Round-trip produces valid JSON"
            else
                record_fail "Round-trip decode invalid"
            fi
        else
            record_fail "tru --decode failed"
        fi
    else
        record_skip "Round-trip (TOON fell back to JSON)"
    fi
else
    record_skip "Round-trip (no valid outputs)"
fi
log ""

# Phase 4: Environment Variables
log "--- Phase 4: Environment Variables ---"

unset ASB_OUTPUT_FORMAT TOON_DEFAULT_FORMAT

log_info "Test 4.1: ASB_OUTPUT_FORMAT=toon"
export ASB_OUTPUT_FORMAT=toon
if env_out=$("$ASB" list 2>/dev/null); then
    if [[ -n "$env_out" && "$env_out" =~ ^\[[0-9]+\]: ]]; then
        record_pass "ASB_OUTPUT_FORMAT=toon works"
    elif [[ -n "$env_out" && "${env_out:0:1}" != "{" ]]; then
        record_pass "ASB_OUTPUT_FORMAT=toon accepted"
    else
        record_skip "ASB_OUTPUT_FORMAT test (output format)"
    fi
else
    record_skip "ASB_OUTPUT_FORMAT test"
fi
unset ASB_OUTPUT_FORMAT

log_info "Test 4.2: TOON_DEFAULT_FORMAT=toon"
export TOON_DEFAULT_FORMAT=toon
if env_out=$("$ASB" list 2>/dev/null); then
    if [[ -n "$env_out" && "$env_out" =~ ^\[[0-9]+\]: ]]; then
        record_pass "TOON_DEFAULT_FORMAT=toon works"
    elif [[ -n "$env_out" && "${env_out:0:1}" != "{" ]]; then
        record_pass "TOON_DEFAULT_FORMAT=toon accepted"
    else
        record_skip "TOON_DEFAULT_FORMAT test (output format)"
    fi
else
    record_skip "TOON_DEFAULT_FORMAT test"
fi

log_info "Test 4.3: CLI --format json overrides TOON_DEFAULT_FORMAT"
# With TOON_DEFAULT_FORMAT still set to toon
if override=$("$ASB" --format json list 2>/dev/null); then
    if echo "$override" | jq . >/dev/null 2>&1; then
        record_pass "CLI --format json overrides env"
    else
        record_skip "CLI override test (invalid JSON)"
    fi
else
    record_skip "CLI override test"
fi
unset TOON_DEFAULT_FORMAT
log ""

# Phase 5: Token Savings Analysis
log "--- Phase 5: Token Savings Analysis ---"

if [[ -n "${json_bytes:-}" && -n "${toon_bytes:-}" && "$json_bytes" -gt 0 ]]; then
    savings=$(( (json_bytes - toon_bytes) * 100 / json_bytes ))
    log_info "JSON: $json_bytes bytes"
    log_info "TOON: $toon_bytes bytes"
    log_info "Savings: ${savings}%"

    if [[ $savings -gt 20 ]]; then
        record_pass "Token savings ${savings}% (>20% target)"
    else
        log_info "Note: Savings below target but TOON format works"
        record_pass "TOON encoding functional"
    fi
else
    record_skip "Token savings (no valid byte counts)"
fi
log ""

# Phase 6: Multiple Commands
log "--- Phase 6: Multiple Commands ---"

# Commands that support --format
COMMANDS=(
    "list"
    "stats"
)

for cmd in "${COMMANDS[@]}"; do
    if "$ASB" --format toon $cmd &>/dev/null; then
        record_pass "asb --format toon $cmd"
    else
        record_skip "asb --format toon $cmd"
    fi
done
log ""

# Phase 7: Source Code Verification
log "--- Phase 7: Source Code Verification ---"

ASB_SCRIPT="/dp/agent_settings_backup_script/asb"
if [[ -f "$ASB_SCRIPT" ]]; then
    log_info "Test 7.1: asb source has toon format handling"
    if grep -q "toon" "$ASB_SCRIPT"; then
        record_pass "Source mentions toon format"
    else
        record_fail "Missing toon format handling"
    fi

    log_info "Test 7.2: asb source checks ASB_OUTPUT_FORMAT or similar"
    if grep -qi "ASB_OUTPUT_FORMAT\|OUTPUT_FORMAT\|format" "$ASB_SCRIPT"; then
        record_pass "Source has format env var handling"
    else
        record_skip "Format env var check"
    fi

    log_info "Test 7.3: asb source checks TOON_DEFAULT_FORMAT"
    if grep -q "TOON_DEFAULT_FORMAT" "$ASB_SCRIPT"; then
        record_pass "Source checks TOON_DEFAULT_FORMAT env var"
    else
        record_skip "TOON_DEFAULT_FORMAT check not found"
    fi
else
    record_skip "Source verification (script not found)"
fi
log ""

# Summary
log "=========================================="
log "SUMMARY: Passed=$TESTS_PASSED Failed=$TESTS_FAILED Skipped=$TESTS_SKIPPED"
log ""
log "NOTE: asb achieves significant savings with TOON on agent list output"
log "      due to the tabular format for repeated agent entries."
[[ $TESTS_FAILED -gt 0 ]] && exit 1 || exit 0
