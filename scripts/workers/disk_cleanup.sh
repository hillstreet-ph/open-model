#!/bin/bash
set -euo pipefail
LOG="/var/log/ollama-cleanup.log"

log() {
    echo "$(date -Iseconds) $1" >> "${LOG}"
}

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
