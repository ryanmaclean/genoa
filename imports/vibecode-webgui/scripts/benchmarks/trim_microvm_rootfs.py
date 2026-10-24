#!/usr/bin/env python3
"""Trim MicroVM Rootfs for Sub-10s Cold Boots.

Removes unnecessary files to optimize boot time.
"""

import argparse
import gzip
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


# Colors for output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
NC = '\033[0m'


@dataclass
class TrimConfig:
    """Trim configuration."""

    rootfs_dir: Path
    output_file: Path
    target_size_mb: int = 50


@dataclass
class TrimResults:
    """Trimming results."""

    original_size_mb: int = 0
    trimmed_size_mb: int = 0
    output_size_mb: int = 0
    savings_mb: int = 0
    savings_percent: int = 0


def log(msg: str) -> None:
    """Print log message."""
    print(msg)


def success(msg: str) -> None:
    """Print success message."""
    print(f"{GREEN}+{NC} {msg}")


def warning(msg: str) -> None:
    """Print warning message."""
    print(f"{YELLOW}!{NC} {msg}")


def error(msg: str) -> None:
    """Print error message."""
    print(f"{RED}x{NC} {msg}")


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    capture: bool = True
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture,
            text=True
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except FileNotFoundError:
        return -1, "", "command not found"


def get_dir_size_mb(path: Path) -> int:
    """Get directory size in MB."""
    total = 0
    for f in path.rglob("*"):
        if f.is_file():
            try:
                total += f.stat().st_size
            except (OSError, PermissionError):
                pass
    return total // (1024 * 1024)


def extract_rootfs(rootfs_path: Path, work_dir: Path) -> Path:
    """Extract rootfs if it's an image."""
    rootfs_work = work_dir / "rootfs"
    rootfs_work.mkdir(parents=True, exist_ok=True)

    rc, stdout, _ = run_command(["file", str(rootfs_path)])

    if "gzip" in stdout:
        log("Extracting gzipped rootfs...")
        # Decompress
        with gzip.open(rootfs_path, "rb") as f_in:
            cpio_path = work_dir / "rootfs.cpio"
            cpio_path.write_bytes(f_in.read())

        # Extract cpio
        with open(cpio_path, "rb") as f_in:
            subprocess.run(
                ["cpio", "-idm"],
                cwd=rootfs_work,
                stdin=f_in,
                capture_output=True
            )
    elif "cpio" in stdout:
        log("Extracting cpio rootfs...")
        with open(rootfs_path, "rb") as f_in:
            subprocess.run(
                ["cpio", "-idm"],
                cwd=rootfs_work,
                stdin=f_in,
                capture_output=True
            )
    else:
        error("Unknown rootfs format")
        return Path()

    return rootfs_work


def remove_directories(rootfs: Path, patterns: list[str]) -> None:
    """Remove directories matching patterns."""
    for pattern in patterns:
        for d in rootfs.rglob(pattern):
            if d.is_dir():
                try:
                    shutil.rmtree(d)
                    log(f"  Removed: {d}")
                except (OSError, PermissionError):
                    pass


def trim_locales(rootfs: Path) -> None:
    """Trim locales, keeping only en_US."""
    locale_dir = rootfs / "usr" / "share" / "locale"
    if locale_dir.is_dir():
        for d in locale_dir.iterdir():
            if d.is_dir() and d.name != "en_US":
                try:
                    shutil.rmtree(d)
                except (OSError, PermissionError):
                    pass
        log("  Trimmed locales (kept en_US only)")


def remove_by_extension(rootfs: Path, extensions: list[str]) -> None:
    """Remove files by extension."""
    for ext in extensions:
        for f in rootfs.rglob(f"*{ext}"):
            if f.is_file():
                try:
                    f.unlink()
                except (OSError, PermissionError):
                    pass


def clear_caches(rootfs: Path) -> None:
    """Clear package manager caches."""
    cache_dirs = [
        rootfs / "var" / "cache" / "apt",
        rootfs / "var" / "cache" / "yum",
        rootfs / "var" / "cache" / "apk"
    ]

    for cache_dir in cache_dirs:
        if cache_dir.is_dir():
            try:
                shutil.rmtree(cache_dir)
                cache_dir.mkdir(parents=True, exist_ok=True)
                log(f"  Cleared {cache_dir.name} cache")
            except (OSError, PermissionError):
                pass


def strip_binaries(rootfs: Path) -> None:
    """Strip executables."""
    log("Stripping binaries...")

    for f in rootfs.rglob("*"):
        if not f.is_file():
            continue

        rc, stdout, _ = run_command(["file", str(f)])
        if "ELF" in stdout:
            run_command(["strip", "--strip-unneeded", str(f)])

    log("  Stripped executables")


