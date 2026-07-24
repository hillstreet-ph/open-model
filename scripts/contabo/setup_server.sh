#!/bin/bash
set -euo pipefail

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"
KNOWN_HOSTS_LINE="169.58.68.183 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINddCkP6ZiPeC7BEBFf49H5wguTslFaAUfHjjlJZkttg codex-contabo-deploy-2026-07-24"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "ERROR: SSH key not found at ${SSH_KEY_PATH}"
    echo "Generate it with: ssh-keygen -t ed25519 -f ${SSH_KEY_PATH} -C codex-contabo-deploy-2026-07-24"
    exit 1
fi

chmod 600 "${SSH_KEY_PATH}"

echo "${KNOWN_HOSTS_LINE}" >> ~/.ssh/known_hosts

SSH="ssh -i ${SSH_KEY_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP}"

echo "=== Connecting to Contabo server ${CONTAINER_IP} ==="

echo "--- Updating system packages ---"
${SSH} "apt-get update && apt-get upgrade -y"

echo "--- Installing prerequisites ---"
${SSH} "apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    git \
    build-essential \
    cmake \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libsqlite3-dev \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    htop \
    ncdu \
    ufw \
    fail2ban \
    cron \
    rsyslog \
    logrotate \
    unzip \
    psmisc"

echo "--- Configuring firewall (UFW) ---"
${SSH} "ufw default deny incoming"
${SSH} "ufw default allow outgoing"
${SSH} "ufw allow 22/tcp"
${SSH} "ufw allow 11434/tcp"
${SSH} "ufw --force enable"

echo "--- Configuring fail2ban ---"
${SSH} "cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[ollama]
enabled = true
port = 11434
logpath = /var/log/ollama.log
maxretry = 5
bantime = 1800
findtime = 300
EOF"
${SSH} "systemctl enable fail2ban --now || true"

echo "--- Setting up logrotate for Ollama ---"
${SSH} "cat > /etc/logrotate.d/ollama << 'EOF'
/var/log/ollama.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF"

echo "--- Creating ollama user and directories ---"
${SSH} "id ollama 2>/dev/null || useradd -m -s /bin/bash ollama"
${SSH} "mkdir -p /opt/ollama /var/lib/ollama /var/log/ollama"
${SSH} "chown -R ollama:ollama /opt/ollama /var/lib/ollama /var/log/ollama"

echo "--- Setting up environment variables for ollama user ---"
${SSH} "cat >> /home/ollama/.bashrc << 'EOF'
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_MODELS=/var/lib/ollama/models
export OLLAMA_ORIGINS=*
export OLLAMA_KEEP_ALIVE=24h
EOF"

echo "=== Contabo server setup complete ==="


echo "--- Deploying monitor script ---"
${SSH} "cat > /opt/ollama/monitor.sh << 'MONITOR_EOF'
#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/ollama-monitor.log"
OLLAMA_URL="http://localhost:11434"
MAX_RETRIES=3
RETRY_DELAY=10

log() {
    echo "\$(date -Iseconds) \$1" | tee -a "\${LOG_FILE}"
}

check_health() {
    curl -sf "\${OLLAMA_URL}/api/tags" > /dev/null 2>&1
}

check_disk() {
    local usage=\$(df /var/lib/ollama | awk 'NR==2{print \$5}' | tr -d '%')
    if [ "\${usage}" -gt 90 ]; then
        log "WARNING: Disk usage at \${usage}%, cleaning up..."
        ollama list --format json 2>/dev/null | jq -r '.models[] | .name' | tail -5 | xargs -r -I{} ollama rm {} 2>/dev/null || true
        log "Cleanup complete"
    fi
}

check_memory() {
    local mem_usage=\$(free | awk '/Mem:/{printf "%.0f", \$3/\$2*100}')
    if [ "\${mem_usage}" -gt 95 ]; then
        log "WARNING: Memory usage at \${mem_usage}%, restarting ollama..."
        systemctl restart ollama
    fi
}

RETRY_COUNT=0
while true; do
    if check_health; then
        log "Health check passed"
        RETRY_COUNT=0
    else
        RETRY_COUNT=\$((RETRY_COUNT + 1))
        log "Health check failed (attempt \${RETRY_COUNT}/\${MAX_RETRIES})"
        if [ "\${RETRY_COUNT}" -ge "\${MAX_RETRIES}" ]; then
            log "Max retries reached, restarting ollama service..."
            systemctl restart ollama
            RETRY_COUNT=0
            sleep 30
        fi
    fi
    check_disk
    check_memory
    sleep 60
done
MONITOR_EOF"

${SSH} "chmod +x /opt/ollama/monitor.sh"

echo "=== Contabo server setup complete ==="
