#!/bin/bash
set -euo pipefail

###############################################
# Ollama Server Bootstrap Script           #
# Run as root on Contabo server            #
# 169.58.68.183                            #
###############################################

export DEBIAN_FRONTEND=noninteractive
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_MODELS=/var/lib/ollama/models
export OLLAMA_ORIGINS=*
export OLLAMA_KEEP_ALIVE=24h

LOG="/var/log/ollama-bootstrap.log"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "${LOG}"
}

step() {
    log "================================"
    log "STEP: $1"
    log "================================"
}

pass() { log "  [PASS] $1"; }
fail() { log "  [FAIL] $1"; }
info() { log "  [INFO] $1"; }

step "0: Bootstrap Starting"
log "Server: $(hostname)"
log "IP: $(curl -s ifconfig.me 2>/dev/null || echo 'unknown')"
log "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
log "Kernel: $(uname -r)"
log "Architecture: $(uname -m)"

step "1: System Update"
apt-get update -qq && apt-get upgrade -y -qq
pass "System updated"

step "2: Install Prerequisites"
apt-get install -y -qq \
    curl \
    wget \
    ca-certificates \
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
    psmisc \
    gnupg
pass "Prerequisites installed"

step "3: Configure Firewall (UFW)"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 11434/tcp
ufw --force enable
pass "Firewall configured"

step "4: Configure Fail2ban"
cat > /etc/fail2ban/jail.local << 'EOF'
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
EOF
systemctl enable fail2ban --now 2>/dev/null || true
pass "Fail2ban configured"

step "5: Configure Logrotate"
cat > /etc/logrotate.d/ollama << 'EOF'
/var/log/ollama.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
/var/log/ollama-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
pass "Logrotate configured"

step "6: Create Ollama User and Directories"
id ollama 2>/dev/null || useradd -m -s /bin/bash ollama
mkdir -p /opt/ollama /var/lib/ollama /var/log/ollama
chown -R ollama:ollama /opt/ollama /var/lib/ollama /var/log/ollama
pass "Ollama user and directories created"

