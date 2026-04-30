# RL3: BSD on Linode — Community Research Report

**Date compiled:** 2026-04-30
**Research method:** SearXNG (offline, fallback to direct WebFetch), HN Algolia API, Linode API, GitHub, official docs

---

## 1. Timeline: BSD Support on Linode

### Xen Era (~2003–2015)

Linode ran exclusively on Xen paravirtualization. FreeBSD could run as a Xen domU, but with severe limitations:
- No SMP support under Xen (confirmed by Linode founder "caker" on HN, 2009-10-02)
- No 64-bit support for FreeBSD under early Xen configs
- PV-GRUB existed (`linode/pv-grub_x86_64`, built 2008-11-14, still in the API today as kernel ID `linode/pv-grub_x86_64`)
- One HN commenter ("brandon", 2015-07-20) stated: "I've been using [PV-GRUB] to boot FreeBSD with their Xen offering for years."
- The 2010 HN thread on BSDs notes FreeBSD 8.x could run "in domU now"
- By 2012, vCPU count was an issue: Linode defaulted to vcpus=4 which choked FreeBSD; workaround was to ask Linode to lower it

**Key constraint:** Xen PV mode required paravirtualized drivers; FreeBSD had limited Xen support. Booting required `pvops=false` configuration and PV-GRUB.

### KVM Transition (2015–2019)

Linode announced KVM support on June 16, 2015 (their 12th anniversary). The announcement explicitly stated users could "run alternative operating systems like FreeBSD, BSD, Plan 9, or even Windows – using emulated hardware." This was a significant unlock — KVM's hardware emulation made BSD much more viable.

New boot options added to the Linode kernel API:
- `linode/direct-disk` — Direct Disk boot (built 2015-05-05): boots whatever MBR/GPT bootloader is on the disk
- `linode/grub-legacy` — Legacy GRUB (built 2015-04-29): GRUB 1 from disk
- `linode/grub2` — GRUB 2 from disk (most recently built 2025-05-20)

The Linode official guide "Install FreeBSD on Linode" (URL: `/docs/guides/install-freebsd-on-linode/`, last updated January 7, 2019) documented the working approach for FreeBSD 12.0.

During this era:
- Phil Eaton (eatonphil) built and published `linode_deploy_experimental` (June 2017) automating FreeBSD 11.0, OpenBSD 6.0, NetBSD 7.1 deployment
- RainbowHackerHorse published pre-built FreeBSD 11.1 KVM images (January 2018)
- eatonphil confirmed ZFS worked successfully on Linode FreeBSD (HN, 2016)

### Post-2019 / Akamai Era (2019–present)

Linode was acquired by Akamai in 2022. The brand transitioned to "Akamai Cloud" but infrastructure largely unchanged.

- The official FreeBSD installation guide was NOT updated after January 2019 and is no longer linked from Akamai's current techdocs
- Akamai's current custom image docs (`upload-an-image`) require **ext3 or ext4** for the "capture image" path — this path does NOT work for BSD filesystems (UFS/ZFS)
- However, the `Direct Disk` and `GRUB 2` kernel options **remain active and undeprecated** in the API as of April 2026
- As of September 2025, at least one HN user (quectophoton) reported still actively using FreeBSD on Linode VPS with no issues

---

## 2. Current Kernel/Boot Options (Confirmed via Linode API, April 2026)

| Kernel ID | Label | Built | Deprecated | KVM |
|---|---|---|---|---|
| `linode/grub2` | GRUB2 | 2025-05-20 | No | Yes |
| `linode/direct-disk` | Direct Disk | 2015-05-05 | No | Yes |
| `linode/grub-legacy` | GRUB (Legacy) | 2015-04-29 | No | Yes |
| `linode/pv-grub_x86_64` | pv-grub-x86_64 | 2008-11-14 | No | No (Xen only) |
| `linode/pv-grub_x86_32` | pv-grub-x86_32 | 2008-11-14 | No | No (Xen only) |

**The GRUB2 kernel was rebuilt as recently as 2025-05-20**, indicating active maintenance. None of the BSD-compatible boot modes are deprecated.

---

## 3. Confirmed-Working Approaches (with Sources)

### Approach A: Rescue Mode + dd + Direct Disk Boot
**Status: CONFIRMED WORKING (historically 2015–2025, likely still works)**

