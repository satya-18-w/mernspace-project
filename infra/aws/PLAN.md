# MERNSpace AWS deployment plan (ap-south-1)

Status: **deployed and verified on 2026-11-10. Actual EC2 type is `c7i-flex.large` (2 vCPU/8 GiB), not the planned `t3.medium`; the cost table below is the original baseline and needs recalculation for the actual type.**

## 1. Architecture

```
Internet
   |
   |  HTTP :80  (only 0.0.0.0/0)
   v
Elastic IP ---> EC2 c7i-flex.large (Ubuntu 24.04, 30 GiB gp3)
                   |
                   +-- K3s (Traefik + ServiceLB + local-path)
                   |     |- gateway (nginx)  :80
                   |     |- client-ui (Next) :3000
                   |     |- admin-ui (nginx) :80
                   |     |- auth-service     :5501
                   |     |- catalog-service  :5502
                   |     |- order-service    :5503
                   |     |- ws-service       :5504
                   |     |- notification-service (no listener)
                   |     |- mongo  (StatefulSet, 8 GiB PVC, replica set rs0)
                   |     |- kafka  (StatefulSet, 8 GiB PVC, KRaft)
                   |     `- mailpit (internal only)
                   |
                   `-- RDS PostgreSQL 16.9, db.t4g.micro, 20 GiB gp3
                         private subnets, no public access, SG from EC2 only

S3 (private, SSE-S3, Block Public Access) <--- catalog-service (instance role)
ECR (7 repositories) <--- node pull credential (instance role)
CloudWatch Logs /mernspace/k3s <--- Fluent Bit DaemonSet
```

Single node, single replica per workload. This is a demo/learning deployment,
not a production HA design.

## 2. Network

| Resource | Value |
|---|---|
| Region | `ap-south-1` |
| VPC | `10.20.0.0/16` |
| Public subnet | `10.20.1.0/24` (`ap-south-1a`) - EC2 |
| Private subnet | `10.20.2.0/24` (`ap-south-1b`) - RDS |
| Private subnet | `10.20.3.0/24` (`ap-south-1a`) - RDS subnet group |
| Internet gateway | one, public route table only |
| NAT gateway | **none** (not needed; saves ~$1/day) |

Security groups:

| SG | Inbound | Notes |
|---|---|---|
| `mernspace-ec2-sg` | `22/tcp` from your current public IP, `80/tcp` from `0.0.0.0/0` | egress all |
| `mernspace-rds-sg` | `5432/tcp` from `mernspace-ec2-sg` | no public access |

Ports 443, 6443, 5501-5504, 9092, 27017, and 8025 stay closed to the internet.
Kubernetes is administered over an SSH tunnel (`ssh -L 6443:127.0.0.1:6443`).

## 3. Resources

| Resource | Specification | Why |
|---|---|---|
| EC2 | `c7i-flex.large`, Ubuntu 24.04, 30 GiB gp3, Elastic IP | 8 GiB fits the measured ~800 MiB idle stack plus Kafka page cache; 30 GiB leaves room for the 16 GiB of PVCs and images |
| RDS | PostgreSQL 16.9, `db.t4g.micro`, Single-AZ, 20 GiB gp3, 1-day backups | auth service only; smallest burstable instance is sufficient |
| ECR | `mernspace/auth`, `/catalog`, `/order`, `/notification`, `/ws`, `/client-ui`, `/admin-ui` | one repo per image, scan on push, keep last 5 |
| S3 | `mernspace-assets-<account-id>-ap-south-1` | product images; private + SSE-S3 + BPA |
| CloudWatch | log group `/mernspace/k3s`, 7-day retention | container logs |
| IAM | instance profile for ECR pull, S3 object access, CloudWatch Logs | no long-lived keys on the node |
| EIP | one, associated | stable public origin |

No ALB, NAT gateway, Multi-AZ RDS, ElastiCache, MSK, Route 53 zone, or ACM
certificate. HTTP only, no domain, as agreed.

## 4. Monthly cost estimate (ap-south-1, 730 h)

Assumptions: light demo traffic, 1 GiB S3, 2 GiB ECR, 1 GiB logs ingested and
stored, 1 GiB internet egress per month.

| Item | Calculation | USD/month |
|---|---|---|
| EC2 `t3.medium` | 730 x $0.0448 | 32.70 |
| EC2 root EBS 30 GiB gp3 | 30 x $0.0912 | 2.74 |
| Public IPv4 (EIP) | 730 x $0.005 | 3.65 |
| RDS `db.t4g.micro` | 730 x $0.021 | 15.33 |
| RDS storage 20 GiB gp3 | 20 x $0.138 | 2.76 |
| S3 Standard 1 GiB | 1 x $0.025 | 0.03 |
| ECR 2 GiB | 2 x $0.10 | 0.20 |
| CloudWatch Logs (1 GiB ingest + store) | 1 x $0.63 + 1 x $0.03 | 0.66 |
| Data transfer out 1 GiB | 1 x $0.1093 | 0.11 |
| **Total** | | **~$58.18** |

