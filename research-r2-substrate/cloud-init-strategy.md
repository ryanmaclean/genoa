# genoa Cloud-Init Strategy

## Problem Statement

Cloud providers inject per-instance configuration (SSH keys, hostname, network
config, user-data scripts) via a metadata service or a seed disk. The guest OS
needs an agent to read this metadata on first boot and apply it. This agent
is traditionally cloud-init (or a subset equivalent).

genoa must handle four OS families with different maturity levels:
- FreeBSD 15: cloud-init port available, dual-licensed
- NetBSD 11: no cloud-init port; manual alternatives only
- OpenBSD 7.6: no official cloud-init; community tool available
- Linux 6.x: cloud-init native, full support

---

## cloud-init License Determination

**cloud-init project license**: Dual-licensed **GPL-3 OR Apache-2.0**  
Source: FreshPorts net/cloud-init confirms `LICENSES: APACHE20 GPLv3`

**genoa chooses Apache-2.0** when consuming cloud-init. Under the dual-license,
the consumer may elect either license. Apache-2.0 is on genoa's allowed list;
GPL-3 is not. Electing Apache-2.0 means:
- genoa may package and distribute cloud-init
- No copyleft obligations on genoa's own image-build tooling
- Attribution required (NOTICE file)

**This applies to**: FreeBSD's `net/cloud-init` port, the upstream Python package,
and any cloud-init usage in genoa's Linux control images.

**Legal caveat**: The dual-license "OR" means the copyright holder grants both;
you choose which terms bind you. This is a standard dual-license grant. If this
interpretation is ever challenged, consult a lawyer — but the prevailing
community understanding is that dual GPL/Apache packages may be used under
Apache-2.0 alone.

---

## cloud-init Cache Behavior — Critical Gotchas

### First-boot detection

cloud-init determines "first boot" by comparing the **instance-id** from the
current metadata source against the cached instance-id stored in
`/var/lib/cloud/instances/<instance-id>/`. If they differ: first boot. If they
match: subsequent boot.

### The NoCloud datasource cache trap (documented upstream)

From upstream docs: *"If you are making updates to user-data you will also have
to change the `instance-id`, or start the disk fresh."*

**The trap**: Bumping `instance-id` triggers re-provisioning ONLY in the default
"check" cache mode. If `manual_cache_clean: true` is set in cloud-init config
(trust mode), instance-id changes are ignored and the only way to force
re-provisioning is `cloud-init clean` (which wipes `/var/lib/cloud/`).

### Image build requirement (CRITICAL)

Before capturing a cloud image for distribution, genoa's build pipeline MUST run:

```sh
cloud-init clean --logs --seed --machine-id
```

Or equivalently wipe manually:
```sh
rm -rf /var/lib/cloud/
rm -f /etc/machine-id          # Linux; systemd-based
truncate -s 0 /etc/machine-id  # preferred: zero-length triggers regeneration
```

**Failure to clean** before image capture means every instance launched from the
image shares the same cached instance-id from the build VM. cloud-init will
detect "not first boot" on every new instance and refuse to apply SSH keys,
hostname, or user-data. This is also a security risk: SSH host keys won't
rotate (cloud-init rotates them on first boot by default).

### trust mode warning

Do NOT set `manual_cache_clean: true` in genoa base images. This disables the
instance-id comparison and makes manual cache clearing the only re-run trigger.
It is intended for "baked" images where the operator controls re-provisioning
entirely. For genoa general-purpose cloud images, use the default check mode.

---

## FreeBSD 15: cloud-init Strategy

### Option A: Full cloud-init (recommended for AWS/GCP/Azure)

**Port**: `net/cloud-init` (FreshPorts), version 25.2_1 as of April 2026  
**License**: Apache-2.0 (elect this; see above)  
**Python deps**: python3.11, pyyaml, jinja2, jsonschema, requests, oauthlib, etc.

**Install**:
```sh
pkg install cloud-init
```

**Enable**:
```sh
sysrc cloudinit_enable="YES"
```

