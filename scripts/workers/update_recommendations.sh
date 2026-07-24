#!/bin/bash
set -euo pipefail

LOG="/var/log/ollama-recommend.log"
OLLAMA_URL="http://localhost:11434"
SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY="${SUPABASE_SERVICE_KEY}"

log() {
    echo "$(date -Iseconds) $1" >> "${LOG}"
}

log "Starting recommendations update"

# Sync current model list to Supabase
CURRENT_MODELS=$(ollama list --format json 2>/dev/null || echo '{"models":[]}')

curl -s -X POST "${SUPABASE_URL}/rest/v1/ollama_models"     -H "Authorization: Bearer ${SUPABASE_KEY}"     -H "Content-Type: application/json"     -H "apikey: ${SUPABASE_KEY}"     -d "${CURRENT_MODELS}"     --fail && log "Model sync to Supabase successful" || log "WARNING: Model sync to Supabase failed"

# Fetch model recommendations from Supabase
RECOMMENDATIONS=$(curl -s -X GET "${SUPABASE_URL}/rest/v1/model_recommendations"     -H "Authorization: Bearer ${SUPABASE_KEY}"     -H "apikey: ${SUPABASE_KEY}"     -H "Content-Type: application/json" 2>/dev/null || echo '[]')

echo "${RECOMMENDATIONS}" | jq -r '.[].name' 2>/dev/null | while read -r model; do
    if [ -n "${model}" ]; then
        if ! ollama list --format json 2>/dev/null | jq -e ".models[] | select(.name == "${model}")" > /dev/null 2>&1; then
            log "Pulling recommended model: ${model}"
            ollama pull "${model}" 2>/dev/null && log "Pulled ${model}" || log "WARNING: Failed to pull ${model}"
        fi
    fi
done

log "Recommendations update complete"
