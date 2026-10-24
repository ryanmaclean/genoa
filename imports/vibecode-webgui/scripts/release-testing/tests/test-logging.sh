#!/bin/bash
# Unit Tests for Logging Functions
# =================================
# Tests for logging functions in scripts/release-testing/vm-lifecycle.sh
# Run: bash scripts/release-testing/tests/test-logging.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VM_LIFECYCLE_SCRIPT="${PROJECT_ROOT}/scripts/release-testing/vm-lifecycle.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
PASS_COUNT=0
FAIL_COUNT=0
TEST_START_TIME=0

# Test helper functions
pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS_COUNT++)) || true; }
fail() { echo -e "${RED}✗${NC} $1"; ((FAIL_COUNT++)) || true; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# Initialize test suite
init_test_suite() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Logging Functions Unit Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    TEST_START_TIME=$(date +%s)
}

# =============================================================================
# Test: Logging Functions Exist
# =============================================================================
test_logging_functions_exist() {
    section "Testing Logging Functions Exist"

    local log_functions=(
        "log_info"
        "log_warn"
        "log_error"
    )

    for func in "${log_functions[@]}"; do
        if grep -q "^${func}()" "$VM_LIFECYCLE_SCRIPT"; then
            pass "Function ${func}() defined in script"
        else
            fail "Function ${func}() not found in script"
        fi
    done
}

# =============================================================================
# Test: Logging Functions Are Sourceable
# =============================================================================
test_logging_functions_sourceable() {
    section "Testing Logging Functions Are Sourceable"

    # Source the script and verify functions are available
    if (source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null && type log_info &>/dev/null); then
        pass "log_info function is available after sourcing"
    else
        fail "log_info function not available after sourcing"
    fi

    if (source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null && type log_warn &>/dev/null); then
        pass "log_warn function is available after sourcing"
    else
        fail "log_warn function not available after sourcing"
    fi

    if (source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null && type log_error &>/dev/null); then
        pass "log_error function is available after sourcing"
    else
        fail "log_error function not available after sourcing"
    fi
}

# =============================================================================
# Test: log_info Function Output
# =============================================================================
test_log_info_output() {
    section "Testing log_info Output"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local output
    output=$(log_info "test info message" 2>&1)

    # Test for INFO tag
    if echo "$output" | grep -q "INFO"; then
        pass "log_info outputs INFO tag"
    else
        fail "log_info missing INFO tag"
    fi

    # Test for message content
    if echo "$output" | grep -q "test info message"; then
        pass "log_info includes message content"
    else
        fail "log_info missing message content"
    fi

    # Test for timestamp format (YYYY-MM-DD HH:MM:SS)
    if echo "$output" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"; then
        pass "log_info includes timestamp"
    else
        fail "log_info missing timestamp"
    fi

    # Test for color code (green for INFO)
    if echo "$output" | grep -q '\[0;32m\|GREEN'; then
        pass "log_info uses green color"
    else
        # Color may not be visible in captured output, check script source
        if grep -q 'GREEN.*INFO' "$VM_LIFECYCLE_SCRIPT"; then
            pass "log_info configured with green color"
        else
            fail "log_info should use green color"
        fi
    fi
}

# =============================================================================
# Test: log_warn Function Output
# =============================================================================
test_log_warn_output() {
    section "Testing log_warn Output"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local output
    output=$(log_warn "test warning message" 2>&1)

    # Test for WARN tag
    if echo "$output" | grep -q "WARN"; then
        pass "log_warn outputs WARN tag"
    else
        fail "log_warn missing WARN tag"
    fi

    # Test for message content
    if echo "$output" | grep -q "test warning message"; then
        pass "log_warn includes message content"
    else
        fail "log_warn missing message content"
    fi

    # Test for timestamp
    if echo "$output" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        pass "log_warn includes timestamp"
    else
        fail "log_warn missing timestamp"
    fi

    # Test that color is yellow (script source check)
    if grep -q 'YELLOW.*WARN' "$VM_LIFECYCLE_SCRIPT"; then
        pass "log_warn configured with yellow color"
    else
        fail "log_warn should use yellow color"
    fi
}

