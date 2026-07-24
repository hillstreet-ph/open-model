#!/bin/bash
set -euo pipefail

###############################################
# Contabo Infrastructure Sync Script      #
# Pulls latest platform code from     #
# GitHub repo to Contabo server       #
###############################################

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
REPO_DIR="/opt/ollama"

log() {
    echo "[$(date -Iseconds)] $1"
}

step() {
    log "=========================================="
    log "STEP: $1"
    log "=========================================="
}

pass() { log "  [PASS] $1"; }
fail() { log "  [FAIL] $1"; }

step "0: Prerequisites Check"
command -v ssh >/dev/null 2>&1 && pass "SSH client available" || fail "SSH not found"
test -f "$SSH_KEY" && pass "SSH key found at $SSH_KEY" || fail "SSH key not found at $SSH_KEY"
log "  Target: ${SSH_USER}@${CONTAINER_IP}:${REPO_DIR}"

step "1: Sync Platform Files to Contabo"
log "  Syncing infrastructure scripts..."
scp -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -P "$SSH_PORT" \
    -r \
    scripts/contabo/ \
    "${SSH_USER}@${CONTAINER_IP}:${REPO_DIR}/scripts/contabo/" \
    && pass "Contabo scripts synced" || fail "Contabo scripts sync failed"

log "  Syncing platform code..."
scp -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -P "$SSH_PORT" \
    -r \
    platform/ \
    "${SSH_USER}@${CONTAINER_IP}:${REPO_DIR}/platform/" \
    && pass "Platform code synced" || fail "Platform code sync failed"

log "  Syncing K8s manifests..."
scp -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -P "$SSH_PORT" \
    -r \
    k8s/ \
    "${SSH_USER}@${CONTAINER_IP}:${REPO_DIR}/k8s/" \
    && pass "K8s manifests synced" || fail "K8s manifests sync failed"

log "  Syncing .github/workflows/..."
scp -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -P "$SSH_PORT" \
    -r \
    .github/workflows/ \
    "${SSH_USER}@${CONTAINER_IP}:${REPO_DIR}/.github/workflows/" \
    && pass "GitHub workflows synced" || fail "GitHub workflows sync failed"

log "  Syncing scripts/supabase/..."
scp -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -P "$SSH_PORT" \
    -r \
    scripts/supabase/ \
    "${SSH_USER}@${CONTAINER_IP}:${REPO_DIR}/scripts/supabase/" \
    && pass "Supabase scripts synced" || fail "Supabase scripts sync failed"

step "2: Execute Platform Deployment on Contabo"
log "  Running server_platform.sh on Contabo..."
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "cd ${REPO_DIR} && chmod +x scripts/contabo/server_platform.sh && bash scripts/contabo/server_platform.sh" \
    && pass "Platform deployment executed on Contabo" || fail "Platform deployment failed"

step "3: Run Production Readiness Check"
log "  Running readiness check on Contabo..."
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "cd ${REPO_DIR} && bash scripts/contabo/production_readiness_check.sh" \
    && pass "Production readiness check passed" || fail "Production readiness check failed"

step "4: Restart All Services"
log "  Restarting all platform services..."
ssh -o StrictHostKeyChecking=no \
    -i "$SSH_KEY" \
    -P "$SSH_PORT" \
    "${SSH_USER}@${CONTAINER_IP}" \
    "cd ${REPO_DIR} && docker compose -f platform/docker-compose.prod.yml restart" \
    && pass "Services restarted" || fail "Service restart failed"

log ""
log "=== Infrastructure Sync Complete ==="
log "All platform code, K8s manifests, and scripts synced to Contabo server"
log "Platform services will be running via docker compose"
