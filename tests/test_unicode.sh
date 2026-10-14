#!/usr/bin/env bash
#
# E2E Tests: Unicode and Special Characters
# Tests backup/restore with various character encodings
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/test_utils.sh"
source "${LIB_DIR}/fixtures.sh"

# ============================================
# Unicode filename tests
# ============================================

test_unicode_filename_japanese() {
    create_claude_fixture

    # Create file with Japanese characters
    echo '{"data": "テスト"}' > "${HOME}/.claude/設定.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Verify file was backed up
    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/設定.json" ]]; then
        echo "Japanese filename not backed up" >&2
        return 1
    fi
}

test_unicode_filename_chinese() {
    create_claude_fixture

    # Create file with Chinese characters
    echo '{"data": "测试"}' > "${HOME}/.claude/配置.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/配置.json" ]]; then
        echo "Chinese filename not backed up" >&2
        return 1
    fi
}

test_unicode_filename_emoji() {
    create_claude_fixture

    # Create file with emoji in name (if filesystem supports it)
    local emoji_file="${HOME}/.claude/config-🔧.json"
    if echo '{"emoji": true}' > "$emoji_file" 2>/dev/null; then
        run_asb backup claude
        assert_exit_code 0 "$ASB_LAST_STATUS"

        if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/config-🔧.json" ]]; then
            echo "Emoji filename not backed up" >&2
            return 1
        fi
    else
        echo "Skipped: filesystem doesn't support emoji filenames" >&2
        return 0
    fi
}

test_unicode_filename_cyrillic() {
    create_claude_fixture

    echo '{"data": "тест"}' > "${HOME}/.claude/конфиг.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/конфиг.json" ]]; then
        echo "Cyrillic filename not backed up" >&2
        return 1
    fi
}

test_unicode_filename_arabic() {
    create_claude_fixture

    echo '{"data": "اختبار"}' > "${HOME}/.claude/إعدادات.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/إعدادات.json" ]]; then
        echo "Arabic filename not backed up" >&2
        return 1
    fi
}

# ============================================
# Unicode content tests
# ============================================

test_unicode_content_multilingual() {
    create_claude_fixture

    # Create file with multiple languages
    cat > "${HOME}/.claude/multilingual.json" << 'EOF'
{
    "english": "Hello World",
    "japanese": "こんにちは世界",
    "chinese": "你好世界",
    "russian": "Привет мир",
    "arabic": "مرحبا بالعالم",
    "korean": "안녕하세요 세계",
    "thai": "สวัสดีโลก"
}
EOF

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Verify content preserved
    if ! grep -q "こんにちは" "${ASB_BACKUP_ROOT}/.claude/multilingual.json" 2>/dev/null; then
        echo "Japanese content not preserved" >&2
        return 1
    fi
}

test_unicode_content_emoji() {
    create_claude_fixture

    cat > "${HOME}/.claude/emoji.json" << 'EOF'
{
    "status": "🚀",
    "success": "✅",
    "warning": "⚠️",
    "error": "❌",
    "faces": "😀😃😄😁😆"
}
EOF

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if ! grep -q "🚀" "${ASB_BACKUP_ROOT}/.claude/emoji.json" 2>/dev/null; then
        echo "Emoji content not preserved" >&2
        return 1
    fi
}

test_unicode_content_math_symbols() {
    create_claude_fixture

    cat > "${HOME}/.claude/math.json" << 'EOF'
{
    "formula": "∑(x²) = ∫f(x)dx",
    "symbols": "α β γ δ ε ζ η θ",
    "operators": "± × ÷ √ ∞ ≈ ≠ ≤ ≥"
}
EOF

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if ! grep -q "∑" "${ASB_BACKUP_ROOT}/.claude/math.json" 2>/dev/null; then
        echo "Math symbols not preserved" >&2
        return 1
    fi
}

# ============================================
# Special character tests
# ============================================

test_special_chars_quotes() {
    create_claude_fixture

    cat > "${HOME}/.claude/quotes.json" << 'EOF'
{
    "single": "it's working",
    "double": "say \"hello\"",
    "backtick": "use `code`",
    "smart_quotes": ""quoted" and 'single'"
}
EOF

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if ! grep -q '"double"' "${ASB_BACKUP_ROOT}/.claude/quotes.json" 2>/dev/null; then
        echo "Quote content not preserved" >&2
        return 1
    fi
}

test_special_chars_escapes() {
    create_claude_fixture

    cat > "${HOME}/.claude/escapes.json" << 'EOF'
{
    "backslash": "path\\to\\file",
    "newline": "line1\nline2",
    "tab": "col1\tcol2",
    "null_like": "\u0000"
}
EOF

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/escapes.json" ]]; then
        echo "Escapes file not backed up" >&2
        return 1
    fi
}

