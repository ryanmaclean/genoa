#!/usr/bin/env python3
from __future__ import annotations

# Datadog Unified Service Tagging
_dd_service = "bench-build-neovim-initramfs-macos"
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

"""Build Neovim initramfs on macOS (cross-platform compatible).

This version downloads pre-built binaries instead of building from source,
making it suitable for use on macOS for building Linux initramfs images.
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
        error as log_error,
    )


DEFAULT_NEOVIM_VERSION = "v0.10.2"
DEFAULT_BUSYBOX_VERSION = "1.36.1"


INIT_SCRIPT = '''#!/bin/sh

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
'''


WELCOME_TEXT = '''Welcome to MiniVim + Neovim!

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
'''


NEOVIM_CONFIG = '''-- Minimal Neovim config for MiniVim
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
'''


README_MD = '''# MiniVim + Neovim Environment

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
'''


def download_neovim(work_dir: Path, version: str) -> None:
    """Download and extract Neovim for Linux."""
    log(f"Downloading Neovim {version} for Linux...")

    url = f"https://github.com/neovim/neovim/releases/download/{version}/nvim-linux64.tar.gz"
    archive = work_dir / "nvim-linux64.tar.gz"

    run_cmd(["curl", "-L", "-o", str(archive), url])

    log("Extracting Neovim...")
    run_cmd(["tar", "xzf", str(archive)], cwd=work_dir)

    # Copy to usr directory
    nvim_dir = work_dir / "nvim-linux64"
    usr_dir = work_dir / "usr"
    shutil.copytree(nvim_dir, usr_dir, dirs_exist_ok=True)

    # Cleanup
    shutil.rmtree(nvim_dir)
    archive.unlink()


def download_busybox(work_dir: Path) -> None:
    """Download pre-built static BusyBox."""
    log("Downloading static BusyBox...")

    url = "https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
    busybox_path = work_dir / "bin" / "busybox"

    try:
        run_cmd(["curl", "-L", "-k", "-o", str(busybox_path), url])
    except BenchmarkError:
        log("Primary download failed, trying alternative...")
        # Alternative: use GitHub mirror
        alt_url = "https://github.com/docker-library/busybox/raw/master/stable/musl/busybox.tar.xz"
        run_cmd(["curl", "-L", "-o", str(busybox_path), alt_url])

    busybox_path.chmod(0o755)


def create_busybox_symlinks(work_dir: Path) -> None:
    """Create BusyBox symlinks."""
    log("Creating BusyBox symlinks...")

    commands = [
        "sh", "ash", "bash", "ls", "cat", "echo", "mount", "umount",
        "mkdir", "rmdir", "cp", "mv", "rm", "ln", "chmod", "chown",
        "ps", "kill", "grep", "sed", "awk", "find", "xargs",
        "tar", "gzip", "gunzip", "less", "more", "head", "tail",
        "wget", "curl", "vi", "ed",
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
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "bench-images" / "busybox",
        help="Output directory",
    )

    args = parser.parse_args(argv)

    work_dir = REPO_ROOT / "artifacts" / "minivim" / "initramfs-work"
    output_path = args.output_dir / "busybox-neovim-initrd.cpio.gz"

    print("=== Building Neovim Initramfs (macOS Compatible) ===")
    print(f"Neovim Version: {args.neovim_version}")
    print(f"BusyBox Version: {args.busybox_version}")
    print(f"Work Directory: {work_dir}")
    print()

    try:
        # Clean and create work directory
        if work_dir.exists():
            shutil.rmtree(work_dir)
        work_dir.mkdir(parents=True)

        # Create directory structure
        log("Creating directory structure...")
        dirs = [
            "bin", "sbin", "etc", "proc", "sys", "dev", "tmp",
            "usr/bin", "usr/sbin", "usr/lib", "lib", "lib64",
            "root/.config/nvim",
        ]
        for d in dirs:
            (work_dir / d).mkdir(parents=True, exist_ok=True)

        # Download components
        download_neovim(work_dir, args.neovim_version)
        download_busybox(work_dir)

        # Create symlinks
        create_neovim_symlinks(work_dir)
        create_busybox_symlinks(work_dir)

        # Create init script
        log("Creating init script...")
        init_path = work_dir / "init"
        init_path.write_text(INIT_SCRIPT)
        init_path.chmod(0o755)

        # Create sample files
        (work_dir / "root" / "welcome.txt").write_text(WELCOME_TEXT)
        (work_dir / "root" / ".config" / "nvim" / "init.lua").write_text(NEOVIM_CONFIG)
        (work_dir / "root" / "README.md").write_text(README_MD)

        # Create initramfs
        create_initramfs(work_dir, output_path)

        # Get sizes
        size = output_path.stat().st_size

        # Calculate uncompressed size
        uncompressed = sum(
            f.stat().st_size for f in work_dir.rglob("*") if f.is_file()
        )

        print()
        print("=== Build Complete ===")
        print(f"Output: {output_path}")
        print(f"Compressed size: {file_size_human(size)}")
        print(f"Uncompressed size: {file_size_human(uncompressed)}")
        print()
        print("Contents:")
        print(f"  - Neovim {args.neovim_version}")
        print(f"  - BusyBox {args.busybox_version} (static)")
        print("  - Sample files and config")
        print()
        print("To test with QEMU (on Linux):")
        print("  qemu-system-x86_64 \\")
        print("    -kernel bench-images/minivim/bzImage-x86_64-6.17 \\")
        print(f"    -initrd {output_path} \\")
        print("    -m 512M -nographic \\")
        print("    -append 'console=ttyS0'")
        print()
        print("Note: Kernel must be built on Linux (use CI workflow)")
        print()

        # Cleanup
        shutil.rmtree(work_dir, ignore_errors=True)

        return 0

    except BenchmarkError as err:
        log_error(str(err))
        return 1


if __name__ == "__main__":
    sys.exit(main())