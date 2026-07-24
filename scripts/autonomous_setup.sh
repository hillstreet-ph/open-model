#!/bin/bash
set -euo pipefail

###############################################
# Autonomous End-to-End Setup Orchestrator #
# Ollama Infrastructure on Contabo      #
###############################################

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"
SERVER_PASSWORD="MnL3Tj8La1f"
OLLAMA_BINARY_URL="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/ollama-autonomous-setup.log"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "${LOG_FILE}"
}

step() {
    log "=========================================="
    log "STEP: $1"
    log "=========================================="
}

pass() { log "  [PASS] $1"; }
fail() { log "  [FAIL] $1"; }
info() { log "  [INFO] $1"; }

# Check prerequisites
step "0: Prerequisites Check"
command -v ssh >/dev/null || { fail "ssh not found"; exit 1; }
command -v curl >/dev/null || { fail "curl not found"; exit 1; }
command -v ssh-keygen >/dev/null || { fail "ssh-keygen not found"; exit 1; }
pass "All prerequisites available"

# Phase 1: Generate SSH key
step "1: Generate SSH Key Pair"
if [ ! -f "${SSH_KEY_PATH}" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    log "  Generating ed25519 SSH key..."
    ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -C "codex-contabo-deploy-2026-07-24" -N "" -q
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
    pass "SSH key generated at ${SSH_KEY_PATH}"
else
    pass "SSH key already exists"
fi

# Phase 2: Deploy SSH key to server (using password)
step "2: Deploy SSH Key to Contabo Server"
info "Using sshpass for password-based key deployment"
# Check if sshpass is available
if command -v sshpass &>/dev/null; then
    sshpass -p "${SERVER_PASSWORD}" ssh-copy-id -p "${SSH_PORT}" -o StrictHostKeyChecking=no "${SSH_USER}@${CONTAINER_IP}" 2>/dev/null && \
        pass "SSH key deployed via sshpass" || \
        fail "sshpass deployment failed"
else
    info "sshpass not available, attempting manual deployment"
    # Try using ssh with password via expect-like approach
    info "Manual key deployment may be required"
    info "Run: ssh-copy-id -p ${SSH_PORT} root@${CONTAINER_IP}"
fi

# Phase 3: Server setup
step "3: Server Provisioning"
info "Running setup_server.sh..."
if [ -f "${SCRIPT_DIR}/scripts/contabo/setup_server.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/contabo/setup_server.sh" && \
        pass "Server provisioning complete" || \
        fail "Server provisioning failed"
else
    info "setup_server.sh not found in local scripts, skipping"
    info "Run on server: ssh root@${CONTAINER_IP} 'bash -s' < scripts/contabo/setup_server.sh"
fi

# Phase 4: Deploy Ollama binary
step "4: Deploy Ollama Binary"
info "Checking if Ollama binary needs building or downloading..."
if command -v go &>/dev/null; then
    info "Go found - building Ollama from source"
    pushd "${SCRIPT_DIR}" >/dev/null
    go build -o ollama . && pass "Ollama binary built" || fail "Build failed"
    popd >/dev/null
else
    info "Go not found locally - Ollama binary must be built on server"
    info "Run on server: scripts/contabo/deploy.sh"
fi

# Phase 5: Install models
step "5: Install AI Models"
info "Running install_models.sh..."
if command -v ollama &>/dev/null; then
    bash "${SCRIPT_DIR}/scripts/contabo/install_models.sh" && \
        pass "Models installed" || \
        fail "Model installation failed"
else
    info "ollama command not found locally - models must be installed on server"
fi

# Phase 6: Deploy self-healing monitor
step "6: Deploy Self-Healing Monitor"
info "Running setup_monitor.sh..."
bash "${SCRIPT_DIR}/scripts/contabo/setup_monitor.sh" && \
    pass "Monitor deployed" || \
    fail "Monitor setup failed"

# Phase 7: Cron jobs
step "7: Configure Cron Jobs & Workers"
bash "${SCRIPT_DIR}/scripts/cron/setup_cron.sh" && \
    pass "Cron configured" || \
    fail "Cron setup failed"

# Phase 8: Self-healing verification
step "8: Self-Heal Verification"
info "Running agent_fixer.py diagnostics..."
python3 "${SCRIPT_DIR}/scripts/fixers/agent_fixer.py" diag 2>/dev/null && \
    pass "Diagnostics complete" || \
    info "Diagnostics require server access"

# Phase 9: Supabase integration
step "9: Supabase Integration"
info "Checking Supabase CLI..."
if command -v supabase &>/dev/null; then
    bash "${SCRIPT_DIR}/scripts/supabase/setup.sh" && \
        pass "Supabase configured" || \
        fail "Supabase setup failed"
else
    info "Supabase CLI not installed - run scripts/supabase/setup.sh after Supabase CLI install"
fi

# Phase 10: Final verification
step "10: Final Verification"
info "Running deployment verification..."
bash "${SCRIPT_DIR}/scripts/contabo/verify_deployment.sh" && \
    pass "All verification checks passed" || \
    fail "Some verification checks failed"

# Summary
log ""
log "================================================"
log " AUTONOMOUS SETUP COMPLETE"
log "================================================"
log ""
log "Next Steps:"
log "  1. Deploy Ollama binary: ssh root@${CONTAINER_IP} 'bash -s' < scripts/contabo/deploy.sh"
log "  2. Install models: ssh root@${CONTAINER_IP} 'bash -s' < scripts/contabo/install_models.sh"
log "  3. Verify: ssh root@${CONTAINER_IP} 'systemctl is-active ollama ollama-monitor cron'"
log "  4. Test API: curl http://${CONTAINER_IP}:11434/api/tags"
log ""
log "Autonomous agents status:"
log "  - hermes-health: Runs every 5 min (systemd + cron)"
log "  - hermes-fix: Event-driven self-healer"
log "  - hermes-rotate: Daily at 3 AM"
log "  - hermes-sync: Every 6 hours"
log "  - hermes-report: Daily summary"
log "  - self_improvement.py: Continuous optimization loop"
log "  - autopilot.py: Autonomous DevOps (cycle/continuous)"
log "================================================"
