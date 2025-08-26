#############################################
#
#
# EML MediaLive Terraform Infra builder
# 
# Latest: Dan 8.19.25 932pm PT
#
# this will be an attempt to have simple Terraform code to
# build a single EML encoder.
# i do not want to have Cursor AI run it tho, rather i will
# review and after i'm confident in the code, i'll run it 
# manually.  boy it sure looks bloated tho already
# 
# i should build this on my personal infra before work
#
#############################################



# Elemental MediaLive slate loop → MediaPackage (with CloudFront)

This repo provisions a minimal AWS Elemental pipeline for a broadcast-style slate: MediaLive plays a looping file and outputs to MediaPackage (EMP). The file is served privately from S3 via CloudFront with Origin Access Control (OAC) and CloudFront Signed URLs.

## Final design (implemented)
- Input: MediaLive `MP4_FILE` (HTTPS) pulling from `https://<cloudfront_domain>/<path>`
- Origin: S3 locked with OAC; CloudFront required for access
- Protection: CloudFront Signed URLs (Key Group with a public key; you sign with the private key)
- Output: MediaPackage (EMP) HLS ingest via MediaLive MediaPackage output group
- IAM: MediaLive role with CloudWatch Logs, SSM read (URL auth placeholder), and EMP describe

### Why this design
- MediaPackage provides resilient origins and standard playback endpoints (HLS/DASH/CMAF)
- File pull avoids standing up an upstream encoder

## Files in this repo
- `providers.tf` — AWS provider config (region via variables)
- `variables.tf` / `terraform.tfvars` — Variables and values (region, bucket, key, price class)
- `iam.tf` — MediaLive IAM role/policies
- `cloudfront.tf` — CloudFront distribution (OAC), key group/public key, outputs for domain, public key ID, private key (sensitive)
- `mediapackage.tf` — MediaPackage channel
- `medialive.tf` — MediaLive input (MP4_FILE) and channel with MediaPackage output group
- `scripts/sign_cf_url.py` — Helper to generate a CloudFront signed URL

## Quickstart (Infra → Start → Play via CloudFront)

1) Init
```
terraform init
```
2) Plan (read-only)
```
terraform plan
```
3) Apply
```
terraform apply
```

4) Start the MediaLive channel
```
aws medialive start-channel --channel-id $(terraform output -raw medialive_channel_id) --region us-east-1
```

5) Play via CloudFront (no tokens)
```
terraform output -raw cloudfront_emp_playback_url
```
Open the returned URL in Safari/Chrome. If you see 404 initially, wait 10–30s and refresh.

---

# CloudFront in front of MediaPackage (EMP) playback

CF distribution `cloudfront_emp.tf` fronts the EMP HLS origin. CURRENT: token requirement is disabled for simplicity, so the CloudFront URL works directly (master + child manifests + segments).

### Operations
- Start channel:
```
aws medialive start-channel --channel-id $(terraform output -raw medialive_channel_id) --region us-east-1
```
- Stop channel:
```
aws medialive stop-channel --channel-id $(terraform output -raw medialive_channel_id) --region us-east-1
```
- Playback URL:
```
terraform output -raw cloudfront_emp_playback_url
```

### Troubleshooting
- 404 at first load: wait 10–30s for first segments, then refresh.
- 403 MissingKey: indicates tokenization was enabled or a cached response. If you re-enable tokens, use signed cookies; otherwise ensure the distribution has no `trusted_key_groups` and hard-refresh.

## Clean up
Stop the MediaLive channel, then:
```
terraform destroy
```
This removes the channel, IAM role/policies, and any managed resources.

## Notes
- Keep MediaLive and MediaPackage in the same Region
- Default CF cert is used; no custom DNS required
- No broad allowlists needed (no RTMP in the final design)

## Helper: token workflows (deferred)

We experimented with signed access for HLS. If you later re-enable tokens (see below), you can use the helper and scripts:
- `scripts/sign_cf_cookies.py` to generate CloudFront signed cookies
- `scripts/sign_cf_url.py` to sign a single URL (master only)
- `scripts/get_cf_playback.sh cookies` to print Set-Cookie lines and the CloudFront URL

### Re-enable tokenization (future)
1) In `cloudfront_emp.tf` add back:
```
default_cache_behavior {
  # ...
  trusted_key_groups = [aws_cloudfront_key_group.kg.id]
}
```
2) `terraform apply`
3) Generate cookies and play via CloudFront (cookies apply to master + children)