The actual deployment uses `c7i-flex.large`; the EC2 row above is the original
`t3.medium` baseline and the total must be recalculated. `t3.large` instead of
`t3.medium` would have been **+$32.70/month**, total **~$90.88/month**.

The estimate excludes taxes, free-tier credits, and any extra data transfer.
Cost Explorer is not enabled for this account, so this is calculated from the
Price List API rates, not actual bills. A budget/alarm may fail if the account
lacks `budgets:*`; it is optional.

## 5. Image build and registry

Build locally with the existing Dockerfiles (no in-cluster builds):
`infra/local/Dockerfile.backend`, `Dockerfile.client-ui`, `Dockerfile.admin-ui`.

| Image | Dockerfile | Build args |
|---|---|---|
| `auth` | `Dockerfile.backend` | `START_FILE=server.js` |
| `catalog` | `Dockerfile.backend` | `START_FILE=server.js` |
| `order` | `Dockerfile.backend` | `START_FILE=server.js` |
| `notification` | `Dockerfile.backend` | `START_FILE=server.js` |
| `ws` | `Dockerfile.backend` | `START_FILE=server.js` |
| `client-ui` | `Dockerfile.client-ui` | `NEXT_PUBLIC_BACKEND_URL=http://<EIP>` |
| `admin-ui` | `Dockerfile.admin-ui` | `VITE_BACKEND_API_URL=http://<EIP>`, `VITE_SOCKET_SERVICE_URL=http://<EIP>`, `VITE_BASE_PATH=/admin/` |

Push to ECR with immutable tags (`v1`, `v2`, ...). The node pulls with a
`ecr-pull` docker-registry secret refreshed every 6 hours by a systemd timer.

## 6. Deploy sequence

1. `create-infra.sh` (gated) - VPC, SGs, RDS, ECR, S3, EIP, EC2, instance
   profile, log group, key pair if requested. Writes `outputs.env`.
2. `build-images.sh` - 7 local images, tagged for ECR.
3. `push-images.sh` - ECR login and push.
4. `ssh` bootstrap completion check; copy `/etc/rancher/k3s/k3s.yaml`.
5. `deploy-k8s.sh` - namespace, secrets, JWKS, runtime ConfigMap, `kubectl apply -k`,
   wait for rollouts and init jobs.
6. `smoke-test.sh` - login, catalog, admin, order flow, Mailpit email, ws event.
7. Optional: seed catalog through the admin UI (tenant `Demo Restaurant`, id 1).

## 7. Verification checklist

- `kubectl get pods` all `Running`/`Completed`; no `CrashLoopBackOff`.
- `rs.status().ok == 1` in Mongo; `kafka-topics.sh --list` shows
  `product`, `topping`, `order`.
- `GET /` returns the client UI; `GET /admin/` returns the admin UI.
- `POST /api/auth/auth/login` with the seeded admin returns 200 and cookies.
- `GET /api/catalog/category` (or tenant/product list) returns 200.
- Create a COD order; `order-service` logs the Kafka publish; Mailpit receives
  the notification; a `socket.io` client receives the order event.
- Catalog image upload works and returns an `https://<bucket>.s3.ap-south-1.amazonaws.com/...`
  presigned URL that loads in a browser.
- `aws logs tail /mernspace/k3s --since 15m` shows container logs.
- RDS is not publicly accessible; `nc -zv <rds-endpoint> 5432` from the internet
  fails, from the node succeeds.
- Only 22 (your IP) and 80 (world) are open on the EC2 SG.

## 8. Cleanup

`cleanup.sh` (gated) performs, in order:

1. `kubectl delete -k infra/k8s/overlays/aws` (optional; the instance is deleted
   anyway).
2. Terminate the EC2 instance and wait; root EBS is deleted on termination.
3. Release the Elastic IP.
4. Delete the RDS instance (`--skip-final-snapshot --delete-automated-backups`)
   and wait, then the DB subnet group.
5. Delete the 7 ECR repositories with `--force`.
6. Empty and delete the S3 bucket.
7. Delete the CloudWatch log group.
8. Delete security groups, subnets, route tables, internet gateway, VPC.
9. Delete the instance profile/role and detach policies.

Manual confirmation is required; the script prints each command before running.

## 9. Approval

Reply with **APPROVE PROVISIONING** plus any changes, and confirm:

- [ ] `t3.medium` (default) or `t3.large`
- [ ] PostgreSQL `16.9` (default) or `17.9`
- [ ] SSH key pair name, or allow creating one and saving the `.pem` locally
- [ ] S3 bucket name (default uses the account id)
- [ ] SSH source is your current public IP

Nothing in this plan is created until that confirmation.
