#!/usr/bin/env bash
# Convenience wrapper for MiniVim kernel builds pinned to Linux 6.17.14.
# Usage: ./build-minivim-kernel-6.17.sh [arch] [kernel_version]
# Example: ./build-minivim-kernel-6.17.sh x86_64
# An optional kernel_version argument keeps room for RC testing while defaulting to 6.17.14.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_KERNEL_VERSION="6.17.14"

ARCH="${1:-x86_64}"
if [ $# -ge 2 ]; then
  KERNEL_VERSION="$2"
else
  KERNEL_VERSION="${KERNEL_VERSION:-${DEFAULT_KERNEL_VERSION}}"
fi

exec "${SCRIPT_DIR}/build-minivim-kernel.sh" "${ARCH}" "${KERNEL_VERSION}"
