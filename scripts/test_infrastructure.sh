#!/bin/bash
set -euo pipefail

echo "=== Ollama Infrastructure Test Suite ==="
echo ""

PASS=0
FAIL=0
TOTAL=0

run_test() {
    TOTAL=$((TOTAL + 1))
    if eval "$2" > /dev/null 2>&1; then
        echo "  [PASS] $1"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $1"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- File Existence Tests ---"

run_test "deploy.yml exists" "test -f .github/workflows/deploy.yml"
run_test "ai-agent.yml exists" "test -f .github/workflows/ai-agent.yml"
run_test "deploy-contabo.yml exists" "test -f .github/workflows/deploy-contabo.yml"
run_test "contabo-setup.yml exists" "test -f .github/workflows/contabo-setup.yml"
run_test "kanban.yml exists" "test -f .github/workflows/kanban.yml"
run_test "setup_ssh.sh exists" "test -f scripts/contabo/setup_ssh.sh"
run_test "setup_server.sh exists" "test -f scripts/contabo/setup_server.sh"
run_test "deploy.sh exists" "test -f scripts/contabo/deploy.sh"
run_test "install_models.sh exists" "test -f scripts/contabo/install_models.sh"
run_test "setup_monitor.sh exists" "test -f scripts/contabo/setup_monitor.sh"
run_test "setup_cli.sh exists" "test -f scripts/contabo/setup_cli.sh"
run_test "ollama-monitor.sh exists" "test -f scripts/contabo/ollama-monitor.sh"
run_test "setup_cron.sh exists" "test -f scripts/cron/setup_cron.sh"
run_test "update_recommendations.sh exists" "test -f scripts/workers/update_recommendations.sh"
run_test "disk_cleanup.sh exists" "test -f scripts/workers/disk_cleanup.sh"
run_test "model_rotation.sh exists" "test -f scripts/workers/model_rotation.sh"
run_test "generate_dashboard.sh exists" "test -f scripts/workers/generate_dashboard.sh"
run_test "agent_fixer.py exists" "test -f scripts/fixers/agent_fixer.py"
run_test "self_improvement.py exists" "test -f scripts/fixers/self_improvement.py"
run_test "autopilot.py exists" "test -f scripts/fixers/autopilot.py"
run_test "hermes_orchestrator.py exists" "test -f agent/hermes_orchestrator.py"
run_test "setup.sh (supabase) exists" "test -f scripts/supabase/setup.sh"
run_test "schema.sql exists" "test -f scripts/supabase/schema.sql"
run_test "sync_ollama_models.ts exists" "test -f supabase/functions/sync_ollama_models.ts"
run_test "rotation-config.json exists" "test -f rotation-config.json"
run_test ".env.example exists" "test -f .env.example"
run_test "GITHUB_SECRETS.md exists" "test -f GITHUB_SECRETS.md"
run_test "DEPLOY.md exists" "test -f DEPLOY.md"
run_test "DEPLOYMENT_READY.md exists" "test -f DEPLOYMENT_READY.md"
run_test "PROJECTS.md exists" "test -f PROJECTS.md"
run_test "CODEOWNERS exists" "test -f CODEOWNERS"
run_test "AGENTS.md exists" "test -f AGENTS.md"
run_test "CONTRIBUTING_infrastructure.md exists" "test -f CONTRIBUTING_infrastructure.md"
run_test "server_bootstrap.sh exists" "test -f scripts/contabo/server_bootstrap.sh"
run_test "server_deploy.sh exists" "test -f scripts/contabo/server_deploy.sh"
run_test "autonomous_setup.sh exists" "test -f scripts/autonomous_setup.sh"
run_test "deploy_all.sh exists" "test -f scripts/deploy_all.sh"
run_test "quick_start.sh exists" "test -f scripts/quick_start.sh"
run_test "verify_deployment.sh exists" "test -f scripts/contabo/verify_deployment.sh"

echo ""
echo "--- Python Syntax Tests ---"

run_test "agent_fixer.py syntax" "python3 -m py_compile scripts/fixers/agent_fixer.py"
run_test "self_improvement.py syntax" "python3 -m py_compile scripts/fixers/self_improvement.py"
run_test "autopilot.py syntax" "python3 -m py_compile scripts/fixers/autopilot.py"
run_test "hermes_orchestrator.py syntax" "python3 -m py_compile agent/hermes_orchestrator.py"

echo ""
echo "--- Shell Script Shebang Tests ---"

for f in scripts/contabo/setup_server.sh scripts/contabo/setup_ssh.sh scripts/contabo/deploy.sh scripts/contabo/install_models.sh scripts/contabo/setup_monitor.sh scripts/contabo/setup_cli.sh scripts/contabo/ollama-monitor.sh scripts/cron/setup_cron.sh scripts/workers/update_recommendations.sh scripts/workers/disk_cleanup.sh scripts/workers/model_rotation.sh scripts/workers/generate_dashboard.sh scripts/contabo/server_bootstrap.sh scripts/contabo/server_deploy.sh scripts/autonomous_setup.sh scripts/deploy_all.sh scripts/quick_start.sh scripts/contabo/verify_deployment.sh scripts/supabase/setup.sh; do
    run_test "$f has shebang" "head -1 "$f" | grep -q '^#!'"
done

echo ""
echo "--- YAML Structure Tests ---"

for f in .github/workflows/deploy.yml .github/workflows/ai-agent.yml .github/workflows/deploy-contabo.yml .github/workflows/contabo-setup.yml .github/workflows/kanban.yml; do
    run_test "$f has 'name:'" "grep -q '^name:' "$f""
    run_test "$f has 'on:'" "grep -q '^on:' "$f""
    run_test "$f has 'jobs:'" "grep -q 'jobs:' "$f""
done

echo ""
echo "--- JSON Validation Tests ---"

run_test "rotation-config.json valid JSON" "python3 -c "import json; json.load(open('rotation-config.json'))""

echo ""
echo "--- Shell Script Error Handling Tests ---"

for f in scripts/contabo/setup_server.sh scripts/contabo/deploy.sh scripts/contabo/setup_monitor.sh scripts/contabo/setup_ssh.sh scripts/cron/setup_cron.sh scripts/autonomous_setup.sh scripts/contabo/server_bootstrap.sh scripts/contabo/server_deploy.sh; do
    run_test "$f has 'set -e'" "grep -q 'set -e' "$f""
done

echo ""
echo "=================================================="
echo " RESULTS: $PASS passed, $FAIL failed, $TOTAL total"
echo "=================================================="

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
