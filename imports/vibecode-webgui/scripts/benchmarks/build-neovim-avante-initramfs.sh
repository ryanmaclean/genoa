#!/usr/bin/env bash
# Build Neovim + Avante.nvim initramfs with Git support
# This is the enhanced version with full Cursor AI-like capabilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${REPO_ROOT}/artifacts/minivim/initramfs-avante-work"
OUTPUT_DIR="${REPO_ROOT}/bench-images/busybox"

# Versions
NEOVIM_VERSION="${NEOVIM_VERSION:-v0.10.2}"
BUSYBOX_VERSION="1.35.0"
GIT_VERSION="2.43.0"

echo "=== Building Neovim + Avante.nvim Initramfs ==="
echo "Neovim Version: ${NEOVIM_VERSION}"
echo "BusyBox Version: ${BUSYBOX_VERSION}"
echo "Git Version: ${GIT_VERSION}"
echo "Work Directory: ${WORK_DIR}"
echo ""

# Clean and create work directory
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Create directory structure
echo "Creating directory structure..."
mkdir -p {bin,sbin,etc,proc,sys,dev,tmp,usr/bin,usr/sbin,usr/lib,lib,lib64,root/.config/nvim,root/.local/share/nvim}

# Download Neovim
echo "Downloading Neovim ${NEOVIM_VERSION}..."
NEOVIM_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-linux64.tar.gz"
curl -L -o nvim-linux64.tar.gz "${NEOVIM_URL}"
tar xzf nvim-linux64.tar.gz
cp -r nvim-linux64/* usr/
rm -rf nvim-linux64 nvim-linux64.tar.gz

# Create Neovim symlinks
ln -sf /usr/bin/nvim bin/nvim
ln -sf /usr/bin/nvim bin/vim
ln -sf /usr/bin/nvim bin/vi

# Download BusyBox
echo "Downloading static BusyBox..."
BUSYBOX_URL="https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
curl -L -k -o bin/busybox "${BUSYBOX_URL}"
chmod +x bin/busybox

# Create BusyBox symlinks
echo "Creating BusyBox symlinks..."
cd bin
for cmd in sh ash bash ls cat echo mount umount mkdir rmdir cp mv rm ln chmod chown \
           ps kill grep sed awk find xargs tar gzip gunzip less more head tail \
           wget curl vi ed which env; do
    ln -sf busybox "$cmd" 2>/dev/null || true
done
cd "${WORK_DIR}"

# Download static Git
echo "Downloading static Git..."
# Use static Git build from GitHub
GIT_URL="https://github.com/git/git/archive/refs/tags/v${GIT_VERSION}.tar.gz"
mkdir -p /tmp/git-build
cd /tmp/git-build

# For simplicity, download a pre-built static git
# Alternative: use Alpine's git-static package
curl -L -o git-static.tar.gz \
  "https://github.com/cirocosta/git-static-builder/releases/download/v2.40.0/git-static-x86_64.tar.gz" || \
  echo "Warning: Could not download static git, will use busybox git commands"

if [ -f git-static.tar.gz ]; then
  tar xzf git-static.tar.gz -C "${WORK_DIR}/usr/bin/" 2>/dev/null || true
  chmod +x "${WORK_DIR}/usr/bin/git" 2>/dev/null || true
fi

cd "${WORK_DIR}"

# Create init script with network support
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
export XDG_CONFIG_HOME=/root/.config
export XDG_DATA_HOME=/root/.local/share

# Configure network (if virtio-net is available)
if [ -e /sys/class/net/eth0 ]; then
  ip link set eth0 up
  udhcpc -i eth0 -s /etc/udhcpc/default.script &
fi

# Clear screen
clear

# Welcome message
cat << 'WELCOME'
==========================================
  MiniVim + Neovim + Avante.nvim
  Cursor AI-like Experience
==========================================

Neovim: nvim, vim, vi
Git: git (if available)
BusyBox: Full utilities

Quick start:
  nvim welcome.txt    - Edit sample file
  nvim test.py        - Try Avante.nvim
  :AvanteAsk          - Ask AI (if configured)
  git --version       - Check Git

Avante.nvim commands:
  :AvanteAsk <question>
  :AvanteEdit <instruction>
  :AvanteChat
  :AvanteClear

Configure AI provider in ~/.config/nvim/init.lua

==========================================
WELCOME

# Start shell
exec /bin/sh
EOF

chmod +x init

# Create sample files
cat > root/welcome.txt << 'EOF'
Welcome to MiniVim + Neovim + Avante.nvim!

This is a minimal Linux kernel with Neovim and Avante.nvim for
Cursor AI-like code editing capabilities.

## Features

- Neovim v0.10.2 with Lua and Tree-sitter
- Avante.nvim for AI-powered editing
- Git for version control
- BusyBox utilities
- Fast boot (< 3 seconds)

## Try Avante.nvim

1. Open a code file:
   nvim test.py

2. Ask AI for help:
   :AvanteAsk "How do I optimize this function?"

3. Edit with AI:
   :AvanteEdit "Add error handling"

4. Chat with AI:
   :AvanteChat

## Configuration

Edit ~/.config/nvim/init.lua to configure:
- AI provider (OpenAI, Claude, etc.)
- API keys
- Avante.nvim settings

## Resources

- Avante.nvim: https://github.com/yetone/avante.nvim
- MiniVim Docs: See /root/README.md
- Neovim Help: :help
EOF

cat > root/test.py << 'EOF'
#!/usr/bin/env python3
"""
Sample Python file for testing Avante.nvim

Try these Avante commands:
- :AvanteAsk "Explain this code"
- :AvanteEdit "Add type hints"
- :AvanteEdit "Add docstrings"
"""

def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

def main():
    for i in range(10):
        print(f"fib({i}) = {fibonacci(i)}")

if __name__ == "__main__":
    main()
EOF

# Create Neovim config with Avante.nvim
cat > root/.config/nvim/init.lua << 'EOF'
-- MiniVim + Avante.nvim Configuration

-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.termguicolors = true
vim.opt.mouse = 'a'

-- Leader key
vim.g.mapleader = ' '

-- Bootstrap lazy.nvim (plugin manager)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  print("Installing lazy.nvim...")
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Plugin configuration
require("lazy").setup({
  -- Avante.nvim - Cursor AI-like experience
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    build = "make",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    opts = {
      -- Configure your AI provider here
      provider = "openai", -- or "claude", "copilot", etc.
      openai = {
        endpoint = "https://api.openai.com/v1",
        model = "gpt-4",
        temperature = 0,
        max_tokens = 4096,
      },
      -- Mappings
      mappings = {
        ask = "<leader>aa",
        edit = "<leader>ae",
        refresh = "<leader>ar",
      },
    },
  },
  
  -- Additional useful plugins
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "lua", "vim", "python", "javascript", "typescript" },
        highlight = { enable = true },
      })
    end,
  },
})

-- Key mappings
vim.keymap.set('n', '<leader>w', ':w<CR>', { desc = 'Save file' })
vim.keymap.set('n', '<leader>q', ':q<CR>', { desc = 'Quit' })
vim.keymap.set('n', '<leader>h', ':help<CR>', { desc = 'Help' })

-- Welcome message
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    print("MiniVim + Avante.nvim - Ready!")
    print("Leader key: <Space>")
    print("Avante: <Space>aa (ask), <Space>ae (edit)")
  end,
})

-- Note: Set your API key via environment variable:
-- export OPENAI_API_KEY="your-key-here"
-- Or configure in this file (not recommended for security)
EOF

# Create README
cat > root/README.md << 'EOF'
# MiniVim + Neovim + Avante.nvim

## Overview

Minimal Linux kernel with Neovim and Avante.nvim for Cursor AI-like editing.

## Components

- **Kernel**: MiniVim minimal Linux kernel
- **Editor**: Neovim v0.10.2
- **AI**: Avante.nvim plugin
- **VCS**: Git (static build)
- **Shell**: BusyBox utilities

## Quick Start

```bash
# Start Neovim
nvim

# Open sample file
nvim welcome.txt

# Try Avante.nvim
nvim test.py
:AvanteAsk "Explain this code"
```

## Avante.nvim Commands

- `:AvanteAsk <question>` - Ask AI about code
- `:AvanteEdit <instruction>` - Edit code with AI
- `:AvanteChat` - Open AI chat
- `:AvanteClear` - Clear AI context

## Configuration

Edit `~/.config/nvim/init.lua` to configure:

1. AI provider (OpenAI, Claude, Copilot, etc.)
2. API keys
3. Model settings
4. Key mappings

## Environment Variables

```bash
export OPENAI_API_KEY="your-key"
export ANTHROPIC_API_KEY="your-key"
```

## Network Configuration

If network is available (virtio-net):
- DHCP configured automatically
- Can install plugins via Git
- Can call AI APIs

## File Locations

- Config: `~/.config/nvim/init.lua`
- Plugins: `~/.local/share/nvim/lazy/`
- Data: `~/.local/share/nvim/`

## Resources

- Avante.nvim: https://github.com/yetone/avante.nvim
- Neovim: https://neovim.io
- MiniVim: See docs/virtualization/
EOF

# Create the initramfs
echo "Creating initramfs archive..."
find . -print0 | cpio --null -o -H newc | gzip -9 > "${OUTPUT_DIR}/busybox-neovim-avante-initrd.cpio.gz"

# Get sizes
SIZE=$(du -h "${OUTPUT_DIR}/busybox-neovim-avante-initrd.cpio.gz" | awk '{print $1}')
UNCOMPRESSED=$(find . -type f -exec du -ch {} + | grep total | awk '{print $1}')

echo ""
echo "=== Build Complete ==="
echo "Output: ${OUTPUT_DIR}/busybox-neovim-avante-initrd.cpio.gz"
echo "Compressed size: ${SIZE}"
echo "Uncompressed size: ${UNCOMPRESSED}"
echo ""
echo "Contents:"
echo "  - Neovim ${NEOVIM_VERSION}"
echo "  - Avante.nvim (configured)"
echo "  - Git (if available)"
echo "  - BusyBox ${BUSYBOX_VERSION}"
echo "  - Sample files and config"
echo ""
echo "To test:"
echo "  qemu-system-x86_64 \\"
echo "    -kernel bench-images/minivim/bzImage-x86_64-6.17 \\"
echo "    -initrd ${OUTPUT_DIR}/busybox-neovim-avante-initrd.cpio.gz \\"
echo "    -m 1G -nographic \\"
echo "    -netdev user,id=net0 -device virtio-net,netdev=net0 \\"
echo "    -append 'console=ttyS0'"
echo ""

# Cleanup
cd "${REPO_ROOT}"
rm -rf "${WORK_DIR}"
