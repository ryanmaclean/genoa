#!/bin/bash
# GitHub Release Integration for Release Testing
# ===============================================
# Functions for fetching GitHub releases and downloading release assets
# Used by the release testing automation framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration if available
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

# GitHub Configuration
GITHUB_OWNER="${GITHUB_OWNER:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_FULL_REPO="${GITHUB_FULL_REPO:-${GITHUB_OWNER}/${GITHUB_REPO}}"
GH_CMD="${GH_CMD:-gh}"

# Release Fetch Configuration
RELEASE_LIMIT="${RELEASE_LIMIT:-1000}"
INCLUDE_PRERELEASES="${INCLUDE_PRERELEASES:-false}"
INCLUDE_DRAFTS="${INCLUDE_DRAFTS:-false}"

# Color output for status
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# =============================================================================
# check_gh_auth - Verify GitHub CLI is authenticated
# =============================================================================
# Returns:
#   0 if authenticated, 1 if not
# =============================================================================
check_gh_auth() {
    if ! command -v "$GH_CMD" &>/dev/null; then
        log_error "GitHub CLI (gh) not found. Install with: brew install gh"
        return 1
    fi

    if ! "$GH_CMD" auth status &>/dev/null; then
        log_error "GitHub CLI not authenticated. Run: gh auth login"
        return 1
    fi

    return 0
}

