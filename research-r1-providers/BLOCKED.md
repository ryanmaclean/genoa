# BLOCKED Providers — genoa Cannot Deliver VM Images Here

These providers cannot accept arbitrary VM/OS disk images for deployment. Each is documented with the precise technical reason.

---

## Fly.io

**Verdict:** Out of scope. Docker/OCI container images only.

Fly.io accepts Docker (OCI) container images and converts them internally to Firecracker microVM root filesystems using containerd. The user-facing interface is the Docker image registry: you push a Docker image, Fly unpacks it to an ext4 filesystem, and boots a Firecracker VM from it. There is no API surface that accepts a raw disk image, qcow2, ISO, or any other VM image format. The Machines API controls lifecycle (start/stop/clone) but not image ingestion. A BSD OS image cannot be expressed as a Docker container in any meaningful operational sense (no BSD kernel, no init, no hypervisor context). `flyctl` deploys via Dockerfile or prebuilt OCI image only.

**Blocker:** No raw/qcow2/ISO ingestion path exists. Docker-only.  
**Recovery path:** None without platform change by Fly.io.

---

## Cloudflare Workers

**Verdict:** Out of scope. Serverless JavaScript/WASM isolates only. No VM concept.

Cloudflare Workers runs user code in V8 JavaScript/WebAssembly isolates, not virtual machines. There is no operating system, no filesystem (beyond key-value stores), no network stack the user controls, no boot process, and no kernel. The "build image" concept in Workers Builds refers to the CI/CD build environment container, not a deployable VM image. Cloudflare Images is a CDN image optimization product unrelated to VM images. No path exists to deploy any OS or VM image.

**Blocker:** No VM model at all. Not a compute platform in the IaaS sense.  
**Recovery path:** None — fundamentally different compute model.

---

## Render

**Verdict:** Out of scope. Docker container deployment platform only.

Render deploys web services, static sites, databases, and background workers from Docker prebuilt images or Dockerfile/Git source builds. The underlying infrastructure is managed Kubernetes; users have no access to node OS images. Services run as Linux containers only. No arbitrary OS image, no BSD, no raw disk, no ISO mounting. Custom Docker images are accepted (from Docker Hub, ECR, etc.) but these must contain Linux-compatible workloads.

**Blocker:** Container/PaaS model; no raw OS image path.  
**Recovery path:** None without Render offering VM/IaaS tier.

---

## Railway

**Verdict:** Out of scope. Docker/Nixpacks container deployment only.

Railway deploys services from Docker images (Docker Hub, GHCR, Quay.io, GitLab CR) or auto-builds via Nixpacks from source repositories. The platform provisions containers, not VMs. No IPMI, no ISO mount, no raw disk image, no custom kernel. Linux containers only.

**Blocker:** Container/PaaS model only.  
**Recovery path:** None.

---

## Northflank

**Verdict:** Out of scope for VM images. BYOC ≠ BYOI.

Northflank's "Bring Your Own Cloud" (BYOC) feature means connecting your AWS/GCP/Azure Kubernetes cluster to Northflank's control plane — it does not mean bringing your own OS image. Workloads deploy as OCI containers (Docker images). The underlying Kubernetes nodes use cloud-provider managed node images (EKS AMIs, GKE node images, AKS node pools) which are not user-configurable through Northflank. Kata Containers/gVisor provide VM-grade isolation, but these are transparent to workloads; the user still submits Docker images.

**Blocker:** Kubernetes/container model; BYOC is about cloud account connection not OS images.  
**Recovery path:** Could theoretically deploy a BSD VM as a KubeVirt workload if Northflank exposed KubeVirt — not currently available.

---

## Koyeb

**Verdict:** Out of scope. Docker/Dockerfile ingestion only, Firecracker internal.

Koyeb uses Firecracker microVMs internally (orchestrated by Nomad with a custom driver) but the user-facing interface accepts only Docker images or Dockerfiles. The Machines API creates instances from container images, not raw OS images. Global edge deployment, scale-to-zero, 250ms cold start. No BSD deployable.

