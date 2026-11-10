#!/usr/bin/env bash
# Create the billable AWS resources for the MERNSpace demo.
# Gated: nothing is created until the exact approval phrase is typed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/infra/aws/outputs.env"

export AWS_PROFILE=${AWS_PROFILE:-mernspace}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}
AWS_REGION=$AWS_DEFAULT_REGION
INSTANCE_TYPE=${INSTANCE_TYPE:-c7i-flex.large}
PG_VERSION=${PG_VERSION:-16.9}
AMI_ID=${AMI_ID:-ami-0fc5120b2d80d4749}
KEY_NAME=${KEY_NAME:-}
IMAGE_PREFIX=${IMAGE_PREFIX:-mernspace}

if [ -f "$OUT" ]; then
    echo "Refusing to run: $OUT exists. Run cleanup.sh first or delete it deliberately."
    exit 1
fi

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
MY_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '\n')/32
BUCKET=${BUCKET:-mernspace-assets-$ACCOUNT-$AWS_REGION}
DB_PASSWORD=${DB_PASSWORD:-$(openssl rand -hex 16)}
REFRESH_TOKEN_SECRET=${REFRESH_TOKEN_SECRET:-$(openssl rand -hex 32)}

cat <<EOF
MERNSpace AWS provisioning (ap-south-1)

  Account          $ACCOUNT
  EC2              $INSTANCE_TYPE, Ubuntu 24.04, 30 GiB gp3, EIP
  SSH source       $MY_IP
  RDS              PostgreSQL $PG_VERSION, db.t4g.micro, 20 GiB gp3, private
  ECR              7 repos: auth catalog order notification ws client-ui admin-ui
  S3               $BUCKET (private, SSE-S3, BPA)
  CloudWatch       /mernspace/k3s (7-day retention)
  Estimated cost   ~\$58.18/month (t3.medium)

This creates billable resources and takes roughly 10-15 minutes.
EOF

read -r -p 'Type APPROVE PROVISIONING to continue: ' answer
[ "$answer" = "APPROVE PROVISIONING" ] || { echo "Aborted."; exit 1; }

emit() { printf '%s=%q\n' "$1" "$2" >> "$OUT"; }
: > "$OUT"
chmod 600 "$OUT"
emit AWS_PROFILE "$AWS_PROFILE"
emit AWS_REGION "$AWS_REGION"
emit ACCOUNT_ID "$ACCOUNT"
emit INSTANCE_TYPE "$INSTANCE_TYPE"
emit DB_USER mernspace
emit DB_NAME mernspace_auth
emit DB_PASSWORD "$DB_PASSWORD"
emit REFRESH_TOKEN_SECRET "$REFRESH_TOKEN_SECRET"
emit TAG v1

echo "== VPC and network =="
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=mernspace}]' \
    --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support

IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=mernspace}]' \
    --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

PUB_SUBNET=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.20.1.0/24 \
    --availability-zone "${AWS_REGION}a" --query 'Subnet.SubnetId' --output text)
PRIV_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.20.3.0/24 \
    --availability-zone "${AWS_REGION}a" --query 'Subnet.SubnetId' --output text)
PRIV_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.20.2.0/24 \
    --availability-zone "${AWS_REGION}b" --query 'Subnet.SubnetId' --output text)

PUB_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=mernspace-public}]' \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUB_RT" \
    --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --subnet-id "$PUB_SUBNET" --route-table-id "$PUB_RT" >/dev/null
aws ec2 modify-subnet-attribute --subnet-id "$PUB_SUBNET" --map-public-ip-on-launch

PRIV_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=mernspace-private}]' \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --subnet-id "$PRIV_A" --route-table-id "$PRIV_RT" >/dev/null
aws ec2 associate-route-table --subnet-id "$PRIV_B" --route-table-id "$PRIV_RT" >/dev/null

emit VPC_ID "$VPC_ID"
emit IGW_ID "$IGW_ID"
emit PUB_SUBNET "$PUB_SUBNET"
emit PRIV_A "$PRIV_A"
emit PRIV_B "$PRIV_B"
emit PUB_RT "$PUB_RT"
emit PRIV_RT "$PRIV_RT"

echo "== Security groups =="
EC2_SG=$(aws ec2 create-security-group --group-name mernspace-ec2-sg \
    --description 'MERNSpace K3s node' --vpc-id "$VPC_ID" --query GroupId --output text)
RDS_SG=$(aws ec2 create-security-group --group-name mernspace-rds-sg \
    --description 'MERNSpace RDS' --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$EC2_SG" --protocol tcp --port 22 --cidr "$MY_IP"
aws ec2 authorize-security-group-ingress --group-id "$EC2_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$RDS_SG" --protocol tcp --port 5432 --source-group "$EC2_SG"
emit EC2_SG "$EC2_SG"
emit RDS_SG "$RDS_SG"

echo "== ECR =="
for repo in auth catalog order notification ws client-ui admin-ui; do
    aws ecr create-repository --repository-name "$IMAGE_PREFIX/$repo" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 >/dev/null 2>&1 || true
    aws ecr put-lifecycle-policy --repository-name "$IMAGE_PREFIX/$repo" \
        --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"keep last 5","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":5},"action":{"type":"expire"}}]}' >/dev/null
