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
