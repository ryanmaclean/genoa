#!/usr/bin/env python3
from __future__ import annotations

# Datadog Unified Service Tagging
_dd_service = "bench-build-neovim-avante-initramfs"
_dd_env = __import__("os").environ.get("DD_ENV", "development")
_dd_version = __import__("os").environ.get("DD_VERSION", "0.1.0")
try:
    from ddtrace import config as _dd_config, patch_all as _dd_patch, tracer as _dd_tracer
    _dd_config.service = _dd_service
    _dd_config.env = _dd_env
    _dd_config.version = _dd_version
    _dd_tracer.set_tags({"team": "platform", "component": "benchmarks"})
    _dd_patch()
except ImportError:
    pass


# Datadog Log Aggregation
from scripts.lib.log_aggregation import get_log_aggregation


# Initialize log aggregation
log_agg = get_log_aggregation()

"""Build Neovim + Avante.nvim initramfs with Git support.

This is the enhanced version with full Cursor AI-like capabilities.
"""


# -- VibeCode Telemetry --
import sys
import os
try:
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../')))
    from vibecode.telemetry import init_telemetry
    tracer = init_telemetry(os.path.basename(__file__))
except ImportError:
    pass
# ------------------------


# Datadog APM tracing
try:
    from ddtrace import patch_all
    patch_all()
except ImportError:
    pass  # ddtrace not installed


import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from .benchmark_utils import (
        REPO_ROOT,
        BenchmarkError,
        file_size_human,
        log,
        run_cmd,
        success,
        warn,
        error as log_error,
    )
except ImportError:
    sys.path.insert(0, str(Path(__file__).parent))
    from benchmark_utils import (
        REPO_ROOT,
        BenchmarkError,
        file_size_human,
        log,
        run_cmd,
        success,
        warn,
        error as log_error,
    )


DEFAULT_NEOVIM_VERSION = "v0.10.2"
DEFAULT_BUSYBOX_VERSION = "1.35.0"
DEFAULT_GIT_VERSION = "2.43.0"


INIT_SCRIPT = '''#!/bin/sh

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
'''


WELCOME_TEXT = '''Welcome to MiniVim + Neovim + Avante.nvim!

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
'''


TEST_PYTHON = '''#!/usr/bin/env python3
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
'''


NEOVIM_CONFIG = '''-- MiniVim + Avante.nvim Configuration

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
'''


README_MD = '''# MiniVim + Neovim + Avante.nvim

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
'''


def download_neovim(work_dir: Path, version: str) -> None:
    """Download and extract Neovim."""
    log(f"Downloading Neovim {version}...")

    url = f"https://github.com/neovim/neovim/releases/download/{version}/nvim-linux64.tar.gz"
    archive = work_dir / "nvim-linux64.tar.gz"

    run_cmd(["curl", "-L", "-o", str(archive), url])
    run_cmd(["tar", "xzf", str(archive)], cwd=work_dir)

    # Copy to usr directory
    nvim_dir = work_dir / "nvim-linux64"
    usr_dir = work_dir / "usr"
    shutil.copytree(nvim_dir, usr_dir, dirs_exist_ok=True)

    # Cleanup
    shutil.rmtree(nvim_dir)
    archive.unlink()


def download_busybox(work_dir: Path) -> None:
    """Download static BusyBox."""
    log("Downloading static BusyBox...")

    url = "https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
    busybox_path = work_dir / "bin" / "busybox"

    run_cmd(["curl", "-L", "-k", "-o", str(busybox_path), url])
    busybox_path.chmod(0o755)


def download_git(work_dir: Path) -> None:
    """Download static Git."""
    log("Downloading static Git...")

    url = "https://github.com/cirocosta/git-static-builder/releases/download/v2.40.0/git-static-x86_64.tar.gz"
    git_tar = work_dir / "git-static.tar.gz"

    try:
        run_cmd(["curl", "-L", "-o", str(git_tar), url])
        run_cmd(["tar", "xzf", str(git_tar), "-C", str(work_dir / "usr" / "bin")])
        (work_dir / "usr" / "bin" / "git").chmod(0o755)
        git_tar.unlink()
        success("Git downloaded successfully")
    except BenchmarkError:
        warn("Could not download static git, will use busybox git commands")


def create_busybox_symlinks(work_dir: Path) -> None:
    """Create BusyBox symlinks."""
    log("Creating BusyBox symlinks...")

    commands = [
        "sh", "ash", "bash", "ls", "cat", "echo", "mount", "umount",
        "mkdir", "rmdir", "cp", "mv", "rm", "ln", "chmod", "chown",
        "ps", "kill", "grep", "sed", "awk", "find", "xargs",
        "tar", "gzip", "gunzip", "less", "more", "head", "tail",
        "wget", "curl", "vi", "ed", "which", "env",
    ]

    bin_dir = work_dir / "bin"
    for cmd in commands:
        link = bin_dir / cmd
        if not link.exists():
            try:
                link.symlink_to("busybox")
            except Exception:
                pass


