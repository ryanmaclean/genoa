# Path 4: Rescue + Chroot Fixup

**Priority: 4 — variant of Path 3 for providers without IMDS or with cloud-init expectations**

## Summary

Identical to Path 3 up through the `dd` step. After writing the raw image to
disk, instead of rebooting immediately, mount the target OS's root filesystem
and inject provider-specific configuration: SSH authorized keys, hostname,
IMDS shim, network config. Then reboot.

Use this path when:
- The provider doesn't expose an IMDS endpoint that the BSD agent can query
- The provider delivers SSH keys only via IMDS (and genoa's BSD doesn't have
  a working IMDS client for that provider yet)
- The provider expects cloud-init to have run (some providers check for
  `/var/lib/cloud/instance/boot-finished`)

## Works for

Same provider set as Path 3, plus providers where cloud-init is expected:

| Provider | Extra fixup needed | Notes |
|----------|-------------------|-------|
| Hetzner Cloud | SSH key injection | Hetzner delivers keys via IMDS (169.254.169.254) — BSD agent must support it OR we inject via chroot |
| Scaleway | Hostname + SSH keys | Scaleway IMDS at 169.254.42.42 — non-standard path |
| Vultr | SSH keys | Vultr IMDS at 169.254.169.254 with `/latest/user-data` |
| DigitalOcean | SSH keys + networking | DO uses cloud-init + IMDS |
| OVHcloud | SSH keys | |
| Exoscale | SSH keys + cloud-init stub | |

## Chroot procedure (BSD rootfs)

```sh
# After dd from Path 3, do NOT reboot yet
# 1. Read partition table
TARGET="/dev/sda"
partprobe "$TARGET" 2>/dev/null || kpartx -a "$TARGET"

# Detect ESP and root partitions (GPT layout from Genoa-A)
# Partition 1 = ESP (FAT32), Partition 2 = root (UFS or ZFS or FFS)
ROOT_PART="${TARGET}2"

# 2. Mount BSD root — use appropriate FS type
# For FreeBSD UFS2:
mkdir -p /mnt/genoa
mount -t ufs -o ro,ufstype=ufs2 "$ROOT_PART" /mnt/genoa 2>/dev/null || \
  mount -t ufs2 "$ROOT_PART" /mnt/genoa  # some rescue kernels use ufs2

# NOTE: ZFS roots cannot be mounted from rescue Linux without importing the pool.
# If Genoa-A uses ZFS, use zpool import -R /mnt/genoa then zfs mount -a.
# For ZFS: rescue Linux must have zfsutils-linux installed or loaded.

# 3. Inject SSH authorized_keys
PROVIDER_SSH_KEYS=$(curl -fSL http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key 2>/dev/null || echo "")
if [ -n "$PROVIDER_SSH_KEYS" ]; then
  mkdir -p /mnt/genoa/root/.ssh
  echo "$PROVIDER_SSH_KEYS" >> /mnt/genoa/root/.ssh/authorized_keys
  chmod 700 /mnt/genoa/root/.ssh
  chmod 600 /mnt/genoa/root/.ssh/authorized_keys
fi

# 4. Set hostname
HOSTNAME=$(curl -fSL http://169.254.169.254/latest/meta-data/hostname 2>/dev/null || echo "genoa-host")
echo "$HOSTNAME" > /mnt/genoa/etc/hostname
# FreeBSD uses /etc/rc.conf hostname= line:
sed -i "s/^hostname=.*/hostname=\"${HOSTNAME}\"/" /mnt/genoa/etc/rc.conf || \
  echo "hostname=\"${HOSTNAME}\"" >> /mnt/genoa/etc/rc.conf

# 5. Inject network config if provider uses static addressing
# (DHCP on vtnet0 is usually fine — skip if DHCP)

# 6. Place IMDS shim if needed (e.g., a rc.local script that queries IMDS at first boot)
# This is provider-specific — see genoa/shims/ directory.

# 7. Unmount
umount /mnt/genoa
sync
```

## cloud-init gotcha (IMPORTANT)

The docs-first reflex flagged this: if the BSD image ships with cloud-init
(unusual but possible for some Linux-BSD hybrids or test images):

**cloud-init's NoCloud datasource caches per-instance-id.** Bumping
`instance-id` in `/var/lib/cloud/instance/` does NOT always invalidate the
cache. The reliable way to force re-run is:

```sh
# In chroot (BSD):
rm -rf /mnt/genoa/var/lib/cloud/instances/*
rm -f  /mnt/genoa/var/lib/cloud/instance
```

For BSD images that use RC scripts instead of cloud-init (the genoa default),
this is irrelevant — there is no cloud-init cache to worry about.

## Scaleway non-standard IMDS

Scaleway's IMDS is at `http://169.254.42.42/` (not the AWS-standard `.169.254`).
The path structure also differs:

```sh
# Scaleway SSH keys
curl http://169.254.42.42/conf | grep SSH_PUBLIC_KEYS
# or
curl http://169.254.42.42/user_data/SSH_PUBLIC_KEYS
```

Any BSD IMDS agent must handle Scaleway's non-standard endpoint. The chroot
fixup can inject a shim that sets the correct URL.

## ZFS root complication

If Genoa-A produces ZFS root images (likely for FreeBSD), mounting from rescue
Linux requires:

```sh
# In rescue Linux:
apt-get install -y zfsutils-linux  # or modprobe zfs
zpool import -f -R /mnt/genoa genoa  # import pool named 'genoa'
zfs mount -a
# ... do fixups ...
zfs unmount -a
zpool export genoa
```

The pool name must be known in advance. Genoa-A should use a deterministic pool
name (e.g., `zroot` following FreeBSD convention).

**Risk**: ZFS feature flags between rescue Linux (OpenZFS version) and the
BSD image's pool may differ. Rescue Linux may refuse to import a pool with
newer feature flags. Mitigation: use a conservative OpenZFS feature set in
Genoa-A's pool creation.

## Implementation effort

**Medium-high.** Requires:
1. All of Path 3 (rescue boot, dd)
2. Per-provider IMDS URL knowledge (hardcoded table)
3. FS mounting logic (UFS2 vs ZFS branch)
4. Per-provider SSH key injection format
5. Chroot cleanup and unmount
6. Reboot

This is roughly twice the code of Path 3.

## License traps

- Same as Path 3: dd, curl, mount — system tools in rescue Linux
- `zfsutils-linux`: CDDL-1.0 — invoked as subprocess in rescue, not vendored. Clean.
- **No iPXE**
- Rust `ssh2` crate (for SSH session management): MIT — clean

## References

- Hetzner Cloud IMDS: https://docs.hetzner.com/cloud/servers/metadata-service/
- Scaleway IMDS: https://www.scaleway.com/en/developers/api/metadata/
- Vultr IMDS: https://www.vultr.com/docs/vultr-metadata-v1-2/
- FreeBSD ZFS pool naming: https://docs.freebsd.org/en/books/handbook/zfs/
- OpenZFS feature flags: https://openzfs.github.io/openzfs-docs/man/8/zpool-features.8.html
