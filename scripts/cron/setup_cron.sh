#!/bin/bash
set -euo pipefail

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"

SSH="ssh -i ${SSH_KEY_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP}"

echo "=== Setting up cron jobs and background workers ==="

${SSH} "mkdir -p /opt/ollama/scripts"

${SSH} "cat > /opt/ollama/scripts/sync_check.sh << 'INNEREOF'
#!/bin/bash
set -euo pipefail
LOG=\"/var/log/ollama-sync.log\"
OLLAMA_URL=\"http://localhost:11434\"

log() {
    echo \"\$(date -Iseconds) \$1\" >> \"\${LOG}\"
}

log \"Starting model sync check\"

if curl -sf \"\${OLLAMA_URL}/api/tags\" > /dev/null 2>&1; then
    log \"Ollama is responsive, checking model sync...\"
    REMOTE_COUNT=\$(curl -s \"\${OLLAMA_URL}/api/tags\" | jq '.models | length')
    log \"Currently installed models: \${REMOTE_COUNT}\"
else
    log \"WARNING: Ollama is not responsive\"
fi

log \"Sync check complete\"
INNEREOF"

${SSH} "chmod +x /opt/ollama/scripts/sync_check.sh"

${SSH} "cat > /opt/ollama/scripts/disk_cleanup.sh << 'INNEREOF'
#!/bin/bash
set -euo pipefail
LOG=\"/var/log/ollama-cleanup.log\"

log() {
    echo \"\$(date -Iseconds) \$1\" >> \"\${LOG}\"
}

log \"Starting disk cleanup\"

DISK_USAGE=\$(df /var/lib/ollama | awk 'NR==2{print \$5}' | tr -d '%')
log \"Current disk usage: \${DISK_USAGE}%\"

if [ \"\${DISK_USAGE}\" -gt 85 ]; then
    log \"Disk usage above 85%, starting cleanup...\"
    OLD_MODELS=\$(ollama list --format json 2>/dev/null | jq -r '.models | sort_by(.created_at) | .[0:3] | .[].name' 2>/dev/null || echo \"\")
    for MODEL in \${OLD_MODELS}; do
        log \"Removing old model: \${MODEL}\"
        ollama rm \"\${MODEL}\" 2>/dev/null || true
    done
    log \"Cleanup complete\"
else
    log \"Disk usage normal, no cleanup needed\"
fi
INNEREOF"

${SSH} "chmod +x /opt/ollama/scripts/disk_cleanup.sh"

${SSH} "cat > /opt/ollama/scripts/supabase_sync.sh << 'INNEREOF'
#!/bin/bash
set -euo pipefail
LOG=\"/var/log/ollama-supabase.log\"
SUPABASE_URL=\"https://olhtxibbyhucxcmhzblq.supabase.co\"
SUPABASE_KEY=\"\${SUPABASE_SERVICE_KEY}\"

log() {
    echo \"\$(date -Iseconds) \$1\" >> \"\${LOG}\"
}

log \"Starting Supabase sync\"

MODELS_JSON=\$(ollama list --format json 2>/dev/null || echo '{\"models\":[]}')

curl -s -X POST \"\${SUPABASE_URL}/rest/v1/ollama_models\" \
    -H \"Authorization: Bearer \${SUPABASE_KEY}\" \
    -H \"Content-Type: application/json\" \
    -H \"apikey: \${SUPABASE_KEY}\" \
    -d \"\${MODELS_JSON}\" \
    --fail || log \"WARNING: Sync to Supabase failed\"

log \"Supabase sync complete\"
INNEREOF"

${SSH} "chmod +x /opt/ollama/scripts/supabase_sync.sh"

${SSH} "cat > /etc/cron.d/ollama-agent << 'INNEREOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/go/bin

*/5 * * * * ollama /opt/ollama/scripts/sync_check.sh >> /var/log/ollama-cron.log 2>&1
0 * * * * ollama /opt/ollama/scripts/sync_check.sh >> /var/log/ollama-sync.log 2>&1
0 2 * * * ollama /opt/ollama/scripts/disk_cleanup.sh >> /var/log/ollama-cleanup.log 2>&1
0 */6 * * * ollama /opt/ollama/scripts/supabase_sync.sh >> /var/log/ollama-sync.log 2>&1
0 3 * * * ollama /opt/ollama/scripts/update_recommendations.sh >> /var/log/ollama-recommend.log 2>&1
INNEREOF"

${SSH} "chmod 644 /etc/cron.d/ollama-agent"
${SSH} "systemctl restart cron || true"

echo "=== Cron jobs and workers configured ==="
