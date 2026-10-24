#!/bin/bash
# Automated build script for VibeCode on OmniOS ARM64
# This runs Packer to create a fully-configured VM

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}║  VibeCode on OmniOS ARM64 - Automated Packer Build        ║${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Configuration
OMNIOS_IMAGE="$HOME/Downloads/omnios-arm64/omnios-arm64.qcow2"
PACKER_TEMPLATE="vibecode-omnios-lx-zone.pkr.hcl"
OUTPUT_DIR="output-vibecode-omnios-lx"

# Pre-flight checks
echo -e "${YELLOW}=== Pre-Flight Checks ===${NC}"

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
    echo -e "${RED}ERROR: Packer not installed${NC}"
    echo "Install with: brew install packer"
    exit 1
fi
echo -e "${GREEN}✓ Packer installed: $(packer version)${NC}"

# Check if QEMU is installed
if ! command -v qemu-system-aarch64 &> /dev/null; then
    echo -e "${RED}ERROR: QEMU not installed${NC}"
    echo "Install with: brew install qemu"
    exit 1
fi
echo -e "${GREEN}✓ QEMU installed: $(qemu-system-aarch64 --version | head -1)${NC}"

# Check if OmniOS image exists
if [ ! -f "$OMNIOS_IMAGE" ]; then
    echo -e "${RED}ERROR: OmniOS image not found${NC}"
    echo "Expected: $OMNIOS_IMAGE"
    echo "Run: cd ~/Downloads/omnios-arm64 && ./launch-omnios.sh"
    exit 1
fi
echo -e "${GREEN}✓ OmniOS image found: $(ls -lh $OMNIOS_IMAGE | awk '{print $5}')${NC}"

# Check if UEFI firmware exists
UEFI_FIRMWARE="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
if [ ! -f "$UEFI_FIRMWARE" ]; then
    echo -e "${RED}ERROR: UEFI firmware not found${NC}"
    echo "Expected: $UEFI_FIRMWARE"
    exit 1
fi
echo -e "${GREEN}✓ UEFI firmware found${NC}"

# Check if scripts exist
if [ ! -f "scripts/create-lx-zone.sh" ]; then
    echo -e "${RED}ERROR: create-lx-zone.sh not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Zone creation script found${NC}"

if [ ! -f "scripts/install-vibecode-deps.sh" ]; then
    echo -e "${RED}ERROR: install-vibecode-deps.sh not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dependency installer found${NC}"

echo

# Initialize Packer
echo -e "${YELLOW}=== Initializing Packer ===${NC}"
packer init $PACKER_TEMPLATE

# Format check
echo -e "${YELLOW}=== Checking Packer Template ===${NC}"
packer fmt $PACKER_TEMPLATE || true

# Validate
echo -e "${YELLOW}=== Validating Packer Template ===${NC}"
if ! packer validate $PACKER_TEMPLATE; then
    echo -e "${RED}ERROR: Packer validation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Packer template valid${NC}"
echo

# Confirm before building
echo -e "${YELLOW}=== Build Configuration ===${NC}"
echo "Template: $PACKER_TEMPLATE"
echo "Base Image: $OMNIOS_IMAGE"
echo "Output Directory: $OUTPUT_DIR"
echo "Estimated Time: 15-30 minutes"
echo

read -p "$(echo -e ${GREEN}Start build? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

# Run Packer build
echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Starting Packer Build                                    ║${NC}"
echo -e "${BLUE}║  This will take 15-30 minutes                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Build with debug output
PACKER_LOG=1 packer build \\
    -var "omnios_image=$OMNIOS_IMAGE" \\
    -var "output_directory=$OUTPUT_DIR" \\
    $PACKER_TEMPLATE

BUILD_EXIT_CODE=$?

echo
if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  ✅ Build Complete!                                        ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Output Image:${NC}"
    ls -lh $OUTPUT_DIR/*.qcow2
    echo
    echo -e "${YELLOW}To launch the built VM:${NC}"
    echo "qemu-system-aarch64 \\"
    echo "  -machine virt -cpu host -accel hvf \\"
    echo "  -smp 4 -m 8192 \\"
    echo "  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \\"
    echo "  -drive file=$OUTPUT_DIR/vibecode-omnios-arm64,if=virtio,format=qcow2 \\"
    echo "  -device virtio-net-pci,netdev=net0 \\"
    echo "  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000 \\"
    echo "  -nographic"
    echo
    echo -e "${YELLOW}To access VibeCode:${NC}"
    echo "1. Boot the VM (command above)"
    echo "2. Login to zone: zlogin vibecode"
    echo "3. Start VibeCode: systemctl start vibecode"
    echo "4. Access: http://localhost:3000"
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}║  ❌ Build Failed                                           ║${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Check the output above for errors"
    echo "Common issues:"
    echo "  - SSH timeout: OmniOS may need manual configuration"
    echo "  - Network issues: Check DHCP in zone"
    echo "  - Permission issues: Run as root or with sudo"
    exit 1
fi
