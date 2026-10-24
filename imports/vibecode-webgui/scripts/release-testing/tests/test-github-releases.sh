#!/bin/bash
# Unit Tests for GitHub Release Integration Functions
# ====================================================
# Tests for scripts/release-testing/github-releases.sh
# Run: bash scripts/release-testing/tests/test-github-releases.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
GITHUB_RELEASES_SCRIPT="${PROJECT_ROOT}/scripts/release-testing/github-releases.sh"

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
    echo -e "${BLUE}GitHub Release Integration Unit Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    TEST_START_TIME=$(date +%s)
}

# =============================================================================
# Test: Script Syntax and Structure
# =============================================================================
test_script_syntax() {
    section "Testing Script Syntax"

    # Test bash syntax
    if bash -n "$GITHUB_RELEASES_SCRIPT" 2>/dev/null; then
        pass "github-releases.sh has valid bash syntax"
    else
        fail "github-releases.sh has syntax errors"
        return 1
    fi

    # Test script is executable or has shebang
    if head -1 "$GITHUB_RELEASES_SCRIPT" | grep -q "^#!/bin/bash"; then
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
        "check_gh_auth"
        "get_all_releases"
        "get_release_count"
        "get_release_info"
        "get_release_assets"
        "has_release_assets"
        "download_release_assets"
        "download_release_asset"
        "get_latest_release"
        "release_exists"
        "get_releases_since"
        "log_info"
        "log_warn"
        "log_error"
    )

    for func in "${required_functions[@]}"; do
        if grep -q "^${func}()" "$GITHUB_RELEASES_SCRIPT"; then
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
    if (source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null && type check_gh_auth &>/dev/null); then
        pass "Script can be sourced successfully"
    else
        fail "Script cannot be sourced"
        return 1
    fi

    # Verify functions are available after sourcing
    if (source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null && type log_info &>/dev/null); then
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
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

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
# Test: Argument Validation - get_all_releases
# =============================================================================
test_get_all_releases_validation() {
    section "Testing get_all_releases Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Mock gh command to avoid actual API calls
    gh() { return 1; }
    export -f gh

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty repo
    local output
    if ! output=$(get_all_releases "" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "get_all_releases rejects empty repository"
        else
            fail "get_all_releases should mention 'Repository is required'"
        fi
    else
        fail "get_all_releases should fail with empty repository"
    fi

    # Test "/" repo (edge case)
    if ! output=$(get_all_releases "/" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "get_all_releases rejects '/' as repository"
        else
            fail "get_all_releases should reject '/' as repository"
        fi
    else
        fail "get_all_releases should fail with '/' repository"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
    unset -f gh
}

# =============================================================================
# Test: Argument Validation - get_release_info
# =============================================================================
test_get_release_info_validation() {
    section "Testing get_release_info Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty tag
    local output
    if ! output=$(get_release_info "" 2>&1); then
        if echo "$output" | grep -q "tag is required"; then
            pass "get_release_info rejects empty tag"
        else
            fail "get_release_info should mention 'tag is required'"
        fi
    else
        fail "get_release_info should fail with empty tag"
    fi

    # Test empty repo with valid tag
    if ! output=$(get_release_info "v1.0.0" "" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "get_release_info rejects empty repository"
        else
            fail "get_release_info should mention 'Repository is required'"
        fi
    else
        fail "get_release_info should fail with empty repository"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: Argument Validation - get_release_assets
# =============================================================================
test_get_release_assets_validation() {
    section "Testing get_release_assets Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty tag
    local output
    if ! output=$(get_release_assets "" 2>&1); then
        if echo "$output" | grep -q "tag is required"; then
            pass "get_release_assets rejects empty tag"
        else
            fail "get_release_assets should mention 'tag is required'"
        fi
    else
        fail "get_release_assets should fail with empty tag"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: Argument Validation - download_release_assets
# =============================================================================
test_download_release_assets_validation() {
    section "Testing download_release_assets Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty tag
    local output
    if ! output=$(download_release_assets "" "/tmp/test" 2>&1); then
        if echo "$output" | grep -q "tag is required"; then
            pass "download_release_assets rejects empty tag"
        else
            fail "download_release_assets should mention 'tag is required'"
        fi
    else
        fail "download_release_assets should fail with empty tag"
    fi

    # Test empty output directory
    if ! output=$(download_release_assets "v1.0.0" "" 2>&1); then
        if echo "$output" | grep -q "directory is required"; then
            pass "download_release_assets rejects empty output directory"
        else
            fail "download_release_assets should mention 'directory is required'"
        fi
    else
        fail "download_release_assets should fail with empty output directory"
    fi

    # Test empty repo
    if ! output=$(download_release_assets "v1.0.0" "/tmp/test" "" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "download_release_assets rejects empty repository"
        else
            fail "download_release_assets should mention 'Repository is required'"
        fi
    else
        fail "download_release_assets should fail with empty repository"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: Argument Validation - download_release_asset
# =============================================================================
test_download_release_asset_validation() {
    section "Testing download_release_asset Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty arguments
    local output
    if ! output=$(download_release_asset "" "asset.zip" "/tmp/test" 2>&1); then
        if echo "$output" | grep -q "required"; then
            pass "download_release_asset rejects empty tag"
        else
            fail "download_release_asset should mention required arguments"
        fi
    else
        fail "download_release_asset should fail with empty tag"
    fi

    if ! output=$(download_release_asset "v1.0.0" "" "/tmp/test" 2>&1); then
        if echo "$output" | grep -q "required"; then
            pass "download_release_asset rejects empty asset name"
        else
            fail "download_release_asset should mention required arguments"
        fi
    else
        fail "download_release_asset should fail with empty asset name"
    fi

    if ! output=$(download_release_asset "v1.0.0" "asset.zip" "" 2>&1); then
        if echo "$output" | grep -q "required"; then
            pass "download_release_asset rejects empty output directory"
        else
            fail "download_release_asset should mention required arguments"
        fi
    else
        fail "download_release_asset should fail with empty output directory"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: Argument Validation - get_latest_release
# =============================================================================
test_get_latest_release_validation() {
    section "Testing get_latest_release Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty repo
    local output
    if ! output=$(get_latest_release "" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "get_latest_release rejects empty repository"
        else
            fail "get_latest_release should mention 'Repository is required'"
        fi
    else
        fail "get_latest_release should fail with empty repository"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: Argument Validation - get_releases_since
# =============================================================================
test_get_releases_since_validation() {
    section "Testing get_releases_since Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty date
    local output
    if ! output=$(get_releases_since "" 2>&1); then
        if echo "$output" | grep -q "Date is required"; then
            pass "get_releases_since rejects empty date"
        else
            fail "get_releases_since should mention 'Date is required'"
        fi
    else
        fail "get_releases_since should fail with empty date"
    fi

    # Test empty repo
    if ! output=$(get_releases_since "2024-01-01" "" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "get_releases_since rejects empty repository"
        else
            fail "get_releases_since should mention 'Repository is required'"
        fi
    else
        fail "get_releases_since should fail with empty repository"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: release_exists Function
# =============================================================================
test_release_exists_function() {
    section "Testing release_exists Function"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Test empty tag
    if ! release_exists ""; then
        pass "release_exists returns false for empty tag"
    else
        fail "release_exists should return false for empty tag"
    fi

    # Test empty repo
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    if ! release_exists "v1.0.0" ""; then
        pass "release_exists returns false for empty repo"
    else
        fail "release_exists should return false for empty repo"
    fi

    # Test "/" repo
    if ! release_exists "v1.0.0" "/"; then
        pass "release_exists returns false for '/' repo"
    else
        fail "release_exists should return false for '/' repo"
    fi

    GITHUB_FULL_REPO="$old_repo"
}

# =============================================================================
# Test: has_release_assets Function
# =============================================================================
test_has_release_assets_function() {
    section "Testing has_release_assets Function"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Test empty tag
    if ! has_release_assets ""; then
        pass "has_release_assets returns false for empty tag"
    else
        fail "has_release_assets should return false for empty tag"
    fi
}

# =============================================================================
# Test: Environment Variables
# =============================================================================
test_environment_defaults() {
    section "Testing Environment Variable Defaults"

    # Source in a clean subshell
    local output

    # Check RELEASE_LIMIT default
    output=$(bash -c "source '$GITHUB_RELEASES_SCRIPT' && echo \"\$RELEASE_LIMIT\"" 2>/dev/null)
    if [[ "$output" == "1000" ]]; then
        pass "RELEASE_LIMIT defaults to 1000"
    else
        fail "RELEASE_LIMIT should default to 1000 (got: $output)"
    fi

    # Check INCLUDE_PRERELEASES default
    output=$(bash -c "source '$GITHUB_RELEASES_SCRIPT' && echo \"\$INCLUDE_PRERELEASES\"" 2>/dev/null)
    if [[ "$output" == "false" ]]; then
        pass "INCLUDE_PRERELEASES defaults to false"
    else
        fail "INCLUDE_PRERELEASES should default to false (got: $output)"
    fi

    # Check INCLUDE_DRAFTS default
    output=$(bash -c "source '$GITHUB_RELEASES_SCRIPT' && echo \"\$INCLUDE_DRAFTS\"" 2>/dev/null)
    if [[ "$output" == "false" ]]; then
        pass "INCLUDE_DRAFTS defaults to false"
    else
        fail "INCLUDE_DRAFTS should default to false (got: $output)"
    fi

    # Check GH_CMD default (may be 'gh' or full path like '/opt/homebrew/bin/gh')
    output=$(bash -c "source '$GITHUB_RELEASES_SCRIPT' && echo \"\$GH_CMD\"" 2>/dev/null)
    if [[ "$output" == "gh" || "$output" =~ /gh$ ]]; then
        pass "GH_CMD defaults to gh (value: $output)"
    else
        fail "GH_CMD should default to gh or path ending in /gh (got: $output)"
    fi
}

# =============================================================================
# Test: Script Help Output
# =============================================================================
test_help_output() {
    section "Testing Script Help Output"

    # Run script with --help
    local output
    output=$("$GITHUB_RELEASES_SCRIPT" --help 2>&1)

    if echo "$output" | grep -q "get_all_releases"; then
        pass "Help mentions get_all_releases function"
    else
        fail "Help should mention get_all_releases function"
    fi

    if echo "$output" | grep -q "Available functions"; then
        pass "Help shows available functions"
    else
        fail "Help should show available functions"
    fi

    if echo "$output" | grep -q "RELEASE_LIMIT"; then
        pass "Help shows RELEASE_LIMIT environment variable"
    else
        fail "Help should show RELEASE_LIMIT"
    fi

    if echo "$output" | grep -q "download_release_asset"; then
        pass "Help mentions download_release_asset function"
    else
        fail "Help should mention download_release_asset function"
    fi
}

# =============================================================================
# Test: Script Test Mode
# =============================================================================
test_script_test_mode() {
    section "Testing Script Test Mode"

    # Run script with --test
    local output
    output=$("$GITHUB_RELEASES_SCRIPT" --test 2>&1) || true

    if echo "$output" | grep -q "Syntax check passed"; then
        pass "Script --test mode outputs 'Syntax check passed'"
    else
        fail "Script --test mode should output 'Syntax check passed'"
    fi

    if echo "$output" | grep -q "INFO"; then
        pass "Test mode exercises log_info"
    else
        fail "Test mode should exercise log_info"
    fi

    if echo "$output" | grep -q "WARN"; then
        pass "Test mode exercises log_warn"
    else
        fail "Test mode should exercise log_warn"
    fi

    if echo "$output" | grep -q "ERROR"; then
        pass "Test mode exercises log_error"
    else
        fail "Test mode should exercise log_error"
    fi
}

# =============================================================================
# Test: Color Variables
# =============================================================================
test_color_variables() {
    section "Testing Color Variables"

    # Check color variables are defined in the script
    if grep -q "RED=" "$GITHUB_RELEASES_SCRIPT"; then
        pass "RED color variable defined"
    else
        fail "RED color variable not defined"
    fi

    if grep -q "GREEN=" "$GITHUB_RELEASES_SCRIPT"; then
        pass "GREEN color variable defined"
    else
        fail "GREEN color variable not defined"
    fi

    if grep -q "YELLOW=" "$GITHUB_RELEASES_SCRIPT"; then
        pass "YELLOW color variable defined"
    else
        fail "YELLOW color variable not defined"
    fi

    if grep -q "NC=" "$GITHUB_RELEASES_SCRIPT"; then
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
    if grep -q "set -euo pipefail" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script uses strict error handling (set -euo pipefail)"
    else
        fail "Script should use 'set -euo pipefail'"
    fi

    # Check functions return proper exit codes
    if grep -q "return 1" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Functions return error exit codes"
    else
        fail "Functions should return error exit codes"
    fi

    if grep -q "return 0" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Functions return success exit codes"
    else
        fail "Functions should return success exit codes"
    fi
}

# =============================================================================
# Test: GitHub CLI Commands Used
# =============================================================================
test_gh_cli_commands() {
    section "Testing GitHub CLI Command Usage"

    # Check that gh release list is used
    if grep -q 'gh release list\|"$GH_CMD" release list' "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script uses 'gh release list' command"
    else
        fail "Script should use 'gh release list' command"
    fi

    # Check that gh release view is used
    if grep -q 'gh release view\|"$GH_CMD" release view' "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script uses 'gh release view' command"
    else
        fail "Script should use 'gh release view' command"
    fi

    # Check that gh release download is used
    if grep -q 'gh release download\|"$GH_CMD" release download' "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script uses 'gh release download' command"
    else
        fail "Script should use 'gh release download' command"
    fi

    # Check that gh auth status is used
    if grep -q 'gh auth status\|"$GH_CMD" auth status' "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script uses 'gh auth status' command"
    else
        fail "Script should use 'gh auth status' command"
    fi
}

# =============================================================================
# Test: JSON Parsing
# =============================================================================
test_json_parsing() {
    section "Testing JSON Parsing"

    # Check that jq filters are used
    if grep -q "\-\-jq" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script uses --jq flag for JSON parsing"
    else
        fail "Script should use --jq flag for JSON parsing"
    fi

    # Check that proper JSON fields are extracted
    if grep -q "tagName" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script extracts tagName field"
    else
        fail "Script should extract tagName field"
    fi

    if grep -q "isDraft" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script filters on isDraft field"
    else
        fail "Script should filter on isDraft field"
    fi

    if grep -q "isPrerelease" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script filters on isPrerelease field"
    else
        fail "Script should filter on isPrerelease field"
    fi
}

# =============================================================================
# Test: Configuration Sourcing
# =============================================================================
test_config_sourcing() {
    section "Testing Configuration Sourcing"

    # Check that script attempts to source config.env
    if grep -q "config.env" "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script references config.env"
    else
        fail "Script should reference config.env"
    fi

    # Check that sourcing is optional (uses -f check)
    if grep -q '\[\[ -f.*config.env' "$GITHUB_RELEASES_SCRIPT"; then
        pass "Script conditionally sources config.env"
    else
        fail "Script should conditionally source config.env"
    fi
}

# =============================================================================
# Test: get_release_count Function
# =============================================================================
test_get_release_count_validation() {
    section "Testing get_release_count Argument Validation"

    # Source the script
    source "$GITHUB_RELEASES_SCRIPT" 2>/dev/null || true

    # Clear GITHUB_FULL_REPO to test empty repo validation
    local old_repo="${GITHUB_FULL_REPO:-}"
    GITHUB_FULL_REPO=""

    # Test empty repo
    local output
    if ! output=$(get_release_count "" 2>&1); then
        if echo "$output" | grep -q "Repository is required"; then
            pass "get_release_count rejects empty repository"
        else
            fail "get_release_count should mention 'Repository is required'"
        fi
    else
        fail "get_release_count should fail with empty repository"
    fi

    # Restore
    GITHUB_FULL_REPO="$old_repo"
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

    # Check if github-releases.sh exists
    if [[ ! -f "$GITHUB_RELEASES_SCRIPT" ]]; then
        fail "github-releases.sh not found at $GITHUB_RELEASES_SCRIPT"
        print_summary
        exit 1
    fi

    # Run all tests
    test_script_syntax
    test_required_functions
    test_sourcing_script
    test_logging_functions
    test_get_all_releases_validation
    test_get_release_info_validation
    test_get_release_assets_validation
    test_download_release_assets_validation
    test_download_release_asset_validation
    test_get_latest_release_validation
    test_get_releases_since_validation
    test_release_exists_function
    test_has_release_assets_function
    test_get_release_count_validation
    test_environment_defaults
    test_help_output
    test_script_test_mode
    test_color_variables
    test_error_handling
    test_gh_cli_commands
    test_json_parsing
    test_config_sourcing

    print_summary
}

main "$@"
