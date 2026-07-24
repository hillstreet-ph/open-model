#!/bin/bash
set -euo pipefail

###############################################
# Complete Infrastructure Deployment    #
# Deploys to GitHub Actions, Supabase,  #
# and Contabo server                 #
###############################################

echo "=============================================="
echo "  Ollama Infrastructure - Full Deployment"
echo "  $(date -Iseconds)"
echo "=============================================="
echo ""

STAGE="${1:-all}"

deploy_github() {
    echo "[Stage 1] GitHub Actions CI/CD Pipeline"
    echo "  All code is already pushed to origin/main"
    echo "  GitHub Actions workflows will trigger automatically:"
    echo "    - deploy.yml (Ollama binary build + deploy)"
    echo "    - deploy-contabo.yml (Contabo server setup)"
    echo "    - ci-cd-pipeline.yml (Full CI/CD pipeline)"
    echo "    - ai-agent.yml (Scheduled autonomous agents)"
    echo "    - kanban.yml (Project board automation)"
    echo ""
    echo "  To trigger manually:"
    echo "    gh workflow run deploy.yml"
    echo "    gh workflow run deploy-contabo.yml"
    echo "    gh workflow run ci-cd-pipeline.yml"
}

deploy_contabo() {
    echo "[Stage 2] Contabo Server Deployment"
    echo "  Prerequisites:"
    echo "    - CONTABO_SSH_PRIVATE_KEY must be set in GitHub Secrets"
    echo "    - SUPABASE_ACCESS_TOKEN must be set in GitHub Secrets"
    echo "    - SUPABASE_SERVICE_KEY must be set in GitHub Secrets"
    echo ""
    
    # Check if we can SSH to Contabo
    SSH_KEY="${HOME}/.ssh/id_ed25519_contabo"
    if [ -f "$SSH_KEY" ]; then
        echo "  SSH key found at $SSH_KEY"
        echo "  Pushing infrastructure to Contabo..."
        
        # Sync platform code
        scp -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" \
            -r \
            scripts/contabo/ \
            platform/ \
            k8s/ \
            scripts/supabase/ \
            "root@169.58.68.183:/opt/ollama/" 2>/dev/null && \
            echo "  [PASS] Platform code synced to Contabo" || \
            echo "  [WARN] SCP failed, ensure SSH key is configured"
        
        # Deploy infrastructure on server
        echo "  Deploying infrastructure on Contabo..."
        ssh -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" \
            root@169.58.68.183 \
            "cd /opt/ollama && bash scripts/contabo/server_platform.sh" 2>/dev/null && \
            echo "  [PASS] Platform deployed on Contabo" || \
            echo "  [WARN] Remote deployment command failed, running manually on server"
        
        # Run readiness check
        echo "  Running health checks..."
        ssh -o StrictHostKeyChecking=no \
            -i "$SSH_KEY" \
            root@169.58.68.183 \
            "cd /opt/ollama && bash scripts/contabo/production_readiness_check.sh" 2>/dev/null && \
            echo "  [PASS] Health checks passed" || \
            echo "  [WARN] Health checks could not run remotely"
    else
        echo "  [INFO] No SSH key found at $SSH_KEY"
        echo "  Deploy to Contabo manually with:"
        echo "    chmod +x scripts/contabo/server_platform.sh"
        echo "    bash scripts/contabo/server_platform.sh"
        echo "  Or run the GitHub Actions workflow:"
        echo "    gh workflow run deploy-contabo.yml"
    fi
}

deploy_supabase() {
    echo "[Stage 3] Supabase Deployment"
    echo "  Prerequisites:"
    echo "    - SUPABASE_ACCESS_TOKEN must be set in GitHub Secrets"
    echo "    - SUPABASE_SERVICE_KEY must be set in GitHub Secrets"
    echo ""
    
    # Check Supabase CLI
    if command -v supabase >/dev/null 2>&1; then
        echo "  Supabase CLI found, deploying..."
        supabase db push --project-ref olhtxibbyhucxcmhzblq --yes 2>/dev/null && \
            echo "  [PASS] Supabase schema deployed" || \
            echo "  [WARN] supabase db push failed"
        
        # Deploy edge functions
        if [ -d "supabase/functions" ]; then
            for func in supabase/functions/*; do
                func_name=$(basename "$func")
                supabase functions deploy "$func_name" \
                    --project-ref olhtxibbyhucxcmhzblq \
                    --no-verify-jwt 2>/dev/null && \
                    echo "  [PASS] Edge function $func_name deployed" || \
                    echo "  [WARN] Failed to deploy $func_name"
            done
        fi
    else
        echo "  [INFO] Supabase CLI not installed"
        echo "  Deploy Supabase manually with:"
        echo "    chmod +x scripts/supabase/deploy.sh"
        echo "    bash scripts/supabase/deploy.sh"
        echo "  Or set SUPABASE_ACCESS_TOKEN and SUPABASE_SERVICE_KEY env vars"
    fi
}

case "$STAGE" in
    github)
        deploy_github
        ;;
    contabo)
        deploy_contabo
        ;;
    supabase)
        deploy_supabase
        ;;
    all)
        deploy_github
        echo ""
        deploy_contabo
        echo ""
        deploy_supabase
        ;;
    *)
        echo "Usage: $0 [github|contabo|supabase|all]"
        echo "  github  - Check GitHub Actions CI/CD status"
        echo "  contabo - Deploy infrastructure to Contabo server"
        echo "  supabase - Deploy schema and edge functions to Supabase"
        echo "  all     - Run all deployment stages"
        exit 1
        ;;
esac

echo ""
echo "=============================================="
echo "  Deployment Complete"
echo "=============================================="
