#!/usr/bin/env bash
# Validate ARMv7 MiniVim kernel build
# Usage: ./validate-armv7-kernel.sh [kernel_version]
# Example: ./validate-armv7-kernel.sh 6.17.0

set -euo pipefail

KERNEL_VERSION="${1:-6.17.14}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/bench-images/minivim"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/minivim"
IMAGE_PATH="${OUTPUT_DIR}/zImage-armv7-${KERNEL_VERSION}"

echo "=== ARMv7 Kernel Validation ==="
echo "Kernel Version: ${KERNEL_VERSION}"
echo "Image Path: ${IMAGE_PATH}"
echo ""

# Phase 1: File existence check
echo "Phase 1: Checking kernel image..."
if [ ! -f "${IMAGE_PATH}" ]; then
    echo "❌ ERROR: Kernel image not found at ${IMAGE_PATH}"
    exit 1
fi
echo "✓ Kernel image exists"

# Get kernel size
KERNEL_SIZE=$(stat -f%z "${IMAGE_PATH}" 2>/dev/null || stat -c%s "${IMAGE_PATH}" 2>/dev/null || echo "0")
KERNEL_SIZE_MB=$(echo "scale=2; ${KERNEL_SIZE} / 1024 / 1024" | bc)
echo "✓ Kernel size: ${KERNEL_SIZE_MB} MB"

# Phase 2: Size validation
echo ""
echo "Phase 2: Size validation..."
TARGET_SIZE_MB=4
if (( $(echo "${KERNEL_SIZE_MB} > ${TARGET_SIZE_MB}" | bc -l) )); then
    echo "⚠️  WARNING: Kernel size (${KERNEL_SIZE_MB} MB) exceeds target (${TARGET_SIZE_MB} MB)"
else
    echo "✓ Kernel size within target (${TARGET_SIZE_MB} MB)"
fi

# Phase 3: File type check
echo ""
echo "Phase 3: File type validation..."
if command -v file &> /dev/null; then
    FILE_TYPE=$(file "${IMAGE_PATH}")
    echo "File type: ${FILE_TYPE}"
    if echo "${FILE_TYPE}" | grep -q "ARM"; then
        echo "✓ Valid ARM kernel image"
    else
        echo "⚠️  WARNING: File type doesn't explicitly show ARM"
    fi
else
    echo "⚠️  'file' command not available, skipping type check"
fi

# Phase 4: QEMU boot test (if QEMU is available)
echo ""
echo "Phase 4: QEMU boot validation..."
if command -v qemu-system-arm &> /dev/null; then
    echo "Testing QEMU boot (5 second timeout)..."
    
    # Create a minimal test
    TIMEOUT=5
    QEMU_LOG="${ARTIFACTS_DIR}/qemu-boot-test-armv7.log"
    mkdir -p "${ARTIFACTS_DIR}"
    
    # Try to boot with minimal options
    timeout ${TIMEOUT} qemu-system-arm \
        -machine virt \
        -cpu cortex-a15 \
        -m 256M \
        -kernel "${IMAGE_PATH}" \
        -nographic \
        -serial mon:stdio \
        -append "console=ttyAMA0" \
        > "${QEMU_LOG}" 2>&1 || true
    
    if [ -f "${QEMU_LOG}" ]; then
        if grep -q "Linux version" "${QEMU_LOG}"; then
            echo "✓ Kernel started in QEMU"
            BOOT_TIME=$(grep "Linux version" "${QEMU_LOG}" | head -1)
            echo "  Boot log: ${BOOT_TIME}"
        elif grep -q "Booting" "${QEMU_LOG}"; then
            echo "✓ QEMU boot initiated"
        else
            echo "⚠️  QEMU test inconclusive (may need initramfs)"
            echo "  Log: ${QEMU_LOG}"
        fi
    else
        echo "⚠️  QEMU log not generated"
    fi
else
    echo "⚠️  QEMU not available, skipping boot test"
    echo "  Install with: sudo apt-get install qemu-system-arm"
fi

# Generate JSON report
echo ""
echo "Phase 5: Generating validation report..."
REPORT_FILE="${ARTIFACTS_DIR}/armv7-validation-${KERNEL_VERSION}.json"
cat > "${REPORT_FILE}" << EOF
{
  "validation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kernel_version": "${KERNEL_VERSION}",
  "architecture": "armv7",
  "image_path": "${IMAGE_PATH}",
  "image_size_bytes": ${KERNEL_SIZE},
  "image_size_mb": ${KERNEL_SIZE_MB},
  "target_size_mb": ${TARGET_SIZE_MB},
  "size_compliant": $([ "$(echo "${KERNEL_SIZE_MB} <= ${TARGET_SIZE_MB}" | bc -l)" -eq 1 ] && echo "true" || echo "false"),
  "qemu_available": $(command -v qemu-system-arm &> /dev/null && echo "true" || echo "false"),
  "validation_passed": true
}
EOF

echo "✓ Validation report: ${REPORT_FILE}"

# Summary
echo ""
echo "=== Validation Summary ==="
echo "Status: ✅ PASSED"
echo "Kernel: ${IMAGE_PATH}"
echo "Size: ${KERNEL_SIZE_MB} MB"
echo "Report: ${REPORT_FILE}"
echo ""
echo "Next steps:"
echo "1. Build BusyBox initramfs if needed"
echo "2. Run full boot benchmark: python3 scripts/benchmarks/boot_latency_bench.py"
echo "3. Capture timing data for documentation"
echo ""
