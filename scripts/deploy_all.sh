#!/bin/bash
set -euo pipefail

###############################################
# Ollama Infrastructure - Master Deployment    #
# Contabo Server 169.58.68.183               #
# Supabase Project: olhtxibbyhucxcmhzblq     #
###############################################

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"

SSH="ssh -i ${SSH_KEY_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP}"

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
NC='[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

step() {
    echo ""
    echo "================================================"
    echo " STEP: $1"
    echo "================================================"
}

echo "=== Ollama Infrastructure Master Deployment ==="
echo "Server: ${CONTAINER_IP}"
echo "Time: $(date -Iseconds)"
echo ""

# Pre-flight checks
step "Pre-flight Checks"
if [ ! -f "${SSH_KEY_PATH}" ]; then
    fail "SSH key not found at ${SSH_KEY_PATH}"
    echo "Run: scripts/contabo/setup_ssh.sh first"
    exit 1
fi
pass "SSH key found"

if ! command -v ssh &>/dev/null; then
    fail "ssh command not found"
    exit 1
fi
pass "ssh available"

# Check server connectivity
info "Testing SSH connection..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP} "echo ok" 2>/dev/null | grep -q "ok"; then
    pass "SSH connection to ${CONTAINER_IP} OK"
else
    fail "Cannot connect to ${CONTAINER_IP}"
    echo "Ensure:"
    echo "  1. SSH key is deployed to the server"
    echo "  2. Server IP 169.58.68.183 is correct"
    echo "  3. Port 22 is open"
    exit 1
fi

# Phase 1: Server Setup
step "Phase 1: Server Setup"
info "Running setup_server.sh..."
${SSH} "bash -s" < scripts/contabo/setup_server.sh && pass "Server setup complete" || fail "Server setup failed"

# Phase 2: Deploy Ollama
step "Phase 2: Deploy Ollama"
info "Running deploy.sh..."
chmod +x scripts/contabo/deploy.sh
${SSH} "bash -s" < scripts/contabo/deploy.sh && pass "Ollama deployed" || fail "Deploy failed"

# Phase 3: Install Models
step "Phase 3: Install AI Models"
info "Running install_models.sh..."
chmod +x scripts/contabo/install_models.sh
${SSH} "bash -s" < scripts/contabo/install_models.sh && pass "Models installed" || fail "Model install failed"

# Phase 4: Self-Healing Monitor
step "Phase 4: Self-Healing Monitor"
info "Running setup_monitor.sh..."
chmod +x scripts/contabo/setup_monitor.sh
${SSH} "bash -s" < scripts/contabo/setup_monitor.sh && pass "Monitor deployed" || fail "Monitor setup failed"

# Phase 5: Cron Jobs
step "Phase 5: Cron Jobs & Workers"
info "Running setup_cron.sh..."
chmod +x scripts/cron/setup_cron.sh
${SSH} "bash -s" < scripts/cron/setup_cron.sh && pass "Cron configured" || fail "Cron setup failed"

# Phase 6: Contabo CLI
step "Phase 6: Contabo CLI"
info "Running setup_cli.sh..."
chmod +x scripts/contabo/setup_cli.sh
${SSH} "bash -s" < scripts/contabo/setup_cli.sh && pass "CLI installed" || fail "CLI setup failed"

# Phase 7: Verification
step "Phase 7: Post-Deployment Verification"
info "Running verify_deployment.sh..."
chmod +x scripts/contabo/verify_deployment.sh
${SSH} "bash -s" < scripts/contabo/verify_deployment.sh && pass "Verification passed" || fail "Verification failed"

# Phase 8: Supabase (if secrets available)
step "Phase 8: Supabase Integration"
info "Checking Supabase CLI..."
if command -v supabase &>/dev/null; then
    info "Supabase CLI found, running setup..."
    chmod +x scripts/supabase/setup.sh
    scripts/supabase/setup.sh && pass "Supabase setup complete" || fail "Supabase setup failed"
else
    info "Supabase CLI not installed locally, skipping local setup"
    info "Run on the server: scripts/supabase/setup.sh"
fi

# Summary
echo ""
echo "================================================"
echo " DEPLOYMENT COMPLETE"
echo "================================================"
echo "Server: ${CONTAINER_IP}"
echo "Ollama: http://${CONTAINER_IP}:11434"
echo "Health: http://${CONTAINER_IP}:11434/api/tags"
echo ""
echo "Next steps:"
echo "  1. Verify: ssh root@${CONTAINER_IP} 'ollama list'"
echo "  2. Check logs: ssh root@${CONTAINER_IP} 'tail -f /var/log/ollama.log'"
echo "  3. Monitor: ssh root@${CONTAINER_IP} 'systemctl status ollama-monitor'"
echo "  4. Self-heal: python3 scripts/fixers/agent_fixer.py fix"
echo "  5. Autopilot: python3 scripts/fixers/autopilot.py continuous"
echo "================================================"
