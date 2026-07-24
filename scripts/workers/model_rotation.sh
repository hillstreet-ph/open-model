#!/bin/bash
set -euo pipefail

ROTATION_CONFIG="/opt/ollama/rotation-config.json"
OLLAMA_URL="http://localhost:11434"
LOG="/var/log/ollama-rotation.log"

log() {
    echo "$(date -Iseconds) $1" >> "${LOG}"
}

log "Starting model rotation check"

# Get current models
CURRENT_MODELS=$(ollama list --format json 2>/dev/null || echo '{"models":[]}')
CURRENT_COUNT=$(echo "${CURRENT_MODELS}" | jq '.models | length')

log "Current model count: ${CURRENT_COUNT}"

# Check each model for staleness
echo "${CURRENT_MODELS}" | jq -c '.models[]' 2>/dev/null | while read -r model; do
    NAME=$(echo "${model}" | jq -r '.name')
    MODIFIED=$(echo "${model}" | jq -r '.modified_at // ""')
    
    log "Checking model: ${NAME}"
    
    # Check if model is in preferred list
    if echo "${PREFERRED_MODELS}" | jq -e ".[] | select(. == "${NAME}")" > /dev/null 2>&1; then
        log "  ${NAME} is in preferred list, keeping"
    else
        log "  ${NAME} not in preferred list, may need rotation"
    fi
    
    # Check request count (approximate via ollama ps)
    ACTIVE_REQUESTS=$(curl -s "${OLLAMA_URL}/api/ps" 2>/dev/null | jq '.models | length' || echo "0")
    log "  Active requests: ${ACTIVE_REQUESTS}"
done

# Check for new preferred models not yet installed
for MODEL in ${PREFERRED_MODELS_LIST}; do
    if ! echo "${CURRENT_MODELS}" | jq -e ".models[] | select(.name == "${MODEL}")" > /dev/null 2>&1; then
        log "Pulling new preferred model: ${MODEL}"
        ollama pull "${MODEL}" 2>/dev/null && log "Pulled ${MODEL}" || log "WARNING: Failed to pull ${MODEL}"
    fi
done

# Log rotation status
ROTATION_STATUS=$(curl -s "${OLLAMA_URL}/api/tags" 2>/dev/null | jq '{
    total_models: (.models | length),
    model_names: [.models[].name]
}' || echo '{"error": "unable to reach Ollama"}')

log "Rotation check complete"
log "Status: ${ROTATION_STATUS}"
