#!/bin/sh
set -eu

WORKDIR="${WORKDIR:-/workspace}"
cd "$WORKDIR"

# Self-heal ownership of the persistent /workspace volume on every
# start - a named volume can retain root ownership from a prior run.
if [ "$(id -u)" = "0" ]; then
    chown -R terraform:terraform "$WORKDIR"
fi

: "${OCI_TENANCY_OCID:?OCI_TENANCY_OCID is required}"
: "${OCI_USER_OCID:?OCI_USER_OCID is required}"
: "${OCI_FINGERPRINT:?OCI_FINGERPRINT is required}"
: "${OCI_COMPARTMENT_OCID:?OCI_COMPARTMENT_OCID is required}"
[ -z "${OCI_PRIVATE_KEY:-}" ] && [ -z "${OCI_PRIVATE_KEY_BASE64:-}" ] && { echo "OCI_PRIVATE_KEY or OCI_PRIVATE_KEY_BASE64 is required" >&2; exit 1; }

KEY_FILE="$WORKDIR/.oci_api_private_key.pem"
mkdir -p "$(dirname "$KEY_FILE")"
if [ -n "${OCI_PRIVATE_KEY_BASE64:-}" ]; then
    printf '%s' "$OCI_PRIVATE_KEY_BASE64" | base64 -d > "$KEY_FILE"
elif printf '%s' "$OCI_PRIVATE_KEY" | grep -q 'BEGIN.*PRIVATE KEY'; then
    printf '%s\n' "$OCI_PRIVATE_KEY" > "$KEY_FILE"
else
    printf '%s' "$OCI_PRIVATE_KEY" | base64 -d > "$KEY_FILE"
fi
chmod 600 "$KEY_FILE"

# Build terraform.tfvars from env vars. The private key is inlined as a
# single-line string with literal \n separators (terraform parses these
# in HCL string values), so it survives a single-line tfvars entry.
TFVARS="$WORKDIR/terraform.tfvars"
KEY_ONELINE=$(sed 's/$/\\n/' "$KEY_FILE" | tr -d '\n' | sed 's/\\n$//')

cat > "$TFVARS" <<EOF
tenancy_ocid         = "${OCI_TENANCY_OCID}"
user_ocid            = "${OCI_USER_OCID}"
api_key_fingerprint  = "${OCI_FINGERPRINT}"
api_key_private_key  = "${KEY_ONELINE}"
compartment_ocid     = "${OCI_COMPARTMENT_OCID}"
EOF

[ -n "${OCI_REGION:-}" ]              && echo "region = \"${OCI_REGION}\""               >> "$TFVARS"
[ -n "${OCI_AVAILABILITY_DOMAIN:-}" ] && echo "availability_domain = \"${OCI_AVAILABILITY_DOMAIN}\"" >> "$TFVARS"
[ -n "${OCI_INSTANCE_IMAGE_OCID:-}" ] && echo "instance_image_ocid = \"${OCI_INSTANCE_IMAGE_OCID}\"" >> "$TFVARS"
[ -n "${OCI_SSH_PUBLIC_KEY:-}" ]      && echo "ssh_public_key = \"${OCI_SSH_PUBLIC_KEY}\"" >> "$TFVARS"
chmod 600 "$TFVARS"

# Optional remote backend (state outside container):
# set TF_BACKEND_TYPE=s3|gcs|remote|etc + TF_BACKEND_BUCKET/KEY/REGION/...
if [ -n "${TF_BACKEND_TYPE:-}" ]; then
    cat > "$WORKDIR/backend.tf" <<EOF
terraform {
  backend "${TF_BACKEND_TYPE}" {
EOF
    [ -n "${TF_BACKEND_BUCKET:-}" ]        && echo "    bucket = \"${TF_BACKEND_BUCKET}\""        >> "$WORKDIR/backend.tf"
    [ -n "${TF_BACKEND_KEY:-}" ]           && echo "    key = \"${TF_BACKEND_KEY}\""             >> "$WORKDIR/backend.tf"
    [ -n "${TF_BACKEND_REGION:-}" ]        && echo "    region = \"${TF_BACKEND_REGION}\""       >> "$WORKDIR/backend.tf"
    [ -n "${TF_BACKEND_DYNAMODB_TABLE:-}" ] && echo "    dynamodb_table = \"${TF_BACKEND_DYNAMODB_TABLE}\"" >> "$WORKDIR/backend.tf"
    [ -n "${TF_BACKEND_PREFIX:-}" ]        && echo "    prefix = \"${TF_BACKEND_PREFIX}\""       >> "$WORKDIR/backend.tf"
    [ -n "${TF_BACKEND_CONN:-}" ]          && echo "    conn_str = \"${TF_BACKEND_CONN}\""        >> "$WORKDIR/backend.tf"
    echo "  }" >> "$WORKDIR/backend.tf"
    echo "}" >> "$WORKDIR/backend.tf"
fi

# Drop to non-root terraform user for everything below.
if [ "$(id -u)" = "0" ]; then
    exec su-exec terraform "$0" "$@"
fi

terraform init -input=false -upgrade

INTERVAL="${RUN_INTERVAL:-1800}"
RUN_ONCE="${RUN_ONCE:-0}"

apply_once() {
    echo "[$(date -u +%FT%TZ)] terraform apply start"
    if terraform apply -auto-approve -input=false -var-file="$TFVARS"; then
        echo "[$(date -u +%FT%TZ)] terraform apply OK"
    else
        echo "[$(date -u +%FT%TZ)] terraform apply FAILED (will retry next interval)" >&2
    fi
}

if [ "$RUN_ONCE" = "1" ]; then
    apply_once
    exit 0
fi

trap 'echo "[$(date -u +%FT%TZ)] received SIGTERM, exiting"; exit 0' TERM INT
while true; do
    apply_once
    echo "[$(date -u +%FT%TZ)] sleeping ${INTERVAL}s until next run"
    sleep "$INTERVAL" &
    wait $!
done
