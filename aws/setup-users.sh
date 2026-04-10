#!/bin/bash
# OTS Post-Deployment User Setup
# Creates user accounts in OTS via the API and generates connection QR codes
# for TAK Can / iTAK client onboarding on port 8089 (TLS).
#
# Usage:  ./setup-users.sh <domain> <secret-id> [CALLSIGN ...]
#
#   <secret-id>  Secrets Manager secret name or ARN — output of CloudFormation
#                AdminSecretArn, e.g. tak-server/tak-admin or the full ARN.
#                Retrieve it: aws cloudformation describe-stacks \
#                               --stack-name tak-server \
#                               --query 'Stacks[0].Outputs[?OutputKey==`AdminSecretArn`].OutputValue' \
#                               --output text
#
# Output: /opt/tak-server/clients/ — QR PNGs, config text files, credentials
#
# After running this script, issue client certificates per user in the Admin portal:
#   https://<domain> → Users → select user → Issue Certificate

set -e

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <domain> <secret-id> [CALLSIGN ...]"
  echo ""
  echo "  Retrieve secret ID from CloudFormation outputs:"
  echo "    aws cloudformation describe-stacks --stack-name tak-server \\"
  echo "      --query 'Stacks[0].Outputs[?OutputKey==\`AdminSecretArn\`].OutputValue' \\"
  echo "      --output text"
  exit 1
fi

DOMAIN="$1"
SECRET_ID="$2"
shift 2

if [[ $# -gt 0 ]]; then
  CALLSIGNS=("$@")
else
  CALLSIGNS=("ALPHA-1" "BRAVO-1" "CHARLIE-1" "DELTA-1" "ECHO-1")
fi

OTS_API="https://${DOMAIN}:8443"
OUT_DIR="/opt/tak-server/clients"

# Install dependencies if missing
for pkg in qrencode jq; do
  which "$pkg" >/dev/null 2>&1 || dnf install -y "$pkg"
done
mkdir -p "$OUT_DIR"

echo "==> Fetching admin credentials from Secrets Manager ..."
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --query 'SecretString' \
  --output text)
ADMIN_PASS=$(echo "$SECRET" | jq -r '.password')

if [[ -z "$ADMIN_PASS" || "$ADMIN_PASS" == "null" ]]; then
  echo "ERROR: Could not read password from secret '$SECRET_ID'."
  echo "  Ensure you have secretsmanager:GetSecretValue on this secret."
  exit 1
fi

echo "==> Authenticating as administrator at $DOMAIN ..."
TOKEN=$(curl -sk -X POST "$OTS_API/oauth/token" \
  -d "username=administrator&password=${ADMIN_PASS}" \
  | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "ERROR: Authentication failed. The password in the secret may not match OTS."
  exit 1
fi

CREDS_FILE="$OUT_DIR/credentials.txt"
> "$CREDS_FILE"

for callsign in "${CALLSIGNS[@]}"; do
  slug=$(echo "$callsign" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  pass=$(openssl rand -hex 12)

  echo "==> Creating user: $slug ..."
  status=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "$OTS_API/api/user/add" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${slug}\",\"password\":\"${pass}\",\"confirm_password\":\"${pass}\",\"roles\":[\"user\"]}")

  case "$status" in
    200|201) echo "  Created:        $slug" ;;
    409)     echo "  Already exists: $slug (skipped)" ;;
    *)       echo "  WARNING: HTTP $status for $slug" ;;
  esac

  printf '%s:%s\n' "$slug" "$pass" >> "$CREDS_FILE"

  CONFIG="TAK Can,$DOMAIN,8089,ssl"
  printf '%s' "$CONFIG" > "$OUT_DIR/config-${slug}.txt"
  qrencode -o "$OUT_DIR/qr-${slug}.png" -s 8 -l H "$CONFIG"
  echo "  QR generated:   $OUT_DIR/qr-${slug}.png"
done

# Generic server QR (no specific user)
CONFIG="TAK Can,$DOMAIN,8089,ssl"
printf '%s' "$CONFIG" > "$OUT_DIR/server-config.txt"
qrencode -o "$OUT_DIR/server-qr.png" -s 8 -l H "$CONFIG"

chmod 600 "$CREDS_FILE"

echo ""
echo "============================================"
echo "  Server:      https://$DOMAIN"
echo "  Credentials: $CREDS_FILE"
echo "  QR codes:    $OUT_DIR/"
echo ""
echo "  NEXT STEP — issue client certificates:"
echo "  Admin portal → https://$DOMAIN"
echo "  Users → select each user → Issue Certificate"
echo "============================================"
echo ""
echo "  Fetch files:  scp ec2-user@$DOMAIN:$OUT_DIR/* ."
echo "============================================"
