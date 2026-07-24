#!/bin/bash
set -euo pipefail

echo "=== Open Platform - Multi-Project Deployment ==="
echo "Server: 169.58.68.183"
echo "Time: $(date -Iseconds)"
echo ""

# Deploy Ollama hub (central shared instance)
echo "[1/5] Starting Ollama hub..."
docker pull ollama/ollama:latest
docker run -d \
  --name ollama-platform-hub \
  --restart unless-stopped \
  -p 11434:11434 \
  -v ollama-models:/root/.ollama/models \
  -v ollama-cache:/root/.ollama/cache \
  --gpus all \
  -e OLLAMA_HOST=0.0.0.0 \
  -e OLLAMA_KEEP_ALIVE=24h \
  ollama/ollama:latest
echo "  Ollama hub started"

# Deploy Open Connect
echo "[2/5] Deploying Open Connect..."
docker pull ghcr.io/open-webui/open-webui:main
docker run -d \
  --name open-connect-platform \
  --restart unless-stopped \
  -p 3000:8080 \
  --network open-platform \
  -e OLLAMA_BASE_URL=http://ollama-platform-hub:11434 \
  -e WEBUI_SECRET_KEY=open-platform-key \
  -v open-connect-data:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
echo "  Open Connect deployed on port 3000"

# Deploy Open Command
echo "[3/5] Deploying Open Command..."
docker build -t open-command-platform platform/open-command/
docker run -d \
  --name open-command-platform \
  --restart unless-stopped \
  -p 8000:8000 \
  --network open-platform \
  -e OLLAMA_URL=http://ollama-platform-hub:11434 \
  -e SWARM_MODE=true \
  -v open-command-data:/app/data \
  open-command-platform
echo "  Open Command deployed on port 8000"

# Deploy Open Worker
echo "[4/5] Deploying Open Worker..."
docker build -t open-worker-platform platform/open-worker/
docker run -d \
  --name open-worker-platform \
  --restart unless-stopped \
  -p 9000:9000 \
  --network open-platform \
  -e OLLAMA_URL=http://ollama-platform-hub:11434 \
  -e WORKER_MODE=true \
  -v open-worker-data:/app/data \
  open-worker-platform
echo "  Open Worker deployed on port 9000"

# Deploy Platform Orchestrator
echo "[5/5] Deploying Platform Orchestrator..."
docker build -t open-platform-orchestrator platform/
docker run -d \
  --name open-platform-orchestrator \
  --restart unless-stopped \
  -p 8080:8080 \
  --network open-platform \
  -e OPEN_CONNECT_URL=http://open-connect-platform:3000 \
  -e OPEN_COMMAND_URL=http://open-command-platform:8000 \
  -e OPEN_WORKER_URL=http://open-worker-platform:9000 \
  -e OLLAMA_URL=http://ollama-platform-hub:11434 \
  open-platform-orchestrator
echo "  Platform Orchestrator deployed on port 8080"

echo ""
echo "=== Platform Deployment Complete ==="
echo "Open Connect (Web UI):     http://169.58.68.183:3000"
echo "Open Command (Swarm):     http://169.58.68.183:8000"
echo "Open Worker (Hermes):     http://169.58.68.183:9000"
echo "Platform Orchestrator:     http://169.58.68.183:8080"
echo "Ollama API:                http://169.58.68.183:11434"
echo ""
echo "Verify all services:"
echo "  curl http://169.58.68.183:8080/health"
echo "  curl http://169.58.68.183:3000/api/health"
echo "  curl http://169.58.68.183:8000/api/health"
echo "  curl http://169.58.68.183:9000/api/health"