done
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
emit ECR_REGISTRY "$REGISTRY"

echo "== S3 and CloudWatch =="
aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws logs create-log-group --log-group-name /mernspace/k3s 2>/dev/null || true
aws logs put-retention-policy --log-group-name /mernspace/k3s --retention-in-days 7
emit S3_BUCKET "$BUCKET"
emit S3_REGION "$AWS_REGION"
emit LOG_GROUP /mernspace/k3s

echo "== IAM instance profile =="
ROLE_NAME=mernspace-k3s-role
PROFILE_NAME=mernspace-k3s-profile
cat > /tmp/mernspace-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    aws iam create-role --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/mernspace-trust.json >/dev/null
fi
aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
cat > /tmp/mernspace-s3.json <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":"arn:aws:s3:::${BUCKET}/*"},{"Effect":"Allow","Action":["s3:ListBucket"],"Resource":"arn:aws:s3:::${BUCKET}"}]}
JSON
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name mernspace-s3 \
    --policy-document file:///tmp/mernspace-s3.json
if ! aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
    aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null
    aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME"
fi
emit IAM_ROLE "$ROLE_NAME"
emit IAM_PROFILE "$PROFILE_NAME"
echo "Waiting for the instance profile to propagate..."
sleep 20

echo "== Elastic IP =="
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
EIP=$(aws ec2 describe-addresses --allocation-ids "$EIP_ALLOC" --query 'Addresses[0].PublicIp' --output text)
emit EIP_ALLOC "$EIP_ALLOC"
emit EIP "$EIP"
emit PUBLIC_ORIGIN "http://$EIP"

cat > /tmp/mernspace-cors.json <<JSON
{"CORSRules":[{"AllowedOrigins":["http://${EIP}"],"AllowedMethods":["GET","HEAD"],"AllowedHeaders":["*"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":3000}]}
JSON
aws s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration file:///tmp/mernspace-cors.json

echo "== Key pair =="
if [ -z "$KEY_NAME" ]; then
    KEY_NAME=mernspace-k3s
    if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
        aws ec2 create-key-pair --key-name "$KEY_NAME" --query KeyMaterial --output text \
            > "$ROOT/infra/aws/$KEY_NAME.pem"
        chmod 600 "$ROOT/infra/aws/$KEY_NAME.pem"
    fi
fi
emit KEY_NAME "$KEY_NAME"

echo "== EC2 =="
TMP_UD=$(mktemp)
trap 'rm -f "$TMP_UD"' EXIT
sed -e "s|__ECR_REGISTRY__|$REGISTRY|g" -e "s|__EIP__|$EIP|g" \
    "$ROOT/infra/aws/bootstrap-k3s.sh" > "$TMP_UD"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$EC2_SG" \
    --subnet-id "$PUB_SUBNET" \
    --associate-public-ip-address \
    --iam-instance-profile "Name=$PROFILE_NAME" \
    --metadata-options HttpTokens=required,HttpEndpoint=enabled \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
    --user-data "file://$TMP_UD" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mernspace-k3s}]' \
    --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC" >/dev/null
emit INSTANCE_ID "$INSTANCE_ID"

echo "== RDS =="
aws rds create-db-subnet-group \
    --db-subnet-group-name mernspace-db-subnets \
    --db-subnet-group-description 'MERNSpace private subnets' \
    --subnet-ids "$PRIV_A" "$PRIV_B" >/dev/null
aws rds create-db-instance \
    --db-instance-identifier mernspace-auth \
    --db-instance-class db.t4g.micro \
    --engine postgres \
    --engine-version "$PG_VERSION" \
    --allocated-storage 20 \
    --storage-type gp3 \
    --storage-encrypted \
    --db-name mernspace_auth \
    --master-username mernspace \
    --master-user-password "$DB_PASSWORD" \
    --vpc-security-group-ids "$RDS_SG" \
    --db-subnet-group-name mernspace-db-subnets \
    --no-publicly-accessible \
    --no-multi-az \
    --backup-retention-period 1 \
    --no-deletion-protection >/dev/null
echo "Waiting for RDS (10-15 minutes)..."
aws rds wait db-instance-available --db-instance-identifier mernspace-auth
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier mernspace-auth \
    --query 'DBInstances[0].Endpoint.Address' --output text)
emit RDS_ENDPOINT "$RDS_ENDPOINT"
emit RDS_ID mernspace-auth

cat <<EOF

Provisioning complete.
  EIP        $EIP
  Instance   $INSTANCE_ID
  RDS        $RDS_ENDPOINT
  Bucket     $BUCKET
  Registry   $REGISTRY

Next:
  1. Wait for K3s (2-3 min), then copy the kubeconfig over SSH:
       scp -i infra/aws/$KEY_NAME.pem ubuntu@$EIP:/etc/rancher/k3s/k3s.yaml ~/.kube/mernspace.yaml
       sed -i 's|https://127.0.0.1:6443|https://127.0.0.1:6443|' ~/.kube/mernspace.yaml
  2. PUBLIC_ORIGIN=http://$EIP TAG=v1 ./build-images.sh
  3. TAG=v1 ./push-images.sh
  4. ./deploy-k8s.sh
  5. ./seed-demo.sh && ./smoke-test.sh
EOF
