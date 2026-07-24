# Ollama Infrastructure - Deployment Guide

## Quick Start (Fully Autonomous)

### 1. Generate SSH Key (local machine)
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_contabo -C "codex-contabo-deploy-2026-07-24" -N ""
```

### 2. Deploy SSH Key to Contabo Server
```bash
ssh-copy-id -i ~/.ssh/id_ed25519_contabo.pub -p 22 root@169.58.68.183
```
(Enter password: `MnL3Tj8La1f` when prompted)

### 3. Clone Repository
```bash
git clone https://github.com/hillstreet-ph/open-model.git
cd open-model
git checkout main
```

### 4. Run Autonomous Setup (one command)
```bash
chmod +x scripts/autonomous_setup.sh
./scripts/autonomous_setup.sh
```

OR run each phase manually:

### 4a. Server Setup
```bash
chmod +x scripts/contabo/setup_server.sh
./scripts/contabo/setup_server.sh
```

### 4b. Deploy Ollama
```bash
chmod +x scripts/contabo/deploy.sh
./scripts/contabo/deploy.sh
```

### 4c. Install Models
```bash
chmod +x scripts/contabo/install_models.sh
./scripts/contabo/install_models.sh
```

### 4d. Deploy Self-Healing Monitor
```bash
chmod +x scripts/contabo/setup_monitor.sh
./scripts/contabo/setup_monitor.sh
```

### 4e. Configure Cron Jobs
```bash
chmod +x scripts/cron/setup_cron.sh
./scripts/cron/setup_cron.sh
```

### 4f. Deploy Server Bootstrap (alternative - all-in-one on server)
```bash
# Copy and execute on the Contabo server directly
scp -i ~/.ssh/id_ed25519_contabo scripts/contabo/server_bootstrap.sh root@169.58.68.183:/tmp/
ssh -i ~/.ssh/id_ed25519_contabo root@169.58.68.183 "bash /tmp/server_bootstrap.sh"
```

### 5. Verify Deployment
```bash
chmod +x scripts/contabo/verify_deployment.sh
./scripts/contabo/verify_deployment.sh
```

### 6. Verify Remote (on Contabo server)
```bash
curl http://localhost:11434/api/tags
ollama list
systemctl is-active ollama ollama-monitor cron
python3 scripts/fixers/autopilot.py status
```

## GitHub Actions CI/CD

The following workflows run automatically on push to `main`:

- **deploy.yml** - Builds Ollama, deploys to Contabo, runs health check
- **ai-agent.yml** - Every 15 min: health checks, code fixing, Supabase sync
- **deploy-contabo.yml** - Contabo-specific deployment after code changes
- **contabo-setup.yml** - One-shot interactive server setup
- **kanban.yml** - Project board automation and model rotation

## Configuration

### GitHub Secrets Required
| Secret | Value |
|--------|-------|
| `CONTABO_SSH_PRIVATE_KEY` | SSH private key content |
| `SUPABASE_ACCESS_TOKEN` | From Supabase dashboard |
| `SUPABASE_SERVICE_KEY` | Service role key |
| `CONTABO_CLIENT_ID` | `INT-15223033` |
| `CONTABO_CLIENT_SECRET` | API client secret |

### Environment Variables (on Contabo server)
- `OLLAMA_HOST=0.0.0.0:11434`
- `OLLAMA_MODELS=/var/lib/ollama/models`
- `OLLAMA_ORIGINS=*`
- `OLLAMA_KEEP_ALIVE=24h`

## Autonomous Agents

The following agents run automatically:

| Agent | Schedule | Role |
|-------|----------|------|
| hermes-health | Every 5 min | Health monitoring |
| hermes-fix | Event-driven | Self-healing restart |
| hermes-rotate | Daily 3 AM | Model rotation |
| hermes-sync | Every 6 hours | Supabase sync |
| hermes-report | Daily | Operations report |

## Self-Improvement

```bash
# One-time diagnostics
python3 scripts/fixers/agent_fixer.py diag

# Run improvement cycle
python3 scripts/fixers/self_improvement.py cycle

# Continuous self-improvement loop
python3 scripts/fixers/self_improvement.py loop

# Autonomous DevOps (continuous)
python3 scripts/fixers/autopilot.py continuous
```

## Project Boards (Kanban)

### Infrastructure Operations (INFRA)
- Backlog -> In Progress -> Review -> Done

### Model Operations (MODELS)
- Queued -> Active -> Evaluating -> Rotating -> Deprecated

### Incident Response (INCIDENTS)
- Detected -> Investigating -> Mitigating -> Resolved

## Model Auto-Rotation

Configured in `rotation-config.json`:
- Evaluation interval: 30 days
- Staleness threshold: <100 requests/week
- Preferred models: gemma4, llama3.2, qwen2.5, mistral, codellama
- Archive before removal: enabled
