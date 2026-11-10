#!/usr/bin/env bash
# Seed one admin, one category, and one published product so the full order
# flow can be exercised. Idempotent for the admin; the catalog items are
# created once (reruns create another product).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/infra/aws/outputs.env"

KUBECONFIG=${KUBECONFIG:-$HOME/.kube/mernspace.yaml}
export KUBECONFIG
export PUBLIC_ORIGIN=${PUBLIC_ORIGIN:-http://$EIP}

echo "== seed admin (inside auth pod) =="
kubectl -n mernspace exec -i deploy/auth-service -- node - <<'JS'
const { Client } = require("pg");
const bcrypt = require("bcryptjs");

(async () => {
  const c = new Client({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    user: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();
  let t = await c.query("SELECT id FROM tenants WHERE name = $1 LIMIT 1", ["Demo Restaurant"]);
  if (t.rowCount === 0) {
    t = await c.query("INSERT INTO tenants(name, address) VALUES ($1,$2) RETURNING id", ["Demo Restaurant", "1 Demo Street"]);
  }
  const tenantId = t.rows[0].id;
  const hash = await bcrypt.hash("Admin@12345", 10);
  await c.query(
    `INSERT INTO users("firstName","lastName",email,password,role,"tenantId")
     VALUES ($1,$2,$3,$4,'admin',$5)
     ON CONFLICT (email) DO UPDATE
       SET password = EXCLUDED.password, role = 'admin', "tenantId" = EXCLUDED."tenantId"`,
    ["Demo", "Admin", "admin@mernspace.local", hash, tenantId],
  );
  console.log(`admin seeded, tenantId=${tenantId}`);
  await c.end();
})().catch((e) => { console.error(e); process.exit(1); });
JS

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== login =="
curl -fsS -c "$TMP/cookies" \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@mernspace.local","password":"Admin@12345"}' \
    "$PUBLIC_ORIGIN/api/auth/auth/login" >/dev/null
TOKEN=$(curl -fsS -b "$TMP/cookies" "$PUBLIC_ORIGIN/api/auth/accessToken" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

echo "== create category =="
CATEGORY_ID=$(curl -fsS -X POST "$PUBLIC_ORIGIN/api/catalog/categories" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d '{"name":"Pizza","priceConfiguration":{"Size":{"priceType":"base","availableOptions":["Small","Large"]}},"attributes":[{"name":"Crust","widgetType":"radio","defaultValue":"Thin","availableOptions":["Thin","Thick"]}]}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
echo "category $CATEGORY_ID"

echo "== create product =="
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=' \
    | base64 -d > "$TMP/pixel.png"
PRODUCT_ID=$(curl -fsS -X POST "$PUBLIC_ORIGIN/api/catalog/products" \
    -H "Authorization: Bearer $TOKEN" \
    -F 'name=Margherita' \
    -F 'description=Tomato, mozzarella, basil' \
    -F 'priceConfiguration={"Size":{"priceType":"base","availableOptions":{"Small":199,"Large":299}}}' \
    -F 'attributes=[{"name":"Crust","value":"Thin"}]' \
    -F 'tenantId=1' \
    -F "categoryId=$CATEGORY_ID" \
    -F 'isPublish=true' \
    -F "image=@$TMP/pixel.png;type=image/png" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
echo "product $PRODUCT_ID"
echo "Seed complete. Run smoke-test.sh next."
