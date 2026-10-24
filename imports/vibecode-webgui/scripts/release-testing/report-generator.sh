#!/bin/bash
# Report Generator for Release Testing
# =====================================
# Functions for aggregating test results and generating summary reports
# Used by the release testing automation framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration if available
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# Report Configuration
RESULTS_DIR="${RESULTS_DIR:-./release-test-results}"
REPORT_FILE="${REPORT_FILE:-./release-test-report.md}"
LOG_FILE="${LOG_FILE:-./release-test.log}"

# In-memory results tracking (arrays)
RELEASE_RESULTS=()
RELEASE_DURATIONS=()
RELEASE_PASS_COUNTS=()
RELEASE_FAIL_COUNTS=()

# Color output for status
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_report() { echo -e "${CYAN}[REPORT]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# =============================================================================
# init_report - Initialize the report structure
# =============================================================================
# Arguments:
#   $1 - report_file: (optional) Path to report file
# Returns:
#   0 on success
# Side effects:
#   Creates or clears the report file and results directory
# =============================================================================
init_report() {
    local report_file="${1:-${REPORT_FILE}}"
    local results_dir="${RESULTS_DIR}"

    log_report "Initializing report: $report_file"

    # Create results directory
    mkdir -p "$results_dir"

    # Clear arrays
    RELEASE_RESULTS=()
    RELEASE_DURATIONS=()
    RELEASE_PASS_COUNTS=()
    RELEASE_FAIL_COUNTS=()

    # Initialize report file with header
    {
        echo "# Release Test Report"
        echo ""
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""
        echo "---"
        echo ""
    } > "$report_file"

    log_report "Report initialized"
    return 0
}

# =============================================================================
# add_result - Add a test result entry for a release
# =============================================================================
# Arguments:
#   $1 - release_tag: Release tag that was tested
#   $2 - status: PASS, FAIL, SKIP, or ERROR
#   $3 - duration: Test duration in seconds
#   $4 - pass_count: Number of passed tests
#   $5 - fail_count: Number of failed tests
#   $6 - message: (optional) Additional message
# Returns:
#   0 on success
# =============================================================================
add_result() {
    local release_tag="$1"
    local status="$2"
    local duration="${3:-0}"
    local pass_count="${4:-0}"
    local fail_count="${5:-0}"
    local message="${6:-}"

    if [[ -z "$release_tag" || -z "$status" ]]; then
        log_error "add_result: release_tag and status are required"
        return 1
    fi

    # Store in arrays for summary
    RELEASE_RESULTS+=("${release_tag}:${status}")
    RELEASE_DURATIONS+=("${duration}")
    RELEASE_PASS_COUNTS+=("${pass_count}")
    RELEASE_FAIL_COUNTS+=("${fail_count}")

    # Log the result
    case "$status" in
        PASS)
            log_report "${GREEN}PASS${NC}: $release_tag (${duration}s, ${pass_count} tests passed)"
            ;;
        FAIL)
            log_report "${RED}FAIL${NC}: $release_tag (${duration}s, ${fail_count} tests failed)"
            ;;
        SKIP)
            log_report "${YELLOW}SKIP${NC}: $release_tag - $message"
            ;;
        ERROR)
            log_report "${RED}ERROR${NC}: $release_tag - $message"
            ;;
        *)
            log_report "$status: $release_tag"
            ;;
    esac

    # Also write to results JSON for persistence
    local results_json="${RESULTS_DIR}/results.json"
    if [[ ! -f "$results_json" ]]; then
        echo '{"results":[]}' > "$results_json"
    fi

    # Create result entry (simple append, proper JSON handling would need jq)
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    local result_file="${RESULTS_DIR}/${release_tag}/result.txt"
    mkdir -p "${RESULTS_DIR}/${release_tag}"
    {
        echo "release_tag=$release_tag"
        echo "status=$status"
        echo "duration=$duration"
        echo "pass_count=$pass_count"
        echo "fail_count=$fail_count"
        echo "message=$message"
        echo "timestamp=$timestamp"
    } > "$result_file"

    return 0
}