# =============================================================================
# Test: log_error Function Output
# =============================================================================
test_log_error_output() {
    section "Testing log_error Output"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local output
    output=$(log_error "test error message" 2>&1)

    # Test for ERROR tag
    if echo "$output" | grep -q "ERROR"; then
        pass "log_error outputs ERROR tag"
    else
        fail "log_error missing ERROR tag"
    fi

    # Test for message content
    if echo "$output" | grep -q "test error message"; then
        pass "log_error includes message content"
    else
        fail "log_error missing message content"
    fi

    # Test for timestamp
    if echo "$output" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        pass "log_error includes timestamp"
    else
        fail "log_error missing timestamp"
    fi

    # Test that color is red (script source check)
    if grep -q 'RED.*ERROR' "$VM_LIFECYCLE_SCRIPT"; then
        pass "log_error configured with red color"
    else
        fail "log_error should use red color"
    fi
}

# =============================================================================
# Test: Color Variables Are Defined
# =============================================================================
test_color_variables() {
    section "Testing Color Variables"

    # Check color variables are defined in the script
    if grep -q 'RED=' "$VM_LIFECYCLE_SCRIPT"; then
        pass "RED color variable is defined"
    else
        fail "RED color variable not defined"
    fi

    if grep -q 'GREEN=' "$VM_LIFECYCLE_SCRIPT"; then
        pass "GREEN color variable is defined"
    else
        fail "GREEN color variable not defined"
    fi

    if grep -q 'YELLOW=' "$VM_LIFECYCLE_SCRIPT"; then
        pass "YELLOW color variable is defined"
    else
        fail "YELLOW color variable not defined"
    fi

    if grep -q 'NC=' "$VM_LIFECYCLE_SCRIPT"; then
        pass "NC (no color) variable is defined"
    else
        fail "NC (no color) variable not defined"
    fi

    # Check colors use correct ANSI codes
    if grep -q "RED=.*0;31" "$VM_LIFECYCLE_SCRIPT"; then
        pass "RED uses correct ANSI code (31)"
    else
        fail "RED should use ANSI code 31"
    fi

    if grep -q "GREEN=.*0;32" "$VM_LIFECYCLE_SCRIPT"; then
        pass "GREEN uses correct ANSI code (32)"
    else
        fail "GREEN should use ANSI code 32"
    fi

    if grep -q "YELLOW=.*1;33" "$VM_LIFECYCLE_SCRIPT"; then
        pass "YELLOW uses correct ANSI code (33)"
    else
        fail "YELLOW should use ANSI code 33"
    fi
}

# =============================================================================
# Test: Logging With Special Characters
# =============================================================================
test_logging_special_characters() {
    section "Testing Logging With Special Characters"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local output

    # Test with message containing quotes
    output=$(log_info "message with \"quotes\"" 2>&1)
    if echo "$output" | grep -q 'quotes'; then
        pass "log_info handles double quotes"
    else
        fail "log_info fails with double quotes"
    fi

    # Test with message containing single quotes
    output=$(log_info "message with 'single quotes'" 2>&1)
    if echo "$output" | grep -q 'single quotes'; then
        pass "log_info handles single quotes"
    else
        fail "log_info fails with single quotes"
    fi

    # Test with message containing path separators
    output=$(log_info "/path/to/file.txt" 2>&1)
    if echo "$output" | grep -q '/path/to/file.txt'; then
        pass "log_info handles path separators"
    else
        fail "log_info fails with path separators"
    fi

    # Test with message containing equals sign
    output=$(log_info "VAR=value" 2>&1)
    if echo "$output" | grep -q 'VAR=value'; then
        pass "log_info handles equals signs"
    else
        fail "log_info fails with equals signs"
    fi

    # Test with empty message
    output=$(log_info "" 2>&1)
    if echo "$output" | grep -q 'INFO'; then
        pass "log_info handles empty message"
    else
        fail "log_info fails with empty message"
    fi
}

