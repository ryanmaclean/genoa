#!/usr/bin/env nu
# profiles/netbsd.nu — NetBSD image build profile (planning stub)
# NetBSD 10.x cloud image generation plan
# Status: dry-run plan only — real builds require cross-build toolchain (nbmake)
# SPDX-License-Identifier: BSD-2-Clause

export def netbsd_build [manifest: record, dry_run: bool = false] {
  let hostname    = $manifest.network?.hostname?  | default "smolnetbsd"
  let image_size  = $manifest.image?.size_mb?     | default 2048
  let image_size_arg = ($image_size | into string) + "M"
  let image_name  = $manifest.image?.name?        | default "genoa-netbsd"
  let image_version = $manifest.image?.version?   | default "v0.0.0"
  let output_dir  = $manifest.image?.output_dir?  | default "./out"
  let image_path  = $"($output_dir)/($image_name)-($image_version).raw"
  let os_ver      = $manifest.target?.os_version? | default "10.0"
  let arch        = $manifest.target?.arch?       | default "amd64"
  let nbsd_arch   = match $arch {
    "amd64"   => "amd64"
    "aarch64" => "evbarm-aarch64"
    _         => "amd64"
  }
  let base_url    = $"https://cdn.netbsd.org/pub/NetBSD/NetBSD-($os_ver)/($nbsd_arch)/"

  {
    schema_version: "v1"
    profile: "netbsd"
    dry_run: true  # always dry-run — real build requires nbmake cross-compile
    status: "planning-stub"
    note: "NetBSD builds require the nbmake cross-build toolchain. This profile generates the build plan only."
    steps: [
      {step: 1  label: "create_disk"         action: "would-run" cmd: $"truncate -s ($image_size_arg) ($image_path)"}
      {step: 2  label: "partition_mbr"       action: "would-run" cmd: $"fdisk -i ($image_path)" note: "NetBSD uses MBR by default on amd64"}
      {step: 3  label: "disklabel"           action: "would-run" cmd: "disklabel -e" note: "Add partition a (root), b (swap), d (whole disk)"}
      {step: 4  label: "newfs_root"          action: "would-run" cmd: "newfs /dev/vnd0a" note: "NetBSD FFS2 root"}
      {step: 5  label: "mount_root"          action: "would-run" cmd: "mount /dev/vnd0a /mnt"}
      {step: 6  label: "fetch_sets"          action: "would-run" cmd: $"ftp -o /tmp/sets ($base_url)kern-GENERIC.tgz" note: "Fetch NetBSD release sets: kern-GENERIC, base, etc"}
      {step: 7  label: "extract_sets"        action: "would-run" cmd: "cd /mnt && tar -xzf /tmp/sets/kern-GENERIC.tgz && tar -xzf /tmp/sets/base.tgz"}
      {step: 8  label: "configure_fstab"     action: "would-run" cmd: "echo '/dev/wd0a / ffs rw 1 1' > /mnt/etc/fstab"}
      {step: 9  label: "configure_rc_conf"   action: "would-run" cmd: $"echo 'hostname=($hostname)' > /mnt/etc/rc.conf && echo 'dhcpcd=YES' >> /mnt/etc/rc.conf && echo 'sshd=YES' >> /mnt/etc/rc.conf"}
      {step: 10 label: "install_bootloader"  action: "would-run" cmd: "installboot -v -o timeout=3 /dev/rvnd0 /usr/mdec/bootxx_ffsv2"}
      {step: 11 label: "copy_agent"          action: "would-run" cmd: "cp <agent_binary> /mnt/usr/local/bin/ii-agent" note: "Agent binary must be NetBSD amd64 or aarch64"}
      {step: 12 label: "umount"              action: "would-run" cmd: "umount /mnt"}
      {step: 13 label: "emit_receipt"        action: "real"      description: "Compute sha256 and emit receipt.json"}
    ]
    image_path: $image_path
    base_url: $base_url
    build_requirements: [
      "NetBSD or cross-build host with nbmake"
      "NetBSD release sets for target arch"
      "vnd(4) driver for disk image manipulation"
      "Agent binary built for NetBSD (pkgsrc: devel/ii-agent or manual build)"
    ]
  }
}
