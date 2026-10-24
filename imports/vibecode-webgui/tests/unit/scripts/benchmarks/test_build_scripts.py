
# -- VibeCode Telemetry --
import sys
import os
try:
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../')))
    from vibecode.telemetry import init_telemetry
    tracer = init_telemetry(os.path.basename(__file__))
except ImportError:
    pass
# ------------------------

"""Tests for build scripts (kernel, initramfs, busybox)."""

import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Add scripts/benchmarks to path for import
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent / "scripts" / "benchmarks"))


class TestBuildMinimalInitramfs:
    """Tests for build_minimal_initramfs.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_minimal_initramfs import (
            INIT_SCRIPT,
            create_init_script,
        )
        assert INIT_SCRIPT is not None
        assert callable(create_init_script)

    def test_create_init_script(self, tmp_path: Path) -> None:
        """Should create executable init script."""
        from build_minimal_initramfs import create_init_script

        create_init_script(tmp_path)

        init_path = tmp_path / "init"
        assert init_path.exists()
        assert init_path.stat().st_mode & 0o111  # Executable


class TestBuildBusyboxMusl:
    """Tests for build_busybox_musl.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_busybox_musl import (
            DEFAULT_BUSYBOX_VERSION,
            set_bool_config,
            disable_config,
        )
        assert DEFAULT_BUSYBOX_VERSION is not None

    def test_set_bool_config_true(self, tmp_path: Path) -> None:
        """Should set boolean config option to True."""
        from build_busybox_musl import set_bool_config

        config_file = tmp_path / ".config"
        config_file.write_text("# CONFIG_STATIC is not set\n")

        set_bool_config(config_file, "CONFIG_STATIC", True)

        content = config_file.read_text()
        # Should enable the config
        assert "# CONFIG_STATIC is not set" not in content

    def test_set_bool_config_false(self, tmp_path: Path) -> None:
        """Should set boolean config option to False."""
        from build_busybox_musl import set_bool_config

        config_file = tmp_path / ".config"
        config_file.write_text("CONFIG_STATIC=y\n")

        set_bool_config(config_file, "CONFIG_STATIC", False)

        content = config_file.read_text()
        assert "CONFIG_STATIC=y" not in content

    def test_disable_config(self, tmp_path: Path) -> None:
        """Should disable config option."""
        from build_busybox_musl import disable_config

        config_file = tmp_path / ".config"
        config_file.write_text("CONFIG_TEST=y\n")

        disable_config(config_file, "CONFIG_TEST")

        content = config_file.read_text()
        assert "# CONFIG_TEST is not set" in content
        assert "CONFIG_TEST=y" not in content


class TestBuildMinivimKernel:
    """Tests for build_minivim_kernel.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_minivim_kernel import (
            DEFAULT_KERNEL_VERSION,
            download_kernel,
        )
        assert DEFAULT_KERNEL_VERSION is not None
        assert callable(download_kernel)


class TestBuildNeovimInitramfs:
    """Tests for build_neovim_initramfs.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_neovim_initramfs import (
            DEFAULT_NEOVIM_VERSION,
            DEFAULT_BUSYBOX_VERSION,
            INIT_SCRIPT,
            WELCOME_TEXT,
            NEOVIM_CONFIG,
        )
        assert DEFAULT_NEOVIM_VERSION is not None
        assert "mount" in INIT_SCRIPT.lower()
        assert len(WELCOME_TEXT) > 0
        assert len(NEOVIM_CONFIG) > 0


class TestBuildNeovimAvanteInitramfs:
    """Tests for build_neovim_avante_initramfs.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_neovim_avante_initramfs import (
            DEFAULT_NEOVIM_VERSION,
            DEFAULT_BUSYBOX_VERSION,
            DEFAULT_GIT_VERSION,
            INIT_SCRIPT,
            NEOVIM_CONFIG,
        )
        assert DEFAULT_NEOVIM_VERSION is not None
        assert DEFAULT_BUSYBOX_VERSION is not None
        assert DEFAULT_GIT_VERSION is not None


class TestBuildEfiStubKernel:
    """Tests for build_efi_stub_kernel.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_efi_stub_kernel import (
            DEFAULT_KERNEL_VERSION,
            KERNEL_URL_TEMPLATE,
        )
        assert DEFAULT_KERNEL_VERSION is not None
        assert "kernel.org" in KERNEL_URL_TEMPLATE


class TestTrimMicrovmRootfs:
    """Tests for trim_microvm_rootfs.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        import trim_microvm_rootfs
        assert hasattr(trim_microvm_rootfs, "main")


class TestValidateArmv7Kernel:
    """Tests for validate_armv7_kernel.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        import validate_armv7_kernel
        assert hasattr(validate_armv7_kernel, "main")
        assert hasattr(validate_armv7_kernel, "validate_kernel")


class TestBuildArmv7Complete:
    """Tests for build_armv7_complete.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_armv7_complete import (
            DEFAULT_KERNEL_VERSION,
            check_dependencies,
        )
        assert DEFAULT_KERNEL_VERSION is not None
        assert callable(check_dependencies)

    def test_check_dependencies_returns_list(self) -> None:
        """Should return list of missing dependencies."""
        from build_armv7_complete import check_dependencies

        # This may find missing deps depending on the system
        result = check_dependencies()
        assert isinstance(result, list)


class TestBuildAndValidateArm64:
    """Tests for build_and_validate_arm64.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        import build_and_validate_arm64
        assert hasattr(build_and_validate_arm64, "main")
        assert hasattr(build_and_validate_arm64, "DEFAULT_KERNEL_VERSION")


class TestBuildMinivimKernelDocker:
    """Tests for build_minivim_kernel_docker.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_minivim_kernel_docker import (
            DEFAULT_KERNEL_VERSION,
            build_in_docker,
        )
        assert DEFAULT_KERNEL_VERSION is not None
        assert callable(build_in_docker)


class TestBuildNeovimInitramfsMacos:
    """Tests for build_neovim_initramfs_macos.py functions."""

    def test_import(self) -> None:
        """Should import successfully."""
        from build_neovim_initramfs_macos import (
            DEFAULT_NEOVIM_VERSION,
            DEFAULT_BUSYBOX_VERSION,
            INIT_SCRIPT,
        )
        assert DEFAULT_NEOVIM_VERSION is not None
        assert DEFAULT_BUSYBOX_VERSION is not None
        assert "mount" in INIT_SCRIPT.lower()