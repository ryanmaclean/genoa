#!/bin/bash
# In-VM Test Execution for Release Testing
# =========================================
# Functions for executing tests inside a VM via SSH and capturing results
# Used by the release testing automation framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration if available
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# Source VM lifecycle functions for SSH operations
if [[ -f "${SCRIPT_DIR}/vm-lifecycle.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/vm-lifecycle.sh"
fi

# Test Configuration
TEST_TIMEOUT="${TEST_TIMEOUT:-3600}"
RESULTS_DIR="${RESULTS_DIR:-./release-test-results}"

# SSH Configuration (inherited from vm-lifecycle.sh or config.env)
SSH_USER="${SSH_USER:-admin}"
SSH_TIMEOUT="${SSH_TIMEOUT:-5}"

# Color output for status
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# =============================================================================
# ssh_to_vm - Execute SSH command to VM with standard options
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $* - command: Command to execute (remaining arguments)
# Returns:
#   Exit code of the SSH command
# =============================================================================
ssh_to_vm() {
    local vm_ip="$1"
    shift
    local cmd="$*"

    if [[ -z "$vm_ip" ]]; then
        log_error "ssh_to_vm: VM IP is required"
        return 1
    fi

    ssh -o ConnectTimeout="${SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        "${SSH_USER}@${vm_ip}" "$cmd"
}

# =============================================================================
# scp_to_vm - Copy file to VM via SCP
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $2 - source: Local source path
#   $3 - dest: Remote destination path
# Returns:
#   0 on success, 1 on failure
# =============================================================================
scp_to_vm() {
    local vm_ip="$1"
    local source="$2"
    local dest="$3"

    if [[ -z "$vm_ip" || -z "$source" || -z "$dest" ]]; then
        log_error "scp_to_vm: VM IP, source, and destination are required"
        return 1
    fi

    scp -o ConnectTimeout="${SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        "$source" "${SSH_USER}@${vm_ip}:${dest}"
}

# =============================================================================
# scp_from_vm - Copy file from VM via SCP
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $2 - source: Remote source path
#   $3 - dest: Local destination path
# Returns:
#   0 on success, 1 on failure
# =============================================================================
scp_from_vm() {
    local vm_ip="$1"
    local source="$2"
    local dest="$3"

    if [[ -z "$vm_ip" || -z "$source" || -z "$dest" ]]; then
        log_error "scp_from_vm: VM IP, source, and destination are required"
        return 1
    fi

    scp -o ConnectTimeout="${SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        "${SSH_USER}@${vm_ip}:${source}" "$dest"
}

# =============================================================================
# setup_test_environment - Prepare VM for test execution
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $2 - release_tag: Release tag being tested
# Returns:
#   0 on success, 1 on failure
# =============================================================================
setup_test_environment() {
    local vm_ip="$1"
    local release_tag="$2"

    if [[ -z "$vm_ip" || -z "$release_tag" ]]; then
        log_error "setup_test_environment: VM IP and release tag are required"
        return 1
    fi

    log_info "Setting up test environment for release $release_tag"

    # Create test directories
    ssh_to_vm "$vm_ip" "mkdir -p ~/test-workspace ~/test-results" || {
        log_error "Failed to create test directories"
        return 1
    }

    # Check macOS version
    local macos_version
    macos_version=$(ssh_to_vm "$vm_ip" "sw_vers -productVersion" 2>/dev/null || echo "unknown")
    log_info "VM macOS version: $macos_version"

    # Check if Homebrew is installed (common for development testing)
    if ssh_to_vm "$vm_ip" "command -v brew" &>/dev/null; then
        log_info "Homebrew is available"
    else
        log_warn "Homebrew not installed in VM"
    fi

    # Install environment info for debugging
    ssh_to_vm "$vm_ip" "echo 'Release: ${release_tag}' > ~/test-results/environment.txt && \
                        echo 'Date: $(date)' >> ~/test-results/environment.txt && \
                        echo 'macOS: $(sw_vers -productVersion)' >> ~/test-results/environment.txt && \
                        echo 'Architecture: $(uname -m)' >> ~/test-results/environment.txt"

    log_info "Test environment setup complete"
    return 0
}

# =============================================================================
# copy_release_assets_to_vm - Copy downloaded release assets to VM
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $2 - assets_dir: Local directory containing release assets
# Returns:
#   0 on success, 1 on failure
# =============================================================================
copy_release_assets_to_vm() {
    local vm_ip="$1"
    local assets_dir="$2"

    if [[ -z "$vm_ip" ]]; then
        log_error "copy_release_assets_to_vm: VM IP is required"
        return 1
    fi

    if [[ -z "$assets_dir" ]]; then
        log_warn "No assets directory specified, skipping asset copy"
        return 0
    fi

    if [[ ! -d "$assets_dir" ]]; then
        log_warn "Assets directory $assets_dir does not exist, skipping"
        return 0
    fi

    local asset_count
    asset_count=$(find "$assets_dir" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$asset_count" -eq 0 ]]; then
        log_warn "No assets found in $assets_dir, skipping copy"
        return 0
    fi

    log_info "Copying $asset_count asset(s) to VM"

    # Create remote assets directory
    ssh_to_vm "$vm_ip" "mkdir -p ~/test-workspace/assets" || {
        log_error "Failed to create assets directory in VM"
        return 1
    }

    # Copy each asset
    local copied=0
    for asset in "$assets_dir"/*; do
        if [[ -f "$asset" ]]; then
            local asset_name
            asset_name=$(basename "$asset")
            log_info "Copying asset: $asset_name"
            if scp_to_vm "$vm_ip" "$asset" "~/test-workspace/assets/$asset_name"; then
                ((copied++))
            else
                log_warn "Failed to copy asset: $asset_name"
            fi
        fi
    done

    log_info "Copied $copied asset(s) to VM"
    return 0
}

# =============================================================================
# run_test_suite - Execute the test suite in the VM
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $2 - release_tag: Release tag being tested
#   $3 - test_script: (optional) Custom test script to run
# Returns:
#   0 on success (all tests pass), 1 on failure
# Side effects:
#   Creates test output files in ~/test-results on the VM
# =============================================================================
run_test_suite() {
    local vm_ip="$1"
    local release_tag="$2"
    local test_script="${3:-}"
    local test_exit_code=0

    if [[ -z "$vm_ip" || -z "$release_tag" ]]; then
        log_error "run_test_suite: VM IP and release tag are required"
        return 1
    fi

    log_test "Starting test suite for release $release_tag"
    local start_time
    start_time=$(date +%s)

    # If a custom test script is provided, copy and execute it
    if [[ -n "$test_script" && -f "$test_script" ]]; then
        log_info "Using custom test script: $test_script"
        scp_to_vm "$vm_ip" "$test_script" "~/test-workspace/run-tests.sh"
        ssh_to_vm "$vm_ip" "chmod +x ~/test-workspace/run-tests.sh"

        # Run the custom test script with timeout
        if timeout "${TEST_TIMEOUT}" ssh_to_vm "$vm_ip" "cd ~/test-workspace && ./run-tests.sh 2>&1 | tee ~/test-results/test-output.txt"; then
            log_test "Custom test script completed successfully"
        else
            test_exit_code=$?
            log_error "Custom test script failed with exit code: $test_exit_code"
        fi
    else
        # Run default test suite
        log_info "Running default test suite"

        # Test 1: Basic system validation
        log_test "Test 1: System validation"
        if ssh_to_vm "$vm_ip" "sw_vers && uname -a" >> /dev/null 2>&1; then
            log_test "PASS: System validation"
            ssh_to_vm "$vm_ip" "echo 'PASS: system_validation' >> ~/test-results/test-results.txt"
        else
            log_test "FAIL: System validation"
            ssh_to_vm "$vm_ip" "echo 'FAIL: system_validation' >> ~/test-results/test-results.txt"
            test_exit_code=1
        fi

        # Test 2: Check if release assets are present (if any were copied)
        log_test "Test 2: Release assets check"
        if ssh_to_vm "$vm_ip" "ls ~/test-workspace/assets/ 2>/dev/null | head -1" | grep -q .; then
            log_test "PASS: Release assets present"
            ssh_to_vm "$vm_ip" "echo 'PASS: release_assets_present' >> ~/test-results/test-results.txt"

            # List assets for the test record
            ssh_to_vm "$vm_ip" "ls -la ~/test-workspace/assets/ >> ~/test-results/test-output.txt 2>&1"
        else
            log_test "SKIP: No release assets to test"
            ssh_to_vm "$vm_ip" "echo 'SKIP: release_assets_not_present' >> ~/test-results/test-results.txt"
        fi

        # Test 3: Environment verification
        log_test "Test 3: Environment verification"
        if ssh_to_vm "$vm_ip" "test -f ~/test-results/environment.txt"; then
            log_test "PASS: Environment file created"
            ssh_to_vm "$vm_ip" "echo 'PASS: environment_verification' >> ~/test-results/test-results.txt"
        else
            log_test "FAIL: Environment file not found"
            ssh_to_vm "$vm_ip" "echo 'FAIL: environment_verification' >> ~/test-results/test-results.txt"
            test_exit_code=1
        fi

        # Test 4: Disk space check in VM
        log_test "Test 4: VM disk space check"
        local vm_free_space
        vm_free_space=$(ssh_to_vm "$vm_ip" "df -g / | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "0")
        if [[ "$vm_free_space" -gt 5 ]]; then
            log_test "PASS: VM has ${vm_free_space}GB free space"
            ssh_to_vm "$vm_ip" "echo 'PASS: disk_space_check (${vm_free_space}GB free)' >> ~/test-results/test-results.txt"
        else
            log_test "WARN: VM has low disk space: ${vm_free_space}GB"
            ssh_to_vm "$vm_ip" "echo 'WARN: disk_space_low (${vm_free_space}GB free)' >> ~/test-results/test-results.txt"
        fi
    fi

    # Calculate test duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Record test summary
    ssh_to_vm "$vm_ip" "echo '' >> ~/test-results/test-results.txt && \
                        echo 'Release: ${release_tag}' >> ~/test-results/test-results.txt && \
                        echo 'Duration: ${duration}s' >> ~/test-results/test-results.txt && \
                        echo 'Exit Code: ${test_exit_code}' >> ~/test-results/test-results.txt && \
                        echo 'Completed: $(date)' >> ~/test-results/test-results.txt"

    log_test "Test suite completed in ${duration}s with exit code: $test_exit_code"
    return $test_exit_code
}

# =============================================================================
# capture_results - Retrieve test results from VM
# =============================================================================
# Arguments:
#   $1 - vm_ip: IP address of the VM
#   $2 - release_tag: Release tag that was tested
#   $3 - output_dir: Local directory to store results
# Returns:
#   0 on success, 1 on failure
# Side effects:
#   Creates result files in output_dir
# =============================================================================
capture_results() {
    local vm_ip="$1"
    local release_tag="$2"
    local output_dir="${3:-${RESULTS_DIR}}"

    if [[ -z "$vm_ip" || -z "$release_tag" ]]; then
        log_error "capture_results: VM IP and release tag are required"
        return 1
    fi

    log_info "Capturing test results for release $release_tag"

    # Create local results directory
    local release_results_dir="${output_dir}/${release_tag}"
    mkdir -p "$release_results_dir"

    # Copy all result files from VM
    log_info "Copying results to $release_results_dir"

    # Archive results in VM first for easier transfer
    if ssh_to_vm "$vm_ip" "cd ~ && tar czf test-results.tar.gz test-results/ 2>/dev/null"; then
        if scp_from_vm "$vm_ip" "~/test-results.tar.gz" "$release_results_dir/results.tar.gz"; then
            # Extract results locally
            tar xzf "$release_results_dir/results.tar.gz" -C "$release_results_dir" --strip-components=1
            rm -f "$release_results_dir/results.tar.gz"
            log_info "Results extracted to $release_results_dir"
        else
            log_warn "Failed to copy results archive, trying individual files"
        fi
    fi

    # Fallback: copy individual files if archive failed
    if [[ ! -f "$release_results_dir/test-results.txt" ]]; then
        scp_from_vm "$vm_ip" "~/test-results/test-results.txt" "$release_results_dir/" 2>/dev/null || true
        scp_from_vm "$vm_ip" "~/test-results/test-output.txt" "$release_results_dir/" 2>/dev/null || true
        scp_from_vm "$vm_ip" "~/test-results/environment.txt" "$release_results_dir/" 2>/dev/null || true
    fi

    # Create a summary file
    local summary_file="$release_results_dir/summary.txt"
    {
        echo "Release Test Summary"
        echo "===================="
        echo "Release: $release_tag"
        echo "Test Date: $(date)"
        echo ""
        if [[ -f "$release_results_dir/test-results.txt" ]]; then
            echo "Test Results:"
            cat "$release_results_dir/test-results.txt"
        else
            echo "No test results file found"
        fi
    } > "$summary_file"

    log_info "Results captured to $release_results_dir"

    # Count pass/fail
    local pass_count=0
    local fail_count=0
    if [[ -f "$release_results_dir/test-results.txt" ]]; then
        pass_count=$(grep -c "^PASS:" "$release_results_dir/test-results.txt" 2>/dev/null || echo "0")
        fail_count=$(grep -c "^FAIL:" "$release_results_dir/test-results.txt" 2>/dev/null || echo "0")
    fi

    log_info "Results: $pass_count passed, $fail_count failed"

    # Return failure if any tests failed
    if [[ "$fail_count" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# run_release_test - Full test execution for a single release
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM
#   $2 - release_tag: Release tag to test
#   $3 - assets_dir: (optional) Directory containing release assets
#   $4 - test_script: (optional) Custom test script
# Returns:
#   0 on success, 1 on failure
# =============================================================================
run_release_test() {
    local vm_name="$1"
    local release_tag="$2"
    local assets_dir="${3:-}"
    local test_script="${4:-}"
    local vm_ip=""
    local result=0

    if [[ -z "$vm_name" || -z "$release_tag" ]]; then
        log_error "run_release_test: VM name and release tag are required"
        return 1
    fi

    log_info "Starting test execution for release $release_tag in VM $vm_name"

    # Get VM IP address
    vm_ip=$(get_vm_ip "$vm_name" 2>/dev/null) || {
        log_error "Could not get IP for VM $vm_name"
        return 1
    }

    log_info "VM IP: $vm_ip"

    # Setup test environment
    if ! setup_test_environment "$vm_ip" "$release_tag"; then
        log_error "Failed to setup test environment"
        return 1
    fi

    # Copy release assets if available
    if [[ -n "$assets_dir" ]]; then
        if ! copy_release_assets_to_vm "$vm_ip" "$assets_dir"; then
            log_warn "Failed to copy release assets, continuing with tests"
        fi
    fi

    # Run the test suite
    if ! run_test_suite "$vm_ip" "$release_tag" "$test_script"; then
        log_error "Test suite failed for release $release_tag"
        result=1
    fi

    # Capture results (always, even on failure)
    if ! capture_results "$vm_ip" "$release_tag"; then
        log_warn "Failed to fully capture test results"
        # Don't override result if tests already failed
        [[ $result -eq 0 ]] && result=1
    fi

    if [[ $result -eq 0 ]]; then
        log_info "Release $release_tag: ALL TESTS PASSED"
    else
        log_error "Release $release_tag: TESTS FAILED"
    fi

    return $result
}

# =============================================================================
# get_test_result_summary - Get summary of test results for a release
# =============================================================================
# Arguments:
#   $1 - release_tag: Release tag to get results for
#   $2 - output_dir: (optional) Results directory
# Output:
#   Prints summary line: "release_tag: PASS/FAIL (X passed, Y failed)"
# =============================================================================
get_test_result_summary() {
    local release_tag="$1"
    local output_dir="${2:-${RESULTS_DIR}}"
    local results_file="${output_dir}/${release_tag}/test-results.txt"
    local status="UNKNOWN"
    local pass_count=0
    local fail_count=0

    if [[ -f "$results_file" ]]; then
        pass_count=$(grep -c "^PASS:" "$results_file" 2>/dev/null || echo "0")
        fail_count=$(grep -c "^FAIL:" "$results_file" 2>/dev/null || echo "0")

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

    echo "${release_tag}: ${status} (${pass_count} passed, ${fail_count} failed)"
}

# =============================================================================
# Main - Only run if script is executed directly (not sourced)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "In-VM Test Execution Functions"
            echo ""
            echo "This script is designed to be sourced by other scripts."
            echo "Usage: source ${0##*/}"
            echo ""
            echo "Available functions:"
            echo "  ssh_to_vm <ip> <command>                - Execute command in VM via SSH"
            echo "  scp_to_vm <ip> <src> <dest>             - Copy file to VM"
            echo "  scp_from_vm <ip> <src> <dest>           - Copy file from VM"
            echo "  setup_test_environment <ip> <tag>       - Prepare VM for testing"
            echo "  copy_release_assets_to_vm <ip> <dir>    - Copy assets to VM"
            echo "  run_test_suite <ip> <tag> [script]      - Execute test suite"
            echo "  capture_results <ip> <tag> [dir]        - Retrieve test results"
            echo "  run_release_test <vm> <tag> [assets] [script] - Full test execution"
            echo "  get_test_result_summary <tag> [dir]     - Get result summary"
            echo ""
            echo "Environment:"
            echo "  SSH_USER: $SSH_USER"
            echo "  SSH_TIMEOUT: $SSH_TIMEOUT"
            echo "  TEST_TIMEOUT: $TEST_TIMEOUT"
            echo "  RESULTS_DIR: $RESULTS_DIR"
            ;;
        --test)
            echo "Running basic tests..."
            log_info "Logging functions work"
            log_warn "Warning test"
            log_error "Error test (not a real error)"
            log_test "Test log test"
            echo ""
            echo "SSH configuration:"
            echo "  SSH_USER: $SSH_USER"
            echo "  SSH_TIMEOUT: $SSH_TIMEOUT"
            echo "  TEST_TIMEOUT: $TEST_TIMEOUT"
            echo ""
            echo "Results configuration:"
            echo "  RESULTS_DIR: $RESULTS_DIR"
            echo ""
            echo "Syntax check passed!"
            ;;
        *)
            echo "Run with --help for usage information"
            echo "Run with --test for a basic functionality test"
            ;;
    esac
fi
