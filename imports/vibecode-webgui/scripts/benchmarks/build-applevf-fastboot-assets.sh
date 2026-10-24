#!/usr/bin/env bash
# Build arm64 EFI-stub kernel + minimal BusyBox initramfs for Apple VF fast boot
set -euo pipefail

ARCH=${1:-arm64}
KERNEL_VERSION=${2:-6.12.10}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUTPUT_DIR="${ROOT_DIR}/bench-images/apple-vf-fastboot"

if [[ "$ARCH" != "arm64" ]]; then
  echo "error: Apple VF fast-boot assets require arm64" >&2
  exit 1
fi

echo "=== Apple VF Fast-Boot Assets ==="
echo "Architecture: ${ARCH}"
echo "Kernel version: ${KERNEL_VERSION}"
echo "Output: ${OUTPUT_DIR}"
echo ""

"${ROOT_DIR}/scripts/benchmarks/build-efi-stub-kernel.sh" "$ARCH" "$KERNEL_VERSION"
"${ROOT_DIR}/scripts/benchmarks/build-minimal-initramfs.sh" "$ARCH"

echo ""
echo "Assets ready:"
echo "  - ${OUTPUT_DIR}/vmlinux-efi-stub"
echo "  - ${OUTPUT_DIR}/initramfs-minimal.cpio.gz"
echo ""
echo "Next:"
echo "  APPLEVF_KERNEL=${OUTPUT_DIR}/vmlinux-efi-stub \\"
echo "  APPLEVF_INITRD=${OUTPUT_DIR}/initramfs-minimal.cpio.gz \\"
echo "  scripts/benchmarks/applevf_fastboot_bench.sh bench 5"
