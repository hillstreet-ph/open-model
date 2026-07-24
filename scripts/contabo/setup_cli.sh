#!/bin/bash
set -euo pipefail

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"

SSH="ssh -i ${SSH_KEY_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP}"

echo "=== Installing Contabo CLI on server ==="

${SSH} "curl -fsSL https://contabo.com/contabo-cli/install.sh | bash || echo 'CLI install skipped, using API directly'"

${SSH} "mkdir -p /opt/ollama/scripts/contabo"

${SSH} "cat > /opt/ollama/scripts/contabo/api_client.sh << 'SCRIPT'
#!/bin/bash
# Contabo API client for server management
export CONTABO_CLIENT_ID="INT-15223033"
export CONTABO_CLIENT_SECRET="wK0gXbqY32hFhDceHUUWjuUGbmekVQ0b"
export CONTABO_API_PASSWORD="CfG3W6eju8S5"
export CONTABO_ENDPOINT="https://my.contabo.com/api/details"

contabo_get() {
    curl -s -X GET "${CONTABO_ENDPOINT}/$1" \
        -H "X-Api-Username: ${CONTABO_CLIENT_ID}" \
        -H "X-Api-Password: ${CONTABO_API_PASSWORD}" \
        -H "Content-Type: application/json"
}

contabo_server_status() {
    contabo_get "/servers" | jq '.data[] | select(.ipAddress == "169.58.68.183")'
}
SCRIPT"

${SSH} "chmod +x /opt/ollama/scripts/contabo/api_client.sh"

echo "=== Contabo CLI setup complete ==="