# =============================================================================
# add_result_from_dir - Add result from a results directory
# =============================================================================
# Arguments:
#   $1 - release_tag: Release tag
#   $2 - results_dir: Directory containing test-results.txt
# Returns:
#   0 on success
# =============================================================================
add_result_from_dir() {
    local release_tag="$1"
    local results_dir="${2:-${RESULTS_DIR}/${release_tag}}"
    local results_file="${results_dir}/test-results.txt"
    local pass_count=0
    local fail_count=0
    local duration=0
    local status="UNKNOWN"

    if [[ -z "$release_tag" ]]; then
        log_error "add_result_from_dir: release_tag is required"
        return 1
    fi

    if [[ -f "$results_file" ]]; then
        # Parse pass/fail counts
        pass_count=$(grep -c "^PASS:" "$results_file" 2>/dev/null || echo "0")
        fail_count=$(grep -c "^FAIL:" "$results_file" 2>/dev/null || echo "0")

        # Parse duration if present
        duration=$(grep "^Duration:" "$results_file" 2>/dev/null | sed 's/[^0-9]//g' | head -1 || echo "0")
        [[ -z "$duration" ]] && duration=0

        # Determine status
        if [[ "$fail_count" -gt 0 ]]; then
            status="FAIL"
        elif [[ "$pass_count" -gt 0 ]]; then
            status="PASS"
        else
            status="NO_TESTS"
        fi
    else
        status="NO_RESULTS"
    fi

    add_result "$release_tag" "$status" "$duration" "$pass_count" "$fail_count"
    return 0
}

