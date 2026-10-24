#!/bin/bash
# VM Lifecycle Management for Tart VMs
# =====================================
# Functions for creating, starting, stopping, and cleaning up Tart VMs
# Used by the release testing automation framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration if available
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# Configure Tart storage location
export TART_HOME="${TART_HOME:-/Volumes/downloads/tart-vms}"

# Default VM configuration
VM_CPU="${VM_CPU:-4}"
VM_MEMORY="${VM_MEMORY:-8192}"
VM_NAME_PREFIX="${VM_NAME_PREFIX:-release-test}"

# SSH Configuration
SSH_USER="${SSH_USER:-admin}"
SSH_TIMEOUT="${SSH_TIMEOUT:-5}"
SSH_MAX_WAIT_ATTEMPTS="${SSH_MAX_WAIT_ATTEMPTS:-60}"
SSH_WAIT_INTERVAL="${SSH_WAIT_INTERVAL:-5}"

# Color output for status
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# Track VM PID for cleanup
VM_PID="${VM_PID:-}"

# =============================================================================
# create_vm - Create a new VM by cloning from base image
# =============================================================================
# Arguments:
#   $1 - vm_name: Name for the new VM
#   $2 - base_image: (optional) Base image to clone from
# Returns:
#   0 on success, 1 on failure
# =============================================================================
create_vm() {
    local vm_name="$1"
    local base_image="${2:-${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}}"

    if [[ -z "$vm_name" ]]; then
        log_error "create_vm: VM name is required"
        return 1
    fi

    log_info "Creating VM: $vm_name from $base_image"
    log_info "TART_HOME: $TART_HOME"

    # Ensure TART_HOME directory exists
    if [[ ! -d "$TART_HOME" ]]; then
        log_info "Creating TART_HOME directory: $TART_HOME"
        mkdir -p "$TART_HOME"
    fi

    # Check if VM already exists
    if tart list 2>/dev/null | grep -q "^${vm_name}$"; then
        log_warn "VM $vm_name already exists, cleaning up first"
        cleanup_vm "$vm_name"
    fi

    # Clone the base image
    if ! tart clone "$base_image" "$vm_name"; then
        log_error "Failed to clone base image $base_image to $vm_name"
        return 1
    fi

    # Configure VM resources
    log_info "Configuring VM with $VM_CPU CPUs and ${VM_MEMORY}MB memory"
    if ! tart set "$vm_name" --cpu "$VM_CPU" --memory "$VM_MEMORY"; then
        log_warn "Failed to set VM resources, continuing with defaults"
    fi

    log_info "VM $vm_name created successfully"
    return 0
}

# =============================================================================
# start_vm_headless - Start a VM in headless mode (no graphics)
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM to start
# Returns:
#   0 on success, 1 on failure
# Side effects:
#   Sets VM_PID global variable with the background process PID
# =============================================================================
start_vm_headless() {
    local vm_name="$1"

    if [[ -z "$vm_name" ]]; then
        log_error "start_vm_headless: VM name is required"
        return 1
    fi

    log_info "Starting VM headless: $vm_name"

    # Start the VM in headless mode in the background
    tart run "$vm_name" --no-graphics &
    VM_PID=$!

    log_info "VM $vm_name started with PID $VM_PID"

    # Wait for VM to be accessible via SSH
    if ! wait_for_ssh "$vm_name"; then
        log_error "VM $vm_name failed to become accessible via SSH"
        return 1
    fi

    return 0
}

# =============================================================================
# wait_for_ssh - Wait for VM to become accessible via SSH
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM to check
# Returns:
#   0 when SSH is ready, 1 on timeout
# =============================================================================
wait_for_ssh() {
    local vm_name="$1"
    local max_attempts="${SSH_MAX_WAIT_ATTEMPTS:-60}"
    local attempt=0
    local ip=""

    if [[ -z "$vm_name" ]]; then
        log_error "wait_for_ssh: VM name is required"
        return 1
    fi

    log_info "Waiting for SSH access to VM $vm_name (max ${max_attempts} attempts, ${SSH_WAIT_INTERVAL}s intervals)"

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))

        # Try to get the VM IP
        ip=$(tart ip "$vm_name" 2>/dev/null || true)

        if [[ -n "$ip" ]]; then
            # Try to connect via SSH
            if ssh -o ConnectTimeout="${SSH_TIMEOUT}" \
                   -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o BatchMode=yes \
                   -o LogLevel=ERROR \
                   "${SSH_USER}@${ip}" "echo ready" 2>/dev/null; then
                log_info "VM $vm_name is ready at $ip (attempt $attempt/$max_attempts)"
                return 0
            fi
        fi

        # Show progress every 10 attempts
        if (( attempt % 10 == 0 )); then
            log_info "Still waiting for SSH... (attempt $attempt/$max_attempts, IP: ${ip:-not assigned})"
        fi

        sleep "${SSH_WAIT_INTERVAL}"
    done

    log_error "Timeout waiting for SSH access to VM $vm_name after $max_attempts attempts"
    return 1
}

