#!/bin/bash
set -euo pipefail

SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"
SSH_PASSPHRASE=""

echo "=== Setting up SSH key for Contabo ==="

if [ -f "${SSH_KEY_PATH}" ]; then
    echo "Key already exists at ${SSH_KEY_PATH}"
else
    echo "Generating new ed25519 key..."
    ssh-keygen -t ed25519 \
        -f "${SSH_KEY_PATH}" \
        -C "codex-contabo-deploy-2026-07-24" \
        -N "${SSH_PASSPHRASE}"
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
fi

echo "Public key:"
cat "${SSH_KEY_PATH}.pub"

echo ""
echo "=== Add this public key to the Contabo server's ~/.ssh/authorized_keys ==="
echo "=== Or add it via the Contabo dashboard/SSH key management ==="
echo ""

echo "--- Testing SSH connection ---"
ssh -i "${SSH_KEY_PATH}" \
    -p 22 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    root@169.58.68.183 "echo 'SSH connection successful'" || {
    echo "WARNING: SSH connection test failed. Please ensure:"
    echo "  1. The SSH key is added to the Contabo server"
    echo "  2. Port 22 is open in the firewall"
    echo "  3. The server IP is correct"
}