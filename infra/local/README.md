# MERNSpace local stack

Runs all nine upstream repos as containers so the app can be validated before any AWS spend.

## Prerequisites

- Docker Engine + Compose v2 (`docker compose version`).
- ~15 GB free disk for images (client-ui is ~2 GB).
- Free host ports: `8080` (gateway/client/admin), `8025` (Mailpit UI).

## One-time setup

```bash
cd infra/local
cp .env.example .env
./scripts/generate-auth-keys.sh   # writes secrets/auth/{certs,public}
```

`secrets/` is gitignored. Regenerating the keys invalidates existing tokens.

## Start

```bash
docker compose up -d --build
docker compose ps
```

First start runs Postgres migrations (`auth-migrate`), seeds the admin/tenant (`auth-seed`),
initialises the Mongo replica set (`mongo-init`) and creates Kafka topics (`kafka-init`).

`order-service` only starts listening after its Kafka consumer joins the group, which can take
~30 s on the first boot. A `502` from the gateway during that window is expected; wait for
`docker compose ps` to report `(healthy)`.

## Access

| What | URL | Notes |
| --- | --- | --- |
| Client UI | http://localhost:8080 | Next.js, server-side fetch via gateway |
| Admin UI | http://localhost:8080/admin/ | Vite SPA (base `/admin/`) |
| Auth API | http://localhost:8080/api/auth/ | prefix stripped by nginx |
| Catalog API | http://localhost:8080/api/catalog/ | |
| Order API | http://localhost:8080/api/order/ | |
| Socket.IO | http://localhost:8080/socket.io/ | upgrade proxied to ws-service |
| Mailpit | http://localhost:8025 | captured order emails |

Admin login: `admin@mernspace.local` / `Admin@12345` (tenant `Demo Restaurant`, id `1`).
Override with `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `TENANT_NAME` in `.env` before the first seed.

## Verify

```bash
./scripts/smoke-test.sh
```

Expected: `FAIL=0`. Order creation is skipped until the catalog has a published product,
because the order service prices carts from its Kafka-fed `productCache`.

Manual order check:

```bash
curl -s -c /tmp/c -H 'Content-Type: application/json' \
  -d '{"email":"admin@mernspace.local","password":"Admin@12345"}' \
  http://localhost:8080/api/auth/auth/login

CID=$(curl -s -b /tmp/c http://localhost:8080/api/order/customer | python3 -c 'import json,sys;print(json.load(sys.stdin)["_id"])')
```

Then POST `/api/order/orders` with a cart item that exists in the order `productCache`.
Order emails appear in Mailpit; `ws-service` logs the same `ORDER_CREATE` event.

## Stop / reset

```bash
docker compose down          # keep volumes
docker compose down -v       # wipe Postgres, Mongo, Kafka
```

## Routing

`gateway/nginx.conf` is the single entry point. It strips the first path segment:

- `/api/auth/` -> `auth-service:5501`
- `/api/catalog/` -> `catalog-service:5502`
- `/api/order/` -> `order-service:5503`
- `/socket.io/` -> `ws-service:5504` (WebSocket upgrade)
- `/` -> `client-ui:3000`

Two exact-match locations (`/api/auth/accessToken`, `/api/auth/refresh`) are routed to the
Next.js server so the client's own route handlers are reachable.

## Config

Per-service `node-config` lives in `config/<service>/default.json` and is mounted at `/app/config`.
The upstream repos gitignore `config/`, so these files are required.

Auth env lives directly on the service (see `docker-compose.yml`): `JWKS_URI`,
`REFRESH_TOKEN_SECRET`, `CLIENT_UI_DOMAIN`, `ADMIN_UI_DOMAIN`, `MAIN_DOMAIN`.

`MAIN_DOMAIN=""` produces host-only cookies so the app works on `localhost`. For a public
domain set it to the bare host (e.g. `example.com`).

## Upstream patches applied

Kept minimal and documented because the local stack uses plaintext Kafka and Mailpit:

| Repo | File | Change |
| --- | --- | --- |
| catalog, order, notification, ws | `src/config/kafka.ts` | production branch now also requires `kafka.ssl`; notification/ws use `ssl: config.get("kafka.ssl")` |
| notification | `src/mail.ts` | `secure` read from config, default `true` |
| order | `src/order/orderController.ts` | convert the created Mongoose order/customer to plain objects before `JSON.stringify` (spreading a document created inside a transaction pulls in driver internals and throws "Converting circular structure to JSON") |
| catalog | `src/common/services/S3Storage.ts` | use the AWS default credential chain when keys are absent (EC2 instance role) and return short-lived presigned GET URLs for a private bucket |
| catalog | `src/common/types/storage.ts`, `product/product-controller.ts`, `topping/topping-controller.ts` | `getObjectUri` is async; map image URLs with `Promise.all` |
| catalog | `package.json`, `package-lock.json` | add `@aws-sdk/s3-request-presigner` (pinned to match `client-s3`) |
| client-ui | `next.config.mjs` | allow `**.amazonaws.com` image hosts for presigned S3 URLs |
| admin-ui | `vite.config.ts`, `src/router.tsx` | configurable `base` path + router basename so the SPA can be served at `/admin/` behind the same ingress |

## Known local limitations

- **Product images do not render.** `catalog-service` now returns presigned S3 URLs; the
  local config points at a non-existent bucket, so images 404. Real images are validated on AWS.
- **Product creation needs S3.** The admin upload flow calls S3, so the local catalog has no
  published products. Order pricing was validated with a seeded `productCache` entry.
- **No TLS.** Fine for an IP/origin demo; put a domain + TLS in front before enabling `Secure` cookies.