**Blocker:** Docker-only interface despite VM-backed infrastructure.  
**Recovery path:** If Koyeb exposed a raw image API (they don't), BSD would be possible given Firecracker substrate.

---

## Lambda Cloud (GPU)

**Verdict:** Partially blocked. No BYOI at all — Lambda provides fixed set of Ubuntu-based images only.

Lambda Cloud GPU instances are provisioned only from Lambda-provided images: "Lambda Stack" (Ubuntu + NVIDIA CUDA + ML frameworks), "GPU Base" (minimal), or "Ubuntu Server" (bare). The API `instance_type` parameter selects hardware; the image is always Lambda-controlled Ubuntu. There is no image_id parameter, no custom image import path, no ISO mounting. Users can install arbitrary software post-boot but cannot change the base OS.

**Blocker:** No image selection API. Lambda controls all images.  
**Recovery path:** Use Lambda as a base (Ubuntu) and install software post-provisioning only. BSD not possible.

---

## RunPod (GPU)

**Verdict:** Partially blocked. OCI container images only, not VM disk images.

RunPod GPU Pods accept Docker/OCI container images from any registry (Docker Hub, ECR, GHCR). The underlying infrastructure provides GPU pass-through to containers. There is no raw disk image import, no ISO boot, no arbitrary OS kernel. The 10 GB registry pull limit further constrains use. BSD OS images cannot be expressed meaningfully as Docker containers.

**Blocker:** Container-only. No VM disk image path.  
**Recovery path:** None for BSD. Could deploy Linux-based ML workloads via Docker.

---

## Paperspace (Gradient product)

**Verdict:** Partially blocked. Gradient product is container-only; Machines product is console-only template cloning.

Paperspace has two products: (1) **Gradient** — deploy notebooks and ML jobs via Docker containers; (2) **Machines** — Linux/Windows VMs with persistent storage. Machines allows creating custom templates by cloning existing machines (console operation), but the base machines are provided by Paperspace (Ubuntu, Windows). No raw disk image upload. No BSD. No ISO mount for VMs.

**Blocker:** No raw image import. Template cloning only from Paperspace-provided Linux/Windows.  
**Recovery path:** None for BSD.

---

## Hetzner Mac mini (Discontinued)

**Verdict:** Defunct. Service discontinued by Hetzner.

Hetzner offered M1 Mac mini dedicated server rental but has discontinued this product. No new orders possible, and existing M1 Mac mini servers cannot be upgraded. The documentation page exists but the service is not orderable. macOS-only in any case.

**Blocker:** Product discontinued.  
**Recovery path:** MacStadium, Scaleway Apple Silicon, or AWS EC2 Mac for Apple Silicon needs.

---

## RootBSD

**Verdict:** Defunct as independent brand. Merged into NetActuate.

RootBSD was a FreeBSD-specialist VPS provider. The rootbsd.net domain now redirects to NetActuate. The original service and branding are gone. NetActuate may carry forward some BSD capability — research separately if needed.

**Blocker:** Brand/company defunct.  
**Recovery path:** Contact NetActuate (netactuate.com) directly to determine BSD VPS availability.

---

## Apple Silicon hosts (Tier 6: MacStadium, Scaleway M4, AWS EC2 Mac)

**Verdict:** Out of scope for BSD/Linux VM deployment. macOS only.

All Apple Silicon hosting providers (MacStadium Orka, Scaleway M4, AWS EC2 Mac) are constrained to macOS by two factors: (1) Apple's macOS license terms require running macOS on Apple hardware and prohibit running it in a VM on non-Apple hardware; (2) the Apple Hypervisor Framework (HVF) only runs on macOS hosts and only supports macOS guests in production configurations. FreeBSD has experimental aarch64 port but Apple Silicon hardware support is incomplete. These providers exist for macOS CI/CD and iOS/macOS app development workflows.

**Blocker:** Hardware + license constraints limit to macOS. BSD not supported as guest.  
**Recovery path:** Wait for FreeBSD Apple Silicon port maturation. Even then, providers would need to allow non-macOS guests (currently prohibited by Apple licensing terms for commercial hosting).
