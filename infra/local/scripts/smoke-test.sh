#!/usr/bin/env bash
# End-to-end smoke test for the local MERNSpace stack.
# Usage: BASE=http://localhost:8080 ./smoke-test.sh
set -uo pipefail

BASE=${BASE:-http://localhost:8080}
ADMIN_URL=${ADMIN_URL:-http://localhost:8080/admin}
MAILPIT=${MAILPIT:-http://localhost:8025}
EMAIL=${ADMIN_EMAIL:-admin@mernspace.local}
PASSWORD=${ADMIN_PASSWORD:-Admin@12345}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
SKIP=0

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check_code() {
    local name=$1 expected=$2
    shift 2
    local got
    got=$(code "$@")
    if [ "$got" = "$expected" ]; then
        echo "PASS  $name ($got)"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $name (expected $expected, got $got)"
        FAIL=$((FAIL + 1))
    fi
}

check_json() {
    local name=$1 expr=$2 file=$3
    if python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if ($expr) else 1)" "$file" 2>/dev/null; then
        echo "PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "== frontends =="
check_code "gateway client" 200 "$BASE/"
check_code "admin ui" 200 "$ADMIN_URL/"

echo "== service roots =="
check_code "auth root" 200 "$BASE/api/auth/"
check_code "catalog root" 200 "$BASE/api/catalog/"
check_code "order root" 200 "$BASE/api/order/"
check_code "jwks" 200 "$BASE/api/auth/.well-known/jwks.json"

echo "== auth =="
check_code "admin login" 200 -c "$TMP/cookies" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    "$BASE/api/auth/auth/login"
check_code "auth self" 200 -b "$TMP/cookies" "$BASE/api/auth/auth/self"
check_code "access token helper" 200 -b "$TMP/cookies" "$BASE/api/auth/accessToken"

echo "== catalog =="
check_code "list categories" 200 "$BASE/api/catalog/categories"
check_code "list products" 200 "$BASE/api/catalog/products?perPage=100&limit=100&tenantId=1"
check_code "list tenants" 200 -b "$TMP/cookies" "$BASE/api/auth/tenants"

echo "== order =="
check_code "get/auto-create customer" 200 -b "$TMP/cookies" "$BASE/api/order/customer"

curl -s -b "$TMP/cookies" "$BASE/api/order/customer" -o "$TMP/customer.json"
CUSTOMER_ID=$(python3 -c "import json;print(json.load(open('$TMP/customer.json'))['_id'])" 2>/dev/null || true)

curl -s "$BASE/api/catalog/products?perPage=100&limit=100&tenantId=1" -o "$TMP/products.json"
PRODUCT_ID=$(python3 -c "import json;d=json.load(open('$TMP/products.json'));print(d['data'][0]['_id'] if d.get('data') else '')" 2>/dev/null || true)

if [ -n "$CUSTOMER_ID" ] && [ -n "$PRODUCT_ID" ]; then
    python3 - "$TMP/products.json" "$CUSTOMER_ID" > "$TMP/order-body.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))["data"][0]
print(json.dumps({
    "cart": [{
        "_id": p["_id"],
        "name": p["name"],
        "image": p.get("image", ""),
        "qty": 1,
        "priceConfiguration": p["priceConfiguration"],
        "chosenConfiguration": {
            "priceConfiguration": {k: list(v["availableOptions"])[0] for k, v in p["priceConfiguration"].items()},
            "selectedToppings": [],
        },
    }],
    "tenantId": "1",
    "paymentMode": "cash",
    "customerId": sys.argv[2],
    "address": "1 Demo Street, Demo City",
    "comment": "smoke test",
}))
PY
    check_code "create COD order" 200 -b "$TMP/cookies" \
        -H 'Content-Type: application/json' \
        -H "Idempotency-Key: smoke-$(date +%s)" \
        --data @"$TMP/order-body.json" \
        "$BASE/api/order/orders"
else
    echo "SKIP  create COD order (no published catalog product yet)"
    SKIP=$((SKIP + 1))
fi

curl -s -b "$TMP/cookies" "$BASE/api/order/orders" -o "$TMP/orders.json"
check_json "list orders" "isinstance(d, list) and len(d) >= 1" "$TMP/orders.json"

echo "== notification =="
if curl -sf "$MAILPIT/api/v1/messages" -o "$TMP/mail.json"; then
    check_json "mailpit received order email" "d.get('total', 0) >= 1" "$TMP/mail.json"
else
    echo "SKIP  mailpit not reachable at $MAILPIT"
    SKIP=$((SKIP + 1))
fi

echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
