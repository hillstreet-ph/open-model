# AGENTS.md

## Building

For a full build from the repository root:

```sh
cmake -B build .
cmake --build build --parallel 8
./ollama serve
```

For quick Go-only iteration against an existing native payload:

```sh
go build .
go run . serve
```

See `docs/development.md` for prerequisites, platform notes, GPU backends, and
the full development workflow.

## Infrastructure

### Contabo Server (169.58.68.183)

SSH-based deployment to a Contabo cloud server running Ollama models.

**Setup scripts:**
- `scripts/contabo/setup_server.sh` - Installs prerequisites, configures UFW, fail2ban, logrotate, creates ollama user
- `scripts/contabo/setup_ssh.sh` - Generates and configures ed25519 SSH key
- `scripts/contabo/deploy.sh` - Builds and deploys Ollama binary with systemd service
- `scripts/contabo/install_models.sh` - Pulls standard LLM models onto the server
- `scripts/contabo/setup_monitor.sh` - Configures self-healing systemd monitor service
- `scripts/contabo/setup_cli.sh` - Installs Contabo CLI and API client

**Cron/Workers:**
- `scripts/cron/setup_cron.sh` - Sets up scheduled jobs for health checks, disk cleanup, Supabase sync
- `scripts/workers/update_recommendations.sh` - Fetches model recommendations from Supabase

**Self-healing monitor** (`scripts/contabo/setup_monitor.sh`) runs as a systemd service
that checks Ollama health every 60 seconds, restarts on failure, and handles disk/memory cleanup.

### Supabase Integration

Project ref: `olhtxibbyhucxcmhzblq`
Storage endpoint: `https://olhtxibbyhucxcmhzblq.storage.supabase.co/storage/v1/s3`
REST API: `https://olhtxibbyhucxcmhzblq.supabase.co/rest/v1/`

**Setup:**
- `scripts/supabase/setup.sh` - Installs Supabase CLI and initializes project config
- `scripts/supabase/schema.sql` - Database schema for model tracking, events, diagnostics, cron runs
- `supabase/functions/sync_ollama_models` - Edge function to sync model inventory from Contabo to Supabase

### GitHub Actions Workflows

- `.github/workflows/deploy.yml` - Full CI/CD pipeline: build, deploy to Contabo, self-heal health check, sync models
- `.github/workflows/deploy-contabo.yml` - Contabo-specific deployment and setup workflow
- `.github/workflows/contabo-setup.yml` - One-shot interactive server setup via GitHub Actions
- `.github/workflows/ai-agent.yml` - Scheduled AI agent: health checks (every 15 min), code fixer (format/vet), Supabase sync, scheduled reports


## Autonomous Operations

### Hermes AI Agent Team
The Hermes agent team provides autonomous orchestration of all infrastructure operations:

| Agent | Role | Interval | Priority |
|-------|------|----------|----------|
| hermes-health | Health monitoring | 5 min | 1 |
| hermes-fix | Self-healing | Event-driven | 0 |
| hermes-rotate | Model rotation | 24h | 2 |
| hermes-sync | Data sync to Supabase | 6h | 3 |
| hermes-report | Operational reporting | Daily | 4 |

Run the agent team:
```sh
# Run all agents in continuous loop (on the Contabo server)
python3 agent/hermes_orchestrator.py

# Run a single agent
python3 agent/hermes_orchestrator.py hermes-fix
```

### Self-Improvement System
Automatically identifies issues and applies fixes:
```sh
# Run one improvement cycle
python3 scripts/fixers/self_improvement.py cycle

# Continuous self-improvement loop
python3 scripts/fixers/self_improvement.py loop

# Just collect metrics
python3 scripts/fixers/self_improvement.py metrics
```

### Autopilot (Autonomous DevOps)
Continuous autonomous monitoring and remediation:
```sh
# Run one autopilot cycle
python3 scripts/fixers/autopilot.py cycle

# Continuous autonomous mode
python3 scripts/fixers/autopilot.py continuous

# Check current status
python3 scripts/fixers/autopilot.py status
```