# =============================================================================
# print_summary - Print summary of all results to console
# =============================================================================
# Arguments:
#   None (uses stored results)
# Returns:
#   0 on success
# Output:
#   Prints formatted summary to stdout
# =============================================================================
print_summary() {
    local total=${#RELEASE_RESULTS[@]}
    local passed=0
    local failed=0
    local skipped=0
    local errors=0
    local total_duration=0

    log_report "Generating summary..."

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}       RELEASE TEST SUMMARY${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    if [[ $total -eq 0 ]]; then
        echo "No test results recorded."
        return 0
    fi

    # Calculate totals
    for i in "${!RELEASE_RESULTS[@]}"; do
        local entry="${RELEASE_RESULTS[$i]}"
        local status="${entry#*:}"
        local duration="${RELEASE_DURATIONS[$i]:-0}"

        case "$status" in
            PASS) ((passed++)) ;;
            FAIL) ((failed++)) ;;
            SKIP) ((skipped++)) ;;
            ERROR) ((errors++)) ;;
        esac

        total_duration=$((total_duration + duration))
    done

    # Print results table
    printf "%-30s %-10s %-10s %-10s %-10s\n" "RELEASE" "STATUS" "PASSED" "FAILED" "DURATION"
    printf "%-30s %-10s %-10s %-10s %-10s\n" "-------" "------" "------" "------" "--------"

    for i in "${!RELEASE_RESULTS[@]}"; do
        local entry="${RELEASE_RESULTS[$i]}"
        local release_tag="${entry%:*}"
        local status="${entry#*:}"
        local pass_count="${RELEASE_PASS_COUNTS[$i]:-0}"
        local fail_count="${RELEASE_FAIL_COUNTS[$i]:-0}"
        local duration="${RELEASE_DURATIONS[$i]:-0}"

        local status_color="$NC"
        case "$status" in
            PASS) status_color="$GREEN" ;;
            FAIL) status_color="$RED" ;;
            SKIP) status_color="$YELLOW" ;;
            ERROR) status_color="$RED" ;;
        esac

        printf "%-30s ${status_color}%-10s${NC} %-10s %-10s %-10s\n" \
            "$release_tag" "$status" "$pass_count" "$fail_count" "${duration}s"
    done

    echo ""
    echo -e "${BOLD}----------------------------------------${NC}"
    printf "Total Releases: %d\n" "$total"
    printf "  ${GREEN}Passed${NC}:  %d\n" "$passed"
    printf "  ${RED}Failed${NC}:  %d\n" "$failed"
    printf "  ${YELLOW}Skipped${NC}: %d\n" "$skipped"
    printf "  ${RED}Errors${NC}:  %d\n" "$errors"
    echo ""
    printf "Total Duration: %ds (%dm %ds)\n" "$total_duration" "$((total_duration / 60))" "$((total_duration % 60))"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # Return non-zero if any failures
    if [[ $failed -gt 0 || $errors -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# generate_report - Generate final markdown report
# =============================================================================
# Arguments:
#   $1 - report_file: (optional) Path to report file
# Returns:
#   0 on success
# Side effects:
#   Writes complete report to report_file
# =============================================================================
generate_report() {
    local report_file="${1:-${REPORT_FILE}}"
    local total=${#RELEASE_RESULTS[@]}
    local passed=0
    local failed=0
    local skipped=0
    local errors=0
    local total_duration=0

    log_report "Generating report: $report_file"

    # Calculate totals
    for i in "${!RELEASE_RESULTS[@]}"; do
        local entry="${RELEASE_RESULTS[$i]}"
        local status="${entry#*:}"
        local duration="${RELEASE_DURATIONS[$i]:-0}"

        case "$status" in
            PASS) ((passed++)) ;;
            FAIL) ((failed++)) ;;
            SKIP) ((skipped++)) ;;
            ERROR) ((errors++)) ;;
        esac

        total_duration=$((total_duration + duration))
    done

    # Generate report
    {
        echo "# Release Test Report"
        echo ""
        echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""
        echo "---"
        echo ""
        echo "## Summary"
        echo ""
        echo "| Metric | Count |"
        echo "|--------|-------|"
        echo "| Total Releases Tested | $total |"
        echo "| Passed | $passed |"
        echo "| Failed | $failed |"
        echo "| Skipped | $skipped |"
        echo "| Errors | $errors |"
        echo "| Total Duration | ${total_duration}s ($(printf '%dm %ds' $((total_duration / 60)) $((total_duration % 60)))) |"
        echo ""

        # Overall status badge
        if [[ $failed -eq 0 && $errors -eq 0 && $passed -gt 0 ]]; then
            echo "**Overall Status:** :white_check_mark: **ALL TESTS PASSED**"
        elif [[ $failed -gt 0 || $errors -gt 0 ]]; then
            echo "**Overall Status:** :x: **SOME TESTS FAILED**"
        else
            echo "**Overall Status:** :warning: **NO TESTS RUN**"
        fi
        echo ""
        echo "---"
        echo ""
        echo "## Detailed Results"
        echo ""
        echo "| Release | Status | Passed | Failed | Duration |"
        echo "|---------|--------|--------|--------|----------|"

        for i in "${!RELEASE_RESULTS[@]}"; do
            local entry="${RELEASE_RESULTS[$i]}"
            local release_tag="${entry%:*}"
            local status="${entry#*:}"
            local pass_count="${RELEASE_PASS_COUNTS[$i]:-0}"
            local fail_count="${RELEASE_FAIL_COUNTS[$i]:-0}"
            local duration="${RELEASE_DURATIONS[$i]:-0}"

            local status_icon=""
            case "$status" in
                PASS) status_icon=":white_check_mark:" ;;
                FAIL) status_icon=":x:" ;;
                SKIP) status_icon=":fast_forward:" ;;
                ERROR) status_icon=":warning:" ;;
                *) status_icon=":question:" ;;
            esac

            echo "| \`$release_tag\` | $status_icon $status | $pass_count | $fail_count | ${duration}s |"
        done

        echo ""
        echo "---"
        echo ""
        echo "## Test Environment"
        echo ""
        echo "- **VM Base Image:** ${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
        echo "- **Repository:** ${GITHUB_FULL_REPO:-ryanmaclean/vibecode-webgui}"
        echo "- **TART_HOME:** ${TART_HOME:-/Volumes/downloads/tart-vms}"
        echo "- **Test Timeout:** ${TEST_TIMEOUT:-3600}s"
        echo ""

        # Add failed release details if any
        if [[ $failed -gt 0 || $errors -gt 0 ]]; then
            echo "---"
            echo ""
            echo "## Failed Releases"
            echo ""

            for i in "${!RELEASE_RESULTS[@]}"; do
                local entry="${RELEASE_RESULTS[$i]}"
                local release_tag="${entry%:*}"
                local status="${entry#*:}"

                if [[ "$status" == "FAIL" || "$status" == "ERROR" ]]; then
                    echo "### $release_tag"
                    echo ""

                    # Try to include test results if available
                    local results_file="${RESULTS_DIR}/${release_tag}/test-results.txt"
                    if [[ -f "$results_file" ]]; then
                        echo '```'
                        grep -E "^(FAIL|ERROR):" "$results_file" 2>/dev/null || echo "No failure details available"
                        echo '```'
                    else
                        echo "No detailed results available."
                    fi
                    echo ""
                fi
            done
        fi

        echo "---"
        echo ""
        echo "*Report generated by release-testing automation framework*"
        echo ""
    } > "$report_file"

    log_report "Report generated: $report_file"
    return 0
}

