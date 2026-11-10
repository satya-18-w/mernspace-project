#!/usr/bin/env bash
# HTTP smoke test against the Elastic IP. For the Mailpit check, run:
#   kubectl -n mernspace port-forward svc/mailpit 8025:8025 &
#   MAILPIT=http://localhost:8025 ./smoke-test.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/infra/aws/outputs.env"
BASE=${BASE:-${PUBLIC_ORIGIN:-http://$EIP}}
ADMIN_URL=${ADMIN_URL:-$BASE/admin}
export BASE ADMIN_URL MAILPIT=${MAILPIT:-http://127.0.0.1:1}

"$ROOT/infra/local/scripts/smoke-test.sh"

echo
echo "Kubernetes state:"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/mernspace.yaml} kubectl -n mernspace get pods
