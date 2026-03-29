#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TF=tofu

# ---------------------------------------------------------------------------
# Load credentials and environment
# ---------------------------------------------------------------------------
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env not found. Copy .env.example and fill in your values." >&2
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/terraform.tfvars" ]; then
  echo "ERROR: terraform.tfvars not found. Copy terraform.tfvars.example and fill in your values." >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$SCRIPT_DIR/env.sh"

# ---------------------------------------------------------------------------
# Validate credentials before doing anything expensive
# ---------------------------------------------------------------------------
echo ""
echo "=== Validating credentials ==="

ERRORS=0
check_var() {
  local name="$1" val="${2:-}"
  if [ -z "$val" ]; then
    echo "  [FAIL] $name is not set in .env"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK]   $name"
  fi
}

check_var "SF_ADMIN_PASSWORD"    "${SF_ADMIN_PASSWORD:-}"
check_var "R2_ACCOUNT_ID"        "${R2_ACCOUNT_ID:-}"
check_var "R2_ACCESS_KEY_ID"     "${R2_ACCESS_KEY_ID:-}"
check_var "R2_SECRET_ACCESS_KEY" "${R2_SECRET_ACCESS_KEY:-}"
check_var "R2_BUCKET_NAME"       "${R2_BUCKET_NAME:-}"

if [ "${STATE_BACKEND:-gitlab}" = "gitlab" ]; then
  check_var "GITLAB_PROJECT_URL"          "${GITLAB_PROJECT_URL:-}"
  check_var "GITLAB_PROJECT_ACCESS_TOKEN" "${GITLAB_PROJECT_ACCESS_TOKEN:-}"
  check_var "TF_STATE_NAME"               "${TF_STATE_NAME:-}"
else
  echo "  [OK]   STATE_BACKEND=local (GitLab credentials not required)"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "Fix the above errors in .env before continuing." >&2
  exit 1
fi

# Validate R2 bucket access using AWS Sig V4 (Python stdlib — no extra tools needed)
if ! command -v python3 &>/dev/null; then
  echo "  [SKIP] python3 not found — skipping R2 connectivity check"
else
  python3 << 'PYEOF'
import datetime, hashlib, hmac, sys, os
import urllib.request, urllib.error

def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

def signing_key(secret, date_stamp, region, service):
    return sign(sign(sign(sign(('AWS4' + secret).encode('utf-8'), date_stamp), region), service), 'aws4_request')

account_id   = os.environ['R2_ACCOUNT_ID']
access_key   = os.environ['R2_ACCESS_KEY_ID']
secret_key   = os.environ['R2_SECRET_ACCESS_KEY']
bucket       = os.environ['R2_BUCKET_NAME']
jurisdiction = os.environ.get('R2_JURISDICTION', '').strip().lower()
region       = 'auto'
service      = 's3'
host         = f'{account_id}.{jurisdiction + "." if jurisdiction else ""}r2.cloudflarestorage.com'

now        = datetime.datetime.now(datetime.timezone.utc)
amz_date   = now.strftime('%Y%m%dT%H%M%SZ')
date_stamp = now.strftime('%Y%m%d')

# ListObjectsV2 with max-keys=0 — authenticated but returns no data
method         = 'GET'
canonical_uri  = f'/{bucket}'
canonical_qs   = 'list-type=2&max-keys=0'
payload_hash   = hashlib.sha256(b'').hexdigest()
canonical_hdrs = f'host:{host}\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{amz_date}\n'
signed_hdrs    = 'host;x-amz-content-sha256;x-amz-date'
canonical_req  = f'{method}\n{canonical_uri}\n{canonical_qs}\n{canonical_hdrs}\n{signed_hdrs}\n{payload_hash}'

cred_scope     = f'{date_stamp}/{region}/{service}/aws4_request'
string_to_sign = f'AWS4-HMAC-SHA256\n{amz_date}\n{cred_scope}\n{hashlib.sha256(canonical_req.encode()).hexdigest()}'
sig            = hmac.new(signing_key(secret_key, date_stamp, region, service), string_to_sign.encode(), hashlib.sha256).hexdigest()
auth           = f'AWS4-HMAC-SHA256 Credential={access_key}/{cred_scope}, SignedHeaders={signed_hdrs}, Signature={sig}'

