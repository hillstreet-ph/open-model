#!/bin/bash
set -euo pipefail

echo "=== Ollama Infrastructure Quick Start ==="
echo ""
echo "This will set up the entire Ollama infrastructure:"
echo "  - Contabo server (169.58.68.183)"
echo "  - SSH key generation and deployment"
echo "  - Ollama installation and deployment"
echo "  - AI model installation"
echo "  - Self-healing monitor"
echo "  - Cron jobs and background workers"
echo "  - Contabo CLI"
echo "  - Supabase integration"
echo "  - GitHub Actions CI/CD"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./scripts/deploy_all.sh
else
    echo "Aborted."
    exit 0
fi
