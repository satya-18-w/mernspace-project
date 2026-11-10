#!/usr/bin/env bash
# Destroy every resource created by create-infra.sh. Gated.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/infra/aws/outputs.env"

export AWS_PROFILE=${AWS_PROFILE:-mernspace}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}
AWS_REGION=$AWS_DEFAULT_REGION

[ -f "$OUT" ] || { echo "Missing $OUT; nothing to clean up from this script."; exit 1; }
# shellcheck disable=SC1091
source "$OUT"

cat <<EOF
This will delete, in $AWS_REGION:
  EC2        ${INSTANCE_ID:-none}
  EIP        ${EIP:-none} (${EIP_ALLOC:-none})
  RDS        ${RDS_ID:-none}
  ECR        7 repositories
  S3         ${S3_BUCKET:-none} (all objects)
  Logs       ${LOG_GROUP:-none}
  Network    VPC ${VPC_ID:-none} and its subnets/route tables/IGW/SGs
  IAM        ${IAM_ROLE:-none} / ${IAM_PROFILE:-none}

Kubernetes resources on the node disappear with the instance.
EOF
read -r -p 'Type APPROVE CLEANUP to continue: ' answer
[ "$answer" = "APPROVE CLEANUP" ] || { echo "Aborted."; exit 1; }

echo "== Kubernetes (best effort) =="
if [ -n "${INSTANCE_ID:-}" ] && command -v kubectl >/dev/null 2>&1 && \
   KUBECONFIG=${KUBECONFIG:-$HOME/.kube/mernspace.yaml} kubectl get ns mernspace >/dev/null 2>&1; then
    (
        cd "$ROOT/infra/k8s/overlays/aws"
        ECR_REGISTRY="${ECR_REGISTRY:-}" TAG="${TAG:-v1}" \
            envsubst < kustomization.yaml.tmpl > kustomization.yaml
    )
    KUBECONFIG=${KUBECONFIG:-$HOME/.kube/mernspace.yaml} \
        kubectl delete -k "$ROOT/infra/k8s/overlays/aws" --ignore-not-found || true
fi

echo "== EC2 =="
if [ -n "${INSTANCE_ID:-}" ]; then
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null || true
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" || true
fi

echo "== EIP =="
if [ -n "${EIP_ALLOC:-}" ]; then
    aws ec2 release-address --allocation-id "$EIP_ALLOC" || true
fi

echo "== RDS =="
if [ -n "${RDS_ID:-}" ]; then
    aws rds delete-db-instance --db-instance-identifier "$RDS_ID" \
        --skip-final-snapshot --delete-automated-backups >/dev/null || true
    aws rds wait db-instance-deleted --db-instance-identifier "$RDS_ID" || true
    aws rds delete-db-subnet-group --db-subnet-group-name mernspace-db-subnets || true
fi

echo "== ECR =="
for repo in auth catalog order notification ws client-ui admin-ui; do
    aws ecr delete-repository --repository-name "mernspace/$repo" --force >/dev/null 2>&1 || true
done

echo "== S3 =="
aws s3 rm "s3://$S3_BUCKET" --recursive >/dev/null 2>&1 || true
aws s3api delete-bucket --bucket "$S3_BUCKET" || true

echo "== CloudWatch =="
aws logs delete-log-group --log-group-name "$LOG_GROUP" || true

echo "== Security groups =="
aws ec2 delete-security-group --group-id "$RDS_SG" || true
aws ec2 delete-security-group --group-id "$EC2_SG" || true

echo "== Subnets and route tables =="
for subnet in "$PUB_SUBNET" "$PRIV_A" "$PRIV_B"; do
    aws ec2 delete-subnet --subnet-id "$subnet" || true
done
for rt in "$PUB_RT" "$PRIV_RT"; do
    aws ec2 delete-route-table --route-table-id "$rt" || true
done

echo "== Internet gateway and VPC =="
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" || true
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" || true
aws ec2 delete-vpc --vpc-id "$VPC_ID" || true

echo "== IAM =="
aws iam detach-role-policy --role-name "$IAM_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly || true
aws iam detach-role-policy --role-name "$IAM_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || true
aws iam delete-role-policy --role-name "$IAM_ROLE" --policy-name mernspace-s3 || true
aws iam remove-role-from-instance-profile --instance-profile-name "$IAM_PROFILE" \
    --role-name "$IAM_ROLE" || true
aws iam delete-instance-profile --instance-profile-name "$IAM_PROFILE" || true
aws iam delete-role --role-name "$IAM_ROLE" || true

rm -f "$OUT"
echo "Cleanup complete. The local .pem file, if any, is now useless; delete it manually."
