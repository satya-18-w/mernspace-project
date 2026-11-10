#!/usr/bin/env bash
# Build the seven application images locally. No AWS mutation.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export AWS_PROFILE=${AWS_PROFILE:-mernspace}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-${AWS_REGION:-ap-south-1}}
AWS_REGION=$AWS_DEFAULT_REGION

PUBLIC_ORIGIN=${PUBLIC_ORIGIN:?Set PUBLIC_ORIGIN, for example http://1.2.3.4}
TAG=${TAG:-v1}
IMAGE_PREFIX=${IMAGE_PREFIX:-mernspace}

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"

build_backend() {
    local svc=$1 start=$2
    docker build \
        -f "$ROOT/infra/local/Dockerfile.backend" \
        --build-arg "START_FILE=$start" \
        -t "$REGISTRY/$IMAGE_PREFIX/$svc:$TAG" \
        "$ROOT/mernspace-c-$svc-service"
}

echo "Building backends for $REGISTRY (tag $TAG)"
build_backend auth src/server.js
build_backend catalog src/server.js
build_backend order server.js
build_backend notification server.js
build_backend ws server.js

echo "Building client-ui with NEXT_PUBLIC_BACKEND_URL=$PUBLIC_ORIGIN"
docker build \
    -f "$ROOT/infra/local/Dockerfile.client-ui" \
    --build-arg "NEXT_PUBLIC_BACKEND_URL=$PUBLIC_ORIGIN" \
    -t "$REGISTRY/$IMAGE_PREFIX/client-ui:$TAG" \
    "$ROOT/mernspace-c-client-ui"

echo "Building admin-ui with origin $PUBLIC_ORIGIN and base /admin/"
docker build \
    -f "$ROOT/infra/local/Dockerfile.admin-ui" \
    --build-arg "VITE_BACKEND_API_URL=$PUBLIC_ORIGIN" \
    --build-arg "VITE_SOCKET_SERVICE_URL=$PUBLIC_ORIGIN" \
    --build-arg "VITE_BASE_PATH=/admin/" \
    -t "$REGISTRY/$IMAGE_PREFIX/admin-ui:$TAG" \
    "$ROOT/mernspace-c-admin-ui"

echo
echo "Built:"
docker images --format '{{.Repository}}:{{.Tag}}' | grep "$REGISTRY/$IMAGE_PREFIX/" | sort
echo "Next: TAG=$TAG ./push-images.sh"
