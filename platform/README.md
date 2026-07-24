# Open Platform - Multi-Project Ollama Integration

## Three Project Forks

### 1. Open Connect (Open Web UI Fork) - Port 3000
Chat and conversation interface with Open Web UI.

### 2. Open Command (SwarmClaw Fork) - Port 5000/8000
Agent swarm orchestration with command execution.
Agent types: coder, debugger, planner, reviewer, researcher.

### 3. Open Worker (Hermes Agent Fork) - Port 6000/9000
Automated worker agents for task execution.
Worker types: executor, reviewer, formatter, validator, optimizer.

## Platform Orchestrator
The orchestrator manages all three platforms with health monitoring, task routing, and scaling.

## API Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Platform overview |
| `/platforms` | GET | All platform statuses |
| `/task` | POST | Route task to a platform |
| `/tasks/batch` | POST | Route batch of tasks |
| `/health` | GET | Health check |

## Quick Start
```bash
cd platform
docker-compose up -d
```
