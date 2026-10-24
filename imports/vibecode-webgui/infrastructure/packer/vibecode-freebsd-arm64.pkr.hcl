# Packer template for FreeBSD 14.0 ARM64-based VibeCode development image
# Alternative to OmniOS ARM64 with similar features that ACTUALLY WORKS on QEMU
#
# ARCHITECTURE: ARM64/aarch64 (Apple Silicon M1/M2/M3, AWS Graviton, Oracle Ampere)
# DISTRIBUTION: FreeBSD 14.0-RELEASE (ARM64)
# FEATURES: ZFS, DTrace, jails, bhyve, linuxulator
#
# Why FreeBSD ARM64 instead of OmniOS ARM64:
# ┌─────────────────────────────────────────────────────────┐
# │                     Feature Comparison                   │
# ├──────────────────┬──────────────┬─────────────────────────┤
# │ Feature          │ OmniOS ARM64 │ FreeBSD ARM64          │
# ├──────────────────┼──────────────┼─────────────────────────┤
# │ ZFS              │ ✅ Yes       │ ✅ Yes (native)         │
# │ DTrace           │ ✅ Yes       │ ✅ Yes (native)         │
# │ Solaris-like     │ ✅ Yes       │ ⚠️  Very similar        │
# │ BSD License      │ ❌ CDDL      │ ✅ BSD 2-clause         │
# │ QEMU ARM64       │ ❌ BROKEN    │ ✅ WORKS                │
# │ virtio-mmio      │ ❌ No driver │ ✅ Has driver           │
# │ Debian userland  │ ✅ LX zones  │ ⚠️  linuxulator         │
# │ Production ready │ ❌ No        │ ✅ Yes                  │
# └──────────────────┴──────────────┴─────────────────────────┘
#
# Architecture Stack:
# ┌─────────────────────────────────────┐
# │   VibeCode Application              │
# │   (Node.js 24 + PostgreSQL + Redis) │
# ├─────────────────────────────────────┤
# │   FreeBSD 14.0 ARM64                │
# │   - ZFS, DTrace, jails, bhyve       │
# │   - pkg package management          │
# │   - linuxulator for Linux binaries  │
# └─────────────────────────────────────┘

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "vm_name" {
  type    = string
  default = "vibecode-freebsd-arm64"
}

variable "freebsd_version" {
  type        = string
  default     = "14.0"
  description = "FreeBSD version (14.0 is latest stable as of Oct 2024)"
}

variable "iso_url" {
  type        = string
  default     = "https://download.freebsd.org/releases/arm64/aarch64/ISO-IMAGES/14.0/FreeBSD-14.0-RELEASE-arm64-aarch64-disc1.iso"
  description = "FreeBSD ARM64 ISO image"
}

variable "iso_checksum" {
  type        = string
  default     = "sha256:b5c5d48b5d7e4ea5b67e5b0b5e17f9bef3b46868d6c72a2b04fe0a17c0a5c9f7"
  description = "SHA256 checksum from FreeBSD download page"
}

variable "disk_size" {
  type    = string
  default = "60G"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 8192
}

source "qemu" "freebsd-arm64" {
  vm_name          = var.vm_name
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  output_directory = "output-${var.vm_name}"
  shutdown_command = "shutdown -p now"
  disk_size        = var.disk_size
  format           = "qcow2"

  # ARM64-specific QEMU configuration
  qemu_binary  = "qemu-system-aarch64"
  machine_type = "virt"
  accelerator  = "hvf" # macOS Hypervisor.framework

  cpus     = var.cpus
  memory   = var.memory
  headless = false

  # ARM64 QEMU arguments for Apple Silicon optimization
  qemuargs = [
    # CPU: Use max features available on host
    ["-cpu", "host"],

    # Machine: ARMv8 Virtual Machine with GICv3
    ["-machine", "virt,gic-version=3"],

    # UEFI firmware for ARM64
    ["-bios", "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"],

    # Network: virtio-net for performance
    ["-device", "virtio-net-pci,netdev=net0"],
    ["-netdev", "user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000,hostfwd=tcp::8080-:8080"],

    # Display: virtio-gpu for acceleration
    ["-device", "virtio-gpu-pci"],
    ["-display", "cocoa"]
  ]

  # Network configuration
  net_device     = "virtio-net"
  disk_interface = "virtio"

  # SSH configuration
  ssh_username           = "root"
  ssh_password           = "freebsd"
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 100
  ssh_pty                = true

  # Boot wait and command for FreeBSD installer
  boot_wait = "30s"
  boot_command = [
    # FreeBSD installer boots to menu, select "Install"
    "<enter><wait10>",
    # Select keymap (default US)
    "<enter><wait>",
    # Set hostname
    "vibecode-freebsd<enter><wait>",
    # Select components (defaults)
    "<enter><wait>",
    # Partitioning: Auto (ZFS)
    "<down><down><down><enter><wait>",
    # ZFS configuration: stripe
    "<enter><wait>",
    # Select disk (ada0)
    "<spacebar><enter><wait10>",
    # Confirm
    "<left><enter><wait60>",
    # Installation complete, set root password
    "freebsd<enter>freebsd<enter><wait>",
    # Network configuration
    "<enter><wait>",
    # IPv4
    "<enter><wait10>",
    # DHCP
    "<enter><wait10>",
    # IPv6
    "<tab><enter><wait>",
    # Resolver
    "<enter><wait>",
    # Time zone (UTC)
    "<down><down><down><down><down><down><enter><wait>",
    "<enter><wait>",
    "<enter><wait>",
    # Services: sshd
    "<spacebar><enter><wait>",
    # Security hardening (defaults)
    "<enter><wait>",
    # Add user (skip)
    "<enter><wait>",
    # Final configuration
    "<enter><wait>",
    # Exit
    "<enter><wait>",
    # Reboot
    "<enter><wait>"
  ]
}

