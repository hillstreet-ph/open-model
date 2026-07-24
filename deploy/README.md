# Contabo production deployment

This layer deploys Ollama without changing upstream application code.

## Required GitHub production secrets

- `CONTABO_HOST`
- `CONTABO_USER` (recommended: `openmodel`)
- `CONTABO_SSH_PORT` (normally `22`)
- `CONTABO_SSH_PRIVATE_KEY` (dedicated deployment key only)

Protect the `production` environment with required approval. Do not store Contabo,
Supabase, root, or Open-Secret administrative credentials in repository files.

## One-time server bootstrap

From Contabo Console/VNC, after creating a dedicated Actions keypair:

```bash
export SSH_PUBLIC_KEY='ssh-ed25519 AAAA... github-actions-open-model'
bash deploy/scripts/bootstrap-ubuntu.sh
```

Populate `/opt/open-model/shared/.env` through the server console or a restricted
Open-Secret machine identity. Set `MODEL_DOMAIN` to a DNS name already pointing to
the VPS. The deployment workflow can then run after its four secrets are configured.

## Operations

```bash
cd /opt/open-model/current/deploy
docker compose ps
docker compose logs --tail=200
docker compose exec ollama ollama list
curl -fsS https://MODEL_DOMAIN/api/tags
```

The API is deliberately exposed only through Caddy. Add authentication at the
Open-Connect/gateway layer before allowing untrusted clients.
