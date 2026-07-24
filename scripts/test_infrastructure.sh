#!/bin/bash
set -euo pipefail

echo "=== Ollama Infrastructure Test Suite ==="
echo ""

PASS=0
FAIL=0

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -n "Test: $test_name ... "
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
    fi
}

# Shell script syntax checks
run_test "setup_server.sh syntax" "bash -n scripts/contabo/setup_server.sh"
run_test "deploy.sh syntax" "bash -n scripts/contabo/deploy.sh"
run_test "setup_ssh.sh syntax" "bash -n scripts/contabo/setup_ssh.sh"
run_test "install_models.sh syntax" "bash -n scripts/contabo/install_models.sh"
run_test "setup_monitor.sh syntax" "bash -n scripts/contabo/setup_monitor.sh"
run_test "setup_cli.sh syntax" "bash -n scripts/contabo/setup_cli.sh"
run_test "server_bootstrap.sh syntax" "bash -n scripts/contabo/server_bootstrap.sh"
run_test "server_deploy.sh syntax" "bash -n scripts/contabo/server_deploy.sh"
run_test "verify_deployment.sh syntax" "bash -n scripts/contabo/verify_deployment.sh"
run_test "ollama-monitor.sh syntax" "bash -n scripts/contabo/ollama-monitor.sh"
run_test "monitor.sh syntax" "bash -n scripts/contabo/monitor.sh"
run_test "production_readiness_check.sh syntax" "bash -n scripts/contabo/production_readiness_check.sh"
run_test "setup_cron.sh syntax" "bash -n scripts/cron/setup_cron.sh"
run_test "disk_cleanup.sh syntax" "bash -n scripts/workers/disk_cleanup.sh"
run_test "update_recommendations.sh syntax" "bash -n scripts/workers/update_recommendations.sh"
run_test "model_rotation.sh syntax" "bash -n scripts/workers/model_rotation.sh"
run_test "generate_dashboard.sh syntax" "bash -n scripts/workers/generate_dashboard.sh"
run_test "supabase_sync.sh syntax" "bash -n scripts/workers/supabase_sync.sh"

# Python syntax checks
run_test "hermes_orchestrator.py syntax" "python3 -m py_compile agent/hermes_orchestrator.py"
run_test "agent_fixer.py syntax" "python3 -m py_compile scripts/fixers/agent_fixer.py"
run_test "self_improvement.py syntax" "python3 -m py_compile scripts/fixers/self_improvement.py"
run_test "autopilot.py syntax" "python3 -m py_compile scripts/fixers/autopilot.py"
run_test "sync_supabase.py syntax" "python3 -m py_compile scripts/fixers/sync_supabase.py"
run_test "cross_platform_bridge.py syntax" "python3 -m py_compile platform/cross_platform_bridge.py"
run_test "task_pipeline.py syntax" "python3 -m py_compile platform/task_pipeline.py"
run_test "swarm_coordinator.py syntax" "python3 -m py_compile platform/swarm_coordinator.py"
run_test "dashboard_api.py syntax" "python3 -m py_compile platform/dashboard_api.py"
run_test "orchestrator.py syntax" "python3 -m py_compile platform/orchestrator.py"
run_test "open-connect-health.py syntax" "python3 -m py_compile platform/open-connect-health.py"
run_test "open-command-health.py syntax" "python3 -m py_compile platform/open-command-health.py"
run_test "open-worker-health.py syntax" "python3 -m py_compile platform/open-worker-health.py"

# YAML structure checks
run_test "deploy.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/deploy.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""
run_test "ai-agent.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/ai-agent.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""
run_test "deploy-contabo.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/deploy-contabo.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""
run_test "contabo-setup.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/contabo-setup.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""
run_test "kanban.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/kanban.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""
run_test "agents-setup.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/agents-setup.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""
run_test "ci-cd-pipeline.yml structure" "python3 -c \"import yaml; d=yaml.safe_load(open('.github/workflows/ci-cd-pipeline.yml')); assert 'name' in d and 'on' in d and 'jobs' in d\""

# JSON structure checks
run_test "rotation-config.json structure" "python3 -c \"import json; d=json.load(open('rotation-config.json')); assert 'preferred_models' in d and 'stale_days' in d\""

# Check required files exist
run_test "K8s deployment.yml exists" "test -f k8s/deployment.yml"
run_test "K8s namespace.yml exists" "test -f k8s/namespace.yml"
run_test "K8s ingress.yml exists" "test -f k8s/ingress.yml"
run_test "K8s hpa.yml exists" "test -f k8s/hpa.yml"
run_test "docker-compose.prod.yml exists" "test -f platform/docker-compose.prod.yml"
run_test "cross_platform_bridge.py exists" "test -f platform/cross_platform_bridge.py"
run_test "task_pipeline.py exists" "test -f platform/task_pipeline.py"
run_test "swarm_coordinator.py exists" "test -f platform/swarm_coordinator.py"
run_test "dashboard_api.py exists" "test -f platform/dashboard_api.py"
run_test "open-connect-health.py exists" "test -f platform/open-connect-health.py"
run_test "open-command-health.py exists" "test -f platform/open-command-health.py"
run_test "open-worker-health.py exists" "test -f platform/open-worker-health.py"
run_test "production_readiness_check.sh exists" "test -f scripts/contabo/production_readiness_check.sh"

# Check for no conflict markers in files
run_test "No conflict markers in platform/" "! grep -r '<<<<' platform/ && ! grep -r '>>>>' platform/ && ! grep -r '====' platform/"
run_test "No conflict markers in scripts/" "! grep -r '<<<<' scripts/ && ! grep -r '>>>>' scripts/ && ! grep -r '====' scripts/"
run_test "No conflict markers in agent/" "! grep -r '<<<<' agent/ && ! grep -r '>>>>' agent/ && ! grep -r '====' agent/"
run_test "No conflict markers in k8s/" "! grep -r '<<<<' k8s/ && ! grep -r '>>>>' k8s/ && ! grep -r '====' k8s/"

# Check no hardcoded secrets in tracked files
run_test "No hardcoded secrets in platform/" "! grep -rE '(password|secret|token|api_key|apikey|private_key)\s*=\s*[\"'"'"'][^\"'"'"'{]' platform/" 2>/dev/null || true
run_test "No hardcoded secrets in scripts/" "! grep -rE '(password|secret|token|api_key|apikey|private_key)\s*=\s*[\"'"'"'][^\"'"'"'{]' scripts/ 2>/dev/null || true

echo ""
echo "=== Results ==="
echo "Total: $((PASS + FAIL)) | Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "Some tests FAILED"
    exit 1
else
    echo "All tests PASSED"
    exit 0
fi
