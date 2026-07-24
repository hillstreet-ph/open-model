#!/bin/bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
PASS=0
FAIL=0
TOTAL=0

check() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"
    
    TOTAL=$((TOTAL + 1))
    
    response=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [ "$response" = "$expected" ]; then
        echo "PASS: $name (HTTP $response)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected HTTP $expected, got $response)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Ollama Infrastructure Readiness Check ==="
echo ""

check "Open Connect Health" "http://localhost:3000/api/health" "200"
check "Open Command Health" "http://localhost:5000/api/health" "200"
check "Open Worker Health" "http://localhost:6000/api/health" "200"
check "Orchestrator Health" "$BASE_URL/api/health" "200"
check "Orchestrator Platforms" "$BASE_URL/api/platforms" "200"
check "Orchestrator Bridge Health" "$BASE_URL/api/bridge/health" "200"
check "Orchestrator Task Status" "$BASE_URL/api/tasks/status" "200"
check "Orchestrator Swarm Status" "$BASE_URL/api/swarm/status" "200"
check "Orchestrator Dashboard" "$BASE_URL/api/dashboard/status" "200"
check "Bridge Health" "http://localhost:8443/api/health" "200"
check "Ollama API" "http://localhost:11434/api/tags" "200"
check "Dashboard API" "http://localhost:80/api/dashboard" "200"
check "Dashboard Status" "http://localhost:80/api/dashboard/status" "200"
check " Dashboard Metrics" "http://localhost:80/api/dashboard/metrics" "200"
check "Dashboard Health" "http://localhost:80/api/dashboard/health" "200"

echo ""
echo "=== Results ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "Readiness check FAILED"
    exit 1
else
    echo "All checks PASSED - Infrastructure is production ready"
    exit 0
fi
