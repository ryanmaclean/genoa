# Path 1: Snapshot from URL

**Priority: 2 — complements Path 0 for providers without direct-upload APIs**

## Summary

The provider fetches the image from an HTTPS URL that genoa-deploy publishes.
Genoa must first run `genoa publish` to host the artifact at a stable URL, then
hand that URL to the provider's snapshot/import API.

This differs from Path 0 in that the provider pulls from our URL rather than
us pushing bytes directly to their storage. Some providers (Vultr, some DO
workflows) prefer this model.

## Works for

| Provider | API | Required format | Notes |
|----------|-----|----------------|-------|
| Vultr | `POST /v2/snapshots/create-from-url` | raw | Provider fetches and ingests |
| DigitalOcean | `POST /v2/images` with `url` field | raw or qcow2 | Alternative to doctl direct |
| Exoscale | `POST /v2/template` with `url` | raw or qcow2 | |
| Hetzner Cloud | No image import API — **skip** | N/A | Use Path 2 or 3 |
| OCI | `image import from-uri` | raw or VMDK | URI must be pre-authenticated |
| Linode | API image upload accepts URL in some workflows | raw.gz | |

## Required capabilities

1. **`genoa publish` step** — the raw (or converted) image must be reachable at
   a stable HTTPS URL before calling the provider API. See `publish-step.md`.

2. **Signed or time-limited URLs** — some providers require the URL to be
   publicly accessible or pre-authenticated (OCI pre-auth requests, S3
   presigned URLs). Token TTL must exceed the provider's import time.

3. **Content-type and size headers** — some provider validators check
   `Content-Length` and `Content-Type`. Ensure the hosting layer sets these.

## Invocation examples

### Vultr
```sh
# 1. Publish image
genoa publish --backend r2 genoa-freebsd.raw
# -> https://pub.genoa.example.com/genoa-freebsd-20260430.raw

# 2. Create snapshot from URL
curl -X POST "https://api.vultr.com/v2/snapshots/create-from-url" \
  -H "Authorization: Bearer ${VULTR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://pub.genoa.example.com/genoa-freebsd-20260430.raw",
       "description": "genoa-freebsd-20260430"}'
# Returns: {"snapshot": {"id": "...", "status": "pending"}}

# 3. Poll until status = "complete"
```

### DigitalOcean (URL variant)
```sh
curl -X POST "https://api.digitalocean.com/v2/images" \
  -H "Authorization: Bearer ${DO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "genoa-freebsd-20260430",
       "url": "https://pub.genoa.example.com/genoa-freebsd-20260430.raw",
       "region": "nyc3",
       "distribution": "FreeBSD"}'
```

### OCI (pre-auth URI)
```sh
# Upload to OCI Object Storage first, create pre-auth request
oci os preauth-request create \
  --bucket-name genoa-images \
  --name genoa-preauth \
  --access-type ObjectRead \
  --time-expires "2026-05-07T00:00:00Z" \
  --object-name genoa-freebsd.raw

# Import from URI
oci compute image import from-object-uri \
  --uri "https://objectstorage.us-phoenix-1.oraclecloud.com/p/TOKEN/n/NS/b/genoa-images/o/genoa-freebsd.raw" \
  --display-name "genoa-freebsd-20260430" \
  --launch-mode "PARAVIRTUALIZED"
```

## genoa publish step

The publish step is a first-class genoa command. See `publish-step.md` for
the full hosting option analysis. Short version:

- **Cloudflare R2**: preferred — no egress fees, S3-compatible, presigned URLs
- **S3**: universal, presigned URLs, Apache-2.0 SDK
- **GitHub Releases**: free for public repos, 2 GiB/asset limit

## Implementation effort

**Medium-high.** Requires `genoa publish` as a prerequisite (separate feature).
Provider API calls themselves are simple HTTP POST + poll. The complexity is:
- Building and maintaining the URL publish step
- Managing URL TTLs (signed URLs expire; provider may take >1 hour to import)
- Ensuring the hosted artifact is the right format for each provider

## License traps

- Hosting SDKs (aws-sdk, @cloudflare/r2): Apache-2.0 or MIT — clean
- Provider CLI tools: all Apache-2.0 or MIT — clean
- **No iPXE involved** — this is pure HTTPS transfer

## References

- Vultr Snapshots API: https://www.vultr.com/api/#tag/snapshot/operation/create-snapshot-create-from-url
- DigitalOcean Images API: https://docs.digitalocean.com/reference/api/api-reference/#operation/images_create
- OCI image import: https://docs.oracle.com/en-us/iaas/api/#/en/iaas/latest/Image/CreateImage
