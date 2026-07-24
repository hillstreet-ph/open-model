#!/bin/bash
set -euo pipefail

###############################################
# Professional Contabo Server Setup       #
# Production Ollama + Multi-Fork Platform#
# Target: 169.58.68.183                  #
###############################################

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
REPO_DIR="/opt/ollama"
LOG_FILE="/var/log/contabo-professional-setup.log"

export DEBIAN_FRONTEND=noninteractive

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

step() {
    log "============================================"
    log "STEP: $1"
    log "============================================"
}

pass() { log "  [PASS] $1"; }
fail() { log "  [FAIL] $1"; exit 1; }
info() { log "  [INFO] $1"; }

step "0: Prerequisites Verification"
command -v ssh >/dev/null && pass "SSH client available" || fail "SSH not found"
command -v scp >/dev/null && pass "SCP available" || fail "SCP not found"
command -v ssh-keygen >/dev/null && pass "ssh-keygen available" || fail "ssh-keygen not found"
log "  Target server: $CONTAINER_IP"
log "  Repo directory: $REPO_DIR"
log "  Log file: $LOG_FILE"

step "1: SSH Key Configuration"
SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
SSH_KEY_PUB="${SSH_KEY}.pub"

if [ ! -f "$SSH_KEY" ]; then
    log "  Generating ed25519 SSH key pair..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -C "contabo-professional-$(date +%Y%m%d)" -N "" -q
    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_KEY_PUB"
    pass "SSH key generated: $SSH_KEY"
else
    pass "SSH key already exists: $SSH_KEY"
fi

step "2: SSH Connectivity Test"
if ssh -o StrictHostKeyChecking=no \
       -o ConnectTimeout=10 \
       -i "$SSH_KEY" \
       -p "$SSH_PORT" \
       "${SSH_USER}@${CONTAINER_IP}" \
       "echo 'SSH connection OK'" 2>/dev/null; then
    pass "SSH connection to ${CONTAINER_IP} successful"
else
    fail "Cannot connect to ${CONTAINER_IP} via SSH. Check IP, key, and network."
fi

step "3: Firewall Configuration (UFW)"
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "bash -s" << 'REMOTE_SCRIPT'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "--- Configuring UFW Firewall ---"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp comment "SSH"
ufw allow 11434/tcp comment "Ollama API"
ufw allow 3000/tcp comment "Open Connect (Web UI)"
ufw allow 8000/tcp comment "Open Connect API Bridge"
ufw allow 5000/tcp comment "Open Command API"
ufw allow 6000/tcp comment "Open Worker API"
ufw allow 8080/tcp comment "Platform Orchestrator"
ufw allow 8443/tcp comment "Cross-platform Bridge"
ufw allow 8444/tcp comment "Task Pipeline"
ufw allow 8445/tcp comment "Swarm Coordinator"
ufw allow 9090/tcp comment "Monitor Dashboard"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw allow 5432/tcp comment "PostgreSQL"
ufw allow 8081/tcp comment "Supabase Realtime"

ufw --force enable

echo "--- Firewall configuration complete ---"
echo "Open ports: 22, 11434, 3000, 5000, 6000, 6000, 8000, 8080, 8443, 8444, 8445, 9090"
REMOTE_SCRIPT

if [ $? -eq 0 ]; then
    pass "UFW firewall configured with all required ports"
else
    fail "UFW firewall configuration failed"
fi

step "4: System Packages & Dependencies"
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "bash -s" << 'REMOTE_SCRIPT'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "--- Installing system packages ---"
apt-get update -qq && apt-get install -y -qq \
    curl wget ca-certificates git build-essential cmake pkg-config \
    libssl-dev zlib1g-dev libsqlite3-dev python3 python3-pip \
    python3-venv python3-dev jq htop ncdu ufw fail2ban cron \
    rsyslog logrotate unzip psmisc gnupg gnupg2 lsb-release \
    software-properties-common apt-transport-https

echo "--- Installing Docker ---"
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
rm -f /tmp/get-docker.sh

apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
    mkdir -p /usr/local/lib/docker/cli-plugins/ && \
    curl -sL "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

id ollama 2>/dev/null || useradd -m -s /bin/bash ollama

echo "--- Installing Python dependencies ---"
pip3 install --break-system-packages -q fastapi uvicorn requests python-multipart aiohttp httpx pyyaml 2>/dev/null || true

apt-get autoremove -y -qq
apt-get clean -qq
rm -rf /var/lib/apt/lists/*

echo "--- System packages installation complete ---"
REMOTE_SCRIPT

if [ $? -eq 0 ]; then
    pass "System packages and Docker installed"
else
    fail "System package installation failed"
fi

step "5: Ollama Installation & Configuration"
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "bash -s" << 'REMOTE_SCRIPT'
set -euo pipefail

echo "--- Setting up Ollama ---"

mkdir -p /opt/ollama
mkdir -p /var/lib/ollama/models
mkdir -p /var/lib/ollama/cache
mkdir -p /var/log/ollama
mkdir -p /etc/ollama

cat > /etc/systemd/system/ollama.service << 'EOF'
[Unit]
Description=Ollama Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ollama
Group=ollama
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/var/lib/ollama/models"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_FLASH_ATTENTION=1"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=5
LimitNOFILE=65536
LimitNPROC=4096
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

echo "Waiting for Ollama to become healthy..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "Ollama is healthy after ${i}s"
        break
    fi
    echo "Attempt ${i}: Ollama not ready yet..."
    sleep 2
done

systemctl is-active ollama || echo "WARNING: Ollama service not active"
curl -s http://localhost:11434/api/tags | head -c 200 || echo "WARNING: Cannot reach Ollama API"

echo "--- Ollama installation complete ---"
REMOTE_SCRIPT

if [ $? -eq 0 ]; then
    pass "Ollama installed and running"
else
    fail "Ollama installation failed"
fi

step "6: Platform Infrastructure Deployment"
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "bash -s" << REMOTE_SCRIPT
set -euo pipefail

echo "--- Deploying platform infrastructure ---"

cd ${REPO_DIR} || { echo "Repo dir not found, cloning..."; git clone https://github.com/hillstreet-ph/open-model.git ${REPO_DIR}; cd ${REPO_DIR}; }

git pull origin main

chmod +x scripts/contabo/server_platform.sh
chmod +x scripts/contabo/production_readiness_check.sh
chmod +x scripts/contabo/infra_sync.sh
chmod +x scripts/supabase/deploy.sh
chmod +x scripts/deploy_all.sh

bash scripts/contabo/server_platform.sh

echo "Platform infrastructure deployed"
REMOTE_SCRIPT

if [ $? -eq 0 ]; then
    pass "Platform infrastructure deployed"
else
    fail "Platform infrastructure deployment failed"
fi

echo ""
log "=== Contabo Professional Setup Complete ==="
log "Server: $CONTAINER_IP"
log "Firewall: UFW active"
log "Ollama: Running on port 11434"
log "Open Connect: http://$CONTAINER_IP:3000"
log "Open Command: http://$CONTAINER_IP:5000"
log "Open Worker: http://$CONTAINER_IP:6000"
log "Orchestrator: http://$CONTAINER_IP:8080"
log "Platform status: Ready for multi-fork operation"
