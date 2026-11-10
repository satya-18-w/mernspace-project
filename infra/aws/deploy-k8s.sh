#!/usr/bin/env bash
# Create Kubernetes secrets/config, then apply the AWS overlay.
# Requires a working KUBECONFIG and the local auth keys.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/infra/aws/outputs.env"

export AWS_PROFILE=${AWS_PROFILE:-mernspace}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/mernspace.yaml}
export KUBECONFIG
PUBLIC_ORIGIN=${PUBLIC_ORIGIN:-http://$EIP}

command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }
command -v envsubst >/dev/null || { echo "envsubst is required"; exit 1; }
[ -f "$KUBECONFIG" ] || { echo "Missing $KUBECONFIG (copy it from the node)"; exit 1; }
[ -f "$ROOT/infra/local/secrets/auth/certs/private.pem" ] || {
    echo "Missing local auth certs; run the local setup first"; exit 1;
}

kubectl apply -f "$ROOT/infra/k8s/base/namespace.yaml"

kubectl -n mernspace create secret generic auth-env \
    --from-literal=DB_HOST="$RDS_ENDPOINT" \
    --from-literal=DB_PORT=5432 \
    --from-literal=DB_USERNAME="$DB_USER" \
    --from-literal=DB_PASSWORD="$DB_PASSWORD" \
    --from-literal=DB_NAME="$DB_NAME" \
    --from-literal=REFRESH_TOKEN_SECRET="$REFRESH_TOKEN_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n mernspace create secret generic auth-certs \
    --from-file=private.pem="$ROOT/infra/local/secrets/auth/certs/private.pem" \
    --from-file=public.pem="$ROOT/infra/local/secrets/auth/certs/public.pem" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n mernspace create configmap auth-jwks \
    --from-file=jwks.json="$ROOT/infra/local/secrets/auth/public/.well-known/jwks.json" \
    --dry-run=client -o yaml | kubectl apply -f -

ECR_PASS=$(aws ecr get-login-password --region "$AWS_REGION")
kubectl -n mernspace create secret docker-registry ecr-pull \
    --docker-server="$ECR_REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -

cd "$ROOT/infra/k8s/overlays/aws"
PUBLIC_ORIGIN="$PUBLIC_ORIGIN" \
S3_BUCKET="$S3_BUCKET" \
S3_REGION="$S3_REGION" \
    envsubst < runtime-config.yaml.tmpl > runtime-config.yaml
ECR_REGISTRY="$ECR_REGISTRY" TAG="$TAG" CATALOG_TAG="${CATALOG_TAG:-v2}" \
    envsubst < kustomization.yaml.tmpl > kustomization.yaml
cd "$ROOT"

kubectl apply -k "$ROOT/infra/k8s/overlays/aws"

echo "Waiting for workloads..."
for d in auth-service catalog-service order-service ws-service notification-service client-ui admin-ui gateway; do
    kubectl -n mernspace rollout status "deploy/$d" --timeout=600s
done
kubectl -n mernspace rollout status statefulset/mongo --timeout=300s
kubectl -n mernspace rollout status statefulset/kafka --timeout=300s
kubectl -n mernspace wait --for=condition=complete job/mongo-init --timeout=300s
kubectl -n mernspace wait --for=condition=complete job/kafka-init --timeout=300s

kubectl -n mernspace get pods -o wide
cat <<EOF

Deployed.
  Client   $PUBLIC_ORIGIN/
  Admin    $PUBLIC_ORIGIN/admin/
  Mailpit  kubectl -n mernspace port-forward svc/mailpit 8025:8025
EOF