### AI Model Auto-Rotation
Models are automatically rotated based on the configuration in `rotation-config.json`:
- Preferred models are prioritized
- Stale models are flagged after 30 days
- Models with low usage (< 100 requests/week) are candidates for deprecation
- Rotation runs daily at 3 AM via cron

## Project Boards (Kanban)

### Infrastructure Operations (INFRA)
- Tracks all server, deployment, and infrastructure tasks
- Columns: Backlog -> In Progress -> Review -> Done

### Model Operations (MODELS)
- Tracks AI model lifecycle: deployment, evaluation, rotation, deprecation
- Columns: Queued -> Active -> Evaluating -> Rotating -> Deprecated

### Incident Response (INCIDENTS)
- Tracks alerts, self-healing events, and remediation
- Columns: Detected -> Investigating -> Mitigating -> Resolved

Automation rules in `.github/workflows/kanban.yml` manage board updates and incident creation.

## Enterprise DevOps

### Key Features
- **Self-Healing**: Automatic service restart on failure (3 retries before escalation)
- **Disk Management**: Automatic cleanup when usage exceeds 85%
- **Memory Management**: Automatic restart when usage exceeds 95%
- **Model Lifecycle**: Automatic rotation based on usage and staleness
- **Data Sync**: Continuous sync between Contabo server and Supabase
- **Incident Response**: Automated issue creation on failure detection
- **Operational Reporting**: Daily reports on system health and model status

### Secrets Required (GitHub Secrets)
| Secret | Description |
|--------|-------------|
| `CONTABO_SSH_PRIVATE_KEY` | SSH private key for Contabo server |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |
| `CONTABO_CLIENT_ID` | Contabo API client ID |
| `CONTABO_CLIENT_SECRET` | Contabo API client secret |

### Quick Start (from scratch)
1. Run `scripts/contabo/setup_ssh.sh` to generate SSH keys
2. Deploy SSH key to Contabo server
3. Run `scripts/contabo/setup_server.sh` to configure the server
4. Run `scripts/contabo/deploy.sh` to deploy Ollama
5. Run `scripts/contabo/setup_monitor.sh` to enable self-healing
6. Run `scripts/cron/setup_cron.sh` to schedule automated tasks
7. Run `scripts/contabo/install_models.sh` to pull AI models
8. Run `scripts/supabase/setup.sh` to configure Supabase integration

## Multi-Project Platform

The Ollama infrastructure serves as a platform for multiple projects:

### Open Connect (Open Web UI Fork)
- **Port**: 3000 (Chat UI) / 8000 (API Bridge)
- **Description**: Open Web UI integration for conversational AI
- **Docker**: `platform/open-connect/docker-compose.yml`
- **API Bridge**: `platform/open-connect/api_bridge.py`
- **Worker**: `platform/open-connect/worker.py`

### Open Command (SwarmClaw Fork)
- **Port**: 5000 (API) / 8000 (Docker)
- **Description**: Agent swarm orchestration for command execution
- **Agent Types**: coder, debugger, planner, reviewer, researcher
- **Docker**: `platform/open-command/docker-compose.yml`
- **API Server**: `platform/open-command/api_server.py`
- **Command Center**: `platform/open-command/command_center.py`

### Open Worker (Hermes Agent Fork)
- **Port**: 6000 (API) / 9000 (Docker)
- **Description**: Automated worker agents for task execution
- **Worker Types**: executor, reviewer, formatter, validator, optimizer
- **Docker**: `platform/open-worker/docker-compose.yml`
- **API Server**: `platform/open-worker/worker_api.py`
- **Worker Manager**: `platform/open-worker/worker_manager.py`

### Platform Orchestrator
- **Port**: 8080
- **Description**: Central orchestration managing all three projects
- **Health monitoring**, task routing, platform scaling
- **Docker**: `platform/docker-compose.yml`
- **API**: `platform/api_server.py`

### Deploy All Platforms
```bash
chmod +x scripts/contabo/server_platform.sh
./scripts/contabo/server_platform.sh
```

### Platform API
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Platform overview |
| `/platforms` | GET | All platform statuses |
| `/task` | POST | Route task to a platform |
| `/tasks/batch` | POST | Route batch tasks |
| `/platform/{name}/status` | GET | Single platform status |
| `/health` | GET | Health check |
