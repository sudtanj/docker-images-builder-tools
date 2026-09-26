# Oracle Cloud Free Tier Claimer

Runs [sudtanj/infrastructure_scripts](https://github.com/sudtanj/infrastructure_scripts/tree/main/oracle-cloud-free-tier)
(Terraform that provisions/reconciles Oracle Cloud Always Free resources in
`ap-singapore-1`) on a schedule inside a slim multi-arch container
(`linux/amd64` and `linux/arm64`).

All OCI credentials come from environment variables (docker compose env /
`.env`) — never baked into the image.

## Quick start

```bash
cp .env.example .env
# edit .env - at minimum: OCI_TENANCY_OCID, OCI_USER_OCID,
# OCI_FINGERPRINT, OCI_PRIVATE_KEY_BASE64, OCI_COMPARTMENT_OCID

# build for both platforms (requires buildx):
docker buildx build --platform linux/amd64,linux/arm64 -t sudtanj/oracle-cloud-free-tier-claimer .

# or local-only:
docker compose build
docker compose up -d

# single run then exit (CI-style):
docker compose run --entrypoint "sh -c 'RUN_ONCE=1 /usr/local/bin/entrypoint.sh'" oracle-cloud-free-tier-claimer

# watch it work:
docker compose logs -f
```

## How it works

- `entrypoint.sh` writes `terraform.tfvars` (and a private key file) from
  env vars, runs `terraform init`, then loops `terraform apply -auto-approve`.
- `RUN_INTERVAL` (default 1800s = 30min) controls the loop - mirrors the
  workflow's commented-out `*/30 * * * *` cron.
- `RUN_ONCE=1` exits after a single apply (useful for CI).
- Free-tier capacity is often exhausted, so a failed apply is retried on
  the next interval rather than exiting.

## Persisted state

The compose file mounts a named volume (`oci-terraform-state`) on `/workspace`,
so `terraform.tfstate` and the plugin cache survive restarts.

## Optional remote state

Set `TF_BACKEND_TYPE` (e.g. `s3`) plus `TF_BACKEND_BUCKET` / `TF_BACKEND_KEY` /
`TF_BACKEND_REGION` in your env to write a `backend.tf` on startup so state
lives outside the container instead of the volume.

## Build args

- `TERRAFORM_VERSION` (default `1.6.0`) - pins the terraform binary; matches
  the version the upstream workflow uses.

## Architecture

Multi-arch `linux/amd64` + `linux/arm64` via `docker buildx`. Terraform ships a
single static binary per platform, so the image is a single `alpine` stage with
no build stage required (unlike [PERSON_NAME]-creator).
