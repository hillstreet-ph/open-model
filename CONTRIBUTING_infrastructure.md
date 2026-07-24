

## Infrastructure Contribution Guide

### Adding New Infrastructure Components

1. Create script in the appropriate directory under `scripts/`
2. Make it executable (`chmod +x`)
3. Add it to the relevant cron schedule if applicable
4. Create a GitHub Actions workflow if it needs CI/CD integration
5. Document it in `AGENTS.md`
6. Add it to `rotation-config.json` if it's a model rotation component
7. Create a project board card for tracking

### Self-Improvement Process

The infrastructure includes automated self-improvement via:
- **hermes-fix**: Self-healing agent that detects and fixes issues
- **hermes-health**: Health monitor that checks Ollama service status
- **hermes-rotate**: Model rotator that manages the AI model lifecycle
- **hermes-sync**: Data sync agent that syncs model inventory to Supabase
- **hermes-report**: Reporting agent that generates operational reports
- **self_improvement.py**: Analyzes metrics and applies fixes automatically
- **autopilot.py**: Continuous autonomous DevOps loop that monitors all systems

All agents log their actions to Supabase and GitHub issues.
