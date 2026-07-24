#!/bin/bash
set -euo pipefail

CONTAINER_IP="169.58.68.183"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"
OUTPUT_DIR="/workspace/ed711665-54e1-4dea-9219-7f06098fcc32/sessions/agent_d55ca74c-f35b-496b-a750-e3en33727f96f"
OUTPUT_DIR="/workspace/ed711665-54e1-4dea-9219-7f06098fcc32/sessions/agent_d55ca74c-f35b-496b-a750-e3433727f96f"

SSH="ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP}"

mkdir -p "${OUTPUT_DIR}/dashboards"

echo "=== Generating Maintenance Dashboard ==="

cat > "${OUTPUT_DIR}/dashboards/maintenance.md" << EOF
# Ollama Infrastructure Maintenance Dashboard

**Generated:** \$(date -Iseconds)
**Server:** ${CONTAINER_IP}

## System Status

| Component | Status |
|-----------|--------|
| Ollama Service | \$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "systemctl is-active ollama" 2>/dev/null || echo "UNKNOWN") |
| Monitor Service | \$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "systemctl is-active ollama-monitor" 2>/dev/null || echo "UNKNOWN") |
| Fail2Ban | \$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "systemctl is-active fail2ban" 2>/dev/null || echo "UNKNOWN") |
| Cron | \$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "systemctl is-active cron" 2>/dev/null || echo "UNKNOWN") |

## Ollama Models

\$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "ollama list" 2>/dev/null || echo "Unable to retrieve models")

## Resource Usage

\$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "echo '=== Memory ===' && free -h && echo '=== Disk ===' && df -h /var/lib/ollama && echo '=== CPU Load ===' && uptime" 2>/dev/null || echo "Unable to retrieve resources")

## Recent Events

\$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "tail -20 /var/log/ollama-monitor.log" 2>/dev/null || echo "No monitor log found")

## Uptime

\$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "uptime" 2>/dev/null || echo "Unable to retrieve uptime")

## Self-Heal Status

Last 10 self-heal actions:
\$(ssh -i ${SSH_KEY_PATH} -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${CONTAINER_IP} "grep -i 'restart\|heal\|remediat' /var/log/ollama-monitor.log 2>/dev/null | tail -10 || echo 'No self-heal events found')"
EOF

echo "Dashboard generated at ${OUTPUT_DIR}/dashboards/maintenance.md"
