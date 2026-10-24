# Vibecode Packer Templates

This directory contains automated image builders for Vibecode WebGUI across multiple
platforms, adapting multi-distro patterns to create reproducible development and
production environments.

## Available Templates

### Ubuntu (vibecode-ubuntu.pkr.hcl)
QEMU builder that provisions Ubuntu 24.04 with:
- Node.js 20 LTS
- Docker CE with compose plugin
- Vibecode CLI tools in `/opt/vibecode/cli`
- Cloud-init for rapid deployment

**Use Case**: General-purpose development, cloud deployment, containerized environments

### OpenIndiana (vibecode-openindiana.pkr.hcl)
QEMU builder that provisions OpenIndiana Hipster with:
- ZFS advanced filesystem (snapshots, compression, deduplication)
- DTrace performance analysis probes
- LX-branded zone with Debian 11 userland
- Node.js 24 + PostgreSQL 16 + pgvector
- StatsD bridge for Datadog integration
- Crossbow network virtualization

**Architecture**: x86-64 only (no official ARM64 support)
**Use Case**: Production environments requiring enterprise stability, advanced
observability, and MIT/BSD/Apache licensing (CDDL-compatible)

### OmniOS ARM64 (vibecode-omnios-arm64.pkr.hcl)
QEMU builder that provisions OmniOS CE (experimental ARM64 build) with:
- Native ARM64 architecture (Apple Silicon M1/M2/M3)
- **Debian ARM64 userland via LX-branded zones** (apt/dpkg)
- **code-server (VS Code in browser)** on port 8080
- ZFS advanced filesystem
- DTrace performance analysis
- Zones for OS-level virtualization
- Node.js 24 + PostgreSQL 16 + pgvector
- Hypervisor.framework acceleration on macOS

**Architecture**: ARM64/aarch64 (experimental build)
**Userland**: Debian ARM64 in LX zone (full apt/dpkg ecosystem)
**Use Case**: Apple Silicon Macs requiring native ARM64 performance with illumos/Solaris
stability, Debian packages, ZFS, and DTrace. Browser-based VS Code included.

### OmniOS LX Zone + VibeCode (vibecode-omnios-lx-zone.pkr.hcl) **⭐ RECOMMENDED**
**Fully automated** QEMU builder that provisions OmniOS ARM64 with complete VibeCode deployment:
- **Zero manual intervention** - complete automation in 20-30 minutes
- Native ARM64 architecture (Apple Silicon M1/M2/M3)
- Debian 11 LX-branded zone with full apt/dpkg ecosystem
- Node.js 24 + PostgreSQL 16 + pgvector + Valkey 8.0
- ZFS advanced filesystem with optimized datasets
- Resource-limited zone (4 CPU, 4GB RAM, 2000 processes)
- systemd services configured (not auto-started)
- VibeCode cloned, built, and service-ready

**Architecture**: ARM64/aarch64 (production-ready)
**Automation Level**: 100% - one command, no interaction needed
**Use Case**: Production deployment on Apple Silicon, local development testing, CI/CD pipelines
**Time to Deploy**: 20-30 minutes automated + 2 minutes to start services
**Status**: ✅ Ready for Monday morning deployment

**Quick Start:**
```bash
cd infrastructure/packer
./build-vibecode-omnios.sh  # One command!
```

See: `MONDAY_MORNING_QUICKSTART.md` for complete guide.

## Files

- `vibecode-ubuntu.pkr.hcl` – Ubuntu 24.04 cloud image builder (x86-64)
- `vibecode-openindiana.pkr.hcl` – OpenIndiana Hipster ISO installer (x86-64)
- `vibecode-omnios-arm64.pkr.hcl` – OmniOS CE ARM64 raw image (experimental)
- `vibecode-omnios-lx-zone.pkr.hcl` – **OmniOS ARM64 + LX Zone + VibeCode (fully automated)** ⭐
- `build-vibecode-omnios.sh` – Automated build script with pre-flight checks
- `scripts/create-lx-zone.sh` – LX zone creation automation
- `scripts/install-vibecode-deps.sh` – Dependency installer for LX zone
- `http/user-data`, `http/meta-data` – Cloud-init seed files for Ubuntu

## Usage

### Ubuntu Build

```bash
# Format, initialize, and build Ubuntu image
packer fmt infrastructure/packer/vibecode-ubuntu.pkr.hcl
packer init infrastructure/packer/vibecode-ubuntu.pkr.hcl
packer build infrastructure/packer/vibecode-ubuntu.pkr.hcl
```

**Output**: `output-vibecode-ubuntu-dev/vibecode-ubuntu-dev.qcow2` + `manifest-vibecode.json`