# =============================================================================
# generate_json_report - Generate JSON format report
# =============================================================================
# Arguments:
#   $1 - output_file: (optional) Path to JSON output file
# Returns:
#   0 on success
# =============================================================================
generate_json_report() {
    local output_file="${1:-${RESULTS_DIR}/report.json}"
    local total=${#RELEASE_RESULTS[@]}
    local passed=0
    local failed=0
    local skipped=0
    local errors=0
    local total_duration=0

    log_report "Generating JSON report: $output_file"

    # Calculate totals
    for i in "${!RELEASE_RESULTS[@]}"; do
        local entry="${RELEASE_RESULTS[$i]}"
        local status="${entry#*:}"
        local duration="${RELEASE_DURATIONS[$i]:-0}"

        case "$status" in
            PASS) ((passed++)) ;;
            FAIL) ((failed++)) ;;
            SKIP) ((skipped++)) ;;
            ERROR) ((errors++)) ;;
        esac

        total_duration=$((total_duration + duration))
    done

    # Build JSON (without jq for portability)
    {
        echo "{"
        echo "  \"generated\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
        echo "  \"summary\": {"
        echo "    \"total\": $total,"
        echo "    \"passed\": $passed,"
        echo "    \"failed\": $failed,"
        echo "    \"skipped\": $skipped,"
        echo "    \"errors\": $errors,"
        echo "    \"total_duration_seconds\": $total_duration"
        echo "  },"
        echo "  \"environment\": {"
        echo "    \"base_image\": \"${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}\","
        echo "    \"repository\": \"${GITHUB_FULL_REPO:-ryanmaclean/vibecode-webgui}\","
        echo "    \"tart_home\": \"${TART_HOME:-/Volumes/downloads/tart-vms}\""
        echo "  },"
        echo "  \"results\": ["

        local first=true
        for i in "${!RELEASE_RESULTS[@]}"; do
            local entry="${RELEASE_RESULTS[$i]}"
            local release_tag="${entry%:*}"
            local status="${entry#*:}"
            local pass_count="${RELEASE_PASS_COUNTS[$i]:-0}"
            local fail_count="${RELEASE_FAIL_COUNTS[$i]:-0}"
            local duration="${RELEASE_DURATIONS[$i]:-0}"

            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi

            echo -n "    {"
            echo -n "\"release\": \"$release_tag\", "
            echo -n "\"status\": \"$status\", "
            echo -n "\"passed\": $pass_count, "
            echo -n "\"failed\": $fail_count, "
            echo -n "\"duration\": $duration"
            echo -n "}"
        done

        echo ""
        echo "  ]"
        echo "}"
    } > "$output_file"

    log_report "JSON report generated: $output_file"
    return 0
}

