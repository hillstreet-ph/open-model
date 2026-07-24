#!/bin/bash
set -euo pipefail

###############################################
# Professional End-to-End Deployment  #
# Contabo + Supabase + Multi-Fork   #
# Platform                        #
###############################################

CONTAINER_IP="169.58.68.183"
LOG_FILE="/tmp/professional-deploy.log"

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

usage() {
    echo "Usage: $0 [stage...]"
    echo ""
    echo "Stages:"
    echo "  contabo    Setup Contabo server (firewall, Docker, Ollama)"
    echo "  supabase   Setup Supabase database and edge functions"
    echo "  platform   Deploy multi-fork platform (Open Connect, Command, Worker)"
    echo "  verify     Run end-to-end verification"
    echo "  all        Run all stages in sequence"
    echo ""
    echo "Examples:"
    echo "  $0 all              Full deployment"
    echo "  $0 contabo platform  Contabo + platform only"
    echo "  $0 verify           Verification only"
    exit 1
}

STAGES=("${@:-all}")
if [ "${STAGES[0]}" = "help" ] || [ "${STAGES[0]}" = "--help" ] || [ "${STAGES[0]}" = "-h" ]; then
    usage
fi

log "=== Professional Deployment Started ==="
log "Target: ${CONTAINER_IP}"
log "Stages: ${STAGES[*]}"
log ""

deploy_contabo() {
    step "Contabo Server Setup"
    log "Running professional Contabo setup..."
    
    SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
    if [ ! -f "$SSH_KEY" ]; then
        fail "SSH key not found at ${SSH_KEY}"
        log "  Generate it with: scripts/contabo/setup_ssh.sh"
        log "  Or copy an existing key to ~/.ssh/id_ed25519_contabo"
        return 1
    fi
    
    log "  Executing setup_contabo_pro.sh locally (scripts will be pushed via SCP)..."
    log "  This will configure UFW, Docker, Ollama, and all platform scripts on the server"
    
    info "Pushing deployment scripts to Contabo..."
    scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
        -r \
        scripts/contabo/ \
        platform/ \
        k8s/ \
        scripts/supabase/ \
        scripts/deploy_all.sh \
        root@${CONTAINER_IP}:/opt/ollama/ 2>/dev/null && \
        pass "Scripts pushed to Contabo" || fail "Failed to push scripts"
    
    info "Running Contabo setup on server..."
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" \
        root@${CONTAINER_IP} \
        "cd /opt/ollama && bash scripts/contabo/setup_contabo_pro.sh" 2>/dev/null && \
        pass "Contabo setup completed" || fail "Contabo setup failed"
}

deploy_supabase() {
    step "Supabase End-to-End Setup"
    log "Running Supabase E2E setup..."
    
    if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
        fail "SUPABASE_ACCESS_TOKEN not set"
        log "  export SUPABASE_ACCESS_TOKEN=your_token"
        return 1
    fi
    
    if [ -z "${SUPABASE_SERVICE_KEY:-}" ]; then
        fail "SUPABASE_SERVICE_KEY not set"
        log "  export SUPABASE_SERVICE_KEY=your_key"
        return 1
    fi
    
    info "Running Supabase setup script..."
    chmod +x scripts/supabase/setup_e2e.sh
    bash scripts/supabase/setup_e2e.sh && \
        pass "Supabase setup completed" || fail "Supabase setup failed"
}

deploy_platform() {
    step "Multi-Fork Platform Deployment"
    log "Deploying Open Connect, Open Command, Open Worker..."
    
    SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
    info "Running platform deployment on Contabo..."
    
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" \
        root@${CONTAINER_IP} \
        "cd /opt/ollama && bash scripts/contabo/server_platform.sh" 2>/dev/null && \
        pass "Platform deployment completed" || fail "Platform deployment failed"
}

verify_deployment() {
    step "End-to-End Verification"
    log "Running verification against ${CONTAINER_IP}..."
    
    SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
    
    if [ ! -f "$SSH_KEY" ]; then
        fail "SSH key not found at ${SSH_KEY}"
        return 1
    fi
    
    info "Pushing verification script to Contabo..."
    scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
        scripts/contabo/verify_e2e.sh \
        root@${CONTAINER_IP}:/opt/ollama/scripts/contabo/ 2>/dev/null && \
        pass "Verification script pushed" || fail "Failed to push verification script"
    
    info "Running verification on Contabo..."
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" \
        root@${CONTAINER_IP} \
        "cd /opt/ollama && bash scripts/contabo/verify_e2e.sh" 2>/dev/null && \
        pass "Verification passed" || fail "Verification failed"
}

for stage in "${STAGES[@]}"; do
    case "$stage" in
        contabo)
            deploy_contabo || true
            ;;
        supabase)
            deploy_supabase || true
            ;;
        platform)
            deploy_platform || true
            ;;
        verify)
            verify_deployment || true
            ;;
        all)
            deploy_contabo || true
            echo ""
            deploy_supabase || true
            echo ""
            deploy_platform || true
            echo ""
            verify_deployment || true
            ;;
        *)
            fail "Unknown stage: $stage"
            usage
            ;;
    esac
done

log ""
log "=== Deployment Complete ==="
log "Check ${LOG_FILE} for full output"
log ""
log "Access URLs:"
log "  Open Connect (Web UI):   http://${CONTAINER_IP}:3000"
log "  Open Connect API Bridge: http://${CONTAINER_IP}:8000"
log "  Open Command (Swarm):    http://${CONTAINER_IP}:5000"
log "  Open Worker (Hermes):     http://${CONTAINER_IP}:6000"
log "  Platform Orchestrator:    http://${CONTAINER_IP}:8080"
log "  Ollama API:               http://${CONTAINER_IP}:11434"
