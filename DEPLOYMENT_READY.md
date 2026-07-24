# Deployment Readiness Checklist

## Pre-Deployment: GitHub Secrets
Configure in: Settings > Secrets and variables > Actions > New repository secret

| Secret | Value |
|--------|-------|
| `CONTABO_SSH_PRIVATE_KEY` | SSH private key (ed25519) |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token |
| `SUPABASE_SERVICE_KEY` | Supabase service_role key |
| `CONTABO_CLIENT_ID` | `INT-15223033` |
| `CONTABO_CLIENT_SECRET` | Contabo API client secret |

## Deployment Order

### Phase 1: SSH Key
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_contabo -C "codex-contabo-deploy-2026-07-24" -N ""
ssh-copy-id -i ~/.ssh/id_ed25519_contabo.pub -p 22 root@169.58.68.183
```

### Phase 2: Server Setup
```bash
./scripts/contabo/setup_server.sh
```

### Phase 3: Deploy Ollama
```bash
./scripts/contabo/deploy.sh
```

### Phase 4: Install Models
```bash
./scripts/contabo/install_models.sh
```

### Phase 5: Self-Healing Monitor
```bash
./scripts/contabo/setup_monitor.sh
```

### Phase 6: Cron Jobs
```bash
./scripts/cron/setup_cron.sh
```

### Phase 7: Contabo CLI
```bash
./scripts/contabo/setup_cli.sh
```

### Phase 8: Verification
```bash
./scripts/contabo/verify_deployment.sh
```

## Post-Deployment Checks
- `curl http://169.58.68.183:11434/api/tags` - Ollama API responding
- `ssh root@169.58.68.183 "systemctl is-active ollama"` - Service running
- `ssh root@169.58.68.183 "systemctl is-active ollama-monitor"` - Monitor active
- `ssh root@169.58.68.183 "ollama list"` - Models installed

## Troubleshooting
| Issue | Fix |
|-------|-----|
| Ollama not responding | `systemctl restart ollama` |
| Monitor not running | `systemctl restart ollama-monitor` |
| Disk full | Run `disk_cleanup.sh` manually |
| SSH connection refused | Verify key is in server's `authorized_keys` |
