#!/usr/bin/env bash
# Runs on the Ubuntu EC2 node (user data, executed as root).
# Expects ECR_REGISTRY and EIP to be substituted before launch.
set -euxo pipefail

ECR_REGISTRY=${ECR_REGISTRY:-__ECR_REGISTRY__}
EIP=${EIP:-__EIP__}

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates jq unzip

if ! command -v aws >/dev/null 2>&1; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
fi

if ! command -v k3s >/dev/null 2>&1; then
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644 --tls-san ${EIP}" sh -
fi

ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

cat > /usr/local/bin/refresh-ecr.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
REGISTRY="${ECR_REGISTRY:?}"
PASS=$(aws ecr get-login-password --region ap-south-1)
k3s kubectl create namespace mernspace --dry-run=client -o yaml | k3s kubectl apply -f -
k3s kubectl -n mernspace create secret docker-registry ecr-pull \
    --docker-server="$REGISTRY" \
    --docker-username=AWS \
    --docker-password="$PASS" \
    --dry-run=client -o yaml | k3s kubectl apply -f -
EOS
chmod +x /usr/local/bin/refresh-ecr.sh

cat > /etc/systemd/system/refresh-ecr.service <<EOS
[Unit]
Description=Refresh ECR pull secret
After=k3s.service

[Service]
Type=oneshot
Environment=ECR_REGISTRY=${ECR_REGISTRY}
ExecStart=/usr/local/bin/refresh-ecr.sh
EOS

cat > /etc/systemd/system/refresh-ecr.timer <<'EOS'
[Unit]
Description=Refresh ECR pull secret every 6 hours

[Timer]
OnBootSec=2min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOS

systemctl daemon-reload
systemctl enable --now refresh-ecr.timer
systemctl start refresh-ecr.service || true

echo "K3s ready on $(hostname). API: https://127.0.0.1:6443"
