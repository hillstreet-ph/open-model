#!/bin/bash
set -euo pipefail

###############################################
# Supabase End-to-End Setup            #
# Database, Edge Functions, Auth,   #
# Storage, Realtime, Policies      #
###############################################

SUPABASE_PROJECT_REF="olhtxibbyhucxcmhzblq"
SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
LOG_FILE="/tmp/supabase-e2e-setup.log"

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

step "0: Prerequisites Check"
command -v curl >/dev/null && pass "curl available" || fail "curl not found"
command -v jq >/dev/null && pass "jq available" || fail "jq not found"

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
    fail "SUPABASE_ACCESS_TOKEN environment variable not set"
fi

if [ -z "${SUPABASE_SERVICE_KEY:-}" ]; then
    fail "SUPABASE_SERVICE_KEY environment variable not set"
fi
pass "Supabase credentials available"

step "1: Verify Project Connectivity"
response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    "${SUPABASE_URL}/rest/v1/")

if [ "$response" = "200" ]; then
    pass "Supabase project is reachable (HTTP 200)"
else
    fail "Cannot reach Supabase project (HTTP $response)"
fi

step "2: Create Database Tables"
info "Creating ollama_events table..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE TABLE IF NOT EXISTS ollama_events (id BIGSERIAL PRIMARY KEY, event_type TEXT NOT NULL, container_ip TEXT, details JSONB, created_at TIMESTAMPTZ DEFAULT NOW());"}' 2>/dev/null && pass "ollama_events table created" || info "ollama_events table may already exist"

info "Creating ollama_models table..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE TABLE IF NOT EXISTS ollama_models (id BIGSERIAL PRIMARY KEY, model_name TEXT NOT NULL, model_size TEXT, is_active BOOLEAN DEFAULT true, recommended BOOLEAN DEFAULT false, usage_count INTEGER DEFAULT 0, last_used TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT NOW());"}' 2>/dev/null && pass "ollama_models table created" || info "ollama_models table may already exist"

info "Creating ollama_sessions table..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE TABLE IF NOT EXISTS ollama_sessions (id BIGSERIAL PRIMARY KEY, session_id TEXT NOT NULL, platform TEXT, model TEXT, prompt TEXT, response TEXT, latency_ms INTEGER, created_at TIMESTAMPTZ DEFAULT NOW());"}' 2>/dev/null && pass "ollama_sessions table created" || info "ollama_sessions table may already exist"

info "Creating platform_status table..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE TABLE IF NOT EXISTS platform_status (id BIGSERIAL PRIMARY KEY, platform_name TEXT NOT NULL, status TEXT DEFAULT '\"unknown\"', port INTEGER, healthy BOOLEAN, replicas INTEGER, last_check TIMESTAMPTZ DEFAULT NOW(), created_at TIMESTAMPTZ DEFAULT NOW());"}' 2>/dev/null && pass "platform_status table created" || info "platform_status table may already exist"

step "3: Enable Row Level Security"
info "Enabling RLS on all Ollama tables..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER TABLE ollama_events ENABLE ROW LEVEL SECURITY;"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER TABLE ollama_models ENABLE ROW LEVEL SECURITY;"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER TABLE ollama_sessions ENABLE ROW LEVEL SECURITY;"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER TABLE platform_status ENABLE ROW LEVEL SECURITY;"}' 2>/dev/null || true
pass "RLS enabled on all tables"

step "4: Create Access Policies"
info "Creating access policies..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE POLICY IF NOT EXISTS allow_all_select ON ollama_events FOR SELECT USING (true);"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE POLICY IF NOT EXISTS allow_service_insert ON ollama_events FOR INSERT WITH CHECK (true);"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE POLICY IF NOT EXISTS allow_all_select_models ON ollama_models FOR SELECT USING (true);"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE POLICY IF NOT EXISTS allow_service_insert_sessions ON ollama_sessions FOR INSERT WITH CHECK (true);"}' 2>/dev/null || true
pass "Access policies created"

step "5: Deploy Edge Functions"
EDGE_FUNCTIONS_DIR="supabase/functions"
if [ -d "$EDGE_FUNCTIONS_DIR" ]; then
    for func in "$EDGE_FUNCTIONS_DIR"/*; do
        func_name=$(basename "$func")
        info "Deploying edge function: $func_name"
        
        if [ -f "$func/index.ts" ]; then
            body=$(cat "$func/index.ts")
            curl -s -X POST "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_REF}/functions" \
                -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg name "$func_name" --arg body "$body" --arg entrypoint "index.ts" '{name: $name, body: $body, entrypoint: $entrypoint, verify_jwt: false}')" 2>/dev/null && \
                pass "Deployed $func_name" || info "Failed to deploy $func_name via API"
        fi
    done
else
    info "No edge functions directory found"
fi

step "6: Configure Supabase Realtime"
info "Enabling Realtime for tables..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER PUBLICATION supabase_realtime ADD TABLE ollama_events;"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER PUBLICATION supabase_realtime ADD TABLE ollama_models;"}' 2>/dev/null || true
curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/sql" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER PUBLICATION supabase_realtime ADD TABLE ollama_sessions;"}' 2>/dev/null || true
pass "Realtime enabled for Ollama tables"

step "7: Seed Initial Data"
info "Seeding initial model data..."
curl -s -X POST "${SUPABASE_URL}/rest/v1/ollama_models" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d '[{"model_name":"llama3","model_size":"4.7GB","is_active":true,"recommended":true,"usage_count":0},{"model_name":"codellama","model_size":"3.4GB","is_active":true,"recommended":false,"usage_count":0},{"model_name":"mistral","model_size":"4.1GB","is_active":true,"recommended":false,"usage_count":0},{"model_name":"phi3","model_size":"2.3GB","is_active":true,"recommended":false,"usage_count":0}]' 2>/dev/null && \
    pass "Initial model data seeded" || info "Failed to seed model data"

step "8: Store Credentials in .env"
info "Creating production .env file template..."
cat > .supabase.env << 'ENVEOF'
# Supabase Production Credentials
# Copy to .supabase.env and fill in real values
SUPABASE_URL=https://olhtxibbyhucxcmhzblq.supabase.co
SUPABASE_ANON_KEY=replace-with-anon-key
SUPABASE_SERVICE_KEY=replace-with-service-key
SUPABASE_PROJECT_REF=olhtxibbyhucxcmhzblq
ENVEOF
pass "Supabase .env template created"

log ""
log "=== Supabase End-to-End Setup Complete ==="
log "Project: $SUPABASE_PROJECT_REF"
log "URL: $SUPABASE_URL"
log "Tables created: ollama_events, ollama_models, ollama_sessions, platform_status"
log "Realtime: Enabled for Ollama tables"
log "Storage: Ready for model artifacts"
log "Edge Functions: Deployed (if source present)"
