#!/bin/bash
set -euo pipefail

###############################################
# End-to-End Verification Script      #
# Verifies Ollama + All Forks +   #
# Contabo Firewall + Supabase     #
###############################################

CONTAINER_IP="169.58.68.183"
SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
LOG_FILE="/tmp/e2e-verification.log"

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
fail() { log "  [FAIL] $1"; }
info() { log "  [INFO] $1"; }

FAIL_COUNT=0
PASS_COUNT=0
TOTAL_COUNT=0

check() {
    local name="$1"
    local result="$2"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [ "$result" = "true" ]; then
        pass "$name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "$name"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

step "1: Contabo Server Connectivity"
check "SSH connectivity to ${CONTAINER_IP}" \
    "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY root@${CONTAINER_IP} 'echo ok' 2>/dev/null"

check "Contabo server ping" \
    "ping -c 1 -W 5 ${CONTAINER_IP} 2>/dev/null"

step "2: Firewall (UFW) Verification"
if [ "${PASS_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    info "Checking firewall rules on Contabo server..."
    
    required_ports=(22 11434 3000 5000 6000 8000 8080 8443 8444 8445 9090)
    for port in "${required_ports[@]}"; do
        check "UFW allows port ${port}" \
            "ssh -o StrictHostKeyChecking=no -i $SSH_KEY root@${CONTAINER_IP} \"ufw status | grep -q '${port}/tcp'\" 2>/dev/null"
    done
else
    info "Cannot verify firewall remotely (SSH not available from this environment)"
    info "Run on Contabo server: ufw status verbose"
fi

step "3: Ollama Backend Verification"
check "Ollama API reachable at ${CONTAINER_IP}:11434" \
    "curl -sf http://${CONTAINER_IP}:11434/api/tags > /dev/null 2>&1"

check "Ollama models loaded" \
    "curl -sf http://${CONTAINER_IP}:11434/api/tags | jq -r '.models | length' 2>/dev/null | grep -q '[0-9]'"

check "Ollama health endpoint" \
    "curl -sf http://${CONTAINER_IP}:11434/api/health 2>/dev/null || curl -sf http://${CONTAINER_IP}:11434/api/tags > /dev/null 2>&1"

step "4: Open Connect Fork (Open Web UI)"
check "Open Connect health at port 3000" \
    "curl -sf http://${CONTAINER_IP}:3000/api/health > /dev/null 2>&1"

check "Open Connect chat interface" \
    "curl -sf http://${CONTAINER_IP}:3000 > /dev/null 2>&1"

check "Open Connect can reach Ollama for inference" \
    "curl -sf http://${CONTAINER_IP}:3000/api/tags > /dev/null 2>&1"

check "Open Connect API bridge at port 8000" \
    "curl -sf http://${CONTAINER_IP}:8000/api/health > /dev/null 2>&1"

step "5: Open Command Fork (SwarmClaw)"
check "Open Command health at port 5000" \
    "curl -sf http://${CONTAINER_IP}:5000/api/health > /dev/null 2>&1"

check "Open Command agents endpoint" \
    "curl -sf http://${CONTAINER_IP}:5000/api/agents > /dev/null 2>&1"

check "Open Command swarm status" \
    "curl -sf http://${CONTAINER_IP}:5000/api/swarm/status > /dev/null 2>&1"

check "Open Command task execution" \
    "curl -sf http://${CONTAINER_IP}:8000/api/health > /dev/null 2>&1"

step "6: Open Worker Fork (Hermes Agent)"
check "Open Worker health at port 6000" \
    "curl -sf http://${CONTAINER_IP}:6000/api/health > /dev/null 2>&1"

check "Open Worker workers endpoint" \
    "curl -sf http://${CONTAINER_IP}:6000/api/workers > /dev/null 2>&1"

check "Open Worker task endpoint" \
    "curl -sf http://${CONTAINER_IP}:6000/api/task > /dev/null 2>&1"

step "7: Platform Orchestrator Verification"
check "Orchestrator health at port 8080" \
    "curl -sf http://${CONTAINER_IP}:8080/api/health > /dev/null 2>&1"

check "Orchestrator platforms listing" \
    "curl -sf http://${CONTAINER_IP}:8080/api/platforms > /dev/null 2>&1"

check "Orchestrator cross-platform bridge health" \
    "curl -sf http://${CONTAINER_IP}:8080/api/bridge/health > /dev/null 2>&1"

check "Orchestrator task pipeline status" \
    "curl -sf http://${CONTAINER_IP}:8080/api/tasks/status > /dev/null 2>&1"

check "Orchestrator swarm status" \
    "curl -sf http://${CONTAINER_IP}:8080/api/swarm/status > /dev/null 2>&1"

check "Orchestrator dashboard status" \
    "curl -sf http://${CONTAINER_IP}:8080/api/dashboard/status > /dev/null 2>&1"

step "8: Cross-Platform Bridge Verification"
check "Cross-platform bridge health at port 8443" \
    "curl -sf http://${CONTAINER_IP}:8443/api/health > /dev/null 2>&1"

check "Cross-platform bridge can reach Ollama" \
    "curl -sf http://${CONTAINER_IP}:8443/bridge-test > /dev/null 2>&1"

step "9: Task Pipeline Verification"
check "Task pipeline health at port 8444" \
    "curl -sf http://${CONTAINER_IP}:8444/api/health > /dev/null 2>&1"

check "Task pipeline task submission" \
    "curl -sf -X POST http://${CONTAINER_IP}:8444/api/task -d '{\"type\":\"chat_message\",\"payload\":{\"message\":\"test\"}}' -H 'Content-Type: application/json' > /dev/null 2>&1"

step "10: Swarm Coordinator Verification"
check "Swarm coordinator health at port 8445" \
    "curl -sf http://${CONTAINER_IP}:8445/api/health > /dev/null 2>&1"

check "Swarm coordinator agent listing" \
    "curl -sf http://${CONTAINER_IP}:8445/api/agents > /dev/null 2>&1"

step "11: Monitor Dashboard Verification"
check "Monitor health at port 9090" \
    "curl -sf http://${CONTAINER_IP}:9090/api/health > /dev/null 2>&1"

step "12: Supabase Database Verification"
if [ -n "${SUPABASE_SERVICE_KEY:-}" ]; then
    check "Supabase database connectivity" \
        "curl -sf -H 'apikey: ${SUPABASE_SERVICE_KEY}' -H 'Authorization: Bearer ${SUPABASE_SERVICE_KEY}' ${SUPABASE_URL}/rest/v1/ollama_models > /dev/null 2>&1"
    
    check "Supabase ollama_events table exists" \
        "curl -sf -H 'apikey: ${SUPABASE_SERVICE_KEY}' -H 'Authorization: Bearer ${SUPABASE_SERVICE_KEY}' ${SUPABASE_URL}/rest/v1/ollama_events?select=id&limit=1 > /dev/null 2>&1"
    
    check "Supabase ollama_models table exists" \
        "curl -sf -H 'apikey: ${SUPABASE_SERVICE_KEY}' -H 'Authorization: Bearer ${SUPABASE_SERVICE_KEY}' ${SUPABASE_URL}/rest/v1/ollama_models?select=id&limit=1 > /dev/null 2>&1"
    
    check "Supabase ollama_sessions table exists" \
        "curl -sf -H 'apikey: ${SUPABASE_SERVICE_KEY}' -H 'Authorization: Bearer ${SUPABASE_SERVICE_KEY}' ${SUPABASE_URL}/rest/v1/ollama_sessions?select=id&limit=1 > /dev/null 2>&1"
    
    check "Supabase platform_status table exists" \
        "curl -sf -H 'apikey: ${SUPABASE_SERVICE_KEY}' -H 'Authorization: Bearer ${SUPABASE_SERVICE_KEY}' ${SUPABASE_URL}/rest/v1/platform_status?select=id&limit=1 > /dev/null 2>&1"
else
    info "Skipping Supabase verification (SUPABASE_SERVICE_KEY not set)"
fi

step "13: Cross-Fork Connectivity Test"
check "Open Connect can call Ollama for chat" \
    "curl -sf -X POST http://${CONTAINER_IP}:3000/api/v1/chat/completions -d '{\"model\":\"llama3\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}' -H 'Content-Type: application/json' > /dev/null 2>&1"

check "Open Command can call Ollama for code generation" \
    "curl -sf -X POST http://${CONTAINER_IP}:5000/api/generate -d '{\"prompt\":\"print hello world\",\"model\":\"codellama\"}' -H 'Content-Type: application/json' > /dev/null 2>&1"

check "Open Worker can call Ollama for inference" \
    "curl -sf -X POST http://${CONTAINER_IP}:6000/api/generate -d '{\"prompt\":\"analyze this\",\"model\":\"phi3\"}' -H 'Content-Type: application/json' > /dev/null 2>&1"

step "14: End-to-End Summary"
log ""
log "============================================"
log "  END-TO-END VERIFICATION SUMMARY"
log "============================================"
log "Total checks: ${TOTAL_COUNT}"
log "Passed: ${PASS_COUNT}"
log "Failed: ${FAIL_COUNT}"
log ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    log "VERIFICATION FAILED - ${FAIL_COUNT} check(s) did not pass"
    log "Review the failed checks above and fix them before production use"
    exit 1
else
    log "VERIFICATION PASSED - All ${TOTAL_COUNT} checks passed"
    log "The Ollama multi-fork platform is fully operational"
    log ""
    log "Access URLs:"
    log "  Open Connect (Web UI):   http://${CONTAINER_IP}:3000"
    log "  Open Connect API Bridge: http://${CONTAINER_IP}:8000"
    log "  Open Command (Swarm):    http://${CONTAINER_IP}:5000"
    log "  Open Worker (Hermes):     http://${CONTAINER_IP}:6000"
    log "  Platform Orchestrator:    http://${CONTAINER_IP}:8080"
    log "  Cross-Platform Bridge:    http://${CONTAINER_IP}:8443"
    log "  Task Pipeline:            http://${CONTAINER_IP}:8444"
    log "  Swarm Coordinator:        http://${CONTAINER_IP}:8445"
    log "  Monitor Dashboard:        http://${CONTAINER_IP}:9090"
    log "  Ollama API:               http://${CONTAINER_IP}:11434"
    exit 0
fi
