#!/bin/bash
set -euo pipefail

# ============================================================
# Ollama Infrastructure - One-Command Server Deployment
# Run this AS ROOT on the Contabo server 169.58.68.183
# ============================================================

export DEBIAN_FRONTEND=noninteractive
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_MODELS=/var/lib/ollama/models
export OLLAMA_ORIGINS=*
export OLLAMA_KEEP_ALIVE=24h

echo "=========================================="
echo " Ollama Infrastructure - Full Deployment"
echo " Server: $(hostname)"
echo " Time: $(date -Iseconds)"
echo "=========================================="
echo ""

# Step 1: System Update + Prerequisites
echo "[1/10] System update..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl wget ca-certificates git build-essential cmake pkg-config libssl-dev zlib1g-dev libsqlite3-dev python3 python3-pip python3-venv jq htop ncdu ufw fail2ban cron rsyslog logrotate unzip psmisc gnupg 2>/dev/null
echo "  [DONE] Prerequisites installed"

# Step 2: Firewall
echo "[2/10] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 11434/tcp
ufw --force enable
echo "  [DONE] Firewall configured"

# Step 3: Fail2ban
echo "[3/10] Configuring fail2ban..."
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
echo "  [DONE] Fail2ban configured"

# Step 4: Logrotate
echo "[4/10] Configuring logrotate..."
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
echo "  [DONE] Logrotate configured"

# Step 5: Ollama User
echo "[5/10] Creating ollama user..."
id ollama 2>/dev/null || useradd -m -s /bin/bash ollama
mkdir -p /opt/ollama /var/lib/ollama /var/log/ollama /opt/ollama/scripts /opt/ollama/workers
chown -R ollama:ollama /opt/ollama /var/lib/ollama /var/log/ollama
echo "  [DONE] Ollama user and directories created"

# Step 6: Download and install Ollama
echo "[6/10] Installing Ollama binary..."
curl -fsSL https://ollama.com/download/ollama-linux-amd64 -o /opt/ollama/ollama
chmod +x /opt/ollama/ollama
chown ollama:ollama /opt/ollama/ollama
echo "  [DONE] Ollama binary installed"

# Step 7: Systemd Service
echo "[7/10] Configuring systemd service..."
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
echo "  [DONE] Systemd service configured"

# Step 8: Monitor
echo "[8/10] Deploying self-healing monitor..."
cat > /opt/ollama/monitor.sh << 'MONITOR'
#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/ollama-monitor.log"
OLLAMA_URL="http://localhost:11434"
MAX_RETRIES=3
RETRY_DELAY=10
log() { echo "$(date -Iseconds) $1" | tee -a "${LOG_FILE}"; }
check_health() { curl -sf "${OLLAMA_URL}/api/tags" > /dev/null 2>&1; }
check_disk() {
    local usage=$(df /var/lib/ollama | awk 'NR==2{print $5}' | tr -d '%')
    if [ "${usage}" -gt 90 ]; then
        log "Disk usage ${usage}%, cleaning up..."
        ollama list --format json 2>/dev/null | jq -r '.models[] | .name' | tail -5 | xargs -r -I{} ollama rm {} 2>/dev/null || true
    fi
}
check_memory() {
    local mem_usage=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
    if [ "${mem_usage}" -gt 95 ]; then
        log "Memory usage ${mem_usage}%, restarting ollama..."
        systemctl restart ollama
    fi
}
RETRY_COUNT=0
while true; do
    if check_health; then
        log "Health check passed"; RETRY_COUNT=0
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "Health check failed (${RETRY_COUNT}/${MAX_RETRIES})"
        if [ "${RETRY_COUNT}" -ge "${MAX_RETRIES}" ]; then
            log "Max retries, restarting ollama..."; systemctl restart ollama; RETRY_COUNT=0; sleep 30
        fi
    fi
    check_disk; check_memory; sleep 60
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
echo "  [DONE] Self-healing monitor deployed"

# Step 9: Cron Jobs
echo "[9/10] Configuring cron jobs..."
mkdir -p /opt/ollama/workers
chown -R ollama:ollama /opt/ollama/workers

# Worker: disk_cleanup
cat > /opt/ollama/workers/disk_cleanup.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-cleanup.log"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Disk cleanup started"
usage=$(df /var/lib/ollama | awk 'NR==2{print $5}' | tr -d '%')
log "Disk usage: ${usage}%"
if [ "${usage}" -gt 85 ]; then
    log "Above 85%, cleaning..."
    old=$(ollama list --format json 2>/dev/null | jq -r '.models | sort_by(.created_at) | .[0:3] | .[].name' 2>/dev/null || echo "")
    for m in ${old}; do ollama rm "${m}" 2>/dev/null || true; done
    log "Cleanup done"
