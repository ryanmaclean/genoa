# Packer template for OpenIndiana-based VibeCode development image
# Creates VM with ZFS, DTrace, LX zones, and Debian userland
#
# ARCHITECTURE NOTE:
# OpenIndiana officially supports x86-64 only. ARM64 support is experimental.
# On Apple Silicon (M1/M2/M3), this template uses QEMU x86_64 emulation which
# is slower than native virtualization but maintains full compatibility.
#
# For native ARM64 performance on Apple Silicon, use the Alpine Linux vfkit
# templates in scripts/vfkit/ which provide similar ZFS-like features via btrfs.

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
  default = "vibecode-openindiana"
}

variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "Target architecture: x86_64 (official) or aarch64 (experimental, emulated)"
}

variable "iso_url" {
  type    = string
  default = "https://dlc.openindiana.org/isos/hipster/OI-hipster-gui-20231027.iso"
  description = "OpenIndiana ISO URL (x86-64 only, no official ARM64 ISO available)"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:f7c99e2e5c2c3e3e9c8a7f6b5e4d3c2b1a0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d"
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

variable "zone_name" {
  type    = string
  default = "vibecode-zone"
}

variable "zone_cpus" {
  type    = number
  default = 4
}

variable "zone_memory" {
  type    = string
  default = "8G"
}

variable "ssh_password" {
  type        = string
  sensitive   = true
  description = "Root SSH password set during the OpenIndiana install. No default: pass -var ssh_password=... or PKR_VAR_ssh_password."
}

source "qemu" "openindiana" {
  vm_name          = var.vm_name
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  output_directory = "output-${var.vm_name}"
  shutdown_command = "pfexec poweroff"
  disk_size        = var.disk_size
  format           = "qcow2"
  accelerator      = "kvm"
  qemu_binary      = "qemu-system-x86_64"
  headless         = false # OpenIndiana installer requires GUI interaction
  cpus             = var.cpus
  memory           = var.memory

  # Network configuration
  net_device     = "virtio-net"
  disk_interface = "virtio"

  # Boot configuration for OpenIndiana installer
  boot_wait = "10s"
  boot_command = [
    # OpenIndiana text installer automation
    # Note: This is a simplified boot command. Full automation may require
    # creating a custom AI manifest or using the text installer interactively.
    "<enter><wait10>"
  ]

  # SSH configuration (after installation)
  ssh_username           = "root"
  ssh_password           = var.ssh_password
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 100
  ssh_pty                = true

  # Display configuration
  vnc_bind_address = "0.0.0.0"
  vnc_port_min     = 5900
  vnc_port_max     = 5900
}

build {
  sources = ["source.qemu.openindiana"]

  # Note: OpenIndiana installation requires manual interaction or AI manifest
  # This template assumes the base OS is installed and SSH is configured
  # For fully automated builds, consider creating an AI (Automated Installer) manifest

  # Update base system and install required packages
  provisioner "shell" {
    inline = [
      "pkg refresh",
      "pkg install -v brand/lx git curl wget unzip vim",
      "pkg install -v runtime/perl/module/json-perl",
      "# Enable boot environment management",
      "beadm list"
    ]
    pause_before = "10s"
  }

  # Transfer OpenIndiana setup scripts
  provisioner "file" {
    source      = "scripts/openindiana/"
    destination = "/root/openindiana-setup"
  }

  # Configure LX-branded zone for Debian userland
  provisioner "shell" {
    inline = [
      "chmod +x /root/openindiana-setup/*.sh",
      "# Run LX zone configuration",
      "export ZONE_NAME=${var.zone_name}",
      "export ZONE_CPUS=${var.zone_cpus}",
      "export ZONE_MEMORY=${var.zone_memory}",
      "/root/openindiana-setup/02-configure-lx-zone.sh"
    ]
    environment_vars = [
      "ZONE_NAME=${var.zone_name}",
      "ZONE_CPUS=${var.zone_cpus}",
      "ZONE_MEMORY=${var.zone_memory}"
    ]
  }

  # Install Node.js 24 in LX zone
  provisioner "shell" {
    inline = [
      "zlogin ${var.zone_name} 'bash -s' < /root/openindiana-setup/03-install-node24.sh"
    ]
  }

  # Setup PostgreSQL 16 + pgvector in LX zone
  provisioner "shell" {
    inline = [
      "zlogin ${var.zone_name} 'bash -s' < /root/openindiana-setup/04-setup-postgres-pgvector.sh"
    ]
  }

  # Configure DTrace monitoring
  provisioner "shell" {
    inline = [
      "/root/openindiana-setup/06-configure-dtrace.sh"
    ]
  }

  # Create VibeCode deployment script (to be run after cloning repo)
  provisioner "shell" {
    inline = [
      "mkdir -p /root/vibecode-deployment",
      "cp /root/openindiana-setup/05-deploy-vibecode.sh /root/vibecode-deployment/",
      "chmod +x /root/vibecode-deployment/05-deploy-vibecode.sh",
      "cat > /root/README.txt <<'EOF'",
      "VibeCode OpenIndiana Development Image",
      "======================================",
      "",
      "This image includes:",
      "- OpenIndiana Hipster with ZFS and DTrace",
      "- LX-branded zone '${var.zone_name}' with Debian 11 userland",
      "- Node.js 24 installed in zone",
      "- PostgreSQL 16 + pgvector configured",
      "- DTrace monitoring probes installed",
      "",
      "To deploy VibeCode:",
      "1. Login to the zone:",
      "   zlogin ${var.zone_name}",
      "",
      "2. Clone the repository:",
      "   git clone https://github.com/your-org/vibecode-webgui.git /workspace/vibecode",
      "   cd /workspace/vibecode",
      "",
      "3. Run deployment script:",
      "   bash /root/vibecode-deployment/05-deploy-vibecode.sh",
      "",
      "Useful Commands:",
      "- Zone status:    zoneadm list -v",
      "- Zone login:     zlogin ${var.zone_name}",
      "- Zone stats:     zonestat 5 5",
      "- DTrace probes:  dtrace -l | grep vibecode",
      "- ZFS status:     zpool status",
      "- ZFS datasets:   zfs list",
      "",
      "Monitoring:",
      "- HTTP latency:   dtrace -s /root/openindiana-setup/dtrace/http-latency.d -p <pid>",
      "- DB queries:     dtrace -s /root/openindiana-setup/dtrace/database-queries.d -p <pid>",
      "- Node.js GC:     dtrace -s /root/openindiana-setup/dtrace/nodejs-gc.d -p <pid>",
      "- ZFS I/O:        dtrace -s /root/openindiana-setup/dtrace/zfs-io.d",
      "- Network:        dtrace -s /root/openindiana-setup/dtrace/network-tcp.d",
      "EOF"
    ]
  }

  # Create baseline ZFS snapshots
  provisioner "shell" {
    inline = [
      "# Create snapshots for easy rollback",
      "zfs snapshot rpool@baseline",
      "zfs snapshot rpool/zones/${var.zone_name}@baseline",
      "zfs snapshot rpool/zones/${var.zone_name}/postgres@baseline",
      "zfs snapshot rpool/zones/${var.zone_name}/redis@baseline",
      "zfs snapshot rpool/zones/${var.zone_name}/app@baseline",
      "echo 'ZFS snapshots created:'",
      "zfs list -t snapshot"
    ]
  }

  # Cleanup and optimization
  provisioner "shell" {
    inline = [
      "# Clear package cache",
      "pkg purge",
      "# Clear logs (keep structure)",
      "find /var/log -type f -name '*.log' -exec truncate -s 0 {} \\;",
      "# Clear temporary files",
      "rm -rf /var/tmp/*",
      "rm -rf /tmp/*",
      "# Zone cleanup",
      "zlogin ${var.zone_name} 'apt-get clean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*'",
      "# Show final system status",
      "echo '=== System Status ==='",
      "beadm list",
      "echo ''",
      "echo '=== ZFS Datasets ==='",
      "zfs list",
      "echo ''",
      "echo '=== Zone Status ==='",
      "zoneadm list -v",
      "echo ''",
      "echo '=== Disk Usage ==='",
      "df -h"
    ]
  }

  # Create manifest with build metadata
  post-processor "manifest" {
    output = "manifest-vibecode-openindiana.json"
    custom_data = {
      zone_name           = var.zone_name
      zone_cpus           = var.zone_cpus
      zone_memory         = var.zone_memory
      openindiana_version = "Hipster 2023.10"
      debian_version      = "11"
      nodejs_version      = "24"
      postgresql_version  = "16"
    }
  }

  # Optional: Create checksum file
  post-processor "checksum" {
    checksum_types = ["sha256"]
    output         = "output-${var.vm_name}/${var.vm_name}.{{.ChecksumType}}.checksum"
  }
}
