# AWS vertical slice (ap-south-1)

This directory drives a single-node K3s deployment on EC2 with RDS PostgreSQL,
ECR, S3, CloudWatch, and an Elastic IP. Read `PLAN.md` first. Nothing is
created until you type `APPROVE PROVISIONING`.

## Prerequisites

- AWS CLI v2 authenticated with the `mernspace` profile, region `ap-south-1`.
- Permissions for EC2/VPC/EIP, RDS, ECR, S3, CloudWatch Logs, and IAM
  role/instance-profile creation (`iam:CreateRole`, `iam:PassRole`, ...).
- Docker, `kubectl`, `envsubst`, `ssh`, `scp`, `python3`, `curl`.
- The local auth keys exist at `infra/local/secrets/auth/` (generated during the
  local setup). They are gitignored. Regenerating them invalidates sessions.

Verify identity:

```bash
AWS_PROFILE=mernspace aws sts get-caller-identity
```

## 1. Create infrastructure (billable, gated)

```bash
cd infra/aws
AWS_PROFILE=mernspace ./create-infra.sh
```

Optional overrides:

```bash
INSTANCE_TYPE=t3.large PG_VERSION=17.9 KEY_NAME=my-existing-key ./create-infra.sh
```

It writes `outputs.env` (chmod 600, gitignored) with the instance, EIP, RDS
endpoint, bucket, ECR registry, and generated secrets. It refuses to run again
while `outputs.env` exists; use `cleanup.sh` to reset.

## 2. Kubernetes access (SSH tunnel, no public API)

Wait 2-3 minutes for the K3s user data to finish, then:

```bash
# terminal 1: keep this open
ssh -i infra/aws/mernspace-k3s.pem \
    -L 6443:127.0.0.1:6443 ubuntu@<EIP>

# terminal 2: copy the kubeconfig (server is already https://127.0.0.1:6443)
scp -i infra/aws/mernspace-k3s.pem \
    ubuntu@<EIP>:/etc/rancher/k3s/k3s.yaml ~/.kube/mernspace.yaml
chmod 600 ~/.kube/mernspace.yaml
export KUBECONFIG=$HOME/.kube/mernspace.yaml
kubectl get nodes
```

Port 6443 is never opened in the security group. The SSH tunnel carries it.
Port 22 is open only to the IP captured when `create-infra.sh` ran.

## 3. Build and push images

Use the EIP from `outputs.env`:

```bash
cd infra/aws
set -a; source outputs.env; set +a
PUBLIC_ORIGIN="http://$EIP" TAG=v1 ./build-images.sh
TAG=v1 ./push-images.sh
```

Tags are immutable by convention (`v1`, `v2`, ...). The node pulls with the
`ecr-pull` secret that the systemd timer refreshes every 6 hours.

Catalog is currently pinned to `v2` in `deploy-k8s.sh` for the S3 Buffer fix;
build/push catalog with that tag when deploying from scratch.

## 4. Deploy

```bash
cd infra/aws
export KUBECONFIG=$HOME/.kube/mernspace.yaml
./deploy-k8s.sh
```

This creates `auth-env`, `auth-certs`, `auth-jwks`, and `ecr-pull`, generates
the runtime ConfigMap and the Kustomize image overrides, applies the overlay,
and waits for rollouts and the Mongo/Kafka init jobs.

## 5. Seed and verify

```bash
./seed-demo.sh
./smoke-test.sh

# Mailpit UI (internal only). Use 18025 if the local stack owns 8025.
kubectl -n mernspace port-forward svc/mailpit 18025:8025
MAILPIT=http://127.0.0.1:18025 ./smoke-test.sh
```

URLs: `http://<EIP>/` and `http://<EIP>/admin/`.
Admin credentials created by the seeder: `admin@mernspace.local` / `Admin@12345`.

## 6. Inspect

```bash
kubectl -n mernspace get pods -o wide
kubectl -n mernspace logs deploy/order-service --tail=100
kubectl -n mernspace logs deploy/notification-service --tail=100
kubectl -n mernspace exec deploy/mongo -- mongosh --quiet --eval 'rs.status().ok'
kubectl -n mernspace exec deploy/kafka -- \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
aws logs tail /mernspace/k3s --since 15m
```

## 7. Cleanup (billable)

```bash
cd infra/aws
AWS_PROFILE=mernspace ./cleanup.sh   # type APPROVE CLEANUP
```

Order: EC2, EIP, RDS, ECR, S3, CloudWatch, network, IAM. `outputs.env` is
removed. Delete `infra/aws/mernspace-k3s.pem` manually; it is useless once the
instance is gone.

## Troubleshooting

| Symptom | Check |
|---|---|
| `ImagePullBackOff` | `kubectl -n mernspace get secret ecr-pull`; `systemctl status refresh-ecr.timer` on the node; re-run `push-images.sh` |
| auth pod stuck in `Init` | RDS SG/route; `kubectl logs <pod> -c migrate`; RDS endpoint in `auth-env` |
| `order-service` not ready | Kafka not up yet; `kubectl logs deploy/order-service`; it joins the consumer group before listening |
| Mongo transactions fail | `kubectl logs job/mongo-init`; `rs.status()` must show one primary |
| admin `/admin/` 404 | image built without `VITE_BASE_PATH=/admin/`; rebuild admin-ui |
| images 403/expired | the S3 CORS origin and the EIP differ; `aws s3api get-bucket-cors` |
| catalog pod `Config validation error` | `NODE_CONFIG` JSON; check the pod env and `/app/config/default.json` |

## Security notes

- SSH is restricted to the operator IP; 80 is public; everything else is closed.
- RDS is not publicly accessible; only the EC2 SG can reach 5432.
- No AWS access keys on the node: the instance profile supplies ECR, S3, and
  CloudWatch permissions.
- `outputs.env`, `*.pem`, and the generated runtime/kustomization files are
  gitignored.
- This is HTTP-only, single-node, single-AZ. It is a demo, not an HA production
  design. Do not reuse the seeded demo credentials for anything real.
