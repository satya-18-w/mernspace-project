#!/usr/bin/env bash
# Push the locally built images to ECR. Requires the repositories created by
# create-infra.sh. This stores data in ECR (small monthly charge).
set -euo pipefail

export AWS_PROFILE=${AWS_PROFILE:-mernspace}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}
AWS_REGION=$AWS_DEFAULT_REGION
TAG=${TAG:-v1}
IMAGE_PREFIX=${IMAGE_PREFIX:-mernspace}

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"

read -r -p "Push 7 images with tag $TAG to $REGISTRY? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Aborted"; exit 1; }

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$REGISTRY"

for svc in auth catalog order notification ws client-ui admin-ui; do
    docker push "$REGISTRY/$IMAGE_PREFIX/$svc:$TAG"
done

echo "Pushed tag $TAG."