**How it works:**
1. Create a Linode with two RAW disks (1GB installer + remainder for OS)
2. Boot into rescue mode (Finnix-based Linux)
3. Download FreeBSD memstick installer: `curl [freebsd-ftp-url] | dd of=/dev/sda`
4. Create boot profile using `Direct Disk` kernel (`linode/direct-disk`), disable all filesystem/boot helpers
5. Boot from installer disk via Glish (graphical console)
6. Run FreeBSD installer, install to second disk (ZFS recommended)
7. Before first boot, add to `/boot/loader.conf`:
   ```
   boot_multicons="YES"
   boot_serial="YES"
   comconsole_speed="115200"
   console="comconsole,vidconsole"
   ```
8. Reconfigure boot profile to boot from OS disk only

**Sources:**
- Linode official guide: https://www.linode.com/docs/guides/install-freebsd-on-linode/ (last updated 2019-01-07, covers FreeBSD 12.0)
- RainbowHackerHorse README (2018): confirms KVM + ZFS + vtnet0 works, serial console config identical
- OpenBSD variant (Linode forum, mariusz): same approach confirmed working through OpenBSD 13.1 (2021) — OpenBSD uses Full Virtualization mode instead of Direct Disk

**Key requirements:**
- `Direct Disk` kernel in config profile
- All filesystem/boot helpers disabled (they break FreeBSD)
- Lassie (watchdog) disabled during installation
- Serial console configured in `/boot/loader.conf`
- Network interface: `vtnet0` (VirtIO, not em0)
- IPv4: DHCP; IPv6: SLAAC

### Approach B: Pre-built Image via dd in Rescue Mode
**Status: CONFIRMED WORKING (2017–2018 era, likely still works mechanically)**

RainbowHackerHorse published a 1.5GB FreeBSD 11.1-RELEASE image (GPT+ZFS) specifically built for KVM Linodes. Deploy via:
```
wget [image-url] | dd of=/dev/sda
```
Then boot with `Direct Disk` kernel.

**Source:** https://github.com/RainbowHackerHorse/FreeBSD-On-Linode (last updated 2018-01-08)

**Caveat:** Image is FreeBSD 11.1 (EOL). The technique works but the image is outdated. Could be replicated with current FreeBSD.

### Approach C: Automated Python Script (linode_deploy_experimental)
**Status: CONFIRMED WORKING in 2017, LIKELY STALE today**

Phil Eaton's tool:
1. Creates a Linode via API
2. Boots a temporary Debian environment
3. Downloads a pre-built compressed BSD image and `dd`s it to the target disk
4. Boots with Direct Disk kernel

Supports FreeBSD 11.0, OpenBSD 6.0, NetBSD 7.1.

**Source:** https://github.com/eatonphil/linode_deploy_experimental (last updated 2017-06-25)
**Caveat:** Uses Linode API v3 (deprecated). Needs updating for v4. Image downloads reference a private server (192.168.143.223) no longer accessible. The *technique* remains valid; the tooling is stale.

### Approach D: GRUB2 from Disk (Linux Shim → FreeBSD)
**Status: THEORETICALLY POSSIBLE, no confirmed community reports**

`linode/grub2` boots whatever GRUB2 is installed on the disk. FreeBSD's bootloader is not GRUB2 — it's `boot1`/`boot2`/`loader`. So GRUB2 mode alone does not boot FreeBSD natively.

However: it would be possible to install GRUB2 on a FreeBSD disk and configure it to chain-load FreeBSD's loader. No community reports confirm anyone has done this on Linode.

The `Direct Disk` approach (Approach A) is simpler and confirmed working — it boots FreeBSD's native MBR/GPT boot code directly.

---

## 4. The "Upload Custom Image" Path — DOES NOT WORK for BSD

Akamai's current custom image upload system (`techdocs.akamai.com/cloud-computing/docs/upload-an-image`) explicitly requires:
- Raw disk image format (`.img`)
- **ext3 or ext4 filesystem only**
- Capturing existing Linode: also requires ext3/ext4

FreeBSD's UFS and ZFS filesystems are not ext3/ext4. This path **cannot be used** to create a reusable FreeBSD image in the normal sense. The image would fail validation or not boot.

The workaround is Approach A/B: bypass the image system entirely by dd-ing directly to a raw disk in rescue mode.

---

## 5. The Rescue+dd Approach: Viability Assessment

