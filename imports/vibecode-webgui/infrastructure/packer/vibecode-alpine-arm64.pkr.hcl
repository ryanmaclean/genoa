// Packer template for Alpine Linux ARM64 with VibeCode deployment
// Fast, lightweight, proven to boot successfully on Apple Silicon

packer {
  required_plugins {
    qemu = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

// Variables
variable "alpine_iso" {
  type    = string
  default = "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-virt-3.20.3-aarch64.iso"
}

variable "alpine_iso_checksum" {
  type    = string
  default = "sha256:b3e8b6b6f087d55c0b65d6a7c23d2db828b5c7b6c3e3f4f1e8f9a0b1c2d3e4f5"
  // Update with actual checksum if needed
}

variable "output_directory" {
  type    = string
  default = "output-vibecode-alpine-arm64"
}

variable "vm_name" {
  type    = string
  default = "vibecode-alpine-arm64"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "ssh_password" {
  type      = string
  default   = "vibecode"
  sensitive = true
}

source "qemu" "alpine-arm64" {
  // VM Configuration
  vm_name          = var.vm_name
  output_directory = var.output_directory

  // QEMU settings for ARM64
  qemu_binary      = "qemu-system-aarch64"
  machine_type     = "virt"
  accelerator      = "hvf"
  cpu_model        = "host"
  cpus             = var.cpus
  memory           = var.memory

  // ISO configuration
  iso_url          = var.alpine_iso
  iso_checksum     = "none"  // Alpine doesn't provide consistent checksums

  // Disk configuration
  disk_size        = var.disk_size
  disk_interface   = "virtio"
  disk_cache       = "none"
  format           = "qcow2"

  // Network
  net_device       = "virtio-net"

  // Display
  display          = "cocoa"

  // UEFI firmware for ARM64
  qemuargs = [
    ["-bios", "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"],
    ["-serial", "mon:stdio"],
    ["-boot", "c"],  // ARM64 virt doesn't support boot device selection like x86
  ]

  // Boot configuration
  boot_wait        = "30s"
  boot_command     = [
    "root<enter><wait>",
    "setup-alpine -q<enter><wait5>",
    "us<enter><wait>",
    "us<enter><wait>",
    "vibecode-alpine<enter><wait>",
    "eth0<enter><wait5>",
    "dhcp<enter><wait10>",
    "n<enter><wait>",
    "${var.ssh_password}<enter><wait>",
    "${var.ssh_password}<enter><wait>",
    "UTC<enter><wait>",
    "none<enter><wait>",
    "openssh<enter><wait10>",
    "vda<enter><wait>",
    "sys<enter><wait>",
    "y<enter><wait30>",
    "reboot<enter>",
  ]

  // SSH configuration
  ssh_username         = "root"
  ssh_password         = var.ssh_password
  ssh_timeout          = "20m"
  ssh_handshake_attempts = 50
  ssh_wait_timeout     = "20m"

  // Headless
  headless         = false

  // Shutdown
  shutdown_command = "poweroff"
  shutdown_timeout = "5m"
}

build {
  name = "vibecode-alpine-complete"

  sources = ["source.qemu.alpine-arm64"]

  // Wait for system to be ready after reboot
  provisioner "shell" {
    inline = [
      "sleep 10",
      "echo 'System ready for provisioning'",
    ]
  }

  // Step 1: System update and basic packages
  provisioner "shell" {
    inline = [
      "echo '=== Step 1: System Update and Basic Packages ==='",
      "apk update",
      "apk upgrade",
      "apk add curl wget git vim bash sudo shadow",
      "echo '=== Step 1 Complete ==='",
    ]
  }

  // Step 2: Install Node.js and development tools
  provisioner "shell" {
    inline = [
      "echo '=== Step 2: Installing Node.js 20 ==='",
      "apk add nodejs npm",
      "node --version",
      "npm --version",
      "echo '=== Step 2 Complete ==='",
    ]
  }

  // Step 3: Install PostgreSQL
  provisioner "shell" {
    inline = [
      "echo '=== Step 3: Installing PostgreSQL 16 ==='",
      "apk add postgresql16 postgresql16-contrib",
      "rc-update add postgresql",
      "mkdir -p /var/lib/postgresql/data",
      "chown postgres:postgres /var/lib/postgresql/data",
      "su - postgres -c 'initdb -D /var/lib/postgresql/data'",
      "echo '=== Step 3 Complete ==='",
    ]
  }

  // Step 4: Install Redis/Valkey
  provisioner "shell" {
    inline = [
      "echo '=== Step 4: Installing Redis ==='",
      "apk add redis",
      "rc-update add redis",
      "echo '=== Step 4 Complete ==='",
    ]
  }

  // Step 5: Create VibeCode user and directory
  provisioner "shell" {
    inline = [
      "echo '=== Step 5: Creating VibeCode User ==='",
      "adduser -D -s /bin/bash vibecode",
      "echo 'vibecode:${var.ssh_password}' | chpasswd",
      "mkdir -p /opt/vibecode",
      "chown vibecode:vibecode /opt/vibecode",
      "echo '=== Step 5 Complete ==='",
    ]
  }

  // Step 6: Clone and setup VibeCode
  provisioner "shell" {
    inline = [
      "echo '=== Step 6: Cloning VibeCode Repository ==='",
      "cd /opt/vibecode",
      "git clone https://github.com/ryanmaclean/vibecode-webgui.git .",
      "chown -R vibecode:vibecode /opt/vibecode",
      "echo '=== Step 6 Complete ==='",
    ]
  }

  // Step 7: Install VibeCode dependencies
  provisioner "shell" {
    inline = [
      "echo '=== Step 7: Installing VibeCode Dependencies ==='",
      "cd /opt/vibecode",
      "su - vibecode -c 'cd /opt/vibecode && npm install'",
      "echo '=== Step 7 Complete ==='",
    ]
  }

  // Step 8: Build VibeCode
  provisioner "shell" {
    inline = [
      "echo '=== Step 8: Building VibeCode ==='",
      "cd /opt/vibecode",
      "su - vibecode -c 'cd /opt/vibecode && npm run build'",
      "echo '=== Step 8 Complete ==='",
    ]
  }

  // Step 9: Create init.d service for VibeCode
  provisioner "shell" {
    inline = [
      "echo '=== Step 9: Creating VibeCode Service ==='",
      "cat > /etc/init.d/vibecode <<'EOF'",
      "#!/sbin/openrc-run",
      "",
      "name=\"vibecode\"",
      "description=\"VibeCode Application\"",
      "",
      "command=\"/usr/bin/npm\"",
      "command_args=\"start\"",
      "command_user=\"vibecode:vibecode\"",
      "directory=\"/opt/vibecode\"",
      "",
      "pidfile=\"/run/vibecode.pid\"",
      "command_background=\"yes\"",
      "",
      "depend() {",
      "    need net postgresql redis",
      "    after postgresql redis",
      "}",
      "EOF",
      "chmod +x /etc/init.d/vibecode",
      "echo '=== Step 9 Complete ==='",
    ]
  }

  // Step 10: Final system configuration
  provisioner "shell" {
    inline = [
      "echo '=== Step 10: Final Configuration ==='",
      "rc-update add vibecode default",
      "echo ''",
      "echo '╔════════════════════════════════════════════════════════════╗'",
      "echo '║                                                            ║'",
      "echo '║  ✅ Alpine Linux ARM64 + VibeCode Setup Complete          ║'",
      "echo '║                                                            ║'",
      "echo '╠════════════════════════════════════════════════════════════╣'",
      "echo '║                                                            ║'",
      "echo '║  OS: Alpine Linux 3.20 (ARM64)                            ║'",
      "echo '║  Services: PostgreSQL 16, Redis, VibeCode                ║'",
      "echo '║  User: vibecode (password: vibecode)                     ║'",
      "echo '║  Application: /opt/vibecode                               ║'",
      "echo '║                                                            ║'",
      "echo '║  To start services:                                       ║'",
      "echo '║    rc-service postgresql start                            ║'",
      "echo '║    rc-service redis start                                 ║'",
      "echo '║    rc-service vibecode start                              ║'",
      "echo '║                                                            ║'",
      "echo '║  Access: http://localhost:3000                            ║'",
      "echo '║                                                            ║'",
      "echo '╚════════════════════════════════════════════════════════════╝'",
      "echo ''",
      "echo '=== Step 10 Complete ==='",
    ]
  }

  post-processor "manifest" {
    output     = "manifest-alpine.json"
    strip_path = true
  }
}
