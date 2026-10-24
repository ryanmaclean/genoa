#!/usr/bin/env bash
# Build minimal BusyBox initramfs for Apple VF fast boot experiments
# Target: Sub-2MB initramfs with /healthz endpoint
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ARCH=${1:-arm64}
OUTPUT_DIR="${ROOT_DIR}/bench-images/apple-vf-fastboot"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"

echo "=== Building Minimal Initramfs for Apple VF Fast Boot ==="
echo "Architecture: $ARCH"
echo "Output: $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"

# Build static BusyBox if not available
BUSYBOX_SRC="${ROOT_DIR}/bench-images/busybox/busybox-${BUSYBOX_VERSION}"
BUSYBOX_BIN="${BUSYBOX_SRC}/busybox"

if [[ ! -f "$BUSYBOX_BIN" ]]; then
  echo "Building BusyBox..."
  "${ROOT_DIR}/scripts/benchmarks/build-busybox-musl.sh" "$ARCH"
fi

# Create rootfs structure
ROOTFS="${OUTPUT_DIR}/rootfs"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"/{bin,sbin,etc,proc,sys,dev,tmp,var/run}

echo "Creating minimal rootfs..."

# Copy BusyBox
cp "$BUSYBOX_BIN" "$ROOTFS/bin/busybox"
chmod 755 "$ROOTFS/bin/busybox"

# Create essential symlinks
for cmd in sh ash init mount umount mkdir cat echo ls ps kill sleep \
           ip ifconfig route ping wget httpd nc; do
  ln -sf busybox "$ROOTFS/bin/$cmd"
done

for cmd in init halt reboot poweroff; do
  ln -sf ../bin/busybox "$ROOTFS/sbin/$cmd"
done

# Create /init script optimized for fast boot
cat > "$ROOTFS/init" << 'INIT_EOF'
#!/bin/sh
# Minimal init for Apple VF fast boot benchmark
# Target: Boot to /healthz in < 3s

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /var/run

# Configure network (static IP for deterministic boot)
ip link set lo up
ip link set eth0 up 2>/dev/null || true

# Try DHCP first, fall back to static
if ! ip addr show eth0 | grep -q "inet "; then
  # Use static IP for Apple VF NAT (10.0.2.x range)
  ip addr add 10.0.2.15/24 dev eth0
  ip route add default via 10.0.2.2
fi

# Create /healthz response file
mkdir -p /www
echo "ok" > /www/healthz
cat > /www/index.html << 'HTML'
<!DOCTYPE html>
<html><head><title>Apple VF Fast Boot</title></head>
<body><h1>VM Ready</h1><p>Boot complete.</p></body>
</html>
HTML

# Start HTTP server for /healthz endpoint
# BusyBox httpd serves /www on port 80
httpd -p 3000 -h /www &

# Signal boot complete
echo "Boot complete - /healthz ready on port 3000"

# Keep init running
exec /bin/sh
INIT_EOF
chmod 755 "$ROOTFS/init"

# Create minimal /etc files
echo "root:x:0:0:root:/:/bin/sh" > "$ROOTFS/etc/passwd"
echo "root:x:0:" > "$ROOTFS/etc/group"
echo "localhost" > "$ROOTFS/etc/hostname"

# Create initramfs
echo ""
echo "Creating initramfs..."
cd "$ROOTFS"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUTPUT_DIR}/initramfs-minimal.cpio.gz"

# Calculate sizes
ROOTFS_SIZE=$(du -sh "$ROOTFS" | cut -f1)
INITRAMFS_SIZE=$(du -sh "${OUTPUT_DIR}/initramfs-minimal.cpio.gz" | cut -f1)

echo ""
echo "=== Build Complete ==="
echo "Rootfs size: $ROOTFS_SIZE"
echo "Initramfs size: $INITRAMFS_SIZE"
echo "Output: ${OUTPUT_DIR}/initramfs-minimal.cpio.gz"
echo ""
echo "To test:"
echo "  MICROVM_INITRD=${OUTPUT_DIR}/initramfs-minimal.cpio.gz \\"
echo "  scripts/benchmarks/vscode_microvm.sh measure"