step "7: Install Ollama Binary"
# Download latest release
OLLAMA_VERSION=$(curl -s https://api.github.com/repos/ollama/ollama/releases/latest | grep -o '"tag_name": "v[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
info "Installing Ollama ${OLLAMA_VERSION}"
curl -fsSL https://ollama.com/download/ollama-linux-amd64 -o /opt/ollama/ollama
chmod +x /opt/ollama/ollama
chown ollama:ollama /opt/ollama/ollama
pass "Ollama binary installed"

# If Go is available, build from source instead
if command -v go &>/dev/null; then
    info "Go found - building from source for latest features"
    if [ -d /opt/ollama/src ]; then
        rm -rf /opt/ollama/src
    fi
    git clone https://github.com/ollama/ollama.git /opt/ollama/src
    cd /opt/ollama/src
    make build
    cp ollama /opt/ollama/ollama
    chown ollama:ollama /opt/ollama/ollama
    cd /
    pass "Ollama built from source"
fi

step "8: Configure Systemd Service"
cat > /etc/systemd/system/ollama.service << 'EOF'
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
EOF
systemctl daemon-reload
systemctl enable ollama --now
pass "Systemd service configured"

step "9: Deploy Self-Healing Monitor"
mkdir -p /opt/ollama/scripts

cat > /opt/ollama/monitor.sh << 'MONITOR'
#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/ollama-monitor.log"
OLLAMA_URL="http://localhost:11434"
MAX_RETRIES=3
RETRY_DELAY=10

log() {
    echo "$(date -Iseconds) $1" | tee -a "${LOG_FILE}"
}

check_health() {
    curl -sf "${OLLAMA_URL}/api/tags" > /dev/null 2>&1
}

check_disk() {
    local usage=$(df /var/lib/ollama | awk 'NR==2{print $5}' | tr -d '%')
    if [ "${usage}" -gt 90 ]; then
        log "WARNING: Disk usage at ${usage}%, cleaning up..."
        ollama list --format json 2>/dev/null | jq -r '.models[] | .name' | tail -5 | xargs -r -I{} ollama rm {} 2>/dev/null || true
        log "Cleanup complete"
    fi
}

check_memory() {
    local mem_usage=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
    if [ "${mem_usage}" -gt 95 ]; then
        log "WARNING: Memory usage at ${mem_usage}%, restarting ollama..."
        systemctl restart ollama
    fi
}

RETRY_COUNT=0
while true; do
    if check_health; then
        log "Health check passed"
        RETRY_COUNT=0
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "Health check failed (attempt ${RETRY_COUNT}/${MAX_RETRIES})"
        if [ "${RETRY_COUNT}" -ge "${MAX_RETRIES}" ]; then
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
MONITOR

chmod +x /opt/ollama/monitor.sh
chown ollama:ollama /opt/ollama/monitor.sh

cat > /etc/systemd/system/ollama-monitor.service << 'EOF'
[Unit]
Description=Ollama Self-Healing Monitor
After=ollama.service
Wants=ollama.service

[Service]
Type=simple
User=ollama
Group=ollama
Restart=always
RestartSec=5
ExecStart=/opt/ollama/monitor.sh
StandardOutput=append:/var/log/ollama-monitor.log
StandardError=append:/var/log/ollama-monitor-error.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ollama-monitor --now
pass "Self-healing monitor deployed"

step "10: Configure Cron Jobs"
cat > /etc/cron.d/ollama-agent << 'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/go/bin

*/5 * * * * ollama /opt/ollama/monitor.sh >> /var/log/ollama-cron.log 2>&1
0 * * * * ollama /opt/ollama/monitor.sh >> /var/log/ollama-sync.log 2>&1
0 2 * * * ollama /opt/ollama/workers/disk_cleanup.sh >> /var/log/ollama-cleanup.log 2>&1
0 */6 * * * ollama /opt/ollama/workers/supabase_sync.sh >> /var/log/ollama-sync.log 2>&1
0 3 * * * ollama /opt/ollama/workers/update_recommendations.sh >> /var/log/ollama-recommend.log 2>&1
EOF
chmod 644 /etc/cron.d/ollama-agent
systemctl restart cron
pass "Cron jobs configured"

step "11: Deploy Worker Scripts"
mkdir -p /opt/ollama/workers
chown -R ollama:ollama /opt/ollama/workers

# disk_cleanup.sh
cat > /opt/ollama/workers/disk_cleanup.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-cleanup.log"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Starting disk cleanup"
DISK_USAGE=$(df /var/lib/ollama | awk 'NR==2{print $5}' | tr -d '%')
log "Current disk usage: ${DISK_USAGE}%"
if [ "${DISK_USAGE}" -gt 85 ]; then
    log "Disk usage above 85%, starting cleanup..."
    OLD_MODELS=$(ollama list --format json 2>/dev/null | jq -r '.models | sort_by(.created_at) | .[0:3] | .[].name' 2>/dev/null || echo "")
    for MODEL in ${OLD_MODELS}; do
        log "Removing old model: ${MODEL}"
        ollama rm "${MODEL}" 2>/dev/null || true
    done
    log "Cleanup complete"
else
    log "Disk usage normal, no cleanup needed"
fi
SCRIPT
chmod +x /opt/ollama/workers/disk_cleanup.sh

# update_recommendations.sh
cat > /opt/ollama/workers/update_recommendations.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-recommend.log"
SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY="${SUPABASE_SERVICE_KEY:-}"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Starting recommendations update"
CURRENT_MODELS=$(ollama list --format json 2>/dev/null || echo '{"models":[]}')
curl -s -X POST "${SUPABASE_URL}/rest/v1/ollama_models" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" \
    -H "Content-Type: application/json" \
    -H "apikey: ${SUPABASE_KEY}" \
    -d "${CURRENT_MODELS}" \
    --fail && log "Model sync to Supabase successful" || log "WARNING: Sync to Supabase failed"
log "Recommendations update complete"
SCRIPT
chmod +x /opt/ollama/workers/update_recommendations.sh

# supabase_sync.sh
cat > /opt/ollama/workers/supabase_sync.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-supabase.log"
SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY="${SUPABASE_SERVICE_KEY:-}"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Starting Supabase sync"
curl -s -X POST "${SUPABASE_URL}/rest/v1/ollama_models" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" \
    -H "Content-Type: application/json" \
    -H "apikey: ${SUPABASE_KEY}" \
    -d "$(ollama list --format json 2>/dev/null || echo '{\"models\":[]}')" \
    --fail && log "Supabase sync complete" || log "WARNING: Supabase sync failed"
SCRIPT
chmod +x /opt/ollama/workers/supabase_sync.sh

# model_rotation.sh
cat > /opt/ollama/workers/model_rotation.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-rotation.log"
SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY="${SUPABASE_SERVICE_KEY:-}"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Starting model rotation check"
CURRENT_MODELS=$(ollama list --format json 2>/dev/null || echo '{"models":[]}')
log "Current model count: $(echo "${CURRENT_MODELS}" | jq '.models | length')"
# Check for new preferred models
for MODEL in gemma4:latest llama3.2:3b llama3.2:1b qwen2.5:7b qwen2.5:1.5b mistral:7b codellama:7b; do
    if ! echo "${CURRENT_MODELS}" | jq -e ".models[] | select(.name == \"${MODEL}\")" > /dev/null 2>&1; then
        log "Pulling preferred model: ${MODEL}"
        ollama pull "${MODEL}" 2>/dev/null && log "Pulled ${MODEL}" || log "WARNING: Failed to pull ${MODEL}"
    fi
done
log "Model rotation check complete"
SCRIPT
chmod +x /opt/ollama/workers/model_rotation.sh

chown -R ollama:ollama /opt/ollama/workers
pass "Worker scripts deployed"

step "12: Install AI Models"
info "Pulling standard models..."
# Pull models as ollama user
su - ollama -c "ollama pull llama3.2:3b" 2>/dev/null && pass "llama3.2:3b installed" || log "llama3.2:3b install failed or skipped"
su - ollama -c "ollama pull llama3.2:1b" 2>/dev/null && pass "llama3.2:1b installed" || log "llama3.2:1b install failed or skipped"
su - ollama -c "ollama pull gemma4:latest" 2>/dev/null && pass "gemma4 installed" || log "gemma4 install failed or skipped"
su - ollama -c "ollama pull qwen2.5:7b" 2>/dev/null && pass "qwen2.5:7b installed" || log "qwen2.5:7b install failed or skipped"
su - ollama -c "ollama pull qwen2.5:1.5b" 2>/dev/null && pass "qwen2.5:1.5b installed" || log "qwen2.5:1.5b install failed or skipped"
su - ollama -c "ollama pull mistral:7b" 2>/dev/null && pass "mistral installed" || log "mistral install failed or skipped"

step "13: Final Verification"
log "Checking system status..."
systemctl is-active ollama && log "Ollama service: ACTIVE" || log "Ollama service: INACTIVE"
systemctl is-active ollama-monitor && log "Monitor service: ACTIVE" || log "Monitor service: INACTIVE"
systemctl is-active cron && log "Cron service: ACTIVE" || log "Cron service: INACTIVE"
systemctl is-active fail2ban && log "Fail2ban service: ACTIVE" || log "Fail2ban service: INACTIVE"
curl -sf http://localhost:11434/api/tags > /dev/null 2>&1 && log "Ollama API: RESPONDING" || log "Ollama API: NOT RESPONDING"
ollama list 2>/dev/null | head -5 && log "Models: Listed" || log "Models: No models installed"

log ""
log "================================================"
log " BOOTSTRAP COMPLETE"
log "================================================"
log "Server: $(hostname)"
log "IP: 169.58.68.183"
log "Ollama URL: http://0.0.0.0:11434"
log "API endpoint: http://169.58.68.183:11434/api/tags"
log "Logs: /var/log/ollama.log"
log "Monitor logs: /var/log/ollama-monitor.log"
log "Bootstrap log: ${LOG}"
log "================================================"
