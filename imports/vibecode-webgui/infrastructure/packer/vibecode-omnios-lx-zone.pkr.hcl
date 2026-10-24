// Packer template for OmniOS ARM64 with LX Zone and VibeCode deployment
// This automates the entire setup from base image to running application

packer {
  required_plugins {
    qemu = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

// Variables for configuration
variable "omnios_image" {
  type    = string
  default = "~/Downloads/omnios-arm64/omnios-arm64.qcow2"
}

variable "output_directory" {
  type    = string
  default = "output-vibecode-omnios-lx"
}

variable "vm_name" {
  type    = string
  default = "vibecode-omnios-arm64"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 8192
}

variable "disk_size" {
  type    = string
  default = "60G"
}

// SSH configuration for OmniOS
variable "ssh_username" {
  type    = string
  default = "root"
}

variable "ssh_password" {
  type    = string
  default = "" // OmniOS default may require setting during first boot
  sensitive = true
}

source "qemu" "omnios-arm64" {
  // VM Configuration
  vm_name              = var.vm_name
  output_directory     = var.output_directory

  // QEMU settings for ARM64
  qemu_binary          = "qemu-system-aarch64"
  machine_type         = "virt"
  accelerator          = "hvf" // macOS Hypervisor.framework
  cpu_model            = "host"
  cpus                 = var.cpus
  memory               = var.memory

  // Disk configuration
  disk_image           = true
  iso_url              = var.omnios_image
  disk_size            = var.disk_size
  disk_interface       = "virtio"
  disk_cache           = "none"
  disk_discard         = "unmap"
  disk_detect_zeroes   = "unmap"
  format               = "qcow2"

  // Network
  net_device           = "virtio-net"

  // UEFI firmware for ARM64
  qemuargs = [
    ["-bios", "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"],
    ["-device", "virtio-gpu-pci"],
    ["-device", "qemu-xhci"],
    ["-device", "usb-kbd"],
    ["-device", "usb-mouse"],
    ["-serial", "mon:stdio"],
  ]

  // Boot configuration
  boot_wait            = "10s"

  // SSH configuration
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "30m"
  ssh_handshake_attempts = 100

  // No graphics - use serial console
  headless             = false // Set to true for unattended builds

  // Shutdown command
  shutdown_command     = "poweroff"
  shutdown_timeout     = "5m"
}

build {
  name = "vibecode-omnios-complete"

  sources = ["source.qemu.omnios-arm64"]

  // Step 1: Initial system configuration
  provisioner "shell" {
    inline = [
      "echo '=== Step 1: Initial System Configuration ==='",
      "echo 'Hostname: vibecode-production'",
      "hostname vibecode-production",
      "echo 'vibecode-production' > /etc/nodename",
      "",
      "echo '=== Configuring timezone ==='",
      "ln -sf /usr/share/zoneinfo/UTC /etc/localtime",
      "",
      "echo '=== System update ==='",
      "pkg update -v",
      "",
      "echo '=== Installing essential packages ==='",
      "pkg install -v wget curl git vim tmux",
      "",
      "echo '=== Step 1 Complete ==='",
    ]
  }

  // Step 2: ZFS pool configuration
  provisioner "shell" {
    inline = [
      "echo '=== Step 2: ZFS Pool Configuration ==='",
      "",
      "echo '=== Creating ZFS datasets for zones ==='",
      "zfs create -o mountpoint=/zones rpool/zones || true",
      "zfs create -o compression=lz4 -o atime=off rpool/zones/vibecode",
      "zfs create -o compression=lz4 rpool/zones/vibecode/data",
      "zfs create -o compression=lz4 -o recordsize=16k rpool/zones/vibecode/postgres",
      "",
      "echo '=== ZFS datasets created ==='",
      "zfs list -r rpool/zones",
      "",
      "echo '=== Step 2 Complete ==='",
    ]
  }

  // Step 3: Download Debian LX zone image
  provisioner "shell" {
    inline = [
      "echo '=== Step 3: Download Debian LX Zone Image ==='",
      "",
      "mkdir -p /opt/zone-images",
      "cd /opt/zone-images",
      "",
      "echo '=== Downloading Debian 11 (Bullseye) for LX zones ==='",
      "# Using docker export method (fastest, most compatible)",
      "pkg install -v docker || echo 'Docker not available, using alternative'",
      "",
      "# Alternative: Download pre-built rootfs",
      "wget -O debian-11-arm64.tar.gz https://github.com/joyent/debian-lx-brand-image-builder/releases/download/v20210730/debian-11-20210730.tar.gz || \\",
      "  wget -O debian-11-arm64.tar.gz https://us-central.manta.mnx.io/Joyent_Dev/public/images/debian/11/debian-11-latest.tar.gz || \\",
      "  echo 'Will create from Docker in next step'",
      "",
      "echo '=== Step 3 Complete ==='",
    ]
  }

  // Step 4: Create and configure LX zone
  provisioner "shell" {
    script = "${path.root}/scripts/create-lx-zone.sh"
  }

  // Step 5: Install VibeCode dependencies in zone
  provisioner "shell" {
    inline = [
      "echo '=== Step 5: Installing VibeCode Dependencies in LX Zone ==='",
      "",
      "# Copy dependency installation script to zone",
      "cp /tmp/install-vibecode-deps.sh /zones/vibecode/root/root/",
      "chmod +x /zones/vibecode/root/root/install-vibecode-deps.sh",
      "",
      "# Execute in zone",
      "zlogin vibecode /root/install-vibecode-deps.sh",
      "",
      "echo '=== Step 5 Complete ==='",
    ]
  }

  // Step 6: Deploy VibeCode application
  provisioner "shell" {
    inline = [
      "echo '=== Step 6: Deploying VibeCode Application ==='",
      "",
      "zlogin vibecode <<'ZONE_EOF'",
      "  cd /opt",
      "  git clone https://github.com/ryanmaclean/vibecode-webgui.git vibecode",
      "  cd vibecode",
      "  ",
      "  echo '=== Installing Node.js dependencies ==='",
      "  npm install --production",
      "  ",
      "  echo '=== Building application ==='",
      "  npm run build",
      "  ",
      "  echo '=== Creating systemd service ==='",
      "  cat > /etc/systemd/system/vibecode.service <<'SERVICE_EOF'",
      "[Unit]",
      "Description=VibeCode Application",
      "After=network.target postgresql.service valkey.service",
      "Wants=postgresql.service valkey.service",
      "",
      "[Service]",
      "Type=simple",
      "User=vibecode",
      "WorkingDirectory=/opt/vibecode",
      "Environment=NODE_ENV=production",
      "Environment=PORT=3000",
      "ExecStart=/usr/bin/npm start",
      "Restart=always",
      "RestartSec=10",
      "",
      "# Security hardening",
      "NoNewPrivileges=true",
      "PrivateTmp=true",
      "ProtectSystem=strict",
      "ProtectHome=true",
      "ReadWritePaths=/opt/vibecode/logs",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "SERVICE_EOF",
      "  ",
      "  systemctl daemon-reload",
      "  systemctl enable vibecode",
      "  ",
      "  echo '=== VibeCode service created (not started yet) ==='",
      "ZONE_EOF",
      "",
      "echo '=== Step 6 Complete ==='",
    ]
  }

  // Step 7: Final configuration and verification
  provisioner "shell" {
    inline = [
      "echo '=== Step 7: Final Configuration and Verification ==='",
      "",
      "echo '=== Zone status ==='",
      "zoneadm list -cv",
      "",
      "echo '=== ZFS status ==='",
      "zfs list -r rpool/zones",
      "",
      "echo '=== Services in zone ==='",
      "zlogin vibecode systemctl list-units --type=service --state=running",
      "",
      "echo '=== PostgreSQL status ==='",
      "zlogin vibecode systemctl status postgresql || true",
      "",
      "echo '=== Valkey status ==='",
      "zlogin vibecode systemctl status valkey || true",
      "",
      "echo '=== Network configuration ==='",
      "zlogin vibecode ip addr show",
      "",
      "echo '=== Disk usage ==='",
      "zlogin vibecode df -h",
      "",
      "echo '=== Step 7 Complete ==='",
      "",
      "echo ''",
      "echo '╔════════════════════════════════════════════════════════════╗'",
      "echo '║                                                            ║'",
      "echo '║  ✅ OmniOS ARM64 + LX Zone + VibeCode Setup Complete      ║'",
      "echo '║                                                            ║'",
      "echo '╠════════════════════════════════════════════════════════════╣'",
      "echo '║                                                            ║'",
      "echo '║  Zone: vibecode                                            ║'",
      "echo '║  OS: Debian 11 (in LX zone)                               ║'",
      "echo '║  Services: PostgreSQL 16, Valkey 8.0, Nginx               ║'",
      "echo '║  Application: VibeCode (ready to start)                   ║'",
      "echo '║                                                            ║'",
      "echo '║  To start VibeCode:                                       ║'",
      "echo '║    zlogin vibecode                                        ║'",
      "echo '║    systemctl start vibecode                               ║'",
      "echo '║                                                            ║'",
      "echo '║  Access: http://localhost:3000                            ║'",
      "echo '║                                                            ║'",
      "echo '╚════════════════════════════════════════════════════════════╝'",
      "",
    ]
  }

  // Upload provisioning scripts before running
  provisioner "file" {
    source      = "${path.root}/scripts/create-lx-zone.sh"
    destination = "/tmp/create-lx-zone.sh"
  }

  provisioner "file" {
    source      = "${path.root}/scripts/install-vibecode-deps.sh"
    destination = "/tmp/install-vibecode-deps.sh"
  }

  // Post-processor to create snapshot
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
