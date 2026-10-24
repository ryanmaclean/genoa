#!/usr/bin/env python3
"""Build a BusyBox + Neovim initramfs for MiniVim benchmarks.

Usage: ./build_neovim_initramfs.py
"""

import argparse
import gzip
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional


# Neovim version to download
DEFAULT_NEOVIM_VERSION = "v0.10.2"


def log(msg: str) -> None:
    """Print log message."""
    print(f"[INFO] {msg}")


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    capture: bool = True,
    timeout: int = 300
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"
    except FileNotFoundError:
        return -1, "", "command not found"


def download_neovim(work_dir: Path, version: str) -> bool:
    """Download and extract Neovim."""
    log("Downloading Neovim AppImage...")

    appimage_url = f"https://github.com/neovim/neovim/releases/download/{version}/nvim.appimage"
    appimage_path = work_dir / "nvim.appimage"

    rc, _, stderr = run_command([
        "curl", "-L", "-o", str(appimage_path), appimage_url
    ])

    if rc != 0:
        print(f"Failed to download AppImage: {stderr}")
        return False

    appimage_path.chmod(0o755)

    # Try to extract AppImage
    log("Extracting Neovim...")
    rc, _, _ = run_command(
        [str(appimage_path), "--appimage-extract"],
        cwd=work_dir
    )

    squashfs_root = work_dir / "squashfs-root"
    if squashfs_root.exists():
        log("Copying Neovim files...")
        usr_dir = work_dir / "usr"
        usr_dir.mkdir(exist_ok=True)
        shutil.copytree(squashfs_root / "usr", usr_dir, dirs_exist_ok=True)

        # Create symlinks
        bin_dir = work_dir / "bin"
        for name in ["nvim", "vim", "vi"]:
            link = bin_dir / name
            if not link.exists():
                link.symlink_to("/usr/bin/nvim")

        # Cleanup
        shutil.rmtree(squashfs_root)
        appimage_path.unlink()
        return True

    # Fallback to static build
    log("WARNING: Could not extract AppImage. Falling back to static build...")
    static_url = f"https://github.com/neovim/neovim/releases/download/{version}/nvim-linux64.tar.gz"

    rc, _, _ = run_command([
        "curl", "-L", "-o", str(work_dir / "nvim-static.tar.gz"), static_url
    ])

    if rc == 0:
        run_command(["tar", "xzf", "nvim-static.tar.gz"], cwd=work_dir)

        nvim_dir = work_dir / "nvim-linux64"
        if nvim_dir.exists():
            usr_dir = work_dir / "usr"
            shutil.copytree(nvim_dir, usr_dir, dirs_exist_ok=True)

            bin_dir = work_dir / "bin"
            for name in ["nvim", "vim", "vi"]:
                link = bin_dir / name
                if not link.exists():
                    link.symlink_to("/usr/bin/nvim")

            shutil.rmtree(nvim_dir)
            (work_dir / "nvim-static.tar.gz").unlink()
            return True

    print("ERROR: Could not download Neovim")
    return False


def setup_busybox(work_dir: Path, busybox_version: str) -> bool:
    """Set up BusyBox."""
    log("Setting up BusyBox...")

    bin_dir = work_dir / "bin"

    # Check for existing busybox
    if shutil.which("busybox"):
        shutil.copy(shutil.which("busybox"), bin_dir / "busybox")
    else:
        # Download and build BusyBox
        log(f"Downloading BusyBox {busybox_version}...")
        url = f"https://busybox.net/downloads/busybox-{busybox_version}.tar.bz2"

        rc, _, _ = run_command([
            "curl", "-L", "-o", str(work_dir / "busybox.tar.bz2"), url
        ])

        if rc != 0:
            return False

        run_command(["tar", "xjf", "busybox.tar.bz2"], cwd=work_dir)

        busybox_src = work_dir / f"busybox-{busybox_version}"

        # Configure
        run_command(["make", "defconfig"], cwd=busybox_src)

        # Enable static
        config_path = busybox_src / ".config"
        content = config_path.read_text()
        content = content.replace(
            "# CONFIG_STATIC is not set",
            "CONFIG_STATIC=y"
        )
        config_path.write_text(content)

        # Build
        log("Building BusyBox (this may take a few minutes)...")
        nproc = os.cpu_count() or 4
        run_command(
            ["make", f"-j{nproc}"],
            cwd=busybox_src,
            timeout=600
        )

        # Copy binary
        shutil.copy(busybox_src / "busybox", bin_dir / "busybox")

        # Cleanup
        shutil.rmtree(busybox_src)
        (work_dir / "busybox.tar.bz2").unlink()

    # Create symlinks
    log("Creating BusyBox symlinks...")
    busybox = bin_dir / "busybox"
    cmds = ["sh", "ash", "bash", "ls", "cat", "echo", "mount", "umount",
            "mkdir", "rmdir", "cp", "mv", "rm", "ln", "chmod", "chown",
            "ps", "kill", "grep", "sed", "awk", "find", "xargs", "tar",
            "gzip", "gunzip", "less", "more", "head", "tail"]

    for cmd in cmds:
        link = bin_dir / cmd
        if not link.exists():
            link.symlink_to("busybox")

    return True


