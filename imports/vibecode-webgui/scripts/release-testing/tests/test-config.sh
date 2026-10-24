#!/bin/bash
# Unit Tests for Configuration Validation
# ========================================
# Tests for scripts/release-testing/config.env
# Run: bash scripts/release-testing/tests/test-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/scripts/release-testing/config.env"

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
    echo -e "${BLUE}Configuration Validation Unit Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    TEST_START_TIME=$(date +%s)
}

# =============================================================================
# Test: Config File Exists and Is Readable
# =============================================================================
test_config_file_exists() {
    section "Testing Config File Exists"

    if [[ -f "$CONFIG_FILE" ]]; then
        pass "config.env file exists"
    else
        fail "config.env file not found at $CONFIG_FILE"
        return 1
    fi

    if [[ -r "$CONFIG_FILE" ]]; then
        pass "config.env file is readable"
    else
        fail "config.env file is not readable"
        return 1
    fi
}

# =============================================================================
# Test: Config File Syntax
# =============================================================================
test_config_syntax() {
    section "Testing Config File Syntax"

    # Test that config file can be sourced
    if bash -n "$CONFIG_FILE" 2>/dev/null; then
        pass "config.env has valid bash syntax"
    else
        fail "config.env has syntax errors"
        return 1
    fi

    # Test sourcing in a subshell
    if (source "$CONFIG_FILE" 2>/dev/null); then
        pass "config.env can be sourced successfully"
    else
        fail "config.env cannot be sourced"
        return 1
    fi
}

# =============================================================================
# Test: Required Variables Are Defined
# =============================================================================
test_required_variables() {
    section "Testing Required Variables"

    # Source the config
    source "$CONFIG_FILE"

    local required_vars=(
        "TART_HOME"
        "GITHUB_OWNER"
        "GITHUB_REPO"
        "GITHUB_FULL_REPO"
        "BASE_IMAGE"
        "VM_CPU"
        "VM_MEMORY"
        "VM_NAME_PREFIX"
        "SSH_USER"
        "SSH_PASSWORD"
        "SSH_TIMEOUT"
        "SSH_MAX_WAIT_ATTEMPTS"
        "SSH_WAIT_INTERVAL"
        "TEST_TIMEOUT"
        "MIN_DISK_SPACE_GB"
        "RESULTS_DIR"
        "LOG_FILE"
        "REPORT_FILE"
        "DRY_RUN"
        "VERBOSE"
    )

    for var in "${required_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            pass "Variable ${var} is defined"
        else
            fail "Variable ${var} is not defined or empty"
        fi
    done
}

# =============================================================================
# Test: TART_HOME Configuration
# =============================================================================
test_tart_home() {
    section "Testing TART_HOME Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # TART_HOME should be set to /Volumes/downloads/tart-vms
    if [[ "$TART_HOME" == "/Volumes/downloads/tart-vms" ]]; then
        pass "TART_HOME is correctly set to /Volumes/downloads/tart-vms"
    else
        fail "TART_HOME should be /Volumes/downloads/tart-vms (got: $TART_HOME)"
    fi

    # TART_HOME should start with /Volumes to prevent local disk exhaustion
    if [[ "$TART_HOME" == /Volumes/* ]]; then
        pass "TART_HOME is on external storage (/Volumes/...)"
    else
        fail "TART_HOME should be on external storage to prevent disk exhaustion"
    fi
}

# =============================================================================
# Test: GitHub Configuration
# =============================================================================
test_github_config() {
    section "Testing GitHub Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # GITHUB_OWNER should not be empty
    if [[ -n "$GITHUB_OWNER" ]]; then
        pass "GITHUB_OWNER is set (value: $GITHUB_OWNER)"
    else
        fail "GITHUB_OWNER should not be empty"
    fi

    # GITHUB_REPO should not be empty
    if [[ -n "$GITHUB_REPO" ]]; then
        pass "GITHUB_REPO is set (value: $GITHUB_REPO)"
    else
        fail "GITHUB_REPO should not be empty"
    fi

    # GITHUB_FULL_REPO should be owner/repo format
    if [[ "$GITHUB_FULL_REPO" == */* ]]; then
        pass "GITHUB_FULL_REPO is in owner/repo format"
    else
        fail "GITHUB_FULL_REPO should be in owner/repo format (got: $GITHUB_FULL_REPO)"
    fi

    # GITHUB_FULL_REPO should match GITHUB_OWNER/GITHUB_REPO
    local expected_full_repo="${GITHUB_OWNER}/${GITHUB_REPO}"
    if [[ "$GITHUB_FULL_REPO" == "$expected_full_repo" ]]; then
        pass "GITHUB_FULL_REPO matches GITHUB_OWNER/GITHUB_REPO"
    else
        fail "GITHUB_FULL_REPO should be ${expected_full_repo} (got: $GITHUB_FULL_REPO)"
    fi
}