# =============================================================================
# get_vm_ip - Get the IP address of a running VM
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM
# Returns:
#   0 and prints IP on success, 1 on failure
# =============================================================================
get_vm_ip() {
    local vm_name="$1"
    local ip=""

    if [[ -z "$vm_name" ]]; then
        log_error "get_vm_ip: VM name is required"
        return 1
    fi

    ip=$(tart ip "$vm_name" 2>/dev/null || true)

    if [[ -z "$ip" ]]; then
        log_error "Could not get IP for VM $vm_name"
        return 1
    fi

    echo "$ip"
    return 0
}

# =============================================================================
# stop_vm - Stop a running VM
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM to stop
# Returns:
#   0 on success, 1 on failure (but always attempts cleanup)
# =============================================================================
stop_vm() {
    local vm_name="$1"

    if [[ -z "$vm_name" ]]; then
        log_error "stop_vm: VM name is required"
        return 1
    fi

    log_info "Stopping VM: $vm_name"

    # Try to stop gracefully
    if tart stop "$vm_name" 2>/dev/null; then
        log_info "VM $vm_name stopped successfully"
        return 0
    fi

    # If graceful stop fails, try force stop
    log_warn "Graceful stop failed, attempting force stop"
    if tart stop "$vm_name" --force 2>/dev/null; then
        log_info "VM $vm_name force stopped successfully"
        return 0
    fi

    # If VM_PID is set, try killing the process
    if [[ -n "${VM_PID:-}" ]] && kill -0 "$VM_PID" 2>/dev/null; then
        log_warn "Killing VM process $VM_PID"
        kill "$VM_PID" 2>/dev/null || true
        sleep 2
        kill -9 "$VM_PID" 2>/dev/null || true
    fi

    log_warn "VM $vm_name may not have stopped cleanly"
    return 0
}

# =============================================================================
# delete_vm - Delete a VM
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM to delete
# Returns:
#   0 on success or if VM doesn't exist, 1 on failure
# =============================================================================
delete_vm() {
    local vm_name="$1"

    if [[ -z "$vm_name" ]]; then
        log_error "delete_vm: VM name is required"
        return 1
    fi

    log_info "Deleting VM: $vm_name"

    # Check if VM exists before attempting deletion
    if ! tart list 2>/dev/null | grep -q "^${vm_name}$"; then
        log_info "VM $vm_name does not exist, nothing to delete"
        return 0
    fi

    if tart delete "$vm_name" 2>/dev/null; then
        log_info "VM $vm_name deleted successfully"
        return 0
    else
        log_error "Failed to delete VM $vm_name"
        return 1
    fi
}

# =============================================================================
# cleanup_vm - Stop and delete a VM (full cleanup)
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM to cleanup
# Returns:
#   0 on success (or if VM doesn't exist), 1 on failure
# Note:
#   This function is designed to be safe to call even on VMs that don't exist
#   or are already stopped. It will attempt cleanup regardless of state.
# =============================================================================
cleanup_vm() {
    local vm_name="$1"
    local result=0

    if [[ -z "$vm_name" ]]; then
        log_error "cleanup_vm: VM name is required"
        return 1
    fi

    log_info "Cleaning up VM: $vm_name"

    # Stop the VM (ignore errors)
    stop_vm "$vm_name" || true

    # Wait a moment for cleanup
    sleep 2

    # Delete the VM
    if ! delete_vm "$vm_name"; then
        result=1
    fi

    # Clear VM_PID
    VM_PID=""

    if [[ $result -eq 0 ]]; then
        log_info "VM $vm_name cleanup completed"
    else
        log_warn "VM $vm_name cleanup completed with warnings"
    fi

    return $result
}

# =============================================================================
# vm_exists - Check if a VM exists
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM to check
# Returns:
#   0 if VM exists, 1 if not
# =============================================================================
vm_exists() {
    local vm_name="$1"

    if [[ -z "$vm_name" ]]; then
        return 1
    fi

    tart list 2>/dev/null | grep -q "^${vm_name}$"
}

