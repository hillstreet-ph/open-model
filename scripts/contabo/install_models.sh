#!/bin/bash
set -euo pipefail

CONTAINER_IP="169.58.68.183"
SSH_USER="root"
SSH_PORT=22
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_contabo"
MODELS_DIR="/var/lib/ollama/models"

SSH="ssh -i ${SSH_KEY_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${CONTAINER_IP}"

echo "=== Installing AI Models on Contabo Server ==="

echo "--- Ensuring models directory exists ---"
${SSH} "mkdir -p ${MODELS_DIR} && chown -R ollama:ollama ${MODELS_DIR}"

echo "--- Pulling standard models ---"
MODELS=(
    "llama3.2:3b"
    "llama3.2:1b"
    "gemma4:latest"
    "qwen2.5:7b"
    "qwen2.5:1.5b"
    "mistral:7b"
    "codellama:7b"
)

for MODEL in "${MODELS[@]}"; do
    echo "Pulling ${MODEL}..."
    ${SSH} "export PATH=\"/usr/local/go/bin:\$PATH\" && \
        /opt/ollama/ollama pull ${MODEL}" || \
        echo "WARNING: Failed to pull ${MODELS}, continuing..."
done

echo "--- Verifying installed models ---"
${SSH} "export PATH=\"/usr/local/go/bin:\$PATH\" && \
    /opt/ollama/ollama list"

echo "=== Model installation complete ==="