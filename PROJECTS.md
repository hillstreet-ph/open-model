# Project Board - Ollama Infrastructure

## Kanban Boards

### 1. Infrastructure Operations (INFRA)
Tracks all server, deployment, and infrastructure tasks.

| Column | Description |
|--------|-------------|
| Backlog | New tasks not yet prioritized |
| In Progress | Currently being worked on |
| Review | Under review/PR |
| Done | Completed and deployed |

### 2. Model Operations (MODELS)
Tracks AI model lifecycle including rotation, updates, and validation.

| Column | Description |
|--------|-------------|
| Queued | Models pending deployment |
| Active | Currently serving models |
| Evaluating | Under performance evaluation |
| Rotating | Being phased out |
| Deprecated | No longer in use |

### 3. Incident Response (INCIDENTS)
Tracks alerts, self-healing events, and remediation.

| Column | Description |
|--------|-------------|
| Detected | Health check failure detected |
| Investigating | Root cause analysis |
| Mitigating | Self-heal or manual fix in progress |
| Resolved | Issue resolved and verified |

## Automation Rules

### Auto-Rotation (Model Lifecycle)
- Models older than 30 days get evaluated for rotation
- Models with < 100 requests/week are flagged for deprecation
- New model versions are pulled and A/B tested
- Deprecated models are archived before removal

### Auto-Scaling
- If Ollama CPU usage > 80% for 5 minutes: trigger scale check
- If memory usage > 90%: restart Ollama service
- If disk usage > 85%: trigger cleanup workflow

### Self-Healing Priority
1. Health check fails 3 consecutive times
2. Restart Ollama service
3. If restart fails: alert via Supabase + GitHub issue
4. If issue persists: escalate to manual intervention

## Labels
- `infra` - Infrastructure changes
- `models` - Model-related tasks
- `auto` - Automated actions
- `critical` - Requires immediate attention
- `self-heal` - Self-healing agent actions
- `rotation` - Model rotation events
- `evaluation` - Model evaluation
- `deprecation` - Model deprecation
- `incident` - Incident response
- `enhancement` - Feature improvements