# =============================================================================
# Test: Logging Output Goes To Stdout
# =============================================================================
test_logging_stdout() {
    section "Testing Logging Output Stream"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local stdout_output
    local stderr_output

    # Capture stdout only
    stdout_output=$(log_info "stdout test" 2>/dev/null)
    if echo "$stdout_output" | grep -q "stdout test"; then
        pass "log_info outputs to stdout"
    else
        fail "log_info should output to stdout"
    fi

    # Test log_warn
    stdout_output=$(log_warn "warn stdout test" 2>/dev/null)
    if echo "$stdout_output" | grep -q "warn stdout test"; then
        pass "log_warn outputs to stdout"
    else
        fail "log_warn should output to stdout"
    fi

    # Test log_error
    stdout_output=$(log_error "error stdout test" 2>/dev/null)
    if echo "$stdout_output" | grep -q "error stdout test"; then
        pass "log_error outputs to stdout"
    else
        fail "log_error should output to stdout"
    fi
}

# =============================================================================
# Test: Timestamp Format Consistency
# =============================================================================
test_timestamp_format() {
    section "Testing Timestamp Format"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local output1
    local output2
    local output3

    output1=$(log_info "timestamp test" 2>&1)
    output2=$(log_warn "timestamp test" 2>&1)
    output3=$(log_error "timestamp test" 2>&1)

    # Extract timestamps using regex
    local timestamp_pattern="[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"

    if echo "$output1" | grep -oE "$timestamp_pattern" >/dev/null; then
        pass "log_info timestamp matches YYYY-MM-DD HH:MM:SS format"
    else
        fail "log_info timestamp should match YYYY-MM-DD HH:MM:SS format"
    fi

    if echo "$output2" | grep -oE "$timestamp_pattern" >/dev/null; then
        pass "log_warn timestamp matches YYYY-MM-DD HH:MM:SS format"
    else
        fail "log_warn timestamp should match YYYY-MM-DD HH:MM:SS format"
    fi

    if echo "$output3" | grep -oE "$timestamp_pattern" >/dev/null; then
        pass "log_error timestamp matches YYYY-MM-DD HH:MM:SS format"
    else
        fail "log_error timestamp should match YYYY-MM-DD HH:MM:SS format"
    fi

    # Verify all timestamps use the same format command in source
    local date_commands
    date_commands=$(grep -oE "date '\\+%[YmdHMS: -]+'" "$VM_LIFECYCLE_SCRIPT" | sort -u | wc -l)
    if [[ "$date_commands" -eq 1 ]]; then
        pass "All logging functions use consistent timestamp format"
    else
        info "Logging functions may use different timestamp formats (informational)"
    fi
}

# =============================================================================
# Test: Logging Function Return Values
# =============================================================================
test_logging_return_values() {
    section "Testing Logging Function Return Values"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test log_info returns 0
    if log_info "test" >/dev/null 2>&1; then
        pass "log_info returns success (0)"
    else
        fail "log_info should return success (0)"
    fi

    # Test log_warn returns 0
    if log_warn "test" >/dev/null 2>&1; then
        pass "log_warn returns success (0)"
    else
        fail "log_warn should return success (0)"
    fi

    # Test log_error returns 0
    if log_error "test" >/dev/null 2>&1; then
        pass "log_error returns success (0)"
    else
        fail "log_error should return success (0)"
    fi
}

# =============================================================================
# Test: Logging Function Bracket Format
# =============================================================================
test_logging_bracket_format() {
    section "Testing Logging Bracket Format"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    local output

    # Test that log levels are in brackets
    output=$(log_info "test" 2>&1)
    if echo "$output" | grep -q '\[INFO\]'; then
        pass "log_info uses [INFO] bracket format"
    else
        fail "log_info should use [INFO] bracket format"
    fi

    output=$(log_warn "test" 2>&1)
    if echo "$output" | grep -q '\[WARN\]'; then
        pass "log_warn uses [WARN] bracket format"
    else
        fail "log_warn should use [WARN] bracket format"
    fi

    output=$(log_error "test" 2>&1)
    if echo "$output" | grep -q '\[ERROR\]'; then
        pass "log_error uses [ERROR] bracket format"
    else
        fail "log_error should use [ERROR] bracket format"
    fi
}