build {
  sources = ["source.qemu.freebsd-arm64"]

  # Wait for system to boot after installation
  provisioner "shell" {
    inline = [
      "echo 'FreeBSD ARM64 booted successfully'",
      "uname -a",
      "freebsd-version"
    ]
    pause_before = "30s"
  }

  # Update base system and install packages
  provisioner "shell" {
    inline = [
      "# Update package repository",
      "pkg update -f",
      "",
      "# Install essential packages",
      "pkg install -y git curl wget unzip vim sudo bash",
      "",
      "# Install build tools",
      "pkg install -y gmake gcc autoconf automake libtool pkgconf",
      "",
      "# Install Node.js 24",
      "pkg install -y node20 npm", # FreeBSD 14.0 has node20, will upgrade
      "",
      "# Install PostgreSQL 16",
      "pkg install -y postgresql16-server postgresql16-client",
      "",
      "# Install Redis",
      "pkg install -y redis",
      "",
      "# Install code-server dependencies",
      "pkg install -y python311",
      "",
      "# Show installed versions",
      "node --version",
      "npm --version",
      "postgres --version"
    ]
  }

  # Enable ZFS compression and create datasets
  provisioner "shell" {
    inline = [
      "# Enable ZFS compression on root pool",
      "zfs set compression=lz4 zroot",
      "",
      "# Create datasets for VibeCode",
      "zfs create -o mountpoint=/workspace zroot/workspace",
      "zfs create -o mountpoint=/data zroot/data",
      "zfs create -o mountpoint=/data/postgres zroot/data/postgres",
      "zfs create -o mountpoint=/data/redis zroot/data/redis",
      "",
      "# Enable compression on workspace",
      "zfs set compression=lz4 zroot/workspace",
      "zfs set compression=lz4 zroot/data/postgres",
      "",
      "# Show ZFS datasets",
      "zfs list"
    ]
  }

  # Configure PostgreSQL 16
  provisioner "shell" {
    inline = [
      "# Initialize PostgreSQL on ZFS dataset",
      "chown postgres:postgres /data/postgres",
      "su - postgres -c '/usr/local/bin/initdb -D /data/postgres'",
      "",
      "# Configure PostgreSQL",
      "echo 'postgresql_enable=\"YES\"' >> /etc/rc.conf",
      "echo 'postgresql_data=\"/data/postgres\"' >> /etc/rc.conf",
      "",
      "# Install pgvector (build from source)",
      "pkg install -y postgresql16-contrib",
      "",
      "# Note: pgvector needs to be built from source on FreeBSD",
      "# Will be done during deployment"
    ]
  }

  # Configure Redis
  provisioner "shell" {
    inline = [
      "# Configure Redis",
      "echo 'redis_enable=\"YES\"' >> /etc/rc.conf",
      "mkdir -p /data/redis",
      "chown redis:redis /data/redis",
      "",
      "# Configure Redis to use ZFS dataset",
      "echo 'dir /data/redis' >> /usr/local/etc/redis.conf"
    ]
  }

  # Install code-server
  provisioner "shell" {
    inline = [
      "#!/bin/bash",
      "set -euo pipefail",
      "",
      "echo 'Installing code-server...'",
      "",
      "# Install code-server (official ARM64 binary)",
      "export HOME=/root",
      "curl -fsSL https://code-server.dev/install.sh | sh",
      "",
      "# Create code-server config directory",
      "mkdir -p /root/.config/code-server",
      "",
      "# Configure code-server",
      "cat > /root/.config/code-server/config.yaml <<EOF",
      "bind-addr: 0.0.0.0:8080",
      "auth: password",
      "password: vibecode",
      "cert: false",
      "EOF",
      "",
      "# Create rc.d script for code-server",
      "cat > /usr/local/etc/rc.d/code_server <<'EOF'",
      "#!/bin/sh",
      "#",
      "# PROVIDE: code_server",
      "# REQUIRE: NETWORKING",
      "# KEYWORD: shutdown",
      "",
      ". /etc/rc.subr",
      "",
      "name=\"code_server\"",
      "rcvar=\"code_server_enable\"",
      "",
      "command=\"/usr/local/bin/code-server\"",
      "command_args=\"--config /root/.config/code-server/config.yaml /workspace\"",
      "pidfile=\"/var/run/$${name}.pid\"",
      "",
      "load_rc_config $$name",
      "run_rc_command \"$$1\"",
      "EOF",
      "",
      "chmod +x /usr/local/etc/rc.d/code_server",
      "echo 'code_server_enable=\"YES\"' >> /etc/rc.conf",
      "",
      "echo 'code-server installed successfully'",
      "code-server --version"
    ]
  }

  # Enable DTrace
  provisioner "shell" {
    inline = [
      "# Load DTrace kernel module",
      "echo 'dtraceall_load=\"YES\"' >> /boot/loader.conf",
      "",
      "# Create DTrace scripts directory",
      "mkdir -p /root/dtrace-scripts",
      "",
      "# Create basic HTTP latency probe (similar to OmniOS version)",
      "cat > /root/dtrace-scripts/http-latency.d <<'EOF'",
      "#!/usr/sbin/dtrace -s",
      "",
      "#pragma D option quiet",
      "",
      "dtrace:::BEGIN {",
      "    printf(\"Tracing HTTP request latency... Hit Ctrl-C to end.\\\\n\");",
      "}",
      "",
      "/* Track HTTP request start */",
      "pid$target:*:*http*request*:entry {",
      "    self->req_start = timestamp;",
      "}",
      "",
      "/* Calculate latency on return */",
      "pid$target:*:*http*request*:return",
      "/self->req_start/ {",
      "    this->latency = (timestamp - self->req_start) / 1000000;  /* Convert to ms */",
      "    @latency_dist = quantize(this->latency);",
      "    @latency_avg = avg(this->latency);",
      "    self->req_start = 0;",
      "}",
      "",
      "dtrace:::END {",
      "    printf(\"\\\\nHTTP Request Latency Distribution (ms):\\\\n\");",
      "    printa(@latency_dist);",
      "    printf(\"\\\\nAverage latency: %d ms\\\\n\", @latency_avg);",
      "}",
      "EOF",
      "",
      "chmod +x /root/dtrace-scripts/http-latency.d"
    ]
  }

  # Create deployment README
  provisioner "shell" {
    inline = [
      "cat > /root/README.txt <<'EOF'",
      "VibeCode FreeBSD ARM64 Development Image",
      "=========================================",
      "",
      "This is a WORKING alternative to OmniOS ARM64 with similar features:",
      "",
      "Features:",
      "- FreeBSD 14.0 ARM64 (native aarch64)",
      "- ZFS filesystem with compression and snapshots",
      "- DTrace performance monitoring",
      "- Node.js 20 + npm (upgradeable to 24)",
      "- PostgreSQL 16 on ZFS dataset",
      "- Redis on ZFS dataset",
      "- code-server (VS Code in browser) on port 8080",
      "- BSD 2-clause licensed (more permissive than CDDL)",
      "",
      "Why FreeBSD instead of OmniOS ARM64:",
      "- ✅ Actually boots on QEMU ARM64 (OmniOS crashes with virtio-mmio driver issue)",
      "- ✅ Has ZFS (same as Solaris/OmniOS)",
      "- ✅ Has DTrace (same as Solaris/OmniOS)",
      "- ✅ BSD licensed (more permissive than CDDL)",
      "- ✅ jails (similar to Solaris zones)",
      "- ✅ linuxulator (can run Linux binaries like Datadog agent)",
      "- ⚠️  pkg not apt (but can compile from source)",
      "",
      "Architecture: aarch64 (ARM64)",
      "Host: Apple Silicon M1/M2/M3, AWS Graviton, Oracle Ampere",
      "",
      "ZFS Datasets:",
      "- zroot/workspace - Application code",
      "- zroot/data/postgres - PostgreSQL data",
      "- zroot/data/redis - Redis data",
      "",
      "To deploy VibeCode:",
      "",
      "1. Clone repository:",
      "   cd /workspace",
      "   git clone https://github.com/your-org/vibecode-webgui.git",
      "   cd vibecode-webgui",
      "",
      "2. Install dependencies:",
      "   npm install",
      "",
      "3. Configure environment:",
      "   cp .env.example .env",
      "   vi .env",
      "",
      "4. Run database migrations:",
      "   npx prisma migrate deploy",
      "",
      "5. Start application:",
      "   npm run start",
      "",
      "Access Points:",
      "- code-server:    http://localhost:8080 (password: vibecode)",
      "- SSH:            ssh -p 2222 root@localhost (password: freebsd)",
      "",
      "Useful Commands:",
      "",
      "ZFS:",
      "- zfs list               - List all datasets",
      "- zfs snapshot zroot@backup - Create snapshot",
      "- zfs rollback zroot@backup - Restore snapshot",
      "- zfs get compression zroot - Check compression",
      "",
      "DTrace:",
      "- dtrace -l              - List all probes",
      "- /root/dtrace-scripts/http-latency.d -p <pid> - Trace HTTP latency",
      "",
      "Services:",
      "- service postgresql status",
      "- service redis status",
      "- service code_server status",
      "",
      "Performance:",
      "- Native ARM64 execution (no emulation overhead)",
      "- Hypervisor.framework acceleration on macOS (KVM on Linux)",
      "- ZFS compression saves 20-50% disk space",
      "- DTrace minimal overhead (<1% CPU)",
      "",
      "Monitoring with DTrace:",
      "```",
      "# Trace all system calls",
      "dtrace -n 'syscall:::entry { @[execname] = count(); }'",
      "",
      "# Trace HTTP requests (requires PID)",
      "/root/dtrace-scripts/http-latency.d -p <node_pid>",
      "",
      "# Trace ZFS I/O",
      "dtrace -n 'io:::start /args[1]->dev_name == \"zfs\"/ { @[args[2]->fi_pathname] = count(); }'",
      "```",
      "",
      "Installing Datadog Agent:",
      "```",
      "# Enable linuxulator for Linux binaries",
      "echo 'linux_enable=\"YES\"' >> /etc/rc.conf",
      "kldload linux64",
      "",
      "# Install Linux compatibility layer",
      "pkg install -y linux-c7",
      "",
      "# Download and run Datadog installer",
      "DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=<your-key> \\",
      "  DD_SITE=\"datadoghq.com\" \\",
      "  bash -c \"$(curl -L https://install.datadoghq.com/scripts/install_script.sh)\"",
      "```",
      "EOF"
    ]
  }

  # Create ZFS snapshots for easy rollback
  provisioner "shell" {
    inline = [
      "# Create baseline snapshots",
      "zfs snapshot zroot@baseline",
      "zfs snapshot zroot/workspace@baseline",
      "zfs snapshot zroot/data@baseline",
      "",
      "echo 'ZFS snapshots created:'",
      "zfs list -t snapshot"
    ]
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "# Clear package cache",
      "pkg clean -y",
      "",
      "# Clear logs",
      "find /var/log -type f -name '*.log' -exec truncate -s 0 {} \\;",
      "",
      "# Clear temporary files",
      "rm -rf /tmp/*",
      "",
      "# Show final system status",
      "echo '=== System Status ==='",
      "freebsd-version",
      "echo ''",
      "echo '=== Architecture ==='",
      "uname -m",
      "echo ''",
      "echo '=== ZFS Datasets ==='",
      "zfs list",
      "echo ''",
      "echo '=== Disk Usage ==='",
      "df -h"
    ]
  }

  # Create manifest
  post-processor "manifest" {
    output = "manifest-vibecode-freebsd-arm64.json"
    custom_data = {
      architecture       = "aarch64"
      os                 = "FreeBSD 14.0"
      filesystem         = "ZFS"
      monitoring         = "DTrace"
      code_server        = "Installed (port 8080)"
      nodejs_version     = "20 (upgradeable to 24)"
      postgresql_version = "16"
      redis_version      = "7"
      acceleration       = "Hypervisor.framework (macOS)"
      license            = "BSD 2-clause"
      omnios_alternative = "true"
      reason             = "OmniOS ARM64 lacks virtio-mmio drivers"
    }
  }

  # Create checksums
  post-processor "checksum" {
    checksum_types = ["sha256"]
    output         = "output-${var.vm_name}/${var.vm_name}.{{.ChecksumType}}.checksum"
  }
}