def create_neovim_symlinks(work_dir: Path) -> None:
    """Create Neovim symlinks."""
    bin_dir = work_dir / "bin"

    nvim_link = bin_dir / "nvim"
    if not nvim_link.exists():
        nvim_link.symlink_to("/usr/bin/nvim")

    for name in ["vim", "vi"]:
        link = bin_dir / name
        if not link.exists():
            link.symlink_to("/usr/bin/nvim")


def create_initramfs(work_dir: Path, output_path: Path) -> None:
    """Create the initramfs archive."""
    log("Creating directory structure...")

    # Create directories
    dirs = [
        "bin", "sbin", "etc", "proc", "sys", "dev", "tmp",
        "usr/bin", "usr/sbin", "usr/lib", "lib", "lib64",
        "root/.config/nvim", "root/.local/share/nvim",
    ]
    for d in dirs:
        (work_dir / d).mkdir(parents=True, exist_ok=True)

    # Create init script
    log("Creating init script...")
    init_path = work_dir / "init"
    init_path.write_text(INIT_SCRIPT)
    init_path.chmod(0o755)

    # Create sample files
    log("Creating sample files...")
    (work_dir / "root" / "welcome.txt").write_text(WELCOME_TEXT)
    (work_dir / "root" / "test.py").write_text(TEST_PYTHON)
    (work_dir / "root" / ".config" / "nvim" / "init.lua").write_text(NEOVIM_CONFIG)
    (work_dir / "root" / "README.md").write_text(README_MD)

    # Create initramfs archive
    log("Creating initramfs archive...")
    find_proc = subprocess.Popen(
        ["find", ".", "-print0"],
        cwd=work_dir,
        stdout=subprocess.PIPE,
    )
    cpio_proc = subprocess.Popen(
        ["cpio", "--null", "-o", "-H", "newc"],
        cwd=work_dir,
        stdin=find_proc.stdout,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    gzip_proc = subprocess.Popen(
        ["gzip", "-9"],
        stdin=cpio_proc.stdout,
        stdout=subprocess.PIPE,
    )

    output, _ = gzip_proc.communicate()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(output)


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--neovim-version",
        default=os.environ.get("NEOVIM_VERSION", DEFAULT_NEOVIM_VERSION),
        help=f"Neovim version (default: {DEFAULT_NEOVIM_VERSION})",
    )
    parser.add_argument(
        "--busybox-version",
        default=DEFAULT_BUSYBOX_VERSION,
        help=f"BusyBox version (default: {DEFAULT_BUSYBOX_VERSION})",
    )
    parser.add_argument(
        "--git-version",
        default=DEFAULT_GIT_VERSION,
        help=f"Git version (default: {DEFAULT_GIT_VERSION})",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "bench-images" / "busybox",
        help="Output directory",
    )

    args = parser.parse_args(argv)

    work_dir = REPO_ROOT / "artifacts" / "minivim" / "initramfs-avante-work"
    output_path = args.output_dir / "busybox-neovim-avante-initrd.cpio.gz"

    print("=== Building Neovim + Avante.nvim Initramfs ===")
    print(f"Neovim Version: {args.neovim_version}")
    print(f"BusyBox Version: {args.busybox_version}")
    print(f"Git Version: {args.git_version}")
    print(f"Work Directory: {work_dir}")
    print()

    try:
        # Clean and create work directory
        if work_dir.exists():
            shutil.rmtree(work_dir)
        work_dir.mkdir(parents=True)

        # Create directory structure first
        for d in ["bin", "sbin", "usr/bin", "usr/lib"]:
            (work_dir / d).mkdir(parents=True, exist_ok=True)

        # Download components
        download_neovim(work_dir, args.neovim_version)
        download_busybox(work_dir)
        download_git(work_dir)

        # Create symlinks
        create_neovim_symlinks(work_dir)
        create_busybox_symlinks(work_dir)

        # Create initramfs
        create_initramfs(work_dir, output_path)

        # Report sizes
        size = output_path.stat().st_size

        print()
        print("=== Build Complete ===")
        print(f"Output: {output_path}")
        print(f"Compressed size: {file_size_human(size)}")
        print()
        print("Contents:")
        print(f"  - Neovim {args.neovim_version}")
        print("  - Avante.nvim (configured)")
        print("  - Git (if available)")
        print(f"  - BusyBox {args.busybox_version}")
        print("  - Sample files and config")
        print()
        print("To test:")
        print("  qemu-system-x86_64 \\")
        print("    -kernel bench-images/minivim/bzImage-x86_64-6.17 \\")
        print(f"    -initrd {output_path} \\")
        print("    -m 1G -nographic \\")
        print("    -netdev user,id=net0 -device virtio-net,netdev=net0 \\")
        print("    -append 'console=ttyS0'")
        print()

        # Cleanup
        shutil.rmtree(work_dir, ignore_errors=True)

        return 0

    except BenchmarkError as err:
        log_error(str(err))
        return 1


if __name__ == "__main__":
    sys.exit(main())