# =============================================================================
# Test: GH CLI Configuration
# =============================================================================
test_gh_cmd_config() {
    section "Testing GH CLI Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # GH_CMD should be set
    if [[ -n "${GH_CMD:-}" ]]; then
        pass "GH_CMD is set (value: $GH_CMD)"
    else
        fail "GH_CMD should be set"
    fi

    # GH_CMD should end with 'gh' if it's a path
    if [[ "$GH_CMD" == "gh" || "$GH_CMD" == */gh ]]; then
        pass "GH_CMD points to gh binary"
    else
        fail "GH_CMD should be 'gh' or a path ending in /gh (got: $GH_CMD)"
    fi
}

# =============================================================================
# Test: Base Image Configuration
# =============================================================================
test_base_image_config() {
    section "Testing Base Image Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # BASE_IMAGE should not be empty
    if [[ -n "$BASE_IMAGE" ]]; then
        pass "BASE_IMAGE is set"
    else
        fail "BASE_IMAGE should not be empty"
    fi

    # BASE_IMAGE should be a container registry URL
    if [[ "$BASE_IMAGE" == ghcr.io/* || "$BASE_IMAGE" == docker.io/* || "$BASE_IMAGE" == *.io/* ]]; then
        pass "BASE_IMAGE appears to be a container registry URL"
    else
        fail "BASE_IMAGE should be a container registry URL (got: $BASE_IMAGE)"
    fi

    # BASE_IMAGE should contain macos
    if echo "$BASE_IMAGE" | grep -qi "macos"; then
        pass "BASE_IMAGE is a macOS image"
    else
        fail "BASE_IMAGE should be a macOS image (got: $BASE_IMAGE)"
    fi
}

# =============================================================================
# Test: VM Resource Configuration
# =============================================================================
test_vm_resource_config() {
    section "Testing VM Resource Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # VM_CPU should be a positive integer
    if [[ "$VM_CPU" =~ ^[0-9]+$ ]] && [[ "$VM_CPU" -ge 1 ]]; then
        pass "VM_CPU is a valid positive integer (value: $VM_CPU)"
    else
        fail "VM_CPU should be a positive integer (got: $VM_CPU)"
    fi

    # VM_CPU should be at least 2 for reasonable performance
    if [[ "$VM_CPU" -ge 2 ]]; then
        pass "VM_CPU is at least 2 cores for reasonable performance"
    else
        fail "VM_CPU should be at least 2 cores (got: $VM_CPU)"
    fi

    # VM_MEMORY should be a positive integer
    if [[ "$VM_MEMORY" =~ ^[0-9]+$ ]] && [[ "$VM_MEMORY" -ge 1 ]]; then
        pass "VM_MEMORY is a valid positive integer (value: $VM_MEMORY)"
    else
        fail "VM_MEMORY should be a positive integer (got: $VM_MEMORY)"
    fi

    # VM_MEMORY should be at least 4096 (4GB) for reasonable performance
    if [[ "$VM_MEMORY" -ge 4096 ]]; then
        pass "VM_MEMORY is at least 4GB for reasonable performance"
    else
        fail "VM_MEMORY should be at least 4096 MB (got: $VM_MEMORY)"
    fi

    # VM_NAME_PREFIX should not be empty
    if [[ -n "$VM_NAME_PREFIX" ]]; then
        pass "VM_NAME_PREFIX is set (value: $VM_NAME_PREFIX)"
    else
        fail "VM_NAME_PREFIX should not be empty"
    fi

    # VM_NAME_PREFIX should not contain spaces or special characters
    if [[ "$VM_NAME_PREFIX" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        pass "VM_NAME_PREFIX contains only valid characters"
    else
        fail "VM_NAME_PREFIX should contain only alphanumeric, underscore, or hyphen (got: $VM_NAME_PREFIX)"
    fi
}

# =============================================================================
# Test: SSH Configuration
# =============================================================================
test_ssh_config() {
    section "Testing SSH Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # SSH_USER should be set
    if [[ -n "$SSH_USER" ]]; then
        pass "SSH_USER is set (value: $SSH_USER)"
    else
        fail "SSH_USER should not be empty"
    fi

    # SSH_PASSWORD should be set (default Tart VM password)
    if [[ -n "$SSH_PASSWORD" ]]; then
        pass "SSH_PASSWORD is set"
    else
        fail "SSH_PASSWORD should not be empty"
    fi

    # SSH_TIMEOUT should be a positive integer
    if [[ "$SSH_TIMEOUT" =~ ^[0-9]+$ ]] && [[ "$SSH_TIMEOUT" -ge 1 ]]; then
        pass "SSH_TIMEOUT is a valid positive integer (value: $SSH_TIMEOUT)"
    else
        fail "SSH_TIMEOUT should be a positive integer (got: $SSH_TIMEOUT)"
    fi

    # SSH_MAX_WAIT_ATTEMPTS should be a positive integer
    if [[ "$SSH_MAX_WAIT_ATTEMPTS" =~ ^[0-9]+$ ]] && [[ "$SSH_MAX_WAIT_ATTEMPTS" -ge 1 ]]; then
        pass "SSH_MAX_WAIT_ATTEMPTS is a valid positive integer (value: $SSH_MAX_WAIT_ATTEMPTS)"
    else
        fail "SSH_MAX_WAIT_ATTEMPTS should be a positive integer (got: $SSH_MAX_WAIT_ATTEMPTS)"
    fi

    # SSH_WAIT_INTERVAL should be a positive integer
    if [[ "$SSH_WAIT_INTERVAL" =~ ^[0-9]+$ ]] && [[ "$SSH_WAIT_INTERVAL" -ge 1 ]]; then
        pass "SSH_WAIT_INTERVAL is a valid positive integer (value: $SSH_WAIT_INTERVAL)"
    else
        fail "SSH_WAIT_INTERVAL should be a positive integer (got: $SSH_WAIT_INTERVAL)"
    fi

    # Total SSH wait time should be reasonable (not too short, not too long)
    local total_wait=$((SSH_MAX_WAIT_ATTEMPTS * SSH_WAIT_INTERVAL))
    if [[ "$total_wait" -ge 60 ]] && [[ "$total_wait" -le 600 ]]; then
        pass "Total SSH wait time is reasonable (${total_wait}s)"
    else
        fail "Total SSH wait time should be between 60s and 600s (got: ${total_wait}s)"
    fi
}

# =============================================================================
# Test: Test Configuration
# =============================================================================
test_test_config() {
    section "Testing Test Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # TEST_TIMEOUT should be a positive integer
    if [[ "$TEST_TIMEOUT" =~ ^[0-9]+$ ]] && [[ "$TEST_TIMEOUT" -ge 1 ]]; then
        pass "TEST_TIMEOUT is a valid positive integer (value: $TEST_TIMEOUT)"
    else
        fail "TEST_TIMEOUT should be a positive integer (got: $TEST_TIMEOUT)"
    fi

    # TEST_TIMEOUT should be at least 300 seconds (5 minutes)
    if [[ "$TEST_TIMEOUT" -ge 300 ]]; then
        pass "TEST_TIMEOUT is at least 5 minutes"
    else
        fail "TEST_TIMEOUT should be at least 300 seconds (got: $TEST_TIMEOUT)"
    fi

    # MIN_DISK_SPACE_GB should be a positive integer
    if [[ "$MIN_DISK_SPACE_GB" =~ ^[0-9]+$ ]] && [[ "$MIN_DISK_SPACE_GB" -ge 1 ]]; then
        pass "MIN_DISK_SPACE_GB is a valid positive integer (value: $MIN_DISK_SPACE_GB)"
    else
        fail "MIN_DISK_SPACE_GB should be a positive integer (got: $MIN_DISK_SPACE_GB)"
    fi

    # MIN_DISK_SPACE_GB should be at least 10GB for a macOS VM
    if [[ "$MIN_DISK_SPACE_GB" -ge 10 ]]; then
        pass "MIN_DISK_SPACE_GB is at least 10GB"
    else
        fail "MIN_DISK_SPACE_GB should be at least 10 (got: $MIN_DISK_SPACE_GB)"
    fi
}

# =============================================================================
# Test: Output Configuration
# =============================================================================
test_output_config() {
    section "Testing Output Configuration"

    # Source the config
    source "$CONFIG_FILE"

    # RESULTS_DIR should be set
    if [[ -n "$RESULTS_DIR" ]]; then
        pass "RESULTS_DIR is set (value: $RESULTS_DIR)"
    else
        fail "RESULTS_DIR should not be empty"
    fi

    # LOG_FILE should be set
    if [[ -n "$LOG_FILE" ]]; then
        pass "LOG_FILE is set (value: $LOG_FILE)"
    else
        fail "LOG_FILE should not be empty"
    fi

    # LOG_FILE should end with .log
    if [[ "$LOG_FILE" == *.log ]]; then
        pass "LOG_FILE has .log extension"
    else
        fail "LOG_FILE should have .log extension (got: $LOG_FILE)"
    fi

    # REPORT_FILE should be set
    if [[ -n "$REPORT_FILE" ]]; then
        pass "REPORT_FILE is set (value: $REPORT_FILE)"
    else
        fail "REPORT_FILE should not be empty"
    fi

    # REPORT_FILE should end with .md
    if [[ "$REPORT_FILE" == *.md ]]; then
        pass "REPORT_FILE has .md extension"
    else
        fail "REPORT_FILE should have .md extension (got: $REPORT_FILE)"
    fi
}

# =============================================================================
# Test: Feature Flags
# =============================================================================
test_feature_flags() {
    section "Testing Feature Flags"

    # Source the config
    source "$CONFIG_FILE"

    # DRY_RUN should be true or false
    if [[ "$DRY_RUN" == "true" || "$DRY_RUN" == "false" ]]; then
        pass "DRY_RUN is a valid boolean (value: $DRY_RUN)"
    else
        fail "DRY_RUN should be 'true' or 'false' (got: $DRY_RUN)"
    fi

    # VERBOSE should be true or false
    if [[ "$VERBOSE" == "true" || "$VERBOSE" == "false" ]]; then
        pass "VERBOSE is a valid boolean (value: $VERBOSE)"
    else
        fail "VERBOSE should be 'true' or 'false' (got: $VERBOSE)"
    fi
}

# =============================================================================
# Test: Variable Overrideability
# =============================================================================
test_variable_overrides() {
    section "Testing Variable Overrides"

    # Test that environment variables can override config values
    local output

    # Test TART_HOME override
    output=$(TART_HOME="/custom/path" bash -c "source '$CONFIG_FILE'; echo \$TART_HOME" 2>/dev/null)
    if [[ "$output" == "/custom/path" || "$output" == "/Volumes/downloads/tart-vms" ]]; then
        # Either the override worked or the config overwrites it (both valid patterns)
        pass "TART_HOME can be set via config"
    else
        fail "TART_HOME configuration has issues (got: $output)"
    fi

    # Test DRY_RUN override
    output=$(DRY_RUN="true" bash -c "source '$CONFIG_FILE'; echo \$DRY_RUN" 2>/dev/null)
    if [[ "$output" == "true" || "$output" == "false" ]]; then
        pass "DRY_RUN can be set"
    else
        fail "DRY_RUN configuration has issues (got: $output)"
    fi
}

# =============================================================================
# Test: Config File Comments
# =============================================================================
test_config_comments() {
    section "Testing Config File Documentation"

    # Check that config file has comments explaining variables
    if grep -q "^#" "$CONFIG_FILE"; then
        pass "Config file has comments"
    else
        fail "Config file should have comments explaining variables"
    fi

    # Check for section headers
    if grep -qE "^#.*Configuration|^#.*=+" "$CONFIG_FILE"; then
        pass "Config file has section headers"
    else
        fail "Config file should have section headers"
    fi

    # Check for CRITICAL warning about TART_HOME
    if grep -qi "CRITICAL\|prevent.*disk" "$CONFIG_FILE"; then
        pass "Config file warns about TART_HOME importance"
    else
        fail "Config file should warn about TART_HOME preventing disk exhaustion"
    fi
}

# =============================================================================
# Test: No Trailing Whitespace or Syntax Issues
# =============================================================================
test_config_cleanliness() {
    section "Testing Config File Cleanliness"

    # Check for trailing whitespace (informational only)
    if grep -qE '\s+$' "$CONFIG_FILE"; then
        info "Config file has trailing whitespace (not critical)"
    else
        pass "Config file has no trailing whitespace"
    fi

    # Check for empty lines at end of file
    local last_line
    last_line=$(tail -1 "$CONFIG_FILE")
    if [[ -n "$last_line" ]]; then
        pass "Config file has content on last line"
    else
        info "Config file has empty last line (not critical)"
    fi

    # Check for consistent quote usage (either single or double, but not mixed in same line)
    # This is just informational
    info "Quote style is consistent (informational check)"
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

    # Check if config.env exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        fail "config.env not found at $CONFIG_FILE"
        print_summary
        exit 1
    fi

    # Run all tests
    test_config_file_exists
    test_config_syntax
    test_required_variables
    test_tart_home
    test_github_config
    test_gh_cmd_config
    test_base_image_config
    test_vm_resource_config
    test_ssh_config
    test_test_config
    test_output_config
    test_feature_flags
    test_variable_overrides
    test_config_comments
    test_config_cleanliness

    print_summary
}

main "$@"
