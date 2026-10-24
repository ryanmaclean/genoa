# Packer template creating an Ubuntu-based Vibecode development image

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
  default = "vibecode-ubuntu-dev"
}

variable "iso_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

source "qemu" "vibecode" {
  vm_name          = var.vm_name
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  disk_image       = true
  output_directory = "output-${var.vm_name}"
  shutdown_command = "echo 'ubuntu' | sudo -S shutdown -P now"
  disk_size        = "30G"
  format           = "qcow2"
  accelerator      = "kvm"
  qemu_binary      = "qemu-system-x86_64"
  headless         = true
  cpus             = 4
  memory           = 8192
  use_backing_file = true
  ssh_username     = "ubuntu"
  ssh_password     = "ubuntu"
  ssh_timeout      = "30m"
  ssh_handshake_attempts = 100
  ssh_pty          = true

  cd_files = ["infrastructure/packer/http/user-data", "infrastructure/packer/http/meta-data"]
  cd_label = "cidata"
}

build {
  sources = ["source.qemu.vibecode"]

  # Parallel provisioning for faster builds
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "sudo apt-get update -qq",
      "# Install base packages in parallel",
      "sudo apt-get install -y -qq --no-install-recommends ca-certificates curl git build-essential unzip python3 jq apt-transport-https software-properties-common &",
      "# Setup Node.js repository in parallel",
      "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - &",
      "# Setup Docker repository in parallel",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - &",
      "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' &",
      "wait",
      "sudo apt-get update -qq",
      "# Install all packages in one go for better caching",
      "sudo apt-get install -y -qq nodejs docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo npm install -g pnpm --prefer-offline",
      "sudo systemctl enable docker || true",
      "sudo usermod -aG docker ubuntu"
    ]
    pause_before = "5s"
  }

  provisioner "file" {
    source      = "scripts/vibecode-cli"
    destination = "/tmp/vibecode-cli"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/vibecode",
      "sudo cp -r /tmp/vibecode-cli /opt/vibecode/cli",
      "sudo chmod -R 755 /opt/vibecode/cli",
      "sudo chown -R ubuntu:ubuntu /opt/vibecode"
    ]
  }

  provisioner "shell" {
    inline = [
      "# Aggressive cleanup for smaller image",
      "sudo apt-get autoremove -y",
      "sudo apt-get autoclean",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo rm -rf /tmp/vibecode-cli",
      "sudo rm -rf /var/cache/apt/archives/*",
      "sudo rm -rf /root/.npm",
      "sudo truncate -s 0 /var/log/*log",
      "# Pre-populate npm cache for faster development setup",
      "sudo -u ubuntu npm config set cache /home/ubuntu/.npm-cache",
      "sudo -u ubuntu npm config set prefer-offline true"
    ]
  }

  post-processor "manifest" {
    output = "manifest-vibecode.json"
  }
}