# =============================================================================
# get_all_releases - Get all published releases for a repository
# =============================================================================
# Arguments:
#   $1 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Output:
#   Prints one release tag per line (newline-separated)
# Returns:
#   0 on success, 1 on failure
# Note:
#   Filters out draft releases by default. Set INCLUDE_DRAFTS=true to include.
#   Filters out pre-releases by default. Set INCLUDE_PRERELEASES=true to include.
# =============================================================================
get_all_releases() {
    local repo="${1:-${GITHUB_FULL_REPO}}"
    local jq_filter=""

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "get_all_releases: Repository is required (format: owner/repo)"
        return 1
    fi

    # Build jq filter based on configuration
    jq_filter=".[]"

    if [[ "${INCLUDE_DRAFTS}" != "true" ]]; then
        jq_filter="${jq_filter} | select(.isDraft == false)"
    fi

    if [[ "${INCLUDE_PRERELEASES}" != "true" ]]; then
        jq_filter="${jq_filter} | select(.isPrerelease == false)"
    fi

    jq_filter="${jq_filter} | .tagName"

    log_info "Fetching releases from $repo (limit: $RELEASE_LIMIT)" >&2

    if ! "$GH_CMD" release list \
        --repo "$repo" \
        --json tagName,name,publishedAt,isDraft,isPrerelease \
        --limit "$RELEASE_LIMIT" \
        --jq "$jq_filter" 2>/dev/null; then
        log_error "Failed to fetch releases from $repo" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# get_release_count - Get the count of releases
# =============================================================================
# Arguments:
#   $1 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Output:
#   Prints the number of releases
# Returns:
#   0 on success, 1 on failure
# =============================================================================
get_release_count() {
    local repo="${1:-${GITHUB_FULL_REPO}}"
    local count

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "get_release_count: Repository is required (format: owner/repo)"
        return 1
    fi

    count=$(get_all_releases "$repo" 2>/dev/null | wc -l | tr -d ' ')
    echo "$count"
    return 0
}

# =============================================================================
# get_release_info - Get detailed information about a specific release
# =============================================================================
# Arguments:
#   $1 - tag: Release tag (e.g., "v1.0.0")
#   $2 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Output:
#   Prints JSON with release details
# Returns:
#   0 on success, 1 on failure
# =============================================================================
get_release_info() {
    local tag="$1"
    local repo="${2:-${GITHUB_FULL_REPO}}"

    if [[ -z "$tag" ]]; then
        log_error "get_release_info: Release tag is required"
        return 1
    fi

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "get_release_info: Repository is required (format: owner/repo)"
        return 1
    fi

    log_info "Fetching release info for $tag from $repo"

    if ! "$GH_CMD" release view "$tag" \
        --repo "$repo" \
        --json tagName,name,body,publishedAt,isDraft,isPrerelease,assets,author,url 2>/dev/null; then
        log_error "Failed to fetch release info for $tag from $repo"
        return 1
    fi

    return 0
}

# =============================================================================
# get_release_assets - Get list of assets for a release
# =============================================================================
# Arguments:
#   $1 - tag: Release tag (e.g., "v1.0.0")
#   $2 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Output:
#   Prints asset names, one per line
# Returns:
#   0 on success, 1 on failure
# =============================================================================
get_release_assets() {
    local tag="$1"
    local repo="${2:-${GITHUB_FULL_REPO}}"

    if [[ -z "$tag" ]]; then
        log_error "get_release_assets: Release tag is required"
        return 1
    fi

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "get_release_assets: Repository is required (format: owner/repo)"
        return 1
    fi

    "$GH_CMD" release view "$tag" \
        --repo "$repo" \
        --json assets \
        --jq '.assets[].name' 2>/dev/null || true
}

# =============================================================================
# has_release_assets - Check if a release has downloadable assets
# =============================================================================
# Arguments:
#   $1 - tag: Release tag (e.g., "v1.0.0")
#   $2 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Returns:
#   0 if release has assets, 1 if not
# =============================================================================
has_release_assets() {
    local tag="$1"
    local repo="${2:-${GITHUB_FULL_REPO}}"
    local asset_count

    if [[ -z "$tag" ]]; then
        return 1
    fi

    asset_count=$("$GH_CMD" release view "$tag" \
        --repo "$repo" \
        --json assets \
        --jq '.assets | length' 2>/dev/null || echo "0")

    [[ "$asset_count" -gt 0 ]]
}

# =============================================================================
# download_release_assets - Download all assets for a release
# =============================================================================
# Arguments:
#   $1 - tag: Release tag (e.g., "v1.0.0")
#   $2 - output_dir: Directory to download assets to
#   $3 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Returns:
#   0 on success (or if no assets to download), 1 on failure
# Note:
#   Creates output_dir if it doesn't exist.
#   If release has no assets, logs a warning and returns 0.
# =============================================================================
download_release_assets() {
    local tag="$1"
    local output_dir="$2"
    local repo="${3:-${GITHUB_FULL_REPO}}"

    if [[ -z "$tag" ]]; then
        log_error "download_release_assets: Release tag is required"
        return 1
    fi

    if [[ -z "$output_dir" ]]; then
        log_error "download_release_assets: Output directory is required"
        return 1
    fi

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "download_release_assets: Repository is required (format: owner/repo)"
        return 1
    fi

    # Create output directory
    mkdir -p "$output_dir"

    log_info "Downloading assets for $tag to $output_dir"

    # Check if release has assets first
    if ! has_release_assets "$tag" "$repo"; then
        log_warn "No downloadable assets for release $tag, skipping download"
        return 0
    fi

    # Download the assets
    if ! "$GH_CMD" release download "$tag" \
        --repo "$repo" \
        --dir "$output_dir" 2>/dev/null; then
        log_warn "Failed to download some assets for $tag, continuing"
        return 0
    fi

    # List downloaded assets
    local downloaded_count
    downloaded_count=$(find "$output_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    log_info "Downloaded $downloaded_count asset(s) to $output_dir"

    return 0
}

# =============================================================================
# download_release_asset - Download a specific asset from a release
# =============================================================================
# Arguments:
#   $1 - tag: Release tag (e.g., "v1.0.0")
#   $2 - asset_name: Name of the asset to download
#   $3 - output_dir: Directory to download asset to
#   $4 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Returns:
#   0 on success, 1 on failure
# =============================================================================
download_release_asset() {
    local tag="$1"
    local asset_name="$2"
    local output_dir="$3"
    local repo="${4:-${GITHUB_FULL_REPO}}"

    if [[ -z "$tag" || -z "$asset_name" || -z "$output_dir" ]]; then
        log_error "download_release_asset: Tag, asset name, and output directory are required"
        return 1
    fi

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "download_release_asset: Repository is required (format: owner/repo)"
        return 1
    fi

    mkdir -p "$output_dir"

    log_info "Downloading asset $asset_name from $tag to $output_dir"

    if ! "$GH_CMD" release download "$tag" \
        --repo "$repo" \
        --pattern "$asset_name" \
        --dir "$output_dir" 2>/dev/null; then
        log_error "Failed to download asset $asset_name from $tag"
        return 1
    fi

    log_info "Successfully downloaded $asset_name"
    return 0
}

# =============================================================================
# get_latest_release - Get the latest non-draft, non-prerelease release tag
# =============================================================================
# Arguments:
#   $1 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Output:
#   Prints the latest release tag
# Returns:
#   0 on success, 1 on failure or if no releases found
# =============================================================================
get_latest_release() {
    local repo="${1:-${GITHUB_FULL_REPO}}"
    local latest

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "get_latest_release: Repository is required (format: owner/repo)"
        return 1
    fi

    latest=$("$GH_CMD" release list \
        --repo "$repo" \
        --json tagName,isDraft,isPrerelease \
        --limit 1 \
        --jq '.[] | select(.isDraft == false and .isPrerelease == false) | .tagName' 2>/dev/null | head -1)

    if [[ -z "$latest" ]]; then
        log_error "No releases found for $repo"
        return 1
    fi

    echo "$latest"
    return 0
}

# =============================================================================
# release_exists - Check if a release exists
# =============================================================================
# Arguments:
#   $1 - tag: Release tag to check
#   $2 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Returns:
#   0 if release exists, 1 if not
# =============================================================================
release_exists() {
    local tag="$1"
    local repo="${2:-${GITHUB_FULL_REPO}}"

    if [[ -z "$tag" ]]; then
        return 1
    fi

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        return 1
    fi

    "$GH_CMD" release view "$tag" --repo "$repo" &>/dev/null
}

# =============================================================================
# get_releases_since - Get releases published after a specific date
# =============================================================================
# Arguments:
#   $1 - since_date: ISO 8601 date string (e.g., "2024-01-01")
#   $2 - repo: Repository in owner/repo format (optional, uses GITHUB_FULL_REPO)
# Output:
#   Prints release tags published after the specified date
# Returns:
#   0 on success, 1 on failure
# =============================================================================
get_releases_since() {
    local since_date="$1"
    local repo="${2:-${GITHUB_FULL_REPO}}"
    local jq_filter

    if [[ -z "$since_date" ]]; then
        log_error "get_releases_since: Date is required (format: YYYY-MM-DD)"
        return 1
    fi

    if [[ -z "$repo" || "$repo" == "/" ]]; then
        log_error "get_releases_since: Repository is required (format: owner/repo)"
        return 1
    fi

    jq_filter=".[] | select(.isDraft == false and .publishedAt >= \"${since_date}\") | .tagName"

    "$GH_CMD" release list \
        --repo "$repo" \
        --json tagName,publishedAt,isDraft \
        --limit "$RELEASE_LIMIT" \
        --jq "$jq_filter" 2>/dev/null || return 1
}

# =============================================================================
# Main - Only run if script is executed directly (not sourced)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "GitHub Release Integration Functions"
            echo ""
            echo "This script is designed to be sourced by other scripts."
            echo "Usage: source ${0##*/}"
            echo ""
            echo "Available functions:"
            echo "  get_all_releases [repo]                 - Get all release tags"
            echo "  get_release_count [repo]                - Get count of releases"
            echo "  get_release_info <tag> [repo]           - Get release details as JSON"
            echo "  get_release_assets <tag> [repo]         - Get asset names for release"
            echo "  has_release_assets <tag> [repo]         - Check if release has assets"
            echo "  download_release_assets <tag> <dir> [repo] - Download all assets"
            echo "  download_release_asset <tag> <name> <dir> [repo] - Download specific asset"
            echo "  get_latest_release [repo]               - Get latest release tag"
            echo "  release_exists <tag> [repo]             - Check if release exists"
            echo "  get_releases_since <date> [repo]        - Get releases after date"
            echo "  check_gh_auth                           - Verify gh CLI authentication"
            echo ""
            echo "Environment:"
            echo "  GITHUB_FULL_REPO: ${GITHUB_FULL_REPO:-<not set>}"
            echo "  RELEASE_LIMIT: $RELEASE_LIMIT"
            echo "  INCLUDE_PRERELEASES: $INCLUDE_PRERELEASES"
            echo "  INCLUDE_DRAFTS: $INCLUDE_DRAFTS"
            ;;
        --test)
            echo "Running basic tests..."
            log_info "Logging functions work"
            log_warn "Warning test"
            log_error "Error test (not a real error)"
            echo ""
            echo "Checking GitHub CLI..."
            if check_gh_auth; then
                echo "GitHub CLI is authenticated"
                if [[ -n "${GITHUB_FULL_REPO:-}" && "${GITHUB_FULL_REPO}" != "/" ]]; then
                    echo "Fetching release count for $GITHUB_FULL_REPO..."
                    count=$(get_release_count "$GITHUB_FULL_REPO" 2>/dev/null || echo "error")
                    echo "Release count: $count"
                fi
            else
                echo "GitHub CLI is not authenticated (run 'gh auth login')"
            fi
            echo ""
            echo "Syntax check passed!"
            ;;
        --list)
            # Quick command to list releases
            repo="${2:-${GITHUB_FULL_REPO}}"
            if [[ -z "$repo" || "$repo" == "/" ]]; then
                echo "Usage: $0 --list <owner/repo>"
                exit 1
            fi
            get_all_releases "$repo"
            ;;
        --info)
            # Quick command to get release info
            tag="${2:-}"
            repo="${3:-${GITHUB_FULL_REPO}}"
            if [[ -z "$tag" ]]; then
                echo "Usage: $0 --info <tag> [owner/repo]"
                exit 1
            fi
            get_release_info "$tag" "$repo"
            ;;
        *)
            echo "Run with --help for usage information"
            echo "Run with --test for a basic functionality test"
            echo "Run with --list <repo> to list releases"
            echo "Run with --info <tag> [repo] to get release info"
            ;;
    esac
fi
