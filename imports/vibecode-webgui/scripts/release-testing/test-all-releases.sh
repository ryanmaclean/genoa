#!/bin/bash
# Main Orchestration Script for Release Testing
# =============================================
# Tests all GitHub releases for a repository using fresh Tart VMs
# Each release is tested in isolation with automatic cleanup
#
# Usage:
#   ./test-all-releases.sh --repo owner/repo
#   ./test-all-releases.sh --repo owner/repo --tag v1.0.0
#   ./test-all-releases.sh --dry-run --repo owner/repo
#   ./test-all-releases.sh --check-prereqs
#
# Environment Variables:
#   TART_HOME      - VM storage location (default: /Volumes/downloads/tart-vms)
#   GH_TOKEN       - GitHub authentication token
#   TEST_TIMEOUT   - Max time per release test (default: 3600s)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# Source helper scripts
if [[ -f "${SCRIPT_DIR}/vm-lifecycle.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/vm-lifecycle.sh"
fi

if [[ -f "${SCRIPT_DIR}/github-releases.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/github-releases.sh"
fi

if [[ -f "${SCRIPT_DIR}/run-tests-in-vm.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/run-tests-in-vm.sh"
fi

if [[ -f "${SCRIPT_DIR}/report-generator.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/report-generator.sh"
fi

# =============================================================================
# Default Configuration
# =============================================================================
TART_HOME="${TART_HOME:-/Volumes/downloads/tart-vms}"
export TART_HOME

# CLI Arguments
REPO="${GITHUB_FULL_REPO:-}"
TAG_FILTER=""
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
MIN_DISK_SPACE_GB="${MIN_DISK_SPACE_GB:-20}"
TEST_TIMEOUT="${TEST_TIMEOUT:-3600}"
RESULTS_DIR="${RESULTS_DIR:-./release-test-results}"
REPORT_FILE="${REPORT_FILE:-./release-test-report.md}"

# Script state
CURRENT_VM_NAME=""
SCRIPT_START_TIME=""

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
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" || true; }
log_step() { echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# =============================================================================
# show_usage - Display usage information
# =============================================================================
show_usage() {
    cat << 'EOF'
Release Testing Framework
=========================

Test all GitHub releases for a repository using fresh Tart VMs.
Each release is tested in isolation with automatic VM cleanup.

Usage:
  test-all-releases.sh [OPTIONS]

Options:
  --repo <owner/repo>     GitHub repository to test (required unless set in config)
  --tag <tag>             Test only a specific release tag
  --base-image <image>    Tart base image to use (default: ghcr.io/cirruslabs/macos-sequoia-base:latest)
  --dry-run               List releases without running tests
  --check-prereqs         Check prerequisites (Tart, gh CLI) and exit
  --verbose               Enable verbose output
  --results-dir <dir>     Directory for test results (default: ./release-test-results)
  --report-file <file>    Path for report file (default: ./release-test-report.md)
  --min-space <GB>        Minimum disk space required (default: 20GB)
  --timeout <seconds>     Timeout per release test (default: 3600)
  -h, --help              Show this help message

Examples:
  # Test all releases
  ./test-all-releases.sh --repo ryanmaclean/vibecode-webgui

  # Test a specific release
  ./test-all-releases.sh --repo ryanmaclean/vibecode-webgui --tag v1.0.0

  # Dry run to list releases
  ./test-all-releases.sh --repo ryanmaclean/vibecode-webgui --dry-run

  # Check prerequisites
  ./test-all-releases.sh --check-prereqs

Environment Variables:
  TART_HOME       VM storage location (default: /Volumes/downloads/tart-vms)
  GH_TOKEN        GitHub authentication token (or use 'gh auth login')
  TEST_TIMEOUT    Maximum time per release test in seconds

Prerequisites:
  - Tart (brew install cirruslabs/cli/tart)
  - GitHub CLI (brew install gh)
  - macOS 13.0+ on Apple Silicon (M1/M2/M3/M4)
  - External storage mounted at /Volumes/downloads (recommended)

EOF
}

# =============================================================================
# check_prerequisites - Verify all required tools are available
# =============================================================================
check_prerequisites() {
    local has_errors=false

    echo ""
    echo -e "${BOLD}Checking Prerequisites${NC}"
    echo "======================"
    echo ""

    # Check Tart
    echo -n "Tart VM Manager: "
    if command -v tart &>/dev/null; then
        local tart_version
        tart_version=$(tart --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "${GREEN}INSTALLED${NC} ($tart_version)"
    else
        echo -e "${RED}NOT FOUND${NC}"
        echo "  Install with: brew install cirruslabs/cli/tart"
        has_errors=true
    fi

    # Check gh CLI
    echo -n "GitHub CLI (gh): "
    if command -v gh &>/dev/null; then
        local gh_version
        gh_version=$(gh --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "${GREEN}INSTALLED${NC} ($gh_version)"

        # Check gh authentication
        echo -n "GitHub Auth:     "
        if gh auth status &>/dev/null; then
            local gh_user
            gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "authenticated")
            echo -e "${GREEN}AUTHENTICATED${NC} ($gh_user)"
        else
            echo -e "${YELLOW}NOT AUTHENTICATED${NC}"
            echo "  Run: gh auth login"
            has_errors=true
        fi
    else
        echo -e "${RED}NOT FOUND${NC}"
        echo "  Install with: brew install gh"
        has_errors=true
    fi

    # Check macOS version
    echo -n "macOS Version:   "
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    echo -e "${GREEN}$macos_version${NC}"

    # Check architecture
    echo -n "Architecture:    "
    local arch
    arch=$(uname -m)
    if [[ "$arch" == "arm64" ]]; then
        echo -e "${GREEN}$arch${NC} (Apple Silicon)"
    else
        echo -e "${YELLOW}$arch${NC} (Tart requires Apple Silicon)"
        has_errors=true
    fi

    # Check TART_HOME storage
    echo -n "Storage (TART_HOME): "
    echo "$TART_HOME"

    echo -n "  Directory exists:  "
    if [[ -d "$TART_HOME" ]]; then
        echo -e "${GREEN}YES${NC}"
    else
        echo -e "${YELLOW}NO${NC} (will be created)"
    fi

    # Check /Volumes/downloads if that's the expected location
    if [[ "$TART_HOME" == /Volumes/downloads/* ]]; then
        echo -n "  External mount:    "
        if [[ -d "/Volumes/downloads" ]]; then
            local space_available
            space_available=$(df -h /Volumes/downloads 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
            echo -e "${GREEN}MOUNTED${NC} ($space_available available)"
        else
            echo -e "${YELLOW}NOT MOUNTED${NC}"
            echo "  Consider mounting external storage to prevent disk exhaustion"
        fi
    fi

    # Check disk space
    echo -n "Disk Space Check: "
    if check_disk_space "$MIN_DISK_SPACE_GB" 2>/dev/null; then
        echo -e "${GREEN}PASSED${NC} (>=${MIN_DISK_SPACE_GB}GB available)"
    else
        echo -e "${YELLOW}WARNING${NC} (<${MIN_DISK_SPACE_GB}GB available)"
    fi

    echo ""

    if [[ "$has_errors" == "true" ]]; then
        echo -e "${RED}Some prerequisites are missing. Please install them before running tests.${NC}"
        return 1
    else
        echo -e "${GREEN}All prerequisites satisfied.${NC}"
        return 0
    fi
}

# =============================================================================
# parse_args - Parse command line arguments
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)
                REPO="$2"
                shift 2
                ;;
            --tag)
                TAG_FILTER="$2"
                shift 2
                ;;
            --base-image)
                BASE_IMAGE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --check-prereqs)
                check_prerequisites
                exit $?
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --results-dir)
                RESULTS_DIR="$2"
                shift 2
                ;;
            --report-file)
                REPORT_FILE="$2"
                shift 2
                ;;
            --min-space)
                MIN_DISK_SPACE_GB="$2"
                shift 2
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run with --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$REPO" || "$REPO" == "/" ]]; then
        log_error "Repository is required. Use --repo owner/repo"
        echo "Run with --help for usage information"
        exit 1
    fi

    # Export for use by sourced scripts
    export GITHUB_FULL_REPO="$REPO"
    export BASE_IMAGE
    export DRY_RUN
    export VERBOSE
    export RESULTS_DIR
    export REPORT_FILE
    export TEST_TIMEOUT
}

# =============================================================================
# cleanup_handler - Cleanup handler for traps
# =============================================================================
cleanup_handler() {
    local exit_code=$?
    log_warn "Cleanup handler triggered (exit code: $exit_code)"

    # Cleanup current VM if any
    if [[ -n "$CURRENT_VM_NAME" ]]; then
        log_info "Cleaning up VM: $CURRENT_VM_NAME"
        cleanup_vm "$CURRENT_VM_NAME" 2>/dev/null || true
        CURRENT_VM_NAME=""
    fi

    # Generate partial report if we have results
    if [[ ${#RELEASE_RESULTS[@]} -gt 0 ]] 2>/dev/null; then
        log_info "Generating partial report..."
        finalize_report "$REPORT_FILE" 2>/dev/null || true
    fi

    exit $exit_code
}

# =============================================================================
# generate_vm_name - Generate a unique VM name for a release
# =============================================================================
generate_vm_name() {
    local release_tag="$1"
    local safe_tag

    # Sanitize tag for use as VM name (replace special chars with dash)
    safe_tag=$(echo "$release_tag" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')

    echo "release-test-${safe_tag}-$(date +%s)"
}

# =============================================================================
# test_single_release - Test a single release
# =============================================================================
# Arguments:
#   $1 - release_tag: Release tag to test
# Returns:
#   0 on success, 1 on failure
# =============================================================================
test_single_release() {
    local release_tag="$1"
    local vm_name=""
    local assets_dir=""
    local start_time
    local result=0

    start_time=$(date +%s)

    log_step "Testing release: $release_tag"

    # Check disk space before creating VM
    if ! check_disk_space "$MIN_DISK_SPACE_GB"; then
        log_error "Insufficient disk space for VM creation"
        add_result "$release_tag" "ERROR" 0 0 0 "Insufficient disk space"
        return 1
    fi

    # Generate VM name
    vm_name=$(generate_vm_name "$release_tag")
    CURRENT_VM_NAME="$vm_name"
    log_debug "VM name: $vm_name"

    # Create assets directory for this release
    assets_dir="${RESULTS_DIR}/${release_tag}/assets"
    mkdir -p "$assets_dir"

    # Download release assets
    log_info "Downloading release assets..."
    if ! download_release_assets "$release_tag" "$assets_dir" "$REPO"; then
        log_warn "Failed to download release assets (may not have any)"
    fi

    # Create VM
    log_info "Creating VM from $BASE_IMAGE..."
    if ! create_vm "$vm_name" "$BASE_IMAGE"; then
        log_error "Failed to create VM"
        add_result "$release_tag" "ERROR" $(($(date +%s) - start_time)) 0 0 "VM creation failed"
        CURRENT_VM_NAME=""
        return 1
    fi

    # Start VM
    log_info "Starting VM in headless mode..."
    if ! start_vm_headless "$vm_name"; then
        log_error "Failed to start VM"
        cleanup_vm "$vm_name" 2>/dev/null || true
        add_result "$release_tag" "ERROR" $(($(date +%s) - start_time)) 0 0 "VM start failed"
        CURRENT_VM_NAME=""
        return 1
    fi

    # Run tests
    log_info "Running tests in VM..."
    if run_release_test "$vm_name" "$release_tag" "$assets_dir"; then
        log_info "Tests passed for release $release_tag"
    else
        log_error "Tests failed for release $release_tag"
        result=1
    fi

    # Get test results for reporting
    local duration=$(($(date +%s) - start_time))
    local pass_count=0
    local fail_count=0
    local results_file="${RESULTS_DIR}/${release_tag}/test-results.txt"

    if [[ -f "$results_file" ]]; then
        pass_count=$(grep -c "^PASS:" "$results_file" 2>/dev/null || echo "0")
        fail_count=$(grep -c "^FAIL:" "$results_file" 2>/dev/null || echo "0")
    fi

    # Add result to report
    if [[ $result -eq 0 ]]; then
        add_result "$release_tag" "PASS" "$duration" "$pass_count" "$fail_count"
    else
        add_result "$release_tag" "FAIL" "$duration" "$pass_count" "$fail_count"
    fi

    # Cleanup VM
    log_info "Cleaning up VM..."
    if ! cleanup_vm "$vm_name"; then
        log_warn "VM cleanup may not have completed fully"
    fi
    CURRENT_VM_NAME=""

    return $result
}

# =============================================================================
# run_dry_run - List releases without running tests
# =============================================================================
run_dry_run() {
    log_info "Dry run mode - listing releases only"
    echo ""
    echo -e "${BOLD}Releases for $REPO:${NC}"
    echo "========================"

    local releases
    releases=$(get_all_releases "$REPO")

    if [[ -z "$releases" ]]; then
        echo "No releases found."
        return 0
    fi

    local count=0
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        ((count++))

        # Check if release has assets
        local has_assets=""
        if has_release_assets "$tag" "$REPO" 2>/dev/null; then
            has_assets=" [has assets]"
        fi

        echo "  $count. $tag$has_assets"
    done <<< "$releases"

    echo ""
    echo "Total: $count releases"
    echo ""

    if [[ -n "$TAG_FILTER" ]]; then
        echo "Note: --tag filter specified. Would test only: $TAG_FILTER"
    fi

    return 0
}

# =============================================================================
# main - Main execution flow
# =============================================================================
main() {
    SCRIPT_START_TIME=$(date +%s)

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Release Testing Framework${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # Parse command line arguments
    parse_args "$@"

    log_info "Repository: $REPO"
    log_info "TART_HOME: $TART_HOME"
    log_info "Base Image: $BASE_IMAGE"
    log_info "Results Dir: $RESULTS_DIR"

    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        run_dry_run
        exit 0
    fi

    # Check prerequisites
    log_step "Checking prerequisites..."
    if ! check_prerequisites; then
        log_error "Prerequisites check failed. Run with --check-prereqs for details."
        exit 1
    fi

    # Pre-check disk space before beginning any testing
    log_step "Verifying disk space availability..."
    if ! check_disk_space "$MIN_DISK_SPACE_GB"; then
        log_error "Insufficient disk space to begin testing. Need at least ${MIN_DISK_SPACE_GB}GB free."
        log_error "Free up space or set MIN_DISK_SPACE_GB to a lower value."
        exit 1
    fi
    log_info "Disk space check passed (>=${MIN_DISK_SPACE_GB}GB available)"

    # Setup cleanup trap
    trap cleanup_handler EXIT INT TERM

    # Initialize report
    log_step "Initializing report..."
    init_report "$REPORT_FILE"

    # Get releases to test
    log_step "Fetching releases..."
    local releases

    if [[ -n "$TAG_FILTER" ]]; then
        # Test specific tag
        if release_exists "$TAG_FILTER" "$REPO"; then
            releases="$TAG_FILTER"
            log_info "Testing specific release: $TAG_FILTER"
        else
            log_error "Release $TAG_FILTER not found in $REPO"
            exit 1
        fi
    else
        # Get all releases
        releases=$(get_all_releases "$REPO")
    fi

    if [[ -z "$releases" ]]; then
        log_warn "No releases found for $REPO"
        add_result "N/A" "SKIP" 0 0 0 "No releases found"
        finalize_report "$REPORT_FILE"
        exit 0
    fi

    # Count releases
    local total_releases
    total_releases=$(echo "$releases" | wc -l | tr -d ' ')
    log_info "Found $total_releases release(s) to test"

    # Test each release
    local tested=0
    local passed=0
    local failed=0

    while IFS= read -r release_tag; do
        [[ -z "$release_tag" ]] && continue
        ((tested++))

        echo ""
        echo -e "${BOLD}----------------------------------------${NC}"
        echo -e "${BOLD}Testing Release $tested/$total_releases: $release_tag${NC}"
        echo -e "${BOLD}----------------------------------------${NC}"

        if test_single_release "$release_tag"; then
            ((passed++))
        else
            ((failed++))
        fi

        echo ""
    done <<< "$releases"

    # Finalize report
    log_step "Finalizing report..."
    finalize_report "$REPORT_FILE"

    # Final summary
    local total_duration=$(($(date +%s) - SCRIPT_START_TIME))
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  TESTING COMPLETE${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo "Releases tested: $tested"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    echo "Total duration: ${total_duration}s ($(printf '%dm %ds' $((total_duration / 60)) $((total_duration % 60))))"
    echo ""
    echo "Report: $REPORT_FILE"
    echo "Results: $RESULTS_DIR"
    echo ""

    # Exit with failure if any tests failed
    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# =============================================================================
# Script Entry Point
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