def create_init_script(work_dir: Path) -> None:
    """Create init script."""
    log("Creating init script...")

    init_script = '''#!/bin/sh

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
'''

    init_path = work_dir / "init"
    init_path.write_text(init_script)
    init_path.chmod(0o755)


def create_sample_files(work_dir: Path) -> None:
    """Create sample files."""
    root_dir = work_dir / "root"
    root_dir.mkdir(exist_ok=True)

    welcome = '''Welcome to MiniVim + Neovim!

This is a minimal Linux kernel with Neovim running in an initramfs.

Try editing this file with:
  nvim welcome.txt

Key features:
- Minimal kernel (< 10MB)
- Neovim for editing
- BusyBox utilities
- Fast boot time

Perfect for testing Avante.nvim and other Neovim plugins!
'''
    (root_dir / "welcome.txt").write_text(welcome)

    # Neovim config
    config_dir = root_dir / ".config" / "nvim"
    config_dir.mkdir(parents=True, exist_ok=True)

    init_lua = '''-- Minimal Neovim config for MiniVim
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
'''
    (config_dir / "init.lua").write_text(init_lua)


def create_initramfs(work_dir: Path, output_file: Path) -> None:
    """Create the initramfs archive."""
    log("Creating initramfs archive...")

    # Create cpio archive
    result = subprocess.run(
        ["find", "."],
        cwd=work_dir,
        capture_output=True
    )

    cpio_result = subprocess.run(
        ["cpio", "-o", "-H", "newc"],
        input=result.stdout,
        cwd=work_dir,
        capture_output=True
    )

    # Compress with gzip
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(output_file, "wb") as f:
        f.write(cpio_result.stdout)


def get_size_human(path: Path) -> str:
    """Get human-readable file size."""
    size = path.stat().st_size
    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024:
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}TB"


def build_initramfs(
    neovim_version: str = DEFAULT_NEOVIM_VERSION,
    busybox_version: str = "1.36.1"
) -> int:
    """Build the Neovim initramfs."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    work_dir = repo_root / "artifacts" / "minivim" / "initramfs-work"
    output_dir = repo_root / "bench-images" / "busybox"
    output_file = output_dir / "busybox-neovim-initrd.cpio.gz"

    print("=== Building Neovim Initramfs ===")
    print(f"Neovim Version: {neovim_version}")
    print(f"Work Directory: {work_dir}")
    print()

    # Clean and create work directory
    if work_dir.exists():
        shutil.rmtree(work_dir)

    # Create directory structure
    log("Creating directory structure...")
    for d in ["bin", "sbin", "etc", "proc", "sys", "dev", "tmp",
              "usr/bin", "usr/sbin", "lib", "lib64", "root"]:
        (work_dir / d).mkdir(parents=True, exist_ok=True)

    # Download Neovim
    if not download_neovim(work_dir, neovim_version):
        return 1

    # Set up BusyBox
    if not setup_busybox(work_dir, busybox_version):
        return 1

    # Create init script
    create_init_script(work_dir)

    # Create sample files
    create_sample_files(work_dir)

    # Create initramfs
    create_initramfs(work_dir, output_file)

    # Report
    size = get_size_human(output_file)
    print()
    print("=== Build Complete ===")
    print(f"Output: {output_file}")
    print(f"Size: {size}")
    print()
    print("To test with QEMU:")
    print(f"  qemu-system-x86_64 -kernel bzImage -initrd {output_file} -m 512M -nographic -append 'console=ttyS0'")
    print()

    # Cleanup
    shutil.rmtree(work_dir)

    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build a BusyBox + Neovim initramfs for MiniVim benchmarks"
    )
    parser.add_argument(
        "--neovim-version",
        default=os.environ.get("NEOVIM_VERSION", DEFAULT_NEOVIM_VERSION),
        help="Neovim version"
    )
    parser.add_argument(
        "--busybox-version",
        default="1.36.1",
        help="BusyBox version"
    )

    args = parser.parse_args()
    return build_initramfs(args.neovim_version, args.busybox_version)


if __name__ == "__main__":
    sys.exit(main())
