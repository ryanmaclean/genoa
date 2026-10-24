#!/bin/bash
# Unit Tests for VM Lifecycle Management Functions
# =================================================
# Tests for scripts/release-testing/vm-lifecycle.sh
# Run: bash scripts/release-testing/tests/test-vm-lifecycle.sh

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
    echo -e "${BLUE}VM Lifecycle Unit Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    TEST_START_TIME=$(date +%s)
}

# =============================================================================
# Test: Script Syntax and Structure
# =============================================================================
test_script_syntax() {
    section "Testing Script Syntax"

    # Test bash syntax
    if bash -n "$VM_LIFECYCLE_SCRIPT" 2>/dev/null; then
        pass "vm-lifecycle.sh has valid bash syntax"
    else
        fail "vm-lifecycle.sh has syntax errors"
        return 1
    fi

    # Test script is executable or has shebang
    if head -1 "$VM_LIFECYCLE_SCRIPT" | grep -q "^#!/bin/bash"; then
        pass "Script has proper bash shebang"
    else
        fail "Script missing bash shebang"
    fi
}

# =============================================================================
# Test: Required Functions Exist
# =============================================================================
test_required_functions() {
    section "Testing Required Functions Exist"

    local required_functions=(
        "create_vm"
        "start_vm_headless"
        "wait_for_ssh"
        "stop_vm"
        "delete_vm"
        "cleanup_vm"
        "get_vm_ip"
        "vm_exists"
        "check_disk_space"
        "run_in_vm"
        "copy_to_vm"
        "log_info"
        "log_warn"
        "log_error"
    )

    for func in "${required_functions[@]}"; do
        if grep -q "^${func}()" "$VM_LIFECYCLE_SCRIPT"; then
            pass "Function ${func}() exists"
        else
            fail "Function ${func}() not found"
        fi
    done
}

# =============================================================================
# Test: Sourcing the Script
# =============================================================================
test_sourcing_script() {
    section "Testing Script Sourcing"

    # Source the script in a subshell to avoid polluting test environment
    if (source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null && type create_vm &>/dev/null); then
        pass "Script can be sourced successfully"
    else
        fail "Script cannot be sourced"
        return 1
    fi

    # Verify functions are available after sourcing
    if (source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null && type log_info &>/dev/null); then
        pass "Functions are available after sourcing"
    else
        fail "Functions not available after sourcing"
    fi
}

# =============================================================================
# Test: Logging Functions
# =============================================================================
test_logging_functions() {
    section "Testing Logging Functions"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test log_info
    local info_output
    info_output=$(log_info "test message" 2>&1)
    if echo "$info_output" | grep -q "INFO"; then
        pass "log_info outputs INFO tag"
    else
        fail "log_info missing INFO tag"
    fi

    if echo "$info_output" | grep -q "test message"; then
        pass "log_info outputs message content"
    else
        fail "log_info missing message content"
    fi

    # Test log_warn
    local warn_output
    warn_output=$(log_warn "warning message" 2>&1)
    if echo "$warn_output" | grep -q "WARN"; then
        pass "log_warn outputs WARN tag"
    else
        fail "log_warn missing WARN tag"
    fi

    # Test log_error
    local error_output
    error_output=$(log_error "error message" 2>&1)
    if echo "$error_output" | grep -q "ERROR"; then
        pass "log_error outputs ERROR tag"
    else
        fail "log_error missing ERROR tag"
    fi

    # Test timestamp in logs
    if echo "$info_output" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        pass "Logging functions include timestamp"
    else
        fail "Logging functions missing timestamp"
    fi
}