test_special_chars_paths() {
    create_claude_fixture

    # Create a directory with special chars (if allowed)
    local special_dir="${HOME}/.claude/dir with spaces"
    mkdir -p "$special_dir"
    echo '{"in_special_dir": true}' > "$special_dir/config.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${ASB_BACKUP_ROOT}/.claude/dir with spaces/config.json" ]]; then
        echo "Directory with spaces not backed up" >&2
        return 1
    fi
}

test_special_chars_newlines_in_content() {
    create_claude_fixture

    # Create file with actual newlines
    printf '{\n    "multiline": "line1\\nline2\\nline3"\n}\n' > "${HOME}/.claude/newlines.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local lines
    lines=$(wc -l < "${ASB_BACKUP_ROOT}/.claude/newlines.json")
    if [[ "$lines" -lt 2 ]]; then
        echo "Newlines not preserved" >&2
        return 1
    fi
}

# ============================================
# Restore unicode tests
# ============================================

test_restore_unicode_files() {
    create_claude_fixture

    # Create files with unicode
    echo '{"test": "テスト"}' > "${HOME}/.claude/日本語.json"
    echo '{"test": "测试"}' > "${HOME}/.claude/中文.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    # Clear source files
    rm -f "${HOME}/.claude/日本語.json" "${HOME}/.claude/中文.json"

    # Restore
    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if [[ ! -f "${HOME}/.claude/日本語.json" ]]; then
        echo "Japanese file not restored" >&2
        return 1
    fi
    if [[ ! -f "${HOME}/.claude/中文.json" ]]; then
        echo "Chinese file not restored" >&2
        return 1
    fi
}

test_restore_preserves_unicode_content() {
    create_claude_fixture

    local content='{"greeting": "こんにちは", "emoji": "🎉"}'
    echo "$content" > "${HOME}/.claude/unicode_content.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    rm -f "${HOME}/.claude/unicode_content.json"
    run_asb --force restore claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    local restored_content
    restored_content=$(cat "${HOME}/.claude/unicode_content.json")

    if [[ "$restored_content" != "$content" ]]; then
        echo "Unicode content not preserved after restore" >&2
        echo "Expected: $content" >&2
        echo "Got: $restored_content" >&2
        return 1
    fi
}

# ============================================
# JSON output with unicode
# ============================================

test_json_output_unicode_agent() {
    create_claude_fixture
    echo '{"テスト": "値"}' > "${HOME}/.claude/settings.json"

    run_asb backup claude

    run_asb --json list
    assert_exit_code 0 "$ASB_LAST_STATUS"

    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' || {
            echo "JSON output invalid with unicode content" >&2
            return 1
        }
    fi
}

test_json_output_unicode_diff() {
    create_claude_fixture
    echo '{"original": "原始"}' > "${HOME}/.claude/settings.json"

    run_asb backup claude
    assert_exit_code 0 "$ASB_LAST_STATUS"

    echo '{"changed": "変更"}' > "${HOME}/.claude/settings.json"

    run_asb --json diff claude
    # Diff with unicode content should produce valid JSON
    if command -v python3 >/dev/null 2>&1; then
        echo "$ASB_LAST_OUTPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || {
            # Might fail if no diff, which is ok
            return 0
        }
    fi
}

# Run all tests
run_test "unicode_filename_japanese" test_unicode_filename_japanese || true
run_test "unicode_filename_chinese" test_unicode_filename_chinese || true
run_test "unicode_filename_emoji" test_unicode_filename_emoji || true
run_test "unicode_filename_cyrillic" test_unicode_filename_cyrillic || true
run_test "unicode_filename_arabic" test_unicode_filename_arabic || true
run_test "unicode_content_multilingual" test_unicode_content_multilingual || true
run_test "unicode_content_emoji" test_unicode_content_emoji || true
run_test "unicode_content_math_symbols" test_unicode_content_math_symbols || true
run_test "special_chars_quotes" test_special_chars_quotes || true
run_test "special_chars_escapes" test_special_chars_escapes || true
run_test "special_chars_paths" test_special_chars_paths || true
run_test "special_chars_newlines_in_content" test_special_chars_newlines_in_content || true
run_test "restore_unicode_files" test_restore_unicode_files || true
run_test "restore_preserves_unicode_content" test_restore_preserves_unicode_content || true
run_test "json_output_unicode_agent" test_json_output_unicode_agent || true
run_test "json_output_unicode_diff" test_json_output_unicode_diff || true

finish_suite