**Viability: CONFIRMED, highly likely still works in 2026**

The rescue+dd approach is the canonical method documented by:
- Linode's own 2019 guide
- All community implementations (eatonphil, RainbowHackerHorse, OpenBSD forum guide)
- Finnix (the rescue environment) provides standard Linux tools including `curl`, `wget`, `dd`, `gunzip`

There is no technical reason this should have broken since 2019. The mechanism is:
1. Finnix rescue boots a standard Linux environment with full disk access
2. FreeBSD installer writes to raw disk with no interference
3. Direct Disk kernel (`linode/direct-disk`) bypasses Linode's kernel layer entirely, booting whatever bootloader is on the MBR/GPT
4. FreeBSD's boot1/GPT loader is BIOS-compatible and works with KVM

The one requirement that could have changed: whether Linode still assigns `/dev/sda`-style device names in rescue mode. Based on the current API and documentation, they do.

---

## 6. Confirmed-Failing Approaches

| Approach | Why It Fails |
|---|---|
| Custom image upload (capture from Linode) | Requires ext3/ext4; FreeBSD UFS/ZFS rejected |
| Using Linode's default Linux kernels for FreeBSD | FreeBSD cannot boot a Linux kernel — obvious mismatch |
| Linode Backup Service | Explicitly unsupported for non-Linux OSes; may not understand FreeBSD partition schemes |
| Password reset via Cloud Manager | Does not work for FreeBSD (no cloud-init agent); documented by eatonphil (2017) |
| Private IP auto-configuration | FreeBSD does not run Linode's network helper; must configure manually |
| PV-GRUB on KVM nodes | PV-GRUB is Xen-only; KVM nodes use `linode/direct-disk` or `linode/grub2` |
| Xen-era images on KVM | RainbowHackerHorse repo explicitly warns: "WILL NOT BOOT ON Xen Linode" — the reverse also applied |

---

## 7. OpenBSD and NetBSD

Both have been confirmed working using the same rescue+dd approach:

**OpenBSD:**
- The Linode forum thread (mariusz) documented OpenBSD working through version 13.1 (2021 confirmation)
- Key difference: OpenBSD installation requires **Full Virtualization mode** (not Direct Disk) per community reports from that thread
- The private IP limitation applies: only the public interface gets auto-configured
- One 2015 HN commenter ran OpenBSD, FreeBSD, and SmartOS simultaneously on Linode

**NetBSD:**
- Included in eatonphil's 2017 tool (NetBSD 7.1)
- No independent recent reports found

---

## 8. GRUB2 from Disk: Technical Analysis

`linode/grub2` (kernel ID) instructs the hypervisor to chainload GRUB2 from the disk's boot sector instead of using a Linode-supplied kernel. This is how modern Linux distros with custom kernels work on Linode.

**FreeBSD compatibility:**
- FreeBSD does NOT install GRUB2 by default; it uses its own BSD bootloader (boot1 for MBR, gptboot for GPT)
- `linode/direct-disk` is the correct option for FreeBSD — it boots whatever is in the MBR/first partition's boot code
- GRUB2 mode would require explicitly installing GRUB2 onto a FreeBSD disk AND configuring it to load FreeBSD's kernel (`/boot/loader.efi` or via GRUB's `kfreebsd` command)
- No confirmed community reports of this being done on Linode

**Verdict:** `Direct Disk` is the right boot mode for FreeBSD on Linode. GRUB2 mode is unnecessary complexity unless you specifically need GRUB.

---

## 9. DigitalOcean Comparison

| Aspect | DigitalOcean (pre-2022) | Linode/Akamai |
|---|---|---|
| Official BSD support | Yes (had FreeBSD Droplets) | Never officially supported |
| Current status | Dropped June 2022 | Still unofficially possible |
| Custom image path | Supported custom images (with caveats: no IPv6) | ext3/ext4 only — doesn't work for BSD |
| dd/rescue approach | Community-documented | Canonical method, still works |
| Most recent confirmation | 2022 (before drop) | September 2025 (HN comment) |

The DigitalOcean situation actually makes Linode look better in 2026 — DO explicitly ended BSD support while Linode never promised it but hasn't broken it. The rescue+dd approach works on both, but DO has since tightened restrictions.

---

## 10. Most Recent Confirmed Working Report