**Supported datasources on FreeBSD** (from cloud-init distros/freebsd.py):
- AWS EC2 (IMDS v1 + v2)
- GCP (metadata.google.internal)
- Azure (IMDS + CDROM config drive)
- OpenStack / Config-Drive
- NoCloud (cidata labeled disk or seedfrom URL)
- Oracle Cloud (OCI)
- Hetzner
- Vultr
- DigitalOcean

**AWS IMDS v2 note**: cloud-init 23.x+ defaults to IMDSv2 (token-based). Ensure
the EC2 instance allows IMDSv2 (it does by default on Nitro). If testing with
IMDSv1-only environments, set `datasource_list: [Ec2]` and
`datasource.Ec2.strict_id: false` in cloud-init config.

**FreeBSD-specific behaviors**:
- Network config written to `/etc/rc.conf` (not netplan/NetworkManager)
- SSH keys written to `/root/.ssh/authorized_keys` and user home dirs
- hostname set via `hostname(1)` and `/etc/rc.conf`

**nuageinit**: FreeBSD 14.1+ ships `nuageinit(7)` as a lightweight alternative.
It supports config-drive (OpenStack/cidata format) and is part of base — no
Python dependency. License: BSD-2-Clause. However, it only supports a subset of
datasources (config-drive / NoCloud; no AWS IMDS, no GCP metadata). For
multi-cloud genoa images, use full cloud-init. Use nuageinit only for
OpenStack/private cloud where config-drive is guaranteed.

```sh
# nuageinit enable (for OpenStack/private cloud only)
sysrc nuageinit_enable="YES"
```

### Option B: Shell script + IMDS curl (minimal, no Python)

For agent images where Python overhead is unacceptable:

```sh
#!/bin/sh
# /etc/rc.d/firstboot — minimal first-boot metadata fetch
# Run once; sets hostname + SSH keys from provider IMDS

IMDS_BASE="http://169.254.169.254"

# Detect provider by trying IMDS endpoints
if fetch -q -o - "${IMDS_BASE}/latest/meta-data/instance-id" > /dev/null 2>&1; then
  PROVIDER=aws
elif fetch -q -o - "http://metadata.google.internal/computeMetadata/v1/" \
     -H "Metadata-Flavor: Google" > /dev/null 2>&1; then
  PROVIDER=gcp
fi

case "$PROVIDER" in
  aws)
    # AWS IMDSv2: get token first
    TOKEN=$(fetch -q -o - -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
            --method PUT "${IMDS_BASE}/latest/api/token")
    HOSTNAME=$(fetch -q -o - -H "X-aws-ec2-metadata-token: ${TOKEN}" \
               "${IMDS_BASE}/latest/meta-data/hostname")
    PUBKEY=$(fetch -q -o - -H "X-aws-ec2-metadata-token: ${TOKEN}" \
             "${IMDS_BASE}/latest/meta-data/public-keys/0/openssh-key")
    ;;
  gcp)
    HOSTNAME=$(fetch -q -o - -H "Metadata-Flavor: Google" \
               "http://metadata.google.internal/computeMetadata/v1/instance/hostname")
    PUBKEY=$(fetch -q -o - -H "Metadata-Flavor: Google" \
             "http://metadata.google.internal/computeMetadata/v1/project/attributes/ssh-keys")
    ;;
esac

hostname "$HOSTNAME"
echo "hostname=\"${HOSTNAME}\"" >> /etc/rc.conf
mkdir -p /root/.ssh
echo "$PUBKEY" >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# Mark done — do not re-run
touch /var/db/firstboot.done
```

This approach has no Python dependency, no GPL risk, and works on FreeBSD out of
the box with `fetch(1)`. Limitations: no user-data script support, no network
config management, AWS only + GCP only detection.

---

## NetBSD 11: cloud-init Strategy

**cloud-init official support**: NetBSD is listed as supported in cloud-init's
distro abstraction (`cloudinit/distros/netbsd.py`) as of cloud-init 23.x+.
However, **there is no NetBSD package in pkgsrc** as of April 2026. The Python
ecosystem on NetBSD is present but the cloud-init port is not maintained.

