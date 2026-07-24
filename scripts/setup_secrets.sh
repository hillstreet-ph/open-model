#!/bin/bash
set -euo pipefail

###############################################
# GitHub Secrets Setup                     #
# Run this once to configure all         #
# required secrets for deployment       #
###############################################

REPO="hillstreet-ph/open-model"

echo "=== GitHub Secrets Setup ==="
echo "Repository: $REPO"
echo ""

echo "Setting CONTABO_SSH_PRIVATE_KEY..."
gh secret set CONTABO_SSH_PRIVATE_KEY \
  --body 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINddCkP6ZiPeC7BEBFf49H5wguTslFaAUfHjjlJZkttg codex-contabo-deploy-2026-07-24' \
  --repo "$REPO" 2>&1 && echo "  [PASS] CONTABO_SSH_PRIVATE_KEY set" || echo "  [FAIL] CONTABO_SSH_PRIVATE_KEY - check permissions"

echo ""
echo "Setting SUPABASE_ACCESS_TOKEN..."
echo "  Enter your Supabase Access Token when prompted:"
gh secret set SUPABASE_ACCESS_TOKEN --repo "$REPO" 2>&1 && echo "  [PASS] SUPABASE_ACCESS_TOKEN set" || echo "  [FAIL] SUPABASE_ACCESS_TOKEN - check permissions"

echo ""
echo "Setting SUPABASE_SERVICE_KEY..."
echo "  Enter your Supabase Service Role Key when prompted:"
gh secret set SUPABASE_SERVICE_KEY --repo "$REPO" 2>&1 && echo "  [PASS] SUPABASE_SERVICE_KEY set" || echo "  [FAIL] SUPABASE_SERVICE_KEY - check permissions"

echo ""
echo "Setting CONTABO_CLIENT_ID..."
gh secret set CONTABO_CLIENT_ID \
  --body 'INT-15223033' \
  --repo "$REPO" 2>&1 && echo "  [PASS] CONTABO_CLIENT_ID set" || echo "  [FAIL] CONTABO_CLIENT_ID - check permissions"

echo ""
echo "Setting CONTABO_CLIENT_SECRET..."
echo "  Enter your Contabo Client Secret when prompted:"
gh secret set CONTABO_CLIENT_SECRET --repo "$REPO" 2>&1 && echo "  [PASS] CONTABO_CLIENT_SECRET set" || echo "  [FAIL] CONTABO_CLIENT_SECRET - check permissions"

echo ""
echo "=== Secrets Setup Complete ==="
echo ""
echo "You may also need to set:"
echo "  - API_PASSWORD (Contabo API password)"
echo "  - SERVER_PASSWORD (Contabo server root password)"
echo ""
echo "After secrets are configured, run:"
echo "  gh workflow run deploy-contabo.yml --repo $REPO"
echo "  gh workflow run deploy.yml --repo $REPO"
echo "  gh workflow run ci-cd-pipeline.yml --repo $REPO"
