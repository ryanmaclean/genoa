# Publish Step: Hosting Genoa Images for Path 1 and Path 3

## Purpose

Paths 1 and 3 both require the genoa raw image (or a derived format) to be
reachable at an HTTPS URL before the provider or rescue environment can fetch it.

`genoa publish` is a first-class command that:
1. Takes a local artifact (`.raw`, `.qcow2`, `.tar.gz`, etc.)
2. Uploads it to a configured backend
3. Returns a stable HTTPS URL and a SHA256 checksum

The URL must remain valid for the duration of the provider's import process
(up to 60+ minutes for some providers).

---

## Option comparison

### 1. Cloudflare R2

| Property | Value |
|----------|-------|
| License (SDK) | Apache-2.0 (`aws4fetch`, `@cloudflare/r2` via S3-compat) |
| File size limit | 5 TiB per object |
| Auth model | S3-compatible API keys (Access Key ID + Secret) |
| Signed URL support | YES — presigned URLs via S3 API, configurable TTL |
| Egress fees | **ZERO** — no egress charges from R2 to internet |
| Cost model | $0.015/GB-month storage; free egress |
| Self-hosted? | No — Cloudflare-managed |
| Best for | Public distribution with unpredictable download volume |

```sh
# Upload via rclone (MIT license) or aws CLI (Apache-2.0)
aws s3 cp genoa.raw s3://genoa-pub/genoa-freebsd-20260430.raw \
  --endpoint-url https://ACCOUNT_ID.r2.cloudflarestorage.com

# Generate presigned URL (1 hour TTL)
aws s3 presign s3://genoa-pub/genoa-freebsd-20260430.raw \
  --endpoint-url https://ACCOUNT_ID.r2.cloudflarestorage.com \
  --expires-in 3600
```

Verdict: **Recommended** for production. Zero egress cost matters when
providers pull multi-GiB images. S3 API compatibility means the same `genoa publish`
code works with R2 and real S3.

---

### 2. Amazon S3

| Property | Value |
|----------|-------|
| License (SDK) | Apache-2.0 (aws-sdk-rust, aws-cli) |
| File size limit | 5 TiB per object (multipart) |
| Auth model | IAM roles, access keys, or STS |
| Signed URL support | YES — presigned URLs, configurable TTL up to 7 days |
| Egress fees | $0.09/GB from us-east-1 to internet |
| Self-hosted? | No — AWS-managed |
| Best for | AWS-native deployments where image and import are in same region |

```sh
aws s3 cp genoa.raw s3://genoa-pub/genoa-freebsd-20260430.raw --region us-east-1

# Presigned URL (1 hour)
aws s3 presign s3://genoa-pub/genoa-freebsd-20260430.raw --expires-in 3600
```

Note: For AWS EC2 import-snapshot, the image must be in S3 in the same region
as the import. S3 is unavoidable here — but it's only used for the import itself,
not for serving to other providers.

---

### 3. Backblaze B2

| Property | Value |
|----------|-------|
| License (SDK) | MIT (b2-sdk-python, b2 CLI) or S3-compat via AWS SDK |
| File size limit | No stated object limit; 10 TB bucket |
| Auth model | Application keys (key ID + secret) |
| Signed URL support | YES — B2 native signed URLs OR S3-compat presigned |
| Egress fees | Free egress to Cloudflare network partners; $0.01/GB otherwise |
| Self-hosted? | No — Backblaze-managed |
| Best for | Cost-sensitive small fleets; Cloudflare integration (free egress via partner) |

```sh
# S3-compatible endpoint
aws s3 cp genoa.raw s3://genoa-pub/genoa-freebsd-20260430.raw \
  --endpoint-url https://s3.us-west-004.backblazeb2.com

# B2 native CLI (MIT license)
b2 upload-file genoa-pub genoa.raw genoa-freebsd-20260430.raw
```

Note: B2's Cloudflare-partnered free egress only applies when B2 bucket is
fronted by Cloudflare. Without that, egress is $0.01/GB.

---

### 4. Gitea Releases (self-hosted)

| Property | Value |
|----------|-------|
| License (SDK) | MIT (Gitea API client) |
| File size limit | Configurable in Gitea server (`APP_MAX_REQUEST_BODY_SIZE`, default 4 GiB) |
| Auth model | Personal access tokens or API tokens |
| Signed URL support | NO — direct HTTPS URLs only |
| Egress fees | Self-hosted — pay for your own bandwidth |
| Self-hosted? | YES — full control |
| Best for | Self-hosted fleet where public access is not needed |

```sh
# Upload via Gitea releases API
curl -X POST "http://gitea.local:3000/api/v1/repos/genoa/images/releases/assets?id=1" \
  -H "Authorization: token $GITEA_TOKEN" \
  -F "attachment=@genoa-freebsd-20260430.raw"
```

