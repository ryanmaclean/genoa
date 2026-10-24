#!/usr/bin/env bash
# Trim MicroVM Rootfs for Sub-10s Cold Boots
# Removes unnecessary files to optimize boot time
set -euo pipefail

ROOTFS_DIR="${1:-artifacts/minivim/rootfs}"
OUTPUT_FILE="${2:-artifacts/minivim/rootfs-trimmed.img}"
TARGET_SIZE_MB="${TARGET_SIZE_MB:-50}"

echo "=== MicroVM Rootfs Trimming ==="
echo "Input: $ROOTFS_DIR"
echo "Output: $OUTPUT_FILE"
echo "Target size: ${TARGET_SIZE_MB}MB"
echo ""

if [[ ! -d "$ROOTFS_DIR" && ! -f "$ROOTFS_DIR" ]]; then
  echo "❌ Rootfs not found: $ROOTFS_DIR"
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Extract if it's an image
if [[ -f "$ROOTFS_DIR" ]]; then
  echo "Extracting rootfs image..."
  mkdir -p "$WORK_DIR/rootfs"
  
  # Try different extraction methods
  if file "$ROOTFS_DIR" | grep -q "gzip"; then
    gunzip -c "$ROOTFS_DIR" > "$WORK_DIR/rootfs.cpio"
    cd "$WORK_DIR/rootfs" && cpio -idm < ../rootfs.cpio
  elif file "$ROOTFS_DIR" | grep -q "cpio"; then
    cd "$WORK_DIR/rootfs" && cpio -idm < "$ROOTFS_DIR"
  else
    echo "❌ Unknown rootfs format"
    exit 1
  fi
  
  ROOTFS_WORK="$WORK_DIR/rootfs"
else
  ROOTFS_WORK="$ROOTFS_DIR"
fi

echo "Analyzing rootfs..."
ORIGINAL_SIZE=$(du -sm "$ROOTFS_WORK" | awk '{print $1}')
echo "Original size: ${ORIGINAL_SIZE}MB"

# Trimming operations
echo ""
echo "Trimming unnecessary files..."

# Remove documentation
find "$ROOTFS_WORK" -type d -name "doc" -o -name "man" -o -name "info" 2>/dev/null | while read dir; do
  rm -rf "$dir"
  echo "  Removed: $dir"
done

# Remove locales (keep en_US only)
if [[ -d "$ROOTFS_WORK/usr/share/locale" ]]; then
  find "$ROOTFS_WORK/usr/share/locale" -mindepth 1 -maxdepth 1 -type d ! -name "en_US" -exec rm -rf {} + 2>/dev/null || true
  echo "  Trimmed locales (kept en_US only)"
fi

# Remove static libraries
find "$ROOTFS_WORK" -name "*.a" -type f -delete 2>/dev/null && echo "  Removed static libraries"

# Remove package manager caches
rm -rf "$ROOTFS_WORK/var/cache/apt"/* 2>/dev/null && echo "  Cleared apt cache"
rm -rf "$ROOTFS_WORK/var/cache/yum"/* 2>/dev/null && echo "  Cleared yum cache"

# Remove kernel sources if present
rm -rf "$ROOTFS_WORK/usr/src"/* 2>/dev/null && echo "  Removed kernel sources"

# Remove development headers
find "$ROOTFS_WORK" -path "*/include/*" -name "*.h" -delete 2>/dev/null && echo "  Removed development headers"

# Remove Python bytecode
find "$ROOTFS_WORK" -name "*.pyc" -o -name "*.pyo" -o -name "__pycache__" | xargs rm -rf 2>/dev/null && echo "  Removed Python bytecode"

# Remove logs
find "$ROOTFS_WORK/var/log" -type f -delete 2>/dev/null && echo "  Cleared logs"

# Strip binaries
echo ""
echo "Stripping binaries..."
find "$ROOTFS_WORK" -type f -executable -exec file {} \; | grep ELF | cut -d: -f1 | while read binary; do
  strip --strip-unneeded "$binary" 2>/dev/null || true
done
echo "  Stripped executables"

# Calculate new size
TRIMMED_SIZE=$(du -sm "$ROOTFS_WORK" | awk '{print $1}')
SAVINGS=$((ORIGINAL_SIZE - TRIMMED_SIZE))
SAVINGS_PCT=$((SAVINGS * 100 / ORIGINAL_SIZE))

echo ""
echo "=== Trimming Results ==="
echo "Original: ${ORIGINAL_SIZE}MB"
echo "Trimmed: ${TRIMMED_SIZE}MB"
echo "Savings: ${SAVINGS}MB (${SAVINGS_PCT}%)"

# Create new rootfs image
echo ""
echo "Creating trimmed rootfs image..."
mkdir -p "$(dirname "$OUTPUT_FILE")"

cd "$ROOTFS_WORK"
find . | cpio -o -H newc | gzip -9 > "$OUTPUT_FILE"

OUTPUT_SIZE=$(du -m "$OUTPUT_FILE" | awk '{print $1}')
echo "Output size: ${OUTPUT_SIZE}MB"

if [[ $OUTPUT_SIZE -le $TARGET_SIZE_MB ]]; then
  echo "✅ Target size achieved (≤${TARGET_SIZE_MB}MB)"
else
  echo "⚠️  Target size not achieved (>${TARGET_SIZE_MB}MB)"
  echo "Consider more aggressive trimming or using busybox-only rootfs"
fi

echo ""
echo "✓ Trimmed rootfs saved to: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Test boot time with trimmed rootfs"
echo "2. Verify essential services still work"
echo "3. Measure cold boot performance improvement"