# =============================================================================
# Test: Multiple Arguments Handling
# =============================================================================
test_multiple_arguments() {
    section "Testing Multiple Arguments"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # The current implementation expects a single string argument
    # Verify this behavior is documented/consistent
    local output

    # Test with single argument (expected usage)
    output=$(log_info "single argument message" 2>&1)
    if echo "$output" | grep -q "single argument message"; then
        pass "log_info handles single argument correctly"
    else
        fail "log_info should handle single argument"
    fi

    # Test with variable in message
    local test_var="variable_value"
    output=$(log_info "message with $test_var" 2>&1)
    if echo "$output" | grep -q "variable_value"; then
        pass "log_info handles variable expansion"
    else
        fail "log_info should handle variable expansion"
    fi

    # Test with command substitution
    output=$(log_info "current user: $(whoami)" 2>&1)
    if echo "$output" | grep -q "$(whoami)"; then
        pass "log_info handles command substitution"
    else
        fail "log_info should handle command substitution"
    fi
}

# =============================================================================
# Test: Script Mode Logging
# =============================================================================
test_script_test_mode_logging() {
    section "Testing Script --test Mode Logging"

    local output
    output=$("$VM_LIFECYCLE_SCRIPT" --test 2>&1)

    # Verify --test mode exercises all logging functions
    if echo "$output" | grep -q "INFO"; then
        pass "--test mode exercises log_info"
    else
        fail "--test mode should exercise log_info"
    fi

    if echo "$output" | grep -q "WARN"; then
        pass "--test mode exercises log_warn"
    else
        fail "--test mode should exercise log_warn"
    fi

    if echo "$output" | grep -q "ERROR"; then
        pass "--test mode exercises log_error"
    else
        fail "--test mode should exercise log_error"
    fi
}

# =============================================================================
# Test: Logging Functions Use echo -e
# =============================================================================
test_logging_uses_echo_e() {
    section "Testing Logging Uses echo -e"

    # Verify logging functions use echo -e for color interpretation
    if grep -E 'log_info\(\).*echo -e' "$VM_LIFECYCLE_SCRIPT"; then
        pass "log_info uses echo -e for color interpretation"
    else
        fail "log_info should use echo -e"
    fi

    if grep -E 'log_warn\(\).*echo -e' "$VM_LIFECYCLE_SCRIPT"; then
        pass "log_warn uses echo -e for color interpretation"
    else
        fail "log_warn should use echo -e"
    fi

    if grep -E 'log_error\(\).*echo -e' "$VM_LIFECYCLE_SCRIPT"; then
        pass "log_error uses echo -e for color interpretation"
    else
        fail "log_error should use echo -e"
    fi
}

# =============================================================================
# Test Summary
# =============================================================================
print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "Duration: ${duration}s"
    echo "Total tests: $((PASS_COUNT + FAIL_COUNT))"
    echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
    echo ""

    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    init_test_suite

    # Check if vm-lifecycle.sh exists
    if [[ ! -f "$VM_LIFECYCLE_SCRIPT" ]]; then
        fail "vm-lifecycle.sh not found at $VM_LIFECYCLE_SCRIPT"
        print_summary
        exit 1
    fi

    # Run all tests
    test_logging_functions_exist
    test_logging_functions_sourceable
    test_log_info_output
    test_log_warn_output
    test_log_error_output
    test_color_variables
    test_logging_special_characters
    test_logging_stdout
    test_timestamp_format
    test_logging_return_values
    test_logging_bracket_format
    test_multiple_arguments
    test_script_test_mode_logging
    test_logging_uses_echo_e

    print_summary
}

main "$@"