### OpenIndiana Build

**Important**: The OpenIndiana template requires semi-automated installation due to
the text-based installer. For fully automated builds, create an AI (Automated Installer)
manifest following Oracle Solaris 11 documentation patterns.

```bash
# Initialize and build OpenIndiana image
packer init infrastructure/packer/vibecode-openindiana.pkr.hcl

# Build with VNC access for installation monitoring
packer build -var "ssh_password=$OI_ROOT_PASSWORD" infrastructure/packer/vibecode-openindiana.pkr.hcl

# During build, connect to VNC to monitor installation:
# VNC: localhost:5900 (default password: none)
```

**Installation Steps** (when VNC console appears):
1. Select "Text Installer and command line"
2. Choose keyboard layout
3. Select "Use entire disk" for ZFS root pool
4. Set the root password to the value you pass as `-var ssh_password=...` (or `PKR_VAR_ssh_password`)
5. Set hostname: `vibecode-oi`
6. Enable SSH server
7. Wait for installation to complete and reboot
8. Packer will automatically connect via SSH and provision

**Output**: `output-vibecode-openindiana/vibecode-openindiana.qcow2` +
`manifest-vibecode-openindiana.json`

### OmniOS ARM64 Build

**Note**: Experimental ARM64 build for Apple Silicon native performance.

```bash
# Initialize
packer init infrastructure/packer/vibecode-omnios-arm64.pkr.hcl

# Build (native ARM64 on Apple Silicon)
packer build infrastructure/packer/vibecode-omnios-arm64.pkr.hcl
```

**Features**:
- Native ARM64 execution (no emulation)
- Debian ARM64 userland in LX zone
- code-server (VS Code) at http://localhost:8080 (password: vibecode)
- Hypervisor.framework acceleration
- VNC on port 5901 for monitoring
- Faster than x86_64 emulation

**Output**: `output-vibecode-omnios-arm64/vibecode-omnios-arm64.qcow2` +
`manifest-vibecode-omnios-arm64.json`

**After Build**:
- Access code-server: http://localhost:8080 (password: vibecode)
- SSH to VM: ssh -p 2222 root@localhost
- Login to Debian zone: zlogin vibecode-zone

### OmniOS LX Zone + VibeCode Build (Fully Automated)

**⭐ Recommended for production deployment and Monday morning quick-start.**

```bash
# One-command build (20-30 minutes)
cd infrastructure/packer
./build-vibecode-omnios.sh
```

**What happens automatically:**
1. ✅ Pre-flight validation (QEMU, Packer, base image)
2. ✅ Boot OmniOS ARM64
3. ✅ Configure ZFS datasets (compression, optimization)
4. ✅ Download Debian 11 LX zone image
5. ✅ Create zone with resource limits
6. ✅ Install Node.js 24 + PostgreSQL 16 + Valkey 8.0
7. ✅ Deploy VibeCode application
8. ✅ Configure systemd services
9. ✅ Create production-ready VM image

**Output**: `output-vibecode-omnios-lx/vibecode-omnios-arm64` (qcow2, ~5-8GB)

**Launch the built VM:**
```bash
qemu-system-aarch64 \
  -machine virt -cpu host -accel hvf \
  -smp 4 -m 8192 \
  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive file=output-vibecode-omnios-lx/vibecode-omnios-arm64,if=virtio,format=qcow2 \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000 \
  -nographic
```

**Start VibeCode (inside VM):**
```bash
zlogin vibecode
systemctl start postgresql valkey vibecode
# Access: http://localhost:3000
```

**See also**: `MONDAY_MORNING_QUICKSTART.md` for complete quick-start guide.

### Using Built Images

**QEMU/KVM**:
```bash
qemu-system-x86_64 \
  -m 8G -smp 4 -cpu host -enable-kvm \
  -drive file=output-vibecode-ubuntu-dev/vibecode-ubuntu-dev.qcow2,if=virtio \
  -net nic,model=virtio -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000
```

**libvirt**:
```bash
# Import to libvirt
virsh vol-create-as default vibecode-ubuntu-dev.qcow2 30G --format qcow2
virsh vol-upload --pool default vibecode-ubuntu-dev.qcow2 \
  output-vibecode-ubuntu-dev/vibecode-ubuntu-dev.qcow2
```

**Lima** (macOS):
```yaml
# ~/.lima/vibecode/lima.yaml
images:
  - location: "/path/to/output-vibecode-ubuntu-dev/vibecode-ubuntu-dev.qcow2"
    arch: "x86_64"
cpus: 4
memory: "8GiB"
```