Caveat: 4 GiB default limit may be too small for full raw images. Increase
`APP_MAX_REQUEST_BODY_SIZE` in `app.ini` or compress images first.

Caveat 2: No presigned URL support — URLs are always public to anyone with
network access to the Gitea instance. For fleet-internal images, this is fine.

---

### 5. GitHub Releases

| Property | Value |
|----------|-------|
| License (SDK) | MIT (octokit.js, gh CLI) |
| File size limit | 2 GiB per asset, 100 GB per release |
| Auth model | GitHub PAT or GitHub App token |
| Signed URL support | Partial — `assets` URLs redirect to S3 with short-lived tokens |
| Egress fees | Free for public repos; bandwidth limits for private |
| Self-hosted? | No — GitHub-managed |
| Best for | Public open-source distribution; small images (<2 GiB) |

```sh
gh release create v20260430 genoa-freebsd-20260430.raw \
  --title "Genoa FreeBSD 20260430" \
  --repo genoa-project/genoa
```

Limitation: 2 GiB per asset is the hard limit. A 4–8 GiB raw disk image
**cannot** be uploaded to GitHub Releases without splitting or heavy compression.
Acceptable for compressed qcow2 or gce-tar; not for raw.

---

### 6. IPFS (InterPlanetary File System)

| Property | Value |
|----------|-------|
| License (SDK) | MIT (kubo/go-ipfs), Apache-2.0 (Estuary) |
| File size limit | No hard limit |
| Auth model | Content-addressed — CID is the address; no auth |
| Signed URL support | NO — content-addressed; immutable by CID |
| Egress fees | Depends on pinning service (Pinata: tiered pricing) |
| Self-hosted? | YES (kubo node) or pinning service |
| Best for | Immutable, content-addressed distribution; manifest hash pinning |

```sh
# Add to IPFS
ipfs add --cid-version=1 genoa-freebsd-20260430.raw
# Returns: Qm... or bafy...

# Access via gateway
https://ipfs.io/ipfs/bafybeiabc123.../
https://cloudflare-ipfs.com/ipfs/bafybeiabc123.../
```

Pros:
- CID is the SHA2-256 of content — perfect for content-addressed manifests
- No central server — resilient to our infrastructure going down
- Cloudflare IPFS gateway (free) provides HTTPS

Cons:
- First-byte latency is high (minutes if not pinned on fast nodes)
- Providers with strict timeouts may fail before content is available
- Not suitable as the primary publish backend for Path 1 (too slow)

Verdict: Use as a **secondary publish target** for audit / archive purposes.
Pin the CID in the genoa manifest (`ipfs_cid` field). Use R2/S3/B2 for the
primary URL handed to providers.

---

## Recommendation

| Use case | Backend |
|----------|---------|
| Production fleet, scale | Cloudflare R2 (zero egress, S3-compat) |
| AWS-only fleet | S3 (required for EC2 import anyway) |
| Self-hosted fleet | Gitea Releases (increase body limit to 10 GiB) |
| Open-source public distribution | GitHub Releases (images <2 GiB compressed) + IPFS CID in manifest |
| Audit / content integrity | IPFS (secondary, always) |

## genoa publish manifest format

The publish step should emit a JSON manifest alongside the artifact:

```json
{
  "schema_version": "1.0.0",
  "artifact": "genoa-freebsd-20260430.raw",
  "sha256": "abc123...",
  "size_bytes": 4294967296,
  "uploaded_at": "2026-04-30T12:00:00Z",
  "urls": {
    "primary": "https://pub.genoa.example.com/genoa-freebsd-20260430.raw",
    "presigned_expiry": "2026-04-30T14:00:00Z",
    "ipfs_cid": "bafybeiabc123..."
  }
}
```

This manifest is what genoa-deploy hands to provider APIs for Path 1.

## License summary

| Tool / SDK | License | Safe? |
|-----------|---------|-------|
| aws-cli / aws-sdk-rust | Apache-2.0 | YES |
| rclone | MIT | YES |
| gh CLI | MIT | YES |
| b2 CLI (Backblaze) | MIT | YES |
| kubo (IPFS) | MIT + Apache-2.0 | YES |
| octokit (GitHub SDK) | MIT | YES |

No GPL dependencies in the publish path.

## References

- Cloudflare R2 docs: https://developers.cloudflare.com/r2/
- B2 S3-compatible API: https://www.backblaze.com/docs/cloud-storage-s3-compatible-api
- GitHub Release assets: https://docs.github.com/en/rest/releases/assets
- Gitea releases API: https://gitea.io/api/swagger#/issue/issueCreateRelease
- IPFS/kubo: https://docs.ipfs.tech/reference/kubo/cli/