url = f'https://{host}/{bucket}?{canonical_qs}'
req = urllib.request.Request(url, headers={
    'Authorization':        auth,
    'x-amz-date':           amz_date,
    'x-amz-content-sha256': payload_hash,
})

try:
    urllib.request.urlopen(req)
    print(f'  [OK]   R2 bucket "{bucket}" is accessible')
except urllib.error.HTTPError as e:
    body = e.read().decode(errors='replace')
    if e.code == 404:
        print(f'  [FAIL] R2 bucket "{bucket}" does not exist — create it in the Cloudflare dashboard', file=sys.stderr)
    elif e.code in (401, 403):
        print(f'  [FAIL] R2 credentials rejected (HTTP {e.code}) — check R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY', file=sys.stderr)
    else:
        print(f'  [FAIL] Unexpected R2 response HTTP {e.code}: {body[:300]}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'  [FAIL] Could not reach R2 endpoint: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
fi

echo "  [NOTE] SF_ADMIN_PASSWORD cannot be validated until the server is running"
echo "=== Validation passed ==="

# ---------------------------------------------------------------------------
# Configure backend
# ---------------------------------------------------------------------------
BACKEND_ARGS=""
if [ "${STATE_BACKEND:-gitlab}" = "gitlab" ]; then
  # Generate backend.hcl from .env values (never committed — in .gitignore)
  # Extract the project path (e.g. "user/repo") and URL-encode the slash.
  PROJECT_PATH="${GITLAB_PROJECT_URL#https://*/}"
  PROJECT_PATH_ENCODED="${PROJECT_PATH/\//\%2F}"
  GITLAB_HOST="${GITLAB_PROJECT_URL%%/${PROJECT_PATH}}"
  STATE_BASE="${GITLAB_HOST}/api/v4/projects/${PROJECT_PATH_ENCODED}/terraform/state/${TF_STATE_NAME}"

  cat > "$SCRIPT_DIR/backend.hcl" <<EOF
address        = "${STATE_BASE}"
lock_address   = "${STATE_BASE}/lock"
unlock_address = "${STATE_BASE}/lock"
lock_method    = "POST"
unlock_method  = "DELETE"
retry_wait_min = 5
headers        = { "PRIVATE-TOKEN" = "${GITLAB_PROJECT_ACCESS_TOKEN}" }
EOF
  BACKEND_ARGS="-backend-config=backend.hcl"
  echo "Using GitLab remote state backend"
else
  echo "Using local state backend (terraform.tfstate)"
fi

# ---------------------------------------------------------------------------
# Terraform init → plan → apply
# ---------------------------------------------------------------------------
echo ""
echo "=== $TF init ==="
# shellcheck disable=SC2086
$TF init -reconfigure $BACKEND_ARGS

echo ""
echo "=== $TF plan ==="
$TF plan -out=tfplan

echo ""
read -rp "Apply the plan? [y/N] " confirm
if [ "${confirm,,}" != "y" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=== $TF apply ==="
$TF apply tfplan
rm -f tfplan

echo ""
echo "=== Done ==="
$TF output

# ---------------------------------------------------------------------------
# Stream installation logs from the new instance
# ---------------------------------------------------------------------------
FLOATING_IP="$($TF output -raw floating_ip)"

echo ""
echo "=== Waiting for SSH on ${FLOATING_IP} ==="
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
until ssh $SSH_OPTS "ubuntu@${FLOATING_IP}" true 2>/dev/null; do
  printf "."
  sleep 5
done
echo " ready."

echo ""
echo "=== Installation log (Ctrl+C to stop following) ==="
# Follow the log until the bootstrap complete marker appears, then exit
ssh $SSH_OPTS "ubuntu@${FLOATING_IP}" \
  "tail -n +1 -f --retry /var/log/satisfactory-setup.log | awk '/Bootstrap complete/{print; fflush(); exit} {print; fflush()}'"
