#!/bin/bash
# Create and configure LX branded zone for VibeCode
# Runs inside OmniOS global zone

set -euo pipefail

echo "=== Step 4: Creating LX Branded Zone ==="

# Configuration
ZONE_NAME="vibecode"
ZONE_PATH="/zones/vibecode"
ZONE_BRAND="lx"
ZONE_CPUS="4"
ZONE_MEM_PHYSICAL="4G"
ZONE_MEM_SWAP="8G"
ZONE_ROOTFS="/opt/zone-images/debian-11-arm64.tar.gz"

echo "=== Zone Configuration ==="
echo "Name: $ZONE_NAME"
echo "Path: $ZONE_PATH"
echo "Brand: $ZONE_BRAND"
echo "CPUs: $ZONE_CPUS"
echo "Memory: $ZONE_MEM_PHYSICAL (physical), $ZONE_MEM_SWAP (swap)"

# Check if zone already exists
if zoneadm list -cp | grep -q "^[0-9]*:$ZONE_NAME:"; then
    echo "Zone $ZONE_NAME already exists. Halting and deleting..."
    zoneadm -z $ZONE_NAME halt 2>/dev/null || true
    sleep 2
    zoneadm -z $ZONE_NAME uninstall -F 2>/dev/null || true
    zonecfg -z $ZONE_NAME delete -F 2>/dev/null || true
fi

echo "=== Creating zone configuration ==="
zonecfg -z $ZONE_NAME <<EOF
create -t lx
set zonepath=$ZONE_PATH
set brand=$ZONE_BRAND
set autoboot=true
set ip-type=exclusive

# CPU limits
add capped-cpu
set ncpus=$ZONE_CPUS
end

# Memory limits
add capped-memory
set physical=$ZONE_MEM_PHYSICAL
set swap=$ZONE_MEM_SWAP
end

# Process limits
add capped-max-lwps
set max-lwps=2000
end

# Shared memory for PostgreSQL
add capped-shmem
set max-shm-memory=2G
end

# Network interface
add net
set physical=net0
end

# Dedicated ZFS dataset for PostgreSQL
add dataset
set name=rpool/zones/vibecode/postgres
end

# Dedicated ZFS dataset for application data
add dataset
set name=rpool/zones/vibecode/data
end

verify
commit
EOF

echo "=== Zone configuration created ==="
zonecfg -z $ZONE_NAME info

# Install the zone
echo "=== Installing zone ==="

# Method 1: If we have a tarball
if [ -f "$ZONE_ROOTFS" ]; then
    echo "Installing from tarball: $ZONE_ROOTFS"
    zoneadm -z $ZONE_NAME install -t $ZONE_ROOTFS

# Method 2: Create from Docker (if available)
elif command -v docker &> /dev/null; then
    echo "Creating rootfs from Docker..."

    # Pull Debian ARM64 image
    docker pull --platform linux/arm64 debian:11

    # Create container and export
    CONTAINER_ID=$(docker create --platform linux/arm64 debian:11)
    mkdir -p /tmp/zone-rootfs
    docker export $CONTAINER_ID | tar -C /tmp/zone-rootfs -xf -
    docker rm $CONTAINER_ID

    # Create tarball
    cd /tmp/zone-rootfs
    tar czf /opt/zone-images/debian-11-arm64.tar.gz .
    cd -

    # Install zone
    zoneadm -z $ZONE_NAME install -t /opt/zone-images/debian-11-arm64.tar.gz

    # Cleanup
    rm -rf /tmp/zone-rootfs

# Method 3: Use zfs send/receive (if available)
else
    echo "ERROR: No zone image available. Please download debian-11-arm64.tar.gz"
    echo "Alternative: Install Docker to create rootfs automatically"
    exit 1
fi

echo "=== Zone installed ==="

# Boot the zone
echo "=== Booting zone ==="
zoneadm -z $ZONE_NAME boot

# Wait for zone to be ready
echo "=== Waiting for zone to be ready ==="
for i in {1..30}; do
    if zlogin $ZONE_NAME true 2>/dev/null; then
        echo "Zone is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Configure zone networking
echo "=== Configuring zone networking ==="
zlogin $ZONE_NAME <<'ZONE_EOF'
# Basic network configuration
cat > /etc/network/interfaces <<'IFACE_EOF'
auto lo
iface lo inet loopback

auto net0
iface net0 inet dhcp
IFACE_EOF

# Start networking
systemctl restart networking || ifup net0

# Update package lists
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

echo "Zone networking configured"
ZONE_EOF

# Verify zone status
echo "=== Zone status ==="
zoneadm list -cv

echo "=== Zone network test ==="
zlogin $ZONE_NAME ping -c 3 8.8.8.8 || echo "Network test failed (may need manual configuration)"

echo "=== Step 4 Complete: LX Zone Created and Running ==="
