-- Supabase schema for Ollama infrastructure monitoring and management

-- Enable required extensions
create extension if not exists "uuid-ossp";

-- Table for Ollama model inventory synced from Contabo
create table ollama_models (
    id uuid default gen_random_uuid() primary key,
    model_name text not null,
    model_tag text,
    size_bytes bigint,
    modified_at timestamp with time zone default now(),
    created_at timestamp with time zone default now(),
    unique (model_name, model_tag)
);

-- Index for fast model lookups
create index idx_ollama_models_name on ollama_models (model_name);

-- Realtime publication for live model updates
alter publication supabase_realtime add table ollama_models;

-- Table for health check events from the self-healing monitor
create table ollama_events (
    id uuid default gen_random_uuid() primary key,
    event_type text not null,
    container_ip text not null,
    timestamp timestamp with time zone default now(),
    details jsonb default '{}',
    resolved boolean default false
);

create index idx_ollama_events_type on ollama_events (event_type);
create index idx_ollama_events_time on ollama_events (timestamp desc);

-- Table for diagnostics snapshots
create table ollama_diagnostics (
    id uuid default gen_random_uuid() primary key,
    server_ip text not null,
    timestamp timestamp with time zone default now(),
    ollama_health boolean,
    model_count int,
    disk_info text,
    memory_info text,
    service_status text,
    details jsonb default '{}'
);

-- Table for scheduled job runs (cron tracking)
create table cron_runs (
    id uuid default gen_random_uuid() primary key,
    job_name text not null,
    status text not null,
    output text,
    started_at timestamp with time zone default now(),
    completed_at timestamp with time zone
);

create index idx_cron_runs_job on cron_runs (job_name);
create index idx_cron_runs_status on cron_runs (status);

-- RLS policies: service role can read/write all, anon can only read health
alter table ollama_models enable row level security;
alter table ollama_events enable row level security;
alter table ollama_diagnostics enable row level security;
alter table cron_runs enable row level security;

create policy "Service role full access" on ollama_models
    for all using (auth.role() = 'service_role');

create policy "Service role full access on events" on ollama_events
    for all using (auth.role() = 'service_role');

create policy "Service role full access on diagnostics" on ollama_diagnostics
    for all using (auth.role() = 'service_role');

create policy "Service role full access on cron_runs" on cron_runs
    for all using (auth.role() = 'service_role');

create policy "Anon read-only for health" on ollama_models
    for select using (true);

-- Edge function: model sync trigger (called by cron/workers)
create or replace function sync_ollama_models()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    model_record record;
begin
    -- This function is called via HTTP from the worker
    -- Worker sends the model list as JSON payload
    -- The actual sync logic is in the Supabase edge function
    null;
end;
$$;

-- Edge function: health check webhook
create or replace function health_check_webhook()
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
    return json_build_object(
        'status', 'ok',
        'timestamp', now()::text,
        'service', 'ollama-infra'
    );
end;
$$;
