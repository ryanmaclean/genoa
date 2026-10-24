#!/bin/bash
# Unit Test Runner for Release Testing Suite
# ===========================================
# Discovers and runs all test-*.sh scripts in this directory
# Run: bash scripts/release-testing/tests/run-all-tests.sh
#
# Options:
#   --verbose    Show full test output (default: summary only)
#   --help       Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_PASS=0
TOTAL_FAIL=0
SUITES_PASS=0
SUITES_FAIL=0
START_TIME=0

# Options
VERBOSE=false

# =============================================================================
# Helper Functions
# =============================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Discovers and runs all test-*.sh scripts in the tests directory."
    echo ""
    echo "Options:"
    echo "  --verbose    Show full test output (default: summary only)"
    echo "  --help       Show this help message"
    echo ""
    echo "Exit codes:"
    echo "  0    All tests passed"
    echo "  1    One or more tests failed"
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# =============================================================================
# Parse Command Line Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# =============================================================================
# Test Discovery
# =============================================================================

discover_tests() {
    local tests=()

    # Find all test-*.sh files in the script directory
    while IFS= read -r -d '' test_file; do
        # Skip this script itself
        if [[ "$(basename "$test_file")" != "run-all-tests.sh" ]]; then
            tests+=("$test_file")
        fi
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test-*.sh" -type f -print0 | sort -z)

    echo "${tests[@]}"
}

# =============================================================================
# Run Single Test Suite
# =============================================================================

run_test_suite() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)

    local output
    local exit_code=0

    echo -e "\n${YELLOW}>>> Running: ${test_name}${NC}"

    # Run the test and capture output
    if [[ "$VERBOSE" == "true" ]]; then
        # Show full output
        if bash "$test_file"; then
            exit_code=0
        else
            exit_code=1
        fi
    else
        # Capture output, only show on failure
        output=$(bash "$test_file" 2>&1) || exit_code=$?
    fi

    # Parse results from test output
    local passed=0
    local failed=0

    if [[ "$VERBOSE" == "false" ]]; then
        # Extract pass/fail counts from output
        passed=$(echo "$output" | grep -oE "Passed: [0-9]+" | grep -oE "[0-9]+" | tail -1) || passed=0
        failed=$(echo "$output" | grep -oE "Failed: [0-9]+" | grep -oE "[0-9]+" | tail -1) || failed=0
    fi

    if [[ "$exit_code" -eq 0 ]]; then
        echo -e "${GREEN}    ✓ PASSED${NC} (${passed:-?} tests)"
        ((SUITES_PASS++)) || true
    else
        echo -e "${RED}    ✗ FAILED${NC} (${failed:-?} failures)"
        ((SUITES_FAIL++)) || true

        # Show output on failure if not verbose
        if [[ "$VERBOSE" == "false" ]]; then
            echo -e "${RED}--- Test Output ---${NC}"
            echo "$output" | tail -50
            echo -e "${RED}--- End Output ---${NC}"
        fi
    fi

    # Accumulate totals
    ((TOTAL_PASS += passed)) || true
    ((TOTAL_FAIL += failed)) || true

    return $exit_code
}

# =============================================================================
# Print Summary
# =============================================================================

print_summary() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    section "Test Suite Summary"

    echo ""
    echo "Duration: ${duration}s"
    echo "Test Suites: $((SUITES_PASS + SUITES_FAIL)) total"
    echo -e "  ${GREEN}Passed: $SUITES_PASS${NC}"
    echo -e "  ${RED}Failed: $SUITES_FAIL${NC}"
    echo ""
    echo "Individual Tests: $((TOTAL_PASS + TOTAL_FAIL)) total"
    echo -e "  ${GREEN}Passed: $TOTAL_PASS${NC}"
    echo -e "  ${RED}Failed: $TOTAL_FAIL${NC}"
    echo ""

    if [[ "$SUITES_FAIL" -eq 0 ]]; then
        echo -e "${GREEN}All test suites passed!${NC}"
        return 0
    else
        echo -e "${RED}Some test suites failed.${NC}"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    START_TIME=$(date +%s)

    section "Release Testing Unit Test Runner"

    log_info "Discovering tests in: $SCRIPT_DIR"

    # Discover test files
    local test_files
    read -ra test_files <<< "$(discover_tests)"

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warn "No test files found matching test-*.sh"
        exit 0
    fi

    log_info "Found ${#test_files[@]} test suite(s)"

    # Track if any suite failed
    local any_failed=false

    # Run each test suite
    for test_file in "${test_files[@]}"; do
        if [[ -f "$test_file" ]]; then
            if ! run_test_suite "$test_file"; then
                any_failed=true
            fi
        fi
    done

    # Print summary and exit
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