## Customization

### Variables

Both templates support customization via variables:

**Ubuntu**:
```bash
packer build \
  -var 'vm_name=vibecode-custom' \
  -var 'iso_url=https://...' \
  infrastructure/packer/vibecode-ubuntu.pkr.hcl
```

**OpenIndiana**:
```bash
packer build \
  -var 'zone_cpus=8' \
  -var 'zone_memory=16G' \
  -var 'disk_size=100G' \
  infrastructure/packer/vibecode-openindiana.pkr.hcl
```

### Extending

**Add provisioners** to preload the Vibecode repository:
```hcl
provisioner "shell" {
  inline = [
    "git clone https://github.com/your-org/vibecode-webgui.git /workspace/vibecode",
    "cd /workspace/vibecode && npm install"
  ]
}
```

**Add Playwright** for E2E testing:
```hcl
provisioner "shell" {
  inline = [
    "npx playwright install --with-deps chromium firefox webkit"
  ]
}
```

**ARM64 builders** – Duplicate the template and adapt:
```hcl
source "qemu" "vibecode-arm64" {
  qemu_binary = "qemu-system-aarch64"
  machine_type = "virt"
  cpu_type = "cortex-a57"
  qemuargs = [["-bios", "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"]]
}
```

## Platform Comparison

| Feature | Ubuntu | OpenIndiana | OmniOS ARM64 |
|---------|--------|-------------|--------------|
| **Architecture** | x86-64 | x86-64 | ARM64 (native) |
| **Filesystem** | ext4 | ZFS (snapshots, compression) | ZFS (snapshots, compression) |
| **Observability** | SystemTap, perf | DTrace (native) | DTrace (native) |
| **Containers** | Docker, containerd | LX zones (OS virtualization) | LX zones (OS virtualization) |
| **Package Mgmt** | APT (native) | APT (in zone) + IPS (host) | APT (in zone) + IPS (host) |
| **code-server** | Not included | Not included | Included (port 8080) |
| **Boot Time** | ~15s | ~20s (zone boot included) | ~18s |
| **Licensing** | GPL | CDDL (MIT/BSD-compatible) | CDDL (MIT/BSD-compatible) |
| **Apple Silicon** | Emulated (slow) | Emulated (slow) | Native (fast) |
| **Use Case** | Cloud, dev | Production, compliance | Apple Silicon dev |

## Automated Installer (OpenIndiana)

For fully automated OpenIndiana builds without VNC interaction, create an AI manifest:

```xml
<!DOCTYPE auto_install SYSTEM "file:///usr/share/install/ai.dtd.1">
<auto_install>
  <ai_instance name="vibecode-oi">
    <target>
      <disk whole_disk="true" in_zpool="rpool"/>
    </target>
    <software type="IPS">
      <destination>
        <image>
          <facet set="false">facet.doc.*</facet>
        </image>
      </destination>
      <software_data action="install">
        <name>pkg:/group/system/solaris-large-server</name>
        <name>pkg:/brand/lx</name>
      </software_data>
    </software>
  </ai_instance>
</auto_install>
```

Then reference in Packer with `boot_command` and `http_directory`.

## Troubleshooting

**VNC connection refused**:
- Check `vnc_port_min/max` in template
- Verify firewall allows port 5900
- Try `headless = false` for GUI display

**SSH timeout**:
- Increase `ssh_timeout` to `90m` for slower installations
- Verify SSH is enabled in installer
- Check VNC console for installation errors

**OpenIndiana zone fails**:
- Verify LX brand installed: `pkg list brand/lx`
- Check zone status: `zoneadm list -v`
- Review zone logs: `/var/log/zones/vibecode-zone.log`

**Build fails with "disk full"**:
- Increase `disk_size` variable
- Run cleanup provisioner earlier
- Disable debug/development packages

## See Also

- [OpenIndiana Platform Guide](https://github.com/ryanmaclean/vibecode-webgui/blob/129302a73be9719d213561116319d13ed679fd71/docs/src/content/docs/platforms/openindiana.md)
- [Datadog OpenIndiana Integration](https://github.com/ryanmaclean/vibecode-webgui/blob/129302a73be9719d213561116319d13ed679fd71/docs/src/content/docs/platforms/datadog-openindiana.md)
- [Vibecode CLI Documentation](https://github.com/ryanmaclean/vibecode-webgui/blob/129302a73be9719d213561116319d13ed679fd71/scripts/VIBECODE_CLI.md)
- [Upstream ZFS Packer Templates](https://github.com/DataDog/integrations-core/tree/master/zfs_linux)