# =============================================================================
# check_disk_space - Check if enough disk space is available
# =============================================================================
# Arguments:
#   $1 - required_gb: Required free space in GB (default: MIN_DISK_SPACE_GB or 20)
# Returns:
#   0 if enough space, 1 if not
# =============================================================================
check_disk_space() {
    local required_gb="${1:-${MIN_DISK_SPACE_GB:-20}}"
    local mount_point="/Volumes/downloads"
    local available_kb
    local available_gb

    # Get available space on the target mount point
    if [[ -d "$mount_point" ]]; then
        available_kb=$(df -k "$mount_point" | tail -1 | awk '{print $4}')
        available_gb=$((available_kb / 1024 / 1024))
    else
        log_warn "Mount point $mount_point not found, checking TART_HOME parent"
        local parent_dir
        parent_dir=$(dirname "$TART_HOME")
        available_kb=$(df -k "$parent_dir" | tail -1 | awk '{print $4}')
        available_gb=$((available_kb / 1024 / 1024))
    fi

    if [[ $available_gb -ge $required_gb ]]; then
        log_info "Disk space check passed: ${available_gb}GB available (${required_gb}GB required)"
        return 0
    else
        log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        return 1
    fi
}

# =============================================================================
# run_in_vm - Execute a command in the VM via SSH
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM
#   $* - command: Command to run in the VM
# Returns:
#   Exit code of the command
# =============================================================================
run_in_vm() {
    local vm_name="$1"
    shift
    local cmd="$*"
    local ip

    if [[ -z "$vm_name" ]]; then
        log_error "run_in_vm: VM name is required"
        return 1
    fi

    if [[ -z "$cmd" ]]; then
        log_error "run_in_vm: Command is required"
        return 1
    fi

    ip=$(get_vm_ip "$vm_name") || return 1

    log_info "Running command in VM $vm_name: $cmd"

    ssh -o ConnectTimeout="${SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        "${SSH_USER}@${ip}" "$cmd"
}

# =============================================================================
# copy_to_vm - Copy a file to the VM via SCP
# =============================================================================
# Arguments:
#   $1 - vm_name: Name of the VM
#   $2 - source: Local source path
#   $3 - dest: Remote destination path
# Returns:
#   0 on success, 1 on failure
# =============================================================================
copy_to_vm() {
    local vm_name="$1"
    local source="$2"
    local dest="$3"
    local ip

    if [[ -z "$vm_name" || -z "$source" || -z "$dest" ]]; then
        log_error "copy_to_vm: VM name, source, and destination are required"
        return 1
    fi

    ip=$(get_vm_ip "$vm_name") || return 1

    log_info "Copying $source to VM $vm_name:$dest"

    scp -o ConnectTimeout="${SSH_TIMEOUT}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        "$source" "${SSH_USER}@${ip}:${dest}"
}

# =============================================================================
# Main - Only run if script is executed directly (not sourced)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # If run directly, show usage or run a quick test
    case "${1:-}" in
        --help|-h)
            echo "VM Lifecycle Management Functions"
            echo ""
            echo "This script is designed to be sourced by other scripts."
            echo "Usage: source ${0##*/}"
            echo ""
            echo "Available functions:"
            echo "  create_vm <vm_name> [base_image]  - Create a new VM"
            echo "  start_vm_headless <vm_name>       - Start VM without graphics"
            echo "  wait_for_ssh <vm_name>            - Wait for SSH to be ready"
            echo "  stop_vm <vm_name>                 - Stop a running VM"
            echo "  delete_vm <vm_name>               - Delete a VM"
            echo "  cleanup_vm <vm_name>              - Stop and delete VM"
            echo "  get_vm_ip <vm_name>               - Get VM IP address"
            echo "  vm_exists <vm_name>               - Check if VM exists"
            echo "  check_disk_space [required_gb]    - Check available disk space"
            echo "  run_in_vm <vm_name> <command>     - Run command in VM via SSH"
            echo "  copy_to_vm <vm> <src> <dest>      - Copy file to VM via SCP"
            echo ""
            echo "Environment:"
            echo "  TART_HOME: $TART_HOME"
            echo "  BASE_IMAGE: ${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
            ;;
        --test)
            echo "Running basic syntax test..."
            log_info "Logging functions work"
            log_warn "Warning test"
            log_error "Error test (not a real error)"
            echo "TART_HOME is set to: $TART_HOME"
            echo "Syntax check passed!"
            ;;
        *)
            echo "Run with --help for usage information"
            echo "Run with --test for a basic syntax test"
            ;;
    esac
fi