**Recommendation**: Shell script + IMDS curl (same pattern as FreeBSD Option B
above, adapted for NetBSD's `ftp(1)` as HTTP client).

```sh
# NetBSD uses ftp(1) for HTTP fetching (not curl, not fetch)
PUBKEY=$(ftp -o - "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key")
```

**Alternative**: Use the `nuageinit` approach from FreeBSD — port the logic or
write a NetBSD-compatible shell firstboot script. The OpenStack config-drive
(ISO9660 labeled `cidata`) is the most portable approach — no IMDS needed,
works by mounting a labeled disk.

**Config-drive (NoCloud) strategy for NetBSD**:

1. Provider attaches an ISO9660 or VFAT disk labeled `cidata` containing:
   - `meta-data` (YAML: instance-id, hostname)
   - `user-data` (cloud-config or shell script)
   - `network-config` (optional)

2. NetBSD firstboot script mounts the `cidata` disk and reads the files:

```sh
#!/bin/sh
# /etc/rc.d/firstboot for NetBSD (config-drive / NoCloud)
for dev in /dev/cd0a /dev/sd1a /dev/ld1a; do
  if mount -t cd9660 -o ro "$dev" /mnt 2>/dev/null; then
    CIDATA_MNT=/mnt
    break
  fi
done

# Also try VFAT label "cidata"
if [ -z "$CIDATA_MNT" ]; then
  for dev in /dev/sd1e /dev/ld1e; do
    if mount -t msdos -o ro "$dev" /mnt 2>/dev/null; then
      CIDATA_MNT=/mnt
      break
    fi
  done
fi

if [ -n "$CIDATA_MNT" ] && [ -f "${CIDATA_MNT}/meta-data" ]; then
  # Parse hostname from meta-data (minimal YAML: "local-hostname: foo")
  HOSTNAME=$(grep local-hostname "${CIDATA_MNT}/meta-data" | awk '{print $2}')
  hostname "$HOSTNAME"
  # Apply SSH keys from user-data if present
  # ... (provider-specific parsing)
  umount "$CIDATA_MNT"
fi
touch /var/db/firstboot.done
```

**Known gap**: NetBSD has no AWS ENA driver and no GCP gVNIC driver, making it
non-viable for modern AWS Nitro or GCP ARM instances regardless of cloud-init
strategy.

---

## OpenBSD 7.6: cloud-init Strategy

**Official cloud-init support**: OpenBSD is listed in cloud-init's distro
abstraction but the official cloud-init package does not exist in OpenBSD ports.

**Option A: exoscale/openbsd-cloud-init** (MIT license)  
Source: https://github.com/exoscale/openbsd-cloud-init  
**Limitation**: Only works in KVM + virtio environments where metadata is served
from the same IP (169.254.169.254). Works for Exoscale, some OpenStack setups.
Does NOT support: AWS Nitro ENA (no driver), Azure (no Hyper-V driver), GCP.

**Option B: arpnetworks/openbsd-cloud-init** (MIT license)  
Source: https://github.com/arpnetworks/openbsd-cloud-init  
Uses NoCloud config-disk (ISO9660 `cidata`) approach. Provider-independent as
long as a `cidata` disk is attached.

**Option C: OpenBSD's built-in autoinstall / firstboot framework**  
OpenBSD 6.9+ has `firstboot(8)` which runs scripts from `/etc/firstboot.d/`
on first boot. This is BSD-native (ISC license) and requires the operator to
place scripts there. Combines with a config-drive reader script.

```sh
# /etc/firstboot.d/10-cloud-keys.sh
#!/bin/sh
# Read SSH keys from NoCloud cidata disk
for dev in /dev/cd0c /dev/sd1c; do
  mount -t cd9660 -o ro "$dev" /mnt 2>/dev/null && break
done
if [ -d /mnt ]; then
  grep ssh-authorized-keys /mnt/meta-data | \
    sed 's/.*ssh-authorized-keys: //' >> /root/.ssh/authorized_keys
  umount /mnt
fi
```

**Recommendation for genoa OpenBSD images**: Use Option C (`firstboot(8)`) with
a custom config-drive reader. This is BSD-native, no external dependencies, no
GPL risk. Accept the limitation that only config-drive (NoCloud) and OpenBSD
vmm/vmd environments are fully supported. AWS and Azure are unsupported due to
missing network drivers.

---

## Provider Metadata API Reference

| Provider | IMDS Base URL | Auth Header | Key Endpoint |
|---|---|---|---|
| AWS EC2 | `http://169.254.169.254/latest/` | IMDSv2: `X-aws-ec2-metadata-token` (PUT first) | `/meta-data/public-keys/0/openssh-key` |
| GCP | `http://metadata.google.internal/computeMetadata/v1/` | `Metadata-Flavor: Google` | `/project/attributes/ssh-keys` |
| Azure | `http://169.254.169.254/metadata/instance?api-version=2021-02-01` | `Metadata: true` | JSON body `.compute.publicKeys` |
| DigitalOcean | `http://169.254.169.254/metadata/v1/` | None | `/public-keys` |
| Hetzner | `http://169.254.169.254/hetzner/v1/metadata` | None | YAML body |
| OCI | `http://169.254.169.254/opc/v2/instance/` | `Authorization: Bearer Oracle` | `/metadata/` |
| OpenStack | `http://169.254.169.254/openstack/latest/` | None | `/meta_data.json` |
| NoCloud/config-drive | ISO9660 or VFAT disk labeled `cidata` | N/A | `/meta-data`, `/user-data` |

---

## Image Build Pipeline: Required Pre-Capture Steps

These steps MUST run before capturing/exporting a genoa cloud image, regardless
of OS:

```sh
# FreeBSD
cloud-init clean --logs --seed    # if cloud-init installed
rm -f /var/db/firstboot.done      # if using custom firstboot script
# Zero-fill free space (optional, reduces image size after compression):
dd if=/dev/zero of=/ZERO bs=1M 2>/dev/null; rm /ZERO

# NetBSD
rm -f /var/db/firstboot.done
# equivalent cleanup

# OpenBSD
rm -f /etc/firstboot.d/.done      # if firstboot(8) tracks completion
```

**SSH host key rotation**: cloud-init handles this on first boot (deletes and
regenerates `/etc/ssh/ssh_host_*`). For the shell-script approach on NetBSD/
OpenBSD, add to the firstboot script:

```sh
rm -f /etc/ssh/ssh_host_*
/usr/sbin/sshd -t  # will regenerate on next sshd start
# Or:
ssh-keygen -A       # regenerate all host key types
```

**machine-id** (Linux only): `truncate -s 0 /etc/machine-id` — ensures a new
machine-id is generated on first boot.

---

## Summary Decision Matrix

| OS | Agent | License | Multi-Cloud? | Limitation |
|---|---|---|---|---|
| FreeBSD 15 | cloud-init (elect Apache-2.0) | Apache-2.0 | YES (AWS/GCP/Azure/OCI/DO/HZ) | Python dep; no nuageinit for AWS |
| FreeBSD 15 (minimal) | nuageinit (base) | BSD-2 | NO — config-drive only | OpenStack/private cloud only |
| FreeBSD 15 (agent) | Shell + IMDS curl | BSD-2 (script) | PARTIAL — per-provider | No user-data; no network config |
| NetBSD 11 | Shell + cidata mount | BSD-2 (script) | PARTIAL — config-drive only | No AWS/GCP/Azure driver support anyway |
| OpenBSD 7.6 | firstboot(8) + cidata | ISC + BSD-2 | NO — config-drive + KVM only | No AWS/GCP/Azure driver support |
| Linux 6.x | cloud-init (Apache-2.0) | Apache-2.0 | YES (all providers) | Full support; elect Apache-2.0 |