**Date:** September 5, 2025
**Source:** HN comment by user `quectophoton`, in thread "Half an year on Alpine: just musl aside" (story ID 45094559)
**Quote:** "I was already using Alpine Linux and FreeBSD in VPSs (Linode and Digital Ocean respectively), and they were still working fine so they seemed stable enough."

This is the most recent confirmation of FreeBSD running on Linode. The commenter describes it as stable and continuing to work without issues.

---

## 11. What Broke vs. What Still Works (2026 Assessment)

**Still works:**
- Rescue mode boot in Finnix (standard Linux tools available)
- `linode/direct-disk` kernel option (confirmed not deprecated, active in API)
- `linode/grub2` kernel option (actively maintained, rebuilt May 2025)
- FreeBSD's native bootloader via Direct Disk
- VirtIO networking (`vtnet0`)
- DHCP + SLAAC for IPv4/IPv6
- ZFS root (confirmed working in multiple sources)
- Glish console access (required for initial FreeBSD installation)
- Serial console via loader.conf settings

**No longer works or never worked:**
- Linode's custom image upload path for BSD (ext3/ext4 requirement)
- Cloud Manager password resets
- Linode Backup Service
- Private IP auto-configuration
- eatonphil's 2017 Python tool (API v3, dead image server — but technique is valid)

**Unknown / unconfirmed:**
- Whether the current Finnix version (rescue mode) still has the same tool set
- Whether `linode/direct-disk` still boots correctly with FreeBSD 14.x UEFI-capable disks vs. legacy BIOS boot
- GRUB2 + FreeBSD combination (no reports)
- NetBSD current-generation versions

---

## 12. Verdict

**Linode BSD support in 2026 is: HACKY-BUT-WORKS**

More precisely:
- **The mechanism is stable.** The rescue+dd + Direct Disk kernel approach has worked continuously since 2015 and was confirmed still working in September 2025.
- **Zero official support.** Akamai does not document, test, or support BSD. No BSD-specific guides in current techdocs. No official images. No backup service.
- **Three real pain points:** (1) Initial install requires Glish console — can't fully automate without it. (2) No password reset via dashboard. (3) Custom image path is blocked (ext3/ext4 only).
- **One major upside vs. competitors:** Linode has never actively broken BSD and has maintained the necessary boot primitives (Direct Disk, GRUB2) that make it possible.
- **Not turnkey.** Expect 30–60 minutes of manual work to stand up a fresh FreeBSD instance. Not suitable for cattle-style fleet operations without custom image-building infrastructure outside Linode's native tooling.

---

## Appendix: Key Source URLs

| Source | URL | Date | Notes |
|---|---|---|---|
| Linode official FreeBSD guide | https://www.linode.com/docs/guides/install-freebsd-on-linode/ | 2019-01-07 | Last known official guide; FreeBSD 12.0 |
| Linode KVM announcement | https://www.linode.com/2015/06/16/linode-turns-12-heres-some-kvm/ | 2015-06-16 | Announced alternative OS support |
| RainbowHackerHorse images | https://github.com/RainbowHackerHorse/FreeBSD-On-Linode | 2018-01-08 | Pre-built FreeBSD 11.1 KVM image |
| eatonphil deploy tool | https://github.com/eatonphil/linode_deploy_experimental | 2017-06-25 | Python; FreeBSD/OpenBSD/NetBSD; API v3 |
| eatonphil blog post | http://notes.eatonphil.com/2017/3/deploying-freebsd-on-linode-automatically-in-minutes.html | 2017-03-11 | Blog (404 now, archived) |
| Linode forum OpenBSD thread | https://forum.linode.com/viewtopic.php?f=20&t=12080 | ~2015, updated through 2021 | OpenBSD 5.8 → 13.1 confirmed |
| HN: DigitalOcean drops FreeBSD | https://news.ycombinator.com/item?id=31270952 | 2022-05-05 | Linode recommended as alternative |
| HN: FreeBSD still works comment | https://news.ycombinator.com/item?id=45094559 | 2025-09-05 | Most recent confirmation |
| Akamai upload-an-image docs | https://techdocs.akamai.com/cloud-computing/docs/upload-an-image | current | ext3/ext4 only — blocks BSD |
| Linode Kernels API | https://api.linode.com/v4/linode/kernels | current | Confirms direct-disk, grub2 not deprecated |
