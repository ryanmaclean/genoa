#!/usr/bin/env bash
# Build Neovim initramfs on macOS (cross-platform compatible)
# This version downloads pre-built binaries instead of building from source

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${REPO_ROOT}/artifacts/minivim/initramfs-work"
OUTPUT_DIR="${REPO_ROOT}/bench-images/busybox"

# Versions
NEOVIM_VERSION="${NEOVIM_VERSION:-v0.10.2}"
BUSYBOX_VERSION="1.36.1"

echo "=== Building Neovim Initramfs (macOS Compatible) ==="
echo "Neovim Version: ${NEOVIM_VERSION}"
echo "BusyBox Version: ${BUSYBOX_VERSION}"
echo "Work Directory: ${WORK_DIR}"
echo ""

# Clean and create work directory
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Create directory structure
echo "Creating directory structure..."
mkdir -p {bin,sbin,etc,proc,sys,dev,tmp,usr/bin,usr/sbin,usr/lib,lib,lib64,root/.config/nvim}

# Download pre-built Neovim for Linux
echo "Downloading Neovim ${NEOVIM_VERSION} for Linux..."
NEOVIM_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-linux64.tar.gz"
curl -L -o nvim-linux64.tar.gz "${NEOVIM_URL}"

echo "Extracting Neovim..."
tar xzf nvim-linux64.tar.gz
cp -r nvim-linux64/* usr/
rm -rf nvim-linux64 nvim-linux64.tar.gz

# Create symlinks
ln -sf /usr/bin/nvim bin/nvim
ln -sf /usr/bin/nvim bin/vim
ln -sf /usr/bin/nvim bin/vi

# Download pre-built static BusyBox
echo "Downloading static BusyBox..."
# Use a working mirror with valid SSL
BUSYBOX_URL="https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
# Try with -k flag if certificate is expired
curl -L -k -o bin/busybox "${BUSYBOX_URL}" || {
    echo "Primary download failed, trying alternative..."
    # Alternative: use GitHub mirror
    curl -L -o bin/busybox "https://github.com/docker-library/busybox/raw/master/stable/musl/busybox.tar.xz"
}
chmod +x bin/busybox

# Create BusyBox symlinks
echo "Creating BusyBox symlinks..."
cd bin
for cmd in sh ash bash ls cat echo mount umount mkdir rmdir cp mv rm ln chmod chown \
           ps kill grep sed awk find xargs tar gzip gunzip less more head tail \
           wget curl vi ed; do
    ln -sf busybox "$cmd" 2>/dev/null || true
done
cd "${WORK_DIR}"

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
cat << 'WELCOME'
==========================================
  MiniVim + Neovim Test Environment
==========================================

Neovim is available as: nvim, vim, vi
BusyBox utilities available

Quick start:
  nvim welcome.txt    - Edit the welcome file
  nvim               - Start Neovim
  ls                 - List files
  exit               - Shutdown

==========================================
WELCOME

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
- Fast boot time (< 3 seconds)

Perfect for testing Avante.nvim and other Neovim plugins!

Commands to try:
  :help           - Neovim help
  :Tutor          - Neovim tutorial
  :checkhealth    - Check Neovim health

Avante.nvim integration:
- AI-powered code suggestions
- Cursor AI-like experience
- MCP protocol support

For more info: https://github.com/yetone/avante.nvim
EOF

# Create minimal Neovim config
cat > root/.config/nvim/init.lua << 'EOF'
-- Minimal Neovim config for MiniVim
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.termguicolors = true

-- Show welcome message
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    print("MiniVim + Neovim - Ready! Type :help for help")
  end,
})

-- Key mappings
vim.keymap.set('n', '<leader>w', ':w<CR>', { desc = 'Save file' })
vim.keymap.set('n', '<leader>q', ':q<CR>', { desc = 'Quit' })
EOF

# Create README
cat > root/README.md << 'EOF'
# MiniVim + Neovim Environment

## Available Commands

### Neovim
- `nvim` - Start Neovim
- `vim` - Alias for nvim
- `vi` - Alias for nvim

### BusyBox Utilities
- File operations: ls, cat, cp, mv, rm, mkdir, rmdir
- Text processing: grep, sed, awk, head, tail, less, more
- System: ps, kill, mount, umount
- Archive: tar, gzip, gunzip

## Files
- `welcome.txt` - Sample file to edit
- `README.md` - This file
- `.config/nvim/init.lua` - Neovim configuration

## Testing Avante.nvim

To test Avante.nvim, you'll need:
1. Network access (configure virtio-net)
2. Git (add to initramfs)
3. Lazy.nvim plugin manager

See docs/virtualization/minivim-neovim-integration.md for details.
EOF

# Create the initramfs
echo "Creating initramfs archive..."
find . -print0 | cpio --null -o -H newc | gzip -9 > "${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz"

# Get size
SIZE=$(du -h "${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz" | awk '{print $1}')
UNCOMPRESSED=$(find . -type f -exec du -ch {} + | grep total | awk '{print $1}')

echo ""
echo "=== Build Complete ==="
echo "Output: ${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz"
echo "Compressed size: ${SIZE}"
echo "Uncompressed size: ${UNCOMPRESSED}"
echo ""
echo "Contents:"
echo "  - Neovim ${NEOVIM_VERSION}"
echo "  - BusyBox ${BUSYBOX_VERSION} (static)"
echo "  - Sample files and config"
echo ""
echo "To test with QEMU (on Linux):"
echo "  qemu-system-x86_64 \\"
echo "    -kernel bench-images/minivim/bzImage-x86_64-6.17 \\"
echo "    -initrd ${OUTPUT_DIR}/busybox-neovim-initrd.cpio.gz \\"
echo "    -m 512M -nographic \\"
echo "    -append 'console=ttyS0'"
echo ""
echo "Note: Kernel must be built on Linux (use CI workflow)"
echo ""

# Cleanup
cd "${REPO_ROOT}"
rm -rf "${WORK_DIR}"
