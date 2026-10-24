# Packer template for macOS vfkit-based VibeCode development image
# Creates macOS VM with vfkit using Apple's Virtualization Framework
#
# ARCHITECTURE: ARM64/aarch64 (Apple Silicon M1/M2/M3/M4)
# DISTRIBUTION: macOS (latest supported version)
# VIRTUALIZATION: vfkit (Apple's Virtualization Framework)
#
# Architecture Stack:
# ┌─────────────────────────────────────┐
# │   VibeCode Application              │
# │   (Node.js 24 + PostgreSQL + Redis) │
# ├─────────────────────────────────────┤
# │   macOS Guest OS                    │
# │   - Homebrew package management     │
# │   - Native macOS development tools  │
# ├─────────────────────────────────────┤
# │   vfkit (Apple Virtualization)     │
# │   - Native ARM64 performance        │
# │   - Hardware acceleration           │
# └─────────────────────────────────────┘

packer {
  required_plugins {
    # No additional plugins required - using built-in provisioners
  }
}

variable "vm_name" {
  type    = string
  default = "vibecode-macos-vfkit"
}

variable "macos_version" {
  type    = string
  default = "14.0"
  description = "macOS version to install"
}

variable "vm_memory" {
  type    = number
  default = 8192
  description = "VM memory in MiB"
}

variable "vm_cpus" {
  type    = number
  default = 4
  description = "Number of vCPUs"
}

variable "disk_size" {
  type    = string
  default = "64G"
  description = "VM disk size"
}

variable "output_directory" {
  type    = string
  default = "output-vibecode-macos-vfkit"
}

# Custom vfkit builder using null builder with vfkit provisioner
source "null" "vfkit-macos" {
  communicator = "none"
}

build {
  sources = ["source.null.vfkit-macos"]

  # Use shell provisioner for vfkit
  provisioner "shell-local" {
    script = "scripts/packer-vfkit-provisioner.sh"
    environment_vars = [
      "VM_NAME=${var.vm_name}",
      "VM_MEMORY=${var.vm_memory}",
      "VM_CPUS=${var.vm_cpus}",
      "DISK_SIZE=${var.disk_size}",
      "MACOS_VERSION=${var.macos_version}",
      "OUTPUT_DIR=${var.output_directory}"
    ]
  }

  # Post-processing: Create deployment package
  post-processor "shell-local" {
    inline = [
      "echo 'Creating deployment package...'",
      "cd ${var.output_directory}",
      "tar -czf ${var.vm_name}-$(date +%Y%m%d).tar.gz vm-files/",
      "echo 'Deployment package created: ${var.vm_name}-$(date +%Y%m%d).tar.gz'"
    ]
  }
}
