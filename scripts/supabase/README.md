# Supabase Integration for Ollama

## Setup

1. Run `supabase login` with your Supabase credentials
2. Run `supabase link --project-ref olhtxibbyhucxcmhzblq`
3. Run `supabase db push` to deploy the schema
4. Run `supabase functions deploy sync_ollama_models` to deploy the edge function

## Environment Variables (GitHub Secrets)

- `SUPABASE_ACCESS_TOKEN` - Supabase personal access token
- `SUPABASE_SERVICE_KEY` - Service role key for API access
- `CONTABO_SSH_PRIVATE_KEY` - SSH private key for Contabo server

## Edge Functions

- `sync_ollama_models` - Syncs model inventory from Contabo Ollama instance to Supabase