# =============================================================================
# Test: Argument Validation - create_vm
# =============================================================================
test_create_vm_validation() {
    section "Testing create_vm Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Mock tart command to avoid actual VM operations
    tart() { return 1; }
    export -f tart

    # Test empty VM name
    local output
    if ! output=$(create_vm "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "create_vm rejects empty VM name"
        else
            fail "create_vm should mention 'VM name is required'"
        fi
    else
        fail "create_vm should fail with empty VM name"
    fi

    unset -f tart
}

# =============================================================================
# Test: Argument Validation - start_vm_headless
# =============================================================================
test_start_vm_headless_validation() {
    section "Testing start_vm_headless Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(start_vm_headless "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "start_vm_headless rejects empty VM name"
        else
            fail "start_vm_headless should mention 'VM name is required'"
        fi
    else
        fail "start_vm_headless should fail with empty VM name"
    fi
}

# =============================================================================
# Test: Argument Validation - stop_vm
# =============================================================================
test_stop_vm_validation() {
    section "Testing stop_vm Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(stop_vm "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "stop_vm rejects empty VM name"
        else
            fail "stop_vm should mention 'VM name is required'"
        fi
    else
        fail "stop_vm should fail with empty VM name"
    fi
}

# =============================================================================
# Test: Argument Validation - delete_vm
# =============================================================================
test_delete_vm_validation() {
    section "Testing delete_vm Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(delete_vm "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "delete_vm rejects empty VM name"
        else
            fail "delete_vm should mention 'VM name is required'"
        fi
    else
        fail "delete_vm should fail with empty VM name"
    fi
}

# =============================================================================
# Test: Argument Validation - cleanup_vm
# =============================================================================
test_cleanup_vm_validation() {
    section "Testing cleanup_vm Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(cleanup_vm "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "cleanup_vm rejects empty VM name"
        else
            fail "cleanup_vm should mention 'VM name is required'"
        fi
    else
        fail "cleanup_vm should fail with empty VM name"
    fi
}

# =============================================================================
# Test: Argument Validation - get_vm_ip
# =============================================================================
test_get_vm_ip_validation() {
    section "Testing get_vm_ip Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(get_vm_ip "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "get_vm_ip rejects empty VM name"
        else
            fail "get_vm_ip should mention 'VM name is required'"
        fi
    else
        fail "get_vm_ip should fail with empty VM name"
    fi
}

# =============================================================================
# Test: Argument Validation - wait_for_ssh
# =============================================================================
test_wait_for_ssh_validation() {
    section "Testing wait_for_ssh Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(wait_for_ssh "" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "wait_for_ssh rejects empty VM name"
        else
            fail "wait_for_ssh should mention 'VM name is required'"
        fi
    else
        fail "wait_for_ssh should fail with empty VM name"
    fi
}

# =============================================================================
# Test: Argument Validation - run_in_vm
# =============================================================================
test_run_in_vm_validation() {
    section "Testing run_in_vm Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    local output
    if ! output=$(run_in_vm "" "echo test" 2>&1); then
        if echo "$output" | grep -q "VM name is required"; then
            pass "run_in_vm rejects empty VM name"
        else
            fail "run_in_vm should mention 'VM name is required'"
        fi
    else
        fail "run_in_vm should fail with empty VM name"
    fi

    # Test empty command
    if ! output=$(run_in_vm "test-vm" "" 2>&1); then
        if echo "$output" | grep -q "Command is required"; then
            pass "run_in_vm rejects empty command"
        else
            fail "run_in_vm should mention 'Command is required'"
        fi
    else
        fail "run_in_vm should fail with empty command"
    fi
}

# =============================================================================
# Test: Argument Validation - copy_to_vm
# =============================================================================
test_copy_to_vm_validation() {
    section "Testing copy_to_vm Argument Validation"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test missing arguments
    local output
    if ! output=$(copy_to_vm "" "/source" "/dest" 2>&1); then
        if echo "$output" | grep -q "required"; then
            pass "copy_to_vm rejects empty VM name"
        else
            fail "copy_to_vm should mention required arguments"
        fi
    else
        fail "copy_to_vm should fail with empty VM name"
    fi

    if ! output=$(copy_to_vm "test-vm" "" "/dest" 2>&1); then
        if echo "$output" | grep -q "required"; then
            pass "copy_to_vm rejects empty source"
        else
            fail "copy_to_vm should mention required arguments"
        fi
    else
        fail "copy_to_vm should fail with empty source"
    fi
}

# =============================================================================
# Test: vm_exists Function
# =============================================================================
test_vm_exists_function() {
    section "Testing vm_exists Function"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test empty VM name
    if ! vm_exists ""; then
        pass "vm_exists returns false for empty VM name"
    else
        fail "vm_exists should return false for empty VM name"
    fi
}

# =============================================================================
# Test: Environment Variables
# =============================================================================
test_environment_defaults() {
    section "Testing Environment Variable Defaults"

    # Source in a clean subshell
    local output
    output=$(bash -c "source '$VM_LIFECYCLE_SCRIPT' && echo \"\$TART_HOME\"" 2>/dev/null)

    if [[ -n "$output" ]]; then
        pass "TART_HOME has a default value"
    else
        fail "TART_HOME should have a default value"
    fi

    # Check VM_CPU default
    output=$(bash -c "source '$VM_LIFECYCLE_SCRIPT' && echo \"\$VM_CPU\"" 2>/dev/null)
    if [[ "$output" == "4" ]]; then
        pass "VM_CPU defaults to 4"
    else
        fail "VM_CPU should default to 4 (got: $output)"
    fi

    # Check VM_MEMORY default
    output=$(bash -c "source '$VM_LIFECYCLE_SCRIPT' && echo \"\$VM_MEMORY\"" 2>/dev/null)
    if [[ "$output" == "8192" ]]; then
        pass "VM_MEMORY defaults to 8192"
    else
        fail "VM_MEMORY should default to 8192 (got: $output)"
    fi

    # Check SSH_USER default
    output=$(bash -c "source '$VM_LIFECYCLE_SCRIPT' && echo \"\$SSH_USER\"" 2>/dev/null)
    if [[ "$output" == "admin" ]]; then
        pass "SSH_USER defaults to admin"
    else
        fail "SSH_USER should default to admin (got: $output)"
    fi

    # Check SSH_TIMEOUT default
    output=$(bash -c "source '$VM_LIFECYCLE_SCRIPT' && echo \"\$SSH_TIMEOUT\"" 2>/dev/null)
    if [[ "$output" == "5" ]]; then
        pass "SSH_TIMEOUT defaults to 5"
    else
        fail "SSH_TIMEOUT should default to 5 (got: $output)"
    fi
}

# =============================================================================
# Test: Script Help Output
# =============================================================================
test_help_output() {
    section "Testing Script Help Output"

    # Run script with --help
    local output
    output=$("$VM_LIFECYCLE_SCRIPT" --help 2>&1)

    if echo "$output" | grep -q "create_vm"; then
        pass "Help mentions create_vm function"
    else
        fail "Help should mention create_vm function"
    fi

    if echo "$output" | grep -q "Available functions"; then
        pass "Help shows available functions"
    else
        fail "Help should show available functions"
    fi

    if echo "$output" | grep -q "TART_HOME"; then
        pass "Help shows TART_HOME environment variable"
    else
        fail "Help should show TART_HOME"
    fi
}

# =============================================================================
# Test: Script Test Mode
# =============================================================================
test_script_test_mode() {
    section "Testing Script Test Mode"

    # Run script with --test
    local output
    output=$("$VM_LIFECYCLE_SCRIPT" --test 2>&1)

    if echo "$output" | grep -q "Syntax check passed"; then
        pass "Script --test mode works"
    else
        fail "Script --test mode should output 'Syntax check passed'"
    fi

    if echo "$output" | grep -q "INFO"; then
        pass "Test mode exercises log_info"
    else
        fail "Test mode should exercise log_info"
    fi
}

# =============================================================================
# Test: check_disk_space Function (Mock)
# =============================================================================
test_check_disk_space() {
    section "Testing check_disk_space Function"

    # Source the script
    source "$VM_LIFECYCLE_SCRIPT" 2>/dev/null || true

    # Test that function exists and accepts parameters
    if type check_disk_space &>/dev/null; then
        pass "check_disk_space function exists"
    else
        fail "check_disk_space function not found"
        return 1
    fi

    # Test that function signature accepts a GB parameter
    if grep -A5 "^check_disk_space()" "$VM_LIFECYCLE_SCRIPT" | grep -q "required_gb"; then
        pass "check_disk_space accepts required_gb parameter"
    else
        fail "check_disk_space should accept required_gb parameter"
    fi
}

# =============================================================================
# Test: Color Variables
# =============================================================================
test_color_variables() {
    section "Testing Color Variables"

    # Check color variables are defined in the script
    if grep -q "RED=" "$VM_LIFECYCLE_SCRIPT"; then
        pass "RED color variable defined"
    else
        fail "RED color variable not defined"
    fi

    if grep -q "GREEN=" "$VM_LIFECYCLE_SCRIPT"; then
        pass "GREEN color variable defined"
    else
        fail "GREEN color variable not defined"
    fi

    if grep -q "YELLOW=" "$VM_LIFECYCLE_SCRIPT"; then
        pass "YELLOW color variable defined"
    else
        fail "YELLOW color variable not defined"
    fi

    if grep -q "NC=" "$VM_LIFECYCLE_SCRIPT"; then
        pass "NC (no color) variable defined"
    else
        fail "NC (no color) variable not defined"
    fi
}

# =============================================================================
# Test: Error Handling Patterns
# =============================================================================
test_error_handling() {
    section "Testing Error Handling Patterns"

    # Check for 'set -euo pipefail'
    if grep -q "set -euo pipefail" "$VM_LIFECYCLE_SCRIPT"; then
        pass "Script uses strict error handling (set -euo pipefail)"
    else
        fail "Script should use 'set -euo pipefail'"
    fi

    # Check functions return proper exit codes
    if grep -q "return 1" "$VM_LIFECYCLE_SCRIPT"; then
        pass "Functions return error exit codes"
    else
        fail "Functions should return error exit codes"
    fi

    if grep -q "return 0" "$VM_LIFECYCLE_SCRIPT"; then
        pass "Functions return success exit codes"
    else
        fail "Functions should return success exit codes"
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
    test_script_syntax
    test_required_functions
    test_sourcing_script
    test_logging_functions
    test_create_vm_validation
    test_start_vm_headless_validation
    test_stop_vm_validation
    test_delete_vm_validation
    test_cleanup_vm_validation
    test_get_vm_ip_validation
    test_wait_for_ssh_validation
    test_run_in_vm_validation
    test_copy_to_vm_validation
    test_vm_exists_function
    test_environment_defaults
    test_help_output
    test_script_test_mode
    test_check_disk_space
    test_color_variables
    test_error_handling

    print_summary
}

main "$@"
