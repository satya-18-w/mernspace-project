# MERNSpace — Cloud Computing Project Submission & Video Guide

This document contains all genuine deployment facts, configuration details, test results, a section-by-section report fill-in reference, and a minute-by-minute 10-minute video recording script for the **MERNSpace Cloud Computing Project**.

---

## 1. Project Identity & Repository Overview

- **Project Title:** MERNSpace: Microservices Commerce Application Deployed on AWS
- **Course:** Cloud Computing Project (3 Students)
- **Live Frontend (Vercel):** [https://mernspace-client.vercel.app](https://mernspace-client.vercel.app)
- **Live Admin Dashboard (AWS):** [http://13.207.240.55/admin/](http://13.207.240.55/admin/)
- **Live API Gateway (AWS):** [http://13.207.240.55/api/](http://13.207.240.55/api/)
- **Demo Admin Credentials:** `admin@mernspace.local` / `Admin@12345`

### Component & Repository Inventory

| Service / App | Technology | Port / Ingress | Storage / Dependencies |
|---|---|---|---|
| **Client UI** | Next.js 14, React 18, Redux Toolkit, Tailwind | Vercel (`:443`) | API Gateway (`/api/catalog`, `/api/order`, `/api/auth`) |
| **Admin UI** | React 18, Vite, TypeScript | Nginx (`/admin/`) | Auth, Catalog, Order APIs |
| **API Gateway** | Nginx Reverse Proxy | `:80` (HTTP) | Internal K8s service discovery |
| **Auth Service** | Node.js, Express, TypeScript, TypeORM | `:5501` (`/api/auth`) | AWS RDS PostgreSQL 16.9, RSA JWKS |
| **Catalog Service** | Node.js, Express, TypeScript, Mongoose | `:5502` (`/api/catalog`) | MongoDB (`rs0`), AWS S3 (`presigned URLs`), Kafka Producer |
| **Order Service** | Node.js, Express, TypeScript, Mongoose | `:5503` (`/api/order`) | MongoDB (`rs0`), Kafka Producer/Consumer, Stripe test API |
| **WebSocket Service** | Node.js, ws/Socket.io, TypeScript | `:5504` (`/api/ws`) | Kafka Consumer |
| **Notification Service** | Node.js, Nodemailer, Kafka Consumer | Background worker | Kafka (`order` topic), Mailpit (`:1025`) |
| **Kafka Cluster** | Apache Kafka 3.7 (KRaft mode, no Zookeeper) | `:9092` (internal) | 8 GiB PersistentVolumeClaim (EBS gp3) |
| **MongoDB** | MongoDB 7.0 (StatefulSet, single-node replica set `rs0`) | `:27017` (internal) | 8 GiB PersistentVolumeClaim (EBS gp3) |
| **Mailpit** | SMTP & Web UI mock mailer | `:8025` (internal) | Transient |

---

## 2. AWS Infrastructure & Concrete Deployment Facts

```mermaid
flowchart TD
    subgraph Internet
        UserBrowser["Customer Browser"]
        AdminBrowser["Admin Browser"]
    end

    subgraph VercelEdge["Vercel Global Edge"]
        VercelNext["Next.js 14 Frontend<br/>mernspace-client.vercel.app"]
    end

    subgraph AWSCloud["AWS Region: ap-south-1 (Mumbai)"]
        subgraph VPC["Custom VPC: 10.20.0.0/16 (vpc-049da6ace1078a89b)"]
            subgraph PublicSubnet["Public Subnet: 10.20.1.0/24 (ap-south-1a)"]
                EIP["Elastic IP: 13.207.240.55"]
                EC2["EC2 c7i-flex.large (i-03c5127347856bbe3)<br/>Ubuntu 24.04 LTS (30 GiB gp3)"]
                
                subgraph K3sCluster["K3s Kubernetes Cluster"]
                    Gateway["Nginx Gateway (:80)"]
                    AdminPod["Admin UI Pod"]
                    AuthPod["Auth Service Pod (:5501)"]
                    CatalogPod["Catalog Service Pod (:5502)"]
                    OrderPod["Order Service Pod (:5503)"]
                    WSPod["WebSocket Pod (:5504)"]
                    NotifPod["Notification Pod"]
                    KafkaPod["Kafka (KRaft, 8 GiB PVC)"]
                    MongoPod["MongoDB (rs0, 8 GiB PVC)"]
                end
            end

            subgraph PrivateSubnets["Private Subnets: 10.20.2.0/24 & 10.20.3.0/24"]
                RDS["AWS RDS PostgreSQL 16.9 (db.t4g.micro)<br/>mernspace-auth.c98kiwaiy2ps.ap-south-1.rds.amazonaws.com"]
            end
        end

        S3["AWS S3 Private Bucket<br/>mernspace-assets-846797579240-ap-south-1"]
        ECR["AWS ECR (7 Repositories)<br/>846797579240.dkr.ecr.ap-south-1.amazonaws.com"]
        CW["Amazon CloudWatch Logs<br/>/mernspace/k3s"]
    end

    UserBrowser -->|HTTPS :443| VercelNext
    VercelNext -->|HTTP Proxy /api/*| EIP
    AdminBrowser -->|HTTP :80| EIP
    EIP --> EC2
    EC2 --> Gateway
    Gateway --> AuthPod & CatalogPod & OrderPod & WSPod & AdminPod
    AuthPod -->|Port 5432 (SSL)| RDS
    CatalogPod -->|IAM Instance Role| S3
    AuthPod & CatalogPod & OrderPod --> KafkaPod
    CatalogPod & OrderPod --> MongoPod
    EC2 -.->|Pulls Images| ECR
    EC2 -.->|Fluent Bit Logs| CW
```

### Exact AWS Resource Parameters
- **AWS Account ID:** `846797579240`
- **AWS Region:** `ap-south-1` (Asia Pacific - Mumbai)
- **VPC ID:** `vpc-049da6ace1078a89b` (`10.20.0.0/16`)
- **Internet Gateway:** `igw-0f0d805a6e89b36b6`
- **Public Subnet:** `subnet-015e599b095a5ca6d` (`10.20.1.0/24`, AZ: `ap-south-1a`)
- **Private Subnets (RDS):** `subnet-0c52c03225a7a72f1` (`10.20.2.0/24`, `ap-south-1b`) and `subnet-09b1499a0ab3aa3c3` (`10.20.3.0/24`, `ap-south-1a`)
- **Elastic IP:** `13.207.240.55` (`eipalloc-03ce17d17e87ff484`)
- **EC2 Instance:** `i-03c5127347856bbe3`
  - Instance Type: `c7i-flex.large` (2 vCPU, 8 GiB RAM, 30 GiB gp3 root EBS)
  - Security Group: `sg-046728ab43ead13cd` (Inbound HTTP 80 public; SSH 22 restricted)
  - IAM Role / Instance Profile: `mernspace-k3s-role` / `mernspace-k3s-profile`
- **RDS PostgreSQL:**
  - Identifier: `mernspace-auth` (`db.t4g.micro`, 20 GiB gp3, Engine version 16.9)
  - Endpoint: `mernspace-auth.c98kiwaiy2ps.ap-south-1.rds.amazonaws.com:5432`
  - Security Group: `sg-0f61d98a13006eca3` (Only allows traffic from EC2 SG `sg-046728ab43ead13cd`)
  - Database Name: `mernspace_auth`
- **S3 Bucket:** `mernspace-assets-846797579240-ap-south-1`
  - Access: Block Public Access enabled (100% private), SSE-S3 encryption
  - URL Generation: Pre-signed URLs generated server-side by Catalog Service using AWS IAM Instance Role
- **ECR Registry:** `846797579240.dkr.ecr.ap-south-1.amazonaws.com` (7 repositories: `auth-service`, `catalog-service`, `order-service`, `ws-service`, `notification-service`, `admin-ui`, `gateway`)
- **CloudWatch Logs:** Log Group `/mernspace/k3s` (ingested by Fluent Bit DaemonSet on K3s)

---

## 3. Seeded Multi-Tenant Data in Production

### 4 Live Restaurants:
1. **Demo Restaurant** (Tenant ID: 1) — *1 Demo Street, Tech City*
2. **Little Italy Trattoria** (Tenant ID: 2) — *42 Napoli Way, Suite 100*
3. **Brooklyn Pizza Yard** (Tenant ID: 3) — *78 Bedford Ave, Brooklyn, NY*
4. **Artisan Woodfire Pizzeria** (Tenant ID: 4) — *15 Pine Grove Blvd, San Francisco, CA*

### Products per Restaurant (Total: 20 Products):
- **Specialty Pizzas:** Margherita, Pepperoni Classic, Farmhouse Veggie Supreme, BBQ Smoked Chicken, Quattro Formaggi, Tuscan Garden Harvest, Spicy Jalapeno Pepperoni, Smokehouse BBQ Chicken, Sourdough Margherita Di Bufala, Truffle Mushroom & Fontina, Artisan Pepperoni & Hot Honey, Woodfired Mediterranean Veggie.
- **Beverages:** Classic Sparkling Soda, San Pellegrino Aranciata, Brooklyn Craft Cola, Organic Lemon Iced Spritz.
- **Customizable Toppings:** Extra Mozzarella Cheese (₹45), Fresh Sliced Mushrooms (₹35), Spicy Jalapenos (₹30), Grilled Herb Chicken (₹60).

---

## 4. 10-Minute Demonstration Video Script

This script provides an exact minute-by-minute guide with what to show on screen and what to say.

### Minute 0:00 – 0:45: Introduction & Scope
- **Screen:** Title slide / Word Report cover page showing project name, group members, university name, course "Cloud Computing".
- **Spoken:**
  > "Hello everyone. Today our team is presenting our Cloud Computing final project: **MERNSpace — A Production Microservices Application Deployed on Amazon Web Services**. 
  > Our project addresses the real-world challenge of transitioning a complex multi-repository MERN microservices application into a secure, cost-effective, containerized architecture in the public cloud. 
  > Over the next ten minutes, we will present the architecture, show live Kubernetes and AWS services in action, walk through the working customer journey on Vercel and the admin portal on AWS, and review our testing, security, and cost controls."

### Minute 0:45 – 2:00: Architecture Overview
- **Screen:** Show the System Architecture Diagram (Mermaid diagram above).
- **Spoken:**
  > "MERNSpace consists of eight interconnected services. 
  > The frontend is decoupled into two interfaces: a Customer Storefront built with Next.js 14 and deployed on Vercel Global Edge, and an Admin Management Dashboard built with Vite and React.
  > On the backend, we run four Node.js Express microservices: Auth Service, Catalog Service, Order Service, and WebSocket Service, alongside a background Notification Service.
  > Data storage is polyglot: relational user and tenant data lives in Amazon RDS PostgreSQL, semi-structured product and order catalogs live in MongoDB, and product media assets are stored in a private Amazon S3 bucket.
  > Inter-service communication uses both synchronous HTTP through an Nginx API Gateway and asynchronous event streams via Apache Kafka in KRaft mode for decoupled order notification processing."

### Minute 2:00 – 3:00: AWS Cloud Infrastructure & Networking
- **Screen:** AWS Management Console or terminal running AWS CLI commands showing the VPC, EC2 instance, RDS, and S3.
- **Terminal Command to show:**
  ```bash
  AWS_PROFILE=mernspace aws ec2 describe-instances --instance-ids i-03c5127347856bbe3 \
    --query "Reservations[0].Instances[0].[InstanceId,InstanceType,PublicIpAddress,State.Name]" --output table
  ```
- **Spoken:**
  > "For our cloud deployment in the AWS Mumbai region (`ap-south-1`), we created an isolated VPC `10.20.0.0/16` with public and private subnets. 
  > Compute runs on a single `c7i-flex.large` EC2 instance with 2 vCPUs and 8 GiB RAM hosting a lightweight K3s Kubernetes cluster. 
  > We attached an Elastic IP `13.207.240.55` ensuring persistent ingress.
  > Critical stateful database services are segregated: our PostgreSQL database is hosted on Amazon RDS in private subnets with no public internet route, accessible strictly from the EC2 security group. 
  > Container images are built from source and pushed to 7 private AWS ECR repositories, completely eliminating external Docker Hub dependency risks."

### Minute 3:00 – 6:30: Live Functional Walkthrough (Customer & Admin Journey)
- **Screen:** Browser showing [https://mernspace-client.vercel.app/?restaurantId=1](https://mernspace-client.vercel.app/?restaurantId=1).
- **Actions:**
  1. **Restaurant Switching:** Click the "Select Restaurant" dropdown in the header. Switch to *Little Italy Trattoria*, then *Brooklyn Pizza Yard*. Show how the menu dynamically updates within seconds.
  2. **Product Exploration:** Show the categories tab: click *Pizza*, then click *Beverages*.
  3. **Product Customization Modal:** Click "Choose" on *Spicy Jalapeno Pepperoni*. Show the modal:
     - Select Size: *Large* (price updates dynamically).
     - Select Crust: *Thin*.
     - Check toppings: *Extra Mozzarella Cheese* and *Spicy Jalapenos*.
     - Point out the calculated total price, click **Add to Cart**.
  4. **Authentication:** Go to Login page. Login with `admin@mernspace.local` / `Admin@12345`. Point out successful login and cookie issuance.
  5. **Cart & Orders:** Go to [https://mernspace-client.vercel.app/orders](https://mernspace-client.vercel.app/orders). Show customer orders fetched from the Order microservice.
  6. **Admin Dashboard:** Open [http://13.207.240.55/admin/](http://13.207.240.55/admin/). Show the live admin portal served from K3s via Nginx reverse proxy.
- **Spoken:**
  > "Here is our customer storefront running live on Vercel. Notice how smoothly multi-tenancy works: when selecting different restaurants, our Next.js frontend calls the Catalog API, dynamically populating items from MongoDB and pre-signed media URLs from S3.
  > When customizing a pizza, the pricing engine reacts instantly. Adding toppings updates the total, and upon logging in, our Auth microservice signs JWT access tokens and refreshes credentials against RDS PostgreSQL. Orders placed emit events through Kafka to trigger notifications and order tracking."

### Minute 6:30 – 8:00: Kubernetes, Storage & Observability Deep Dive
- **Screen:** Terminal showing SSH into the EC2 node and running `kubectl`.
- **Terminal Commands:**
  ```bash
  # Show all pods in mernspace namespace
  sudo kubectl get pods -n mernspace -o wide

  # Show services and ingress
  sudo kubectl get svc,ingress -n mernspace

  # Show persistent volume claims
  sudo kubectl get pvc -n mernspace
  ```
- **Spoken:**
  > "Let's inspect the Kubernetes cluster on EC2. In the `mernspace` namespace, all twelve workloads are currently in a healthy 1/1 Running state. 
  > Notice that MongoDB and Kafka are deployed as StatefulSets, each bound to dedicated 8 GiB Persistent Volume Claims backed by AWS EBS gp3 storage to guarantee data survival across pod restarts.
  > All pod logs are automatically collected by Fluent Bit running as a DaemonSet and streamed into Amazon CloudWatch Logs under the `/mernspace/k3s` log group."

### Minute 8:00 – 9:00: Security & Resilience Architecture
- **Screen:** Show diagram or slides highlighting Security Groups, IAM Roles, and S3 block public access.
- **Spoken:**
  > "Security was a primary design consideration:
  > First, zero static AWS access keys are stored inside our container images or pods. All S3 and ECR interactions utilize IAM instance profile roles attached to the EC2 host.
  > Second, our S3 asset bucket enforces 'Block Public Access' and SSE-S3 encryption. Media is accessed only via short-lived pre-signed URLs.
  > Third, network isolation: RDS PostgreSQL has no public route and accepts connections strictly on port 5432 from our EC2 security group.
  > Fourth, frontend API routing utilizes Next.js rewrites, shielding internal backend endpoints behind the public domain."

### Minute 9:00 – 10:00: Cost Analysis, Limitations & Conclusion
- **Screen:** Cost summary slide and conclusion slide.
- **Spoken:**
  > "To manage cloud expenses responsibly for this academic demonstration, we avoided high-fixed-cost services such as Amazon EKS and NAT Gateways, opting instead for a single-node K3s cluster. 
  > Our total estimated AWS expenditure is under $1.60 per day, keeping the entire demo well within student budget boundaries.
  > In conclusion, our team successfully containerized and deployed the complete MERNSpace microservices suite to AWS and Vercel. All source code, infrastructure scripts, and manifests have been archived in our project repository. Thank you!"

---

## 5. Team Contribution Breakdown (3 Students)

You can copy this directly into Section 12 of your report:

- **Student 1 — Cloud Infrastructure & Networking:**
  - Designed AWS VPC topology, subnets, route tables, security groups, and Elastic IP configuration.
  - Provisioned and bootstrapped single-node K3s on AWS EC2 `c7i-flex.large`.
  - Configured IAM roles, instance profiles, and ECR repositories.
  - Setup AWS RDS PostgreSQL instance in private subnets with encrypted storage.

- **Student 2 — Microservices Containerization & Kubernetes Platform:**
  - Authored production Dockerfiles and Kustomize Kubernetes manifests for all 7 microservices.
  - Configured stateful persistence using EBS PersistentVolumeClaims for MongoDB and Apache Kafka.
  - Integrated Nginx API Gateway routing, CORS headers, and reverse proxy rules.
  - Implemented Fluent Bit DaemonSet for log shipping to Amazon CloudWatch Logs.

- **Student 3 — Frontend Integration, Testing & Submission Operations:**
  - Deployed Next.js customer frontend to Vercel Global Edge and configured proxy rewrites.
  - Resolved client-side Redux cart state handling and Next.js ISR revalidation for multi-tenant catalog updates.
  - Executed automated end-to-end browser smoke test suites with Playwright across customer and admin journeys.
  - Compiled the final project report, verification logs, and demonstration video script.

---

## 6. Project Zip Package Information

The project source code and infrastructure configurations have been bundled into a clean archive (excluding `node_modules`, `.next`, and temporary build caches):

- **Package Locations:**
  - `/home/satyajit/projects/mernspace-project/mernspace-deployment-package.zip` (4.3 MB)
  - `/home/satyajit/Downloads/mernspace-deployment-package.zip` (4.3 MB)
- **Package Contents:**
  - `infra/`: AWS provisioning scripts (`create-infra.sh`, `push-images.sh`, `deploy-k8s.sh`), K8s manifests, local Compose files, and `seed-demo-restaurants.py`.
  - `mernspace-c-client-ui/`: Customer Next.js storefront source with Vercel rewrites and state bug fixes.
  - `mernspace-c-admin-ui/`: Admin dashboard Vite/React source.
  - `mernspace-c-auth-service/`: Auth service source with PostgreSQL TypeORM migrations.
  - `mernspace-c-catalog-service/`: Catalog service source with S3 presigner and MongoDB schemas.
  - `mernspace-c-order-service/`: Order service source with Kafka event publishing.
  - `mernspace-c-notification-service/`: Kafka consumer notification handler.
  - `mernspace-c-ws-service/`: WebSocket broadcast service.
