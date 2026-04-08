#!/bin/bash
# TAK Server — Server Config QR Code Generator
# Generates QR codes for TAK Can / iTAK client onboarding.
# Run on the EC2 instance after FreeTAKServer 2.x is up.
#
# Usage:  ./setup-users.sh [domain]
# Output: /opt/tak-server/clients/ — QR code PNGs + config text files
# Format: name,host,port,protocol  (iTAK / TAK Can QR format)

set -e

DOMAIN="${1:-tak.takaware.ca}"
OUT_DIR="/opt/tak-server/clients"
mkdir -p "$OUT_DIR"

which qrencode >/dev/null 2>&1 || yum install -y qrencode

# Connection string: iTAK / TAK Can server config QR format
CONFIG="TAK Can,$DOMAIN,8089,ssl"

DEVICES=("ALPHA-1" "BRAVO-1" "CHARLIE-1" "DELTA-1" "ECHO-1")
for callsign in "${DEVICES[@]}"; do
  slug=$(echo "$callsign" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$CONFIG" > "$OUT_DIR/config-${slug}.txt"
  qrencode -o "$OUT_DIR/qr-${slug}.png" -s 8 -l H "$CONFIG"
  echo "Generated: qr-${slug}.png  →  $CONFIG"
done

# Generic server QR (no callsign)
printf '%s' "$CONFIG" > "$OUT_DIR/server-config.txt"
qrencode -o "$OUT_DIR/server-qr.png" -s 8 -l H "$CONFIG"

echo ""
echo "============================================"
echo "  TAK Server: $DOMAIN"
echo "  QR content: $CONFIG"
echo "  QR files:   $OUT_DIR/"
echo "  Fetch them: scp ec2-user@$DOMAIN:$OUT_DIR/*.png ."
echo "============================================"
