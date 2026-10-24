#!/usr/bin/env bash
# Build a BusyBox + Neovim initramfs for MiniVim benchmarks
# Usage: ./build-neovim-initramfs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${REPO_ROOT}/artifacts/minivim/initramfs-work"
OUTPUT_DIR="${REPO_ROOT}/bench-images/busybox"

# Neovim version to download
NEOVIM_VERSION="${NEOVIM_VERSION:-v0.10.2}"
NEOVIM_APPIMAGE_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim.appimage"

echo "=== Building Neovim Initramfs ==="
echo "Neovim Version: ${NEOVIM_VERSION}"
echo "Work Directory: ${WORK_DIR}"
echo ""

# Clean and create work directory
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Create directory structure
echo "Creating directory structure..."
mkdir -p {bin,sbin,etc,proc,sys,dev,tmp,usr/bin,usr/sbin,lib,lib64,root}

# Download and extract Neovim AppImage
echo "Downloading Neovim AppImage..."
curl -L -o nvim.appimage "${NEOVIM_APPIMAGE_URL}"
chmod +x nvim.appimage

# Extract AppImage (requires FUSE or --appimage-extract)
echo "Extracting Neovim..."
./nvim.appimage --appimage-extract >/dev/null 2>&1 || true

if [ -d "squashfs-root" ]; then
    echo "Copying Neovim files..."
    cp -r squashfs-root/usr/* usr/
    
    # Create symlinks
    ln -sf /usr/bin/nvim bin/nvim
    ln -sf /usr/bin/nvim bin/vim
    ln -sf /usr/bin/nvim bin/vi
    
    # Clean up extraction
    rm -rf squashfs-root nvim.appimage
else
    echo "WARNING: Could not extract AppImage. Falling back to static build..."
    
    # Try to download static build instead
    STATIC_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-linux64.tar.gz"
    echo "Downloading static build from ${STATIC_URL}..."
    curl -L -o nvim-static.tar.gz "${STATIC_URL}"
    tar xzf nvim-static.tar.gz
    
    if [ -d "nvim-linux64" ]; then
        cp -r nvim-linux64/* usr/
        ln -sf /usr/bin/nvim bin/nvim
        ln -sf /usr/bin/nvim bin/vim
        ln -sf /usr/bin/nvim bin/vi
        rm -rf nvim-linux64 nvim-static.tar.gz
    else
        echo "ERROR: Could not download Neovim"
        exit 1
    fi
fi

# Download and build BusyBox for basic utilities
echo "Setting up BusyBox..."
BUSYBOX_VERSION="1.36.1"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

if ! command -v busybox &> /dev/null; then
    echo "Downloading BusyBox ${BUSYBOX_VERSION}..."
    curl -L -o busybox.tar.bz2 "${BUSYBOX_URL}"
    tar xjf busybox.tar.bz2
    cd "busybox-${BUSYBOX_VERSION}"
    
    # Configure for static build
    make defconfig
    sed -i.bak 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    
    # Build
    echo "Building BusyBox (this may take a few minutes)..."
    make -j$(nproc 2>/dev/null || echo 4) >/dev/null 2>&1
    
    # Copy to initramfs
    cp busybox "${WORK_DIR}/bin/"
    cd "${WORK_DIR}"
    rm -rf "busybox-${BUSYBOX_VERSION}" busybox.tar.bz2
else
    # Use system busybox
    cp "$(command -v busybox)" bin/
fi

# Create BusyBox symlinks
echo "Creating BusyBox symlinks..."
cd bin
for cmd in sh ash bash ls cat echo mount umount mkdir rmdir cp mv rm ln chmod chown \
           ps kill grep sed awk find xargs tar gzip gunzip less more head tail; do
    ln -sf busybox "$cmd" 2>/dev/null || true
done
cd "${WORK_DIR}"

# Copy essential libraries (if needed)
echo "Checking for required libraries..."
if [ -f usr/bin/nvim ]; then
    # Get library dependencies
    LIBS=$(ldd usr/bin/nvim 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$" || true)
    
    if [ -n "$LIBS" ]; then
        echo "Copying required libraries..."
        for lib in $LIBS; do
            if [ -f "$lib" ]; then
                cp -L "$lib" lib/ 2>/dev/null || true
            fi
        done
        
        # Copy ld-linux
        LD_LINUX=$(ldd usr/bin/nvim 2>/dev/null | grep "ld-linux" | awk '{print $1}')
        if [ -n "$LD_LINUX" ] && [ -f "$LD_LINUX" ]; then
            cp -L "$LD_LINUX" lib/ 2>/dev/null || true
        fi
    fi
fi

# Create init script
echo "Creating init script..."
cat > init << 'EOF'
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Set up environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export TERM=xterm-256color

# Clear screen
clear

# Welcome message
echo "=========================================="
echo "  MiniVim Kernel + Neovim Test Environment"
echo "=========================================="
echo ""
echo "Neovim is available as: nvim, vim, vi"
echo "Type 'nvim' to start Neovim"
echo "Type 'exit' to shutdown"
echo ""

# Start shell
exec /bin/sh
EOF

chmod +x init

# Create a sample file to edit
cat > root/welcome.txt << 'EOF'
Welcome to MiniVim + Neovim!

This is a minimal Linux kernel with Neovim running in an initramfs.

Try editing this file with:
  nvim welcome.txt

Key features:
- Minimal kernel (< 10MB)
- Neovim for editing
- BusyBox utilities
- Fast boot time

Perfect for testing Avante.nvim and other Neovim plugins!
EOF

# Create minimal Neovim config
mkdir -p root/.config/nvim
cat > root/.config/nvim/init.lua << 'EOF'
-- Minimal Neovim config for MiniVim
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2

-- Show welcome message
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    print("MiniVim + Neovim - Ready!")
  end,
})
EOF

# Create the initramfs
echo "Creating initramfs archive..."
find . | cpio -o -H newc | gzip > "${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz"

# Get size
SIZE=$(du -h "${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz" | cut -f1)

echo ""
echo "=== Build Complete ==="
echo "Output: ${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz"
echo "Size: ${SIZE}"
echo ""
echo "To test with QEMU:"
echo "  qemu-system-x86_64 -kernel bzImage -initrd busybox-neovim-initrd.cpio.gz -m 512M -nographic -append 'console=ttyS0'"
echo ""

# Cleanup
cd "${REPO_ROOT}"
rm -rf "${WORK_DIR}"
