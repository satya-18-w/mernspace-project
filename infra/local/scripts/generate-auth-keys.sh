#!/usr/bin/env bash
# Generates a fresh RSA keypair + JWKS for the auth service and stores them in
# infra/local/secrets/auth (never committed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$LOCAL_DIR/../.." && pwd)"
AUTH_DIR="$PROJECT_DIR/mernspace-c-auth-service"
OUT_DIR="$LOCAL_DIR/secrets/auth"

mkdir -p "$OUT_DIR/certs" "$OUT_DIR/public/.well-known"

if [ ! -d "$AUTH_DIR/node_modules/rsa-pem-to-jwk" ]; then
    echo "Installing auth-service dependencies (needed for key conversion)..." >&2
    ( cd "$AUTH_DIR" && npm ci --ignore-scripts >/dev/null )
fi

(
    cd "$AUTH_DIR"
    rm -rf certs
    mkdir -p certs
    node scripts/generateKeys.mjs >/dev/null
    cp certs/private.pem certs/public.pem "$OUT_DIR/certs/"
    # convertPemToJwk prints a single JWK; wrap it in the JWKS shape.
    node scripts/convertPemToJwk.mjs > /tmp/mernspace-jwk.json
    node -e '
      const fs = require("fs");
      const jwk = JSON.parse(fs.readFileSync("/tmp/mernspace-jwk.json", "utf8"));
      fs.writeFileSync(process.argv[1], JSON.stringify({ keys: [jwk] }, null, 4) + "\n");
    ' "$OUT_DIR/public/.well-known/jwks.json"
    rm -rf certs
)

chmod 600 "$OUT_DIR/certs/private.pem"
chmod 644 "$OUT_DIR/certs/public.pem" "$OUT_DIR/public/.well-known/jwks.json"

echo "Auth keys written to $OUT_DIR"
