# GitHub Actions Secrets Setup

## Required Secrets
Add these in: Settings > Secrets and variables > Actions > New repository secret

| Secret Name | Description |
|-------------|-------------|
| `CONTABO_SSH_PRIVATE_KEY` | SSH private key for Contabo server access |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |
| `CONTABO_CLIENT_ID` | Contabo API client ID (`INT-15223033`) |
| `CONTABO_CLIENT_SECRET` | Contabo API client secret |

## How to Generate

### SSH Key
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_contabo -C "codex-contabo-deploy-2026-07-24" -N ""
```
Copy the entire private key content (including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`) to the `CONTABO_SSH_PRIVATE_KEY` secret.

### Supabase Token
1. Go to https://supabase.com/dashboard/project/olhtxibbyhucxcmhzblq/settings/api
2. Copy the `supabase_pat_...` token
3. Add to `SUPABASE_ACCESS_TOKEN` secret

### Contabo Credentials
Find in the Contabo dashboard: https://new.contabo.com/
Under API Access, copy the Client ID and Client Secret.
