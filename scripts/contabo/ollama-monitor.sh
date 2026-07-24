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