# =============================================================================
# load_results_from_dir - Load all results from results directory
# =============================================================================
# Arguments:
#   $1 - results_dir: (optional) Results directory path
# Returns:
#   0 on success
# =============================================================================
load_results_from_dir() {
    local results_dir="${1:-${RESULTS_DIR}}"

    log_report "Loading results from: $results_dir"

    # Clear existing results
    RELEASE_RESULTS=()
    RELEASE_DURATIONS=()
    RELEASE_PASS_COUNTS=()
    RELEASE_FAIL_COUNTS=()

    if [[ ! -d "$results_dir" ]]; then
        log_warn "Results directory does not exist: $results_dir"
        return 0
    fi

    # Find all result directories
    local count=0
    for release_dir in "$results_dir"/*/; do
        if [[ -d "$release_dir" ]]; then
            local release_tag
            release_tag=$(basename "$release_dir")

            # Skip non-release directories
            [[ "$release_tag" == "*" ]] && continue

            add_result_from_dir "$release_tag" "$release_dir"
            ((count++))
        fi
    done

    log_report "Loaded $count release results"
    return 0
}

# =============================================================================
# get_result_count - Get count of results by status
# =============================================================================
# Arguments:
#   $1 - status: Status to count (PASS, FAIL, SKIP, ERROR, or "all")
# Output:
#   Prints count
# =============================================================================
get_result_count() {
    local target_status="${1:-all}"
    local count=0

    if [[ "$target_status" == "all" ]]; then
        echo "${#RELEASE_RESULTS[@]}"
        return 0
    fi

    for entry in "${RELEASE_RESULTS[@]}"; do
        local status="${entry#*:}"
        if [[ "$status" == "$target_status" ]]; then
            ((count++))
        fi
    done

    echo "$count"
}

# =============================================================================
# finalize_report - Complete the report and cleanup
# =============================================================================
# Arguments:
#   $1 - report_file: (optional) Path to report file
# Returns:
#   0 if all passed, 1 if any failures
# =============================================================================
finalize_report() {
    local report_file="${1:-${REPORT_FILE}}"
    local exit_code=0

    log_report "Finalizing report..."

    # Generate all report formats
    generate_report "$report_file"
    generate_json_report

    # Print summary to console
    print_summary || exit_code=1

    # Log final status
    local passed
    passed=$(get_result_count "PASS")
    local failed
    failed=$(get_result_count "FAIL")
    local total
    total=$(get_result_count "all")

    log_report "Final results: $passed/$total passed, $failed failed"
    log_report "Report saved to: $report_file"

    return $exit_code
}

# =============================================================================
# Main - Only run if script is executed directly (not sourced)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "Report Generator for Release Testing"
            echo ""
            echo "This script is designed to be sourced by other scripts."
            echo "Usage: source ${0##*/}"
            echo ""
            echo "Available functions:"
            echo "  init_report [file]                - Initialize report"
            echo "  add_result <tag> <status> [dur] [pass] [fail] [msg] - Add result"
            echo "  add_result_from_dir <tag> [dir]   - Add result from directory"
            echo "  print_summary                     - Print summary to console"
            echo "  generate_report [file]            - Generate markdown report"
            echo "  generate_json_report [file]       - Generate JSON report"
            echo "  load_results_from_dir [dir]       - Load existing results"
            echo "  get_result_count [status]         - Get result count"
            echo "  finalize_report [file]            - Complete and save report"
            echo ""
            echo "Status values: PASS, FAIL, SKIP, ERROR"
            echo ""
            echo "Environment:"
            echo "  RESULTS_DIR: $RESULTS_DIR"
            echo "  REPORT_FILE: $REPORT_FILE"
            ;;
        --test)
            echo "Running report generator tests..."
            log_info "Logging functions work"
            log_warn "Warning test"
            log_error "Error test (not a real error)"
            log_report "Report log test"
            echo ""
            echo "Testing report functions..."
            init_report "/tmp/test-report.md"
            add_result "v1.0.0" "PASS" 120 5 0
            add_result "v1.1.0" "FAIL" 90 3 2 "2 tests failed"
            add_result "v1.2.0" "SKIP" 0 0 0 "No assets available"
            print_summary
            generate_report "/tmp/test-report.md"
            echo ""
            echo "Test report generated: /tmp/test-report.md"
            echo "Syntax check passed!"
            ;;
        --demo)
            echo "Running demo report generation..."
            init_report
            add_result "v0.9.0" "PASS" 45 3 0
            add_result "v1.0.0" "PASS" 120 5 0
            add_result "v1.0.1" "PASS" 60 4 0
            add_result "v1.1.0" "FAIL" 90 3 2 "Integration tests failed"
            add_result "v1.2.0-beta" "SKIP" 0 0 0 "Prerelease skipped"
            finalize_report
            echo ""
            echo "Demo complete. Check: $REPORT_FILE"
            ;;
        *)
            echo "Run with --help for usage information"
            echo "Run with --test for a basic functionality test"
            echo "Run with --demo for a demo report generation"
            ;;
    esac
fi
