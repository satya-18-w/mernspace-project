# MERNSpace on single-node K3s

This tree is a **Kustomize** deployment for the seven MERNSpace images, Kafka,
MongoDB, and Mailpit. It is designed for one K3s node on EC2 with Traefik and
the `local-path` provisioner.

## Layout

```
base/                      # all workloads, services, jobs, generated configs
baseline/                  # base + placeholder runtime ConfigMap (local use)
overlays/aws/              # base + real runtime ConfigMap + Traefik Ingress
```

Everything is pinned to one replica. MongoDB is a single-node replica set
(`rs0`) because the order service uses transactions. Kafka is a single-node
KRaft broker. Mailpit has no public route; use `kubectl port-forward` for its UI.

## Prerequisites on the node

- K3s installed with its bundled Traefik and ServiceLB.
- `kubectl` configured (copy `/etc/rancher/k3s/k3s.yaml`).
- Images pushed to ECR (see `infra/aws/`).
- An ECR pull secret named `ecr-pull` in namespace `mernspace`, refreshed by a
  systemd timer (set up by the K3s bootstrap).

## One-time secrets and config

Do **not** commit these values.

```bash
kubectl create namespace mernspace

kubectl -n mernspace create secret generic auth-env \
  --from-literal=DB_HOST="$RDS_ENDPOINT" \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_USERNAME="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=DB_NAME=mernspace_auth \
  --from-literal=REFRESH_TOKEN_SECRET="$REFRESH_TOKEN_SECRET"

kubectl -n mernspace create secret generic auth-certs \
  --from-file=private.pem=./infra/local/secrets/auth/private.pem \
  --from-file=public.pem=./infra/local/secrets/auth/public.pem

kubectl -n mernspace create configmap auth-jwks \
  --from-file=jwks.json=./infra/local/secrets/auth/jwks.json

kubectl -n mernspace create secret generic ecr-pull \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson=./infra/aws/.dockerconfigjson
```

`infra/local/secrets/auth/` is gitignored. Back it up somewhere safe; regenerating
the keys invalidates existing sessions.

## Deploy

```bash
cd infra/k8s/overlays/aws
PUBLIC_ORIGIN="http://$EIP" \
S3_BUCKET="$S3_BUCKET" \
S3_REGION="ap-south-1" \
  envsubst < runtime-config.yaml.tmpl > runtime-config.yaml

kubectl apply -k .

kubectl -n mernspace rollout status deploy/auth-service
kubectl -n mernspace rollout status deploy/catalog-service
kubectl -n mernspace rollout status deploy/order-service
kubectl -n mernspace rollout status deploy/ws-service
kubectl -n mernspace rollout status deploy/notification-service
kubectl -n mernspace rollout status deploy/client-ui
kubectl -n mernspace rollout status deploy/admin-ui
kubectl -n mernspace rollout status deploy/gateway
kubectl -n mernspace rollout status statefulset/mongo
kubectl -n mernspace rollout status statefulset/kafka
kubectl -n mernspace wait --for=condition=complete job/mongo-init --timeout=300s
kubectl -n mernspace wait --for=condition=complete job/kafka-init --timeout=300s
```

## Checks

```bash
kubectl -n mernspace get pods -o wide
kubectl -n mernspace logs deploy/order-service --tail=100
kubectl -n mernspace logs deploy/notification-service --tail=100
kubectl -n mernspace exec deploy/mongo -- mongosh --quiet --eval 'rs.status().ok'
kubectl -n mernspace exec deploy/kafka -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
kubectl -n mernspace port-forward svc/mailpit 8025:8025   # http://localhost:8025
```

## Notes

- `generatorOptions.disableNameSuffixHash` keeps ConfigMap names stable. After
  changing a generated ConfigMap, run `kubectl -n mernspace rollout restart` on
  the affected Deployment.
- `order-service` joins its Kafka consumer group before it starts listening, so
  its startup probe allows up to five minutes.
- Mongo and Kafka PVCs are 8 GiB each. The EC2 root volume is sized at 30 GiB.
- `main_domain` is intentionally empty: cookies are host-only because the app
  is served from an IP address, not a domain.
