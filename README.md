# MERNSpace: Cloud-Native Microservices Commerce Platform on AWS

[![Live Storefront](https://img.shields.io/badge/Vercel-Storefront%20Live-brightgreen)](https://mernspace-client.vercel.app)
[![AWS Deployment](https://img.shields.io/badge/AWS-K3s%20Cluster%20(13.207.240.55)-orange)](http://13.207.240.55/admin/)
[![Architecture](https://img.shields.io/badge/Architecture-Event--Driven%20Microservices-blue)](#architecture)
[![Report](https://img.shields.io/badge/Docs-Technical%20Report-purple)](docs/REPORT.md)

MERNSpace is a production-grade, multi-tenant cloud-native food commerce platform built using distributed microservices. It features an edge-accelerated Next.js 14 storefront deployed on Vercel Global Edge, an Nginx API Gateway, four core backend microservices (Auth, Catalog, Order, WebSocket), a background Notification worker, and containerized polyglot data stores (PostgreSQL 16.9 on Amazon RDS, MongoDB 7.0 replica set on EBS, and Apache Kafka 3.8 in KRaft mode) orchestrated on an AWS EC2 `c7i-flex.large` instance running K3s Kubernetes.

---

## Quick Links

- 📄 **[Technical Engineering Report (Comprehensive)](docs/REPORT.md)** — Detailed academic & cloud engineering report following standard publication guidelines.
- 🎬 **[Deployment & Demonstration Video Guide](DEPLOYMENT_AND_VIDEO_GUIDE.md)** — Minute-by-minute script, verified AWS resource IDs, and seed data guide.
- 🛒 **[Live Customer Storefront](https://mernspace-client.vercel.app)** (Vercel Global Edge)
- ⚙️ **[Live Admin Dashboard](http://13.207.240.55/admin/)** (AWS K3s via Nginx Gateway)
- 🔌 **[Live API Gateway](http://13.207.240.55/api/)**
- 🔑 **Demo Admin Credentials:** `admin@mernspace.local` / `Admin@12345`

---

## Architecture Overview

```mermaid
flowchart LR
    Customer["Customer Browser"] -->|HTTPS| Vercel["Vercel Global Edge<br/>Next.js 14 Storefront"]
    Admin["Admin Browser"] -->|HTTP /admin/| Gateway
    Vercel -->|Proxy /api/*| Gateway["Nginx API Gateway (:80)"]

    subgraph AWS["AWS Cloud (ap-south-1) · EC2 c7i-flex.large"]
        Gateway --> Auth["Auth Service (:5501)"]
        Gateway --> Catalog["Catalog Service (:5502)"]
        Gateway --> Order["Order Service (:5503)"]
        Gateway --> WS["WebSocket Service (:5504)"]

        Auth -->|Private Subnet (5432)| RDS[("Amazon RDS<br/>PostgreSQL 16.9")]
        Catalog -->|Presigned URLs| S3[("Amazon S3<br/>Asset Bucket")]
        Catalog & Order --> Mongo[("MongoDB 7.0<br/>rs0 Replica Set (8 GiB PVC)")]
        
        Catalog & Order --> Kafka["Apache Kafka 3.8<br/>KRaft Mode (8 GiB PVC)"]
        Kafka --> Notif["Notification Worker"]
        Kafka --> WS
        Notif --> Mailpit["Mailpit SMTP (:1025)"]
    end
```

---

## Repository Map

| Path | Description |
|---|---|
| [`docs/REPORT.md`](docs/REPORT.md) | **Formal Cloud Computing Engineering Report** (Abstract, Problem Statement, Objectives, Architecture, Cloud Services, Implementation, Results, Cost Analysis, Lessons Learned) |
| [`DEPLOYMENT_AND_VIDEO_GUIDE.md`](DEPLOYMENT_AND_VIDEO_GUIDE.md) | Complete AWS facts, 10-minute video presentation script, and tenant data reference |
| [`mernspace-c-client-ui/`](mernspace-c-client-ui/) | Customer Storefront (Next.js 14 App Router, Redux, Tailwind, Vercel Edge rewrites) |
| [`mernspace-c-admin-ui/`](mernspace-c-admin-ui/) | Admin Management SPA (React 18, Vite, TypeScript, Ant Design) |
| [`mernspace-c-auth-service/`](mernspace-c-auth-service/) | Authentication & Tenancy Service (Express, TypeORM, PostgreSQL, RS256 JWKS) |
| [`mernspace-c-catalog-service/`](mernspace-c-catalog-service/) | Catalog Service (Express, Mongoose, MongoDB, AWS S3 presigned URLs, Kafka Producer) |
| [`mernspace-c-order-service/`](mernspace-c-order-service/) | Order Service (MongoDB multi-document ACID transactions, Stripe SDK, Kafka Producer/Consumer) |
| [`mernspace-c-ws-service/`](mernspace-c-ws-service/) | Real-time WebSocket Service (Socket.io, Kafka Consumer) |
| [`mernspace-c-notification-service/`](mernspace-c-notification-service/) | Background Worker (Kafka Consumer, Nodemailer, Mailpit mock SMTP) |
| [`infra/aws/`](infra/aws/) | AWS provisioning automation (`create-infra.sh`, `deploy-k8s.sh`, `smoke-test.sh`, `outputs.env`) |
| [`infra/k8s/`](infra/k8s/) | Kubernetes manifests (Kustomize base & AWS production overlay) |
| [`infra/local/`](infra/local/) | Local Docker Compose development environment |

---

## Running the Project

### Local Development
```bash
cd infra/local
cp .env.example .env
docker compose up -d --build
```

### AWS Production Deployment
```bash
cd infra/aws
export AWS_PROFILE=mernspace
./create-infra.sh          # Provisions VPC, EC2, RDS, S3, ECR, IAM
./build-images.sh          # Builds 7 microservice images
./push-images.sh           # Pushes images to AWS ECR
./deploy-k8s.sh            # Applies Kustomize manifests to K3s cluster
./smoke-test.sh             # Executes automated end-to-end cloud smoke test
```

For complete details, see **[docs/REPORT.md](docs/REPORT.md)**.
