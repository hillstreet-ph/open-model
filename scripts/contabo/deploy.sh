#!/bin/bash
set -euo pipefail

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"
REPO_URL="https://github.com/ollama/ollama.git"
BUILD_DIR="/opt/ollama/build"
INSTALL_DIR="/opt/ollama"

SSH="ssh -i ${SSH_KEY_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP}"
SCP="scp -i ${SSH_KEY_PATH} -P ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=== Deploying Ollama to Contabo server ${CONTAINER_IP} ==="

echo "--- Installing Go ---"
${SSH} 'wget -q https://go.dev/dl/go1.22.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz'

${SSH} "export PATH=\"/usr/local/go/bin:\$PATH\" && go version"

echo "--- Cloning repository ---"
${SSH} "rm -rf /opt/ollama/src && mkdir -p /opt/ollama/src && git clone ${REPO_URL} /opt/ollama/src"

echo "--- Building Ollama ---"
${SSH} "export PATH=\"/usr/local/go/bin:\$PATH\" && \
    cd /opt/ollama/src && \
    make build"

echo "--- Copying binary to deploy location ---"
${SSH} "cp /opt/ollama/src/ollama /opt/ollama/ollama && chown ollama:ollama /opt/ollama/ollama"

echo "--- Setting up systemd service ---"
${SSH} "cat > /etc/systemd/system/ollama.service << 'EOF'
[Unit]
Description=Ollama Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment=OLLAMA_HOST=0.0.0.0:11434
Environment=OLLAMA_MODELS=/var/lib/ollama/models
Environment=OLLAMA_ORIGINS=*
Environment=OLLAMA_KEEP_ALIVE=24h
ExecStart=/opt/ollama/ollama serve
WorkingDirectory=/opt/ollama
StandardOutput=append:/var/log/ollama.log
StandardError=append:/var/log/ollama-error.log
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF"

${SSH} "systemctl daemon-reload"
${SSH} "systemctl enable ollama --now"

echo "--- Deploying monitor script ---"
${SSH} "mkdir -p /opt/ollama/scripts && chown -R ollama:ollama /opt/ollama/scripts"
${SCP} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     scripts/contabo/ollama-monitor.sh     root@169.58.68.183:/opt/ollama/monitor.sh
${SSH} "chmod +x /opt/ollama/monitor.sh && chown ollama:ollama /opt/ollama/monitor.sh"

echo "--- Deploying cron setup ---"
${SCP} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     scripts/cron/setup_cron.sh     root@169.58.68.183:/tmp/setup_cron.sh
${SSH} "bash /tmp/setup_cron.sh"

echo "--- Verifying service is running ---"
${SSH} "systemctl is-active ollama"

echo "=== Deployment complete ==="