def trim_rootfs(rootfs: Path) -> None:
    """Apply all trimming operations."""
    log("Trimming unnecessary files...")

    # Remove documentation
    remove_directories(rootfs, ["doc", "man", "info"])

    # Trim locales
    trim_locales(rootfs)

    # Remove static libraries
    remove_by_extension(rootfs, [".a"])
    log("  Removed static libraries")

    # Clear caches
    clear_caches(rootfs)

    # Remove kernel sources
    src_dir = rootfs / "usr" / "src"
    if src_dir.is_dir():
        shutil.rmtree(src_dir, ignore_errors=True)
        log("  Removed kernel sources")

    # Remove development headers
    remove_by_extension(rootfs, [".h"])
    log("  Removed development headers")

    # Remove Python bytecode
    for pattern in ["*.pyc", "*.pyo", "__pycache__"]:
        for f in rootfs.rglob(pattern):
            try:
                if f.is_file():
                    f.unlink()
                elif f.is_dir():
                    shutil.rmtree(f)
            except (OSError, PermissionError):
                pass
    log("  Removed Python bytecode")

    # Clear logs
    log_dir = rootfs / "var" / "log"
    if log_dir.is_dir():
        for f in log_dir.rglob("*"):
            if f.is_file():
                try:
                    f.unlink()
                except (OSError, PermissionError):
                    pass
        log("  Cleared logs")

    # Strip binaries
    strip_binaries(rootfs)


def create_trimmed_image(rootfs: Path, output_file: Path) -> None:
    """Create trimmed rootfs image."""
    log("Creating trimmed rootfs image...")
    output_file.parent.mkdir(parents=True, exist_ok=True)

    # Create cpio archive
    result = subprocess.run(
        ["find", ".", "-print0"],
        cwd=rootfs,
        capture_output=True
    )

    cpio_result = subprocess.run(
        ["cpio", "--null", "-o", "-H", "newc"],
        input=result.stdout,
        cwd=rootfs,
        capture_output=True
    )

    # Compress with gzip
    with gzip.open(output_file, "wb", compresslevel=9) as f:
        f.write(cpio_result.stdout)


def trim(config: TrimConfig) -> TrimResults:
    """Run the full trimming process."""
    results = TrimResults()

    print("=== MicroVM Rootfs Trimming ===")
    print(f"Input: {config.rootfs_dir}")
    print(f"Output: {config.output_file}")
    print(f"Target size: {config.target_size_mb}MB")
    print()

    if not config.rootfs_dir.exists():
        error(f"Rootfs not found: {config.rootfs_dir}")
        return results

    # Determine working directory
    import tempfile
    work_dir = Path(tempfile.mkdtemp())

    try:
        # Extract if needed
        if config.rootfs_dir.is_file():
            rootfs_work = extract_rootfs(config.rootfs_dir, work_dir)
            if not rootfs_work:
                return results
        else:
            rootfs_work = config.rootfs_dir

        log("Analyzing rootfs...")
        results.original_size_mb = get_dir_size_mb(rootfs_work)
        log(f"Original size: {results.original_size_mb}MB")

        # Trim
        print()
        trim_rootfs(rootfs_work)

        # Calculate new size
        results.trimmed_size_mb = get_dir_size_mb(rootfs_work)
        results.savings_mb = results.original_size_mb - results.trimmed_size_mb
        if results.original_size_mb > 0:
            results.savings_percent = (results.savings_mb * 100) // results.original_size_mb

        print()
        print("=== Trimming Results ===")
        print(f"Original: {results.original_size_mb}MB")
        print(f"Trimmed: {results.trimmed_size_mb}MB")
        print(f"Savings: {results.savings_mb}MB ({results.savings_percent}%)")

        # Create new image
        print()
        create_trimmed_image(rootfs_work, config.output_file)

        results.output_size_mb = config.output_file.stat().st_size // (1024 * 1024)
        print(f"Output size: {results.output_size_mb}MB")

        if results.output_size_mb <= config.target_size_mb:
            success(f"Target size achieved (<={config.target_size_mb}MB)")
        else:
            warning(f"Target size not achieved (>{config.target_size_mb}MB)")
            print("Consider more aggressive trimming or using busybox-only rootfs")

        print()
        success(f"Trimmed rootfs saved to: {config.output_file}")
        print()
        print("Next steps:")
        print("1. Test boot time with trimmed rootfs")
        print("2. Verify essential services still work")
        print("3. Measure cold boot performance improvement")

    finally:
        # Cleanup
        shutil.rmtree(work_dir, ignore_errors=True)

    return results


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Trim MicroVM Rootfs for Sub-10s Cold Boots"
    )
    parser.add_argument(
        "rootfs_dir",
        nargs="?",
        default="artifacts/minivim/rootfs",
        help="Rootfs directory or image"
    )
    parser.add_argument(
        "output_file",
        nargs="?",
        default="artifacts/minivim/rootfs-trimmed.img",
        help="Output file"
    )
    parser.add_argument(
        "--target-size",
        type=int,
        default=int(os.environ.get("TARGET_SIZE_MB", "50")),
        help="Target size in MB"
    )

    args = parser.parse_args()

    config = TrimConfig(
        rootfs_dir=Path(args.rootfs_dir),
        output_file=Path(args.output_file),
        target_size_mb=args.target_size
    )

    trim(config)
    return 0


if __name__ == "__main__":
    sys.exit(main())