fi
SCRIPT
chmod +x /opt/ollama/workers/disk_cleanup.sh

# Worker: supabase_sync
cat > /opt/ollama/workers/supabase_sync.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-supabase.log"
url="https://olhtxibbyhucxcmhzblq.supabase.co"
key="${SUPABASE_SERVICE_KEY:-}"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Supabase sync started"
curl -s -X POST "${url}/rest/v1/ollama_models" \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" -H "apikey: ${key}" \
    -d "$(ollama list --format json 2>/dev/null || echo '{\"models\":[]}')" \
    --fail && log "Sync complete" || log "Sync failed"
SCRIPT
chmod +x /opt/ollama/workers/supabase_sync.sh

# Worker: model_rotation
cat > /opt/ollama/workers/model_rotation.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-rotation.log"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Model rotation check started"
current=$(ollama list --format json 2>/dev/null || echo '{"models":[]}')
for model in gemma4:latest llama3.2:3b llama3.2:1b qwen2.5:7b qwen2.5:1.5b mistral:7b codellama:7b; do
    if ! echo "${current}" | jq -e ".models[] | select(.name == \"${model}\")" > /dev/null 2>&1; then
        log "Pulling: ${model}"
        ollama pull "${model}" 2>/dev/null && log "Pulled ${model}" || log "Failed: ${model}"
    fi
done
log "Rotation check complete"
SCRIPT
chmod +x /opt/ollama/workers/model_rotation.sh

# Worker: update_recommendations
cat > /opt/ollama/workers/update_recommendations.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-recommend.log"
url="https://olhtxibbyhucxcmhzblq.supabase.co"
key="${SUPABASE_SERVICE_KEY:-}"
log() { echo "$(date -Iseconds) $1" >> "${LOG}"; }
log "Recommendations update started"
curl -s -X POST "${url}/rest/v1/ollama_models" \
    -H "Authorization: Bearer ${key}" -H "Content-Type: application/json" -H "apikey: ${key}" \
    -d "$(ollama list --format json 2>/dev/null || echo '{\"models\":[]}')" \
    --fail && log "Sync OK" || log "Sync failed"
recs=$(curl -s -X GET "${url}/rest/v1/model_recommendations" \
    -H "Authorization: Bearer ${key}" -H "apikey: ${key}" -H "Content-Type: application/json" 2>/dev/null || echo '[]')
echo "${recs}" | jq -r '.[].name' 2>/dev/null | while read -r model; do
    [ -n "${model}" ] && ! ollama list --format json 2>/dev/null | jq -e ".models[] | select(.name == \"${model}\")" > /dev/null 2>&1 && \
        log "Pulling recommended: ${model}" && ollama pull "${model}" 2>/dev/null && log "Pulled ${model}" || true
done
log "Recommendations update complete"
SCRIPT
chmod +x /opt/ollama/workers/update_recommendations.sh

chown -R ollama:ollama /opt/ollama/workers

# Cron
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
echo "  [DONE] Cron jobs configured"

# Step 10: Install Models
echo "[10/10] Installing AI models..."
su - ollama -c "ollama pull llama3.2:3b" 2>/dev/null && echo "  [DONE] llama3.2:3b" || true
su - ollama -c "ollama pull llama3.2:1b" 2>/dev/null && echo "  [DONE] llama3.2:1b" || true
su - ollama -c "ollama pull gemma4:latest" 2>/dev/null && echo "  [DONE] gemma4" || true
su - ollama -c "ollama pull qwen2.5:7b" 2>/dev/null && echo "  [DONE] qwen2.5:7b" || true
su - ollama -c "ollama pull qwen2.5:1.5b" 2>/dev/null && echo "  [DONE] qwen2.5:1.5b" || true
su - ollama -c "ollama pull mistral:7b" 2>/dev/null && echo "  [DONE] mistral:7b" || true

# Final verification
echo ""
echo "=========================================="
echo " DEPLOYMENT COMPLETE"
echo "=========================================="
echo " Ollama URL: http://0.0.0.0:11434"
echo " API endpoint: http://169.58.68.183:11434/api/tags"
echo " Service status: $(systemctl is-active ollama)"
echo " Monitor status: $(systemctl is-active ollama-monitor)"
echo " Cron status: $(systemctl is-active cron)"
echo " Models installed: $(ollama list 2>/dev/null | wc -l || echo '0')"
echo "=========================================="