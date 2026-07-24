#!/usr/bin/env python3
"""Hermes AI Agent Team - Autonomous orchestration for Ollama infrastructure."""

import json
import logging
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
)

SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9saHR4aWJieWh1Y3hjbWh6YmxxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NDg1Mzc3MCwiZXhwIjoyMTAwNDI5NzcwfQ.rz3vITWn504AhSdS52mbGvuOTxBpnAq0dUz7YrgcTsw"
CONTAINER_IP = "169.58.68.183"
OLLAMA_URL = f"http://{CONTAINER_IP}:11434"

logger = logging.getLogger("hermes")

AGENTS = {
    "hermes-health": {
        "role": "health_monitor",
        "interval": 300,
        "priority": 1,
        "enabled": True,
    },
    "hermes-rotate": {
        "role": "model_rotator",
        "interval": 86400,
        "priority": 2,
        "enabled": True,
    },
    "hermes-fix": {
        "role": "self_healer",
        "triggers": ["health_check_failed", "disk_full", "memory_pressure", "service_down"],
        "priority": 0,
        "enabled": True,
    },
    "hermes-sync": {
        "role": "data_sync",
        "interval": 21600,
        "priority": 3,
        "enabled": True,
    },
    "hermes-report": {
        "role": "reporting",
        "schedule": "daily",
        "priority": 4,
        "enabled": True,
    },
}


def ssh(cmd):
    key = str(Path.home() / ".ssh/id_ed25519_contabo")
    result = subprocess.run(
        ["ssh", "-i", key, "-p", "22", "-o", "StrictHostKeyChecking=no",
         "-o", "UserKnownHostsFile=/dev/null", f"root@{CONTAINER_IP}", cmd],
        capture_output=True, text=True, timeout=30,
    )
    return result.stdout.strip(), result.returncode


def api(path, method="GET", payload=None):
    headers = {
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "apikey": SUPABASE_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    url = f"{SUPABASE_URL}/rest/v1{path}"
    resp = requests.request(method, url, headers=headers, json=payload, timeout=15)
    resp.raise_for_status()
    return resp.json() if resp.text else None


def check_health():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=10)
        r.raise_for_status()
        return True, r.json()
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return False, {"error": str(e)}


def agent_health(agent_name, state):
    event = {
        "agent_name": agent_name,
        "role": AGENTS[agent_name]["role"],
        "state": state,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "container_ip": CONTAINER_IP,
    }
    try:
        api("/hermes_agents", method="POST", payload=event)
        logger.info(f"Recorded agent state: {agent_name} -> {state}")
    except Exception as e:
        logger.error(f"Failed to record agent state: {e}")


def hermes_health():
    logger.info("[hermes-health] Running health check...")
    agent_health("hermes-health", "running")
    healthy, data = check_health()
    if healthy:
        count = len(data.get("models", []))
        logger.info(f"[hermes-health] Ollama healthy, {count} models active")
        agent_health("hermes-health", "healthy")
        return True
    else:
        logger.warning("[hermes-health] Ollama unhealthy, triggering hermes-fix")
        agent_health("hermes-health", "unhealthy")
        return False


def hermes_rotate():
    logger.info("[hermes-rotate] Running model rotation check...")
    agent_health("hermes-rotate", "running")
    stdout, rc = ssh("ollama list --format json")
    if rc != 0:
        logger.error("[hermes-rotate] Failed to list models")
        agent_health("hermes-rotate", "failed")
        return False
    
    try:
        models = json.loads(stdout)
        active = models.get("models", [])
        logger.info(f"[hermes-rotate] {len(active)} models currently installed")
        
        rotation_config_path = Path.home() / ".config/hermes/rotation.json"
        if rotation_config_path.exists():
            with open(rotation_config_path) as f:
                config = json.load(f)
            preferred = config.get("rotation_policy", {}).get("preferred_models", [])
            for model in preferred:
                if not any(m.get("name") == model for m in active):
                    logger.info(f"[hermes-rotate] Pulling preferred model: {model}")
                    ssh(f"ollama pull {model}")
        
        agent_health("hermes-rotate", "complete")
        return True
    except json.JSONDecodeError as e:
        logger.error(f"[hermes-rotate] JSON parse error: {e}")
        agent_health("hermes-rotate", "failed")
        return False


def hermes_fix():
    logger.info("[hermes-fix] Running self-heal...")
    agent_health("hermes-fix", "running")
    healthy, data = check_health()
    if not healthy:
        logger.warning("[hermes-fix] Ollama unhealthy, attempting restart...")
        stdout, rc = ssh("systemctl restart ollama")
        if rc == 0:
            time.sleep(10)
            healthy2, _ = check_health()
            if healthy2:
                logger.info("[hermes-fix] Self-heal successful after restart")
                agent_health("hermes-fix", "healed")
                return True
            else:
                logger.error("[hermes-fix] Self-heal failed, Ollama still unhealthy")
                agent_health("hermes-fix", "failed")
                return False
        else:
            logger.error(f"[hermes-fix] SSH restart failed: {stdout}")
            agent_health("hermes-fix", "ssh_failed")
            return False
    else:
        logger.info("[hermes-fix] Ollama healthy, no action needed")
        agent_health("hermes-fix", "no_action")
        return True


def hermes_sync():
    logger.info("[hermes-sync] Running data sync...")
    agent_health("hermes-sync", "running")
    stdout, rc = ssh("ollama list --format json")
    if rc != 0:
        agent_health("hermes-sync", "failed")
        return False
    
    try:
        models = json.loads(stdout)
        api("/ollama_models", method="POST", payload=models)
        logger.info("[hermes-sync] Data synced to Supabase")
        agent_health("hermes-sync", "complete")
        return True
    except Exception as e:
        logger.error(f"[hermes-sync] Sync failed: {e}")
        agent_health("hermes-sync", "failed")
        return False


def hermes_report():
    logger.info("[hermes-report] Generating report...")
    agent_health("hermes-report", "running")
    
    healthy, data = check_health()
    stdout, _ = ssh("free -h | head -2")
    mem_info = stdout
    stdout2, _ = ssh("df -h /var/lib/ollama | tail -1")
    disk_info = stdout2
    
    report = {
        "report_type": "daily_operations",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "container_ip": CONTAINER_IP,
        "ollama_healthy": healthy,
        "model_count": len(data.get("models", [])) if healthy else 0,
        "models": [m.get("name") for m in data.get("models", [])] if healthy else [],
        "memory": mem_info,
        "disk": disk_info,
    }
    
    try:
        api("/hermes_reports", method="POST", payload=report)
        logger.info("[hermes-report] Report generated and stored")
        agent_health("hermes-report", "complete")
        return True
    except Exception as e:
        logger.error(f"[hermes-report] Failed to store report: {e}")
        agent_health("hermes-report", "failed")
        return False


def run_agent_loop():
    logger.info("Hermes AI Agent Team starting...")
    
    while True:
        for name, agent in AGENTS.items():
            if not agent.get("enabled", True):
                continue
            
            role = agent["role"]
            try:
                if role == "health_monitor":
                    hermes_health()
                elif role == "model_rotator":
                    hermes_rotate()
                elif role == "self_healer":
                    hermes_fix()
                elif role == "data_sync":
                    hermes_sync()
                elif role == "reporting":
                    hermes_report()
            except Exception as e:
                logger.error(f"[{name}] Error: {e}")
                agent_health(name, "error")
        
        logger.info("Hermes agents loop completed, sleeping...")
        time.sleep(300)


def run_single(agent_name):
    if agent_name not in AGENTS:
        logger.error(f"Unknown agent: {agent_name}")
        sys.exit(1)
    
    role = AGENTS[agent_name]["role"]
    if role == "health_monitor":
        hermes_health()
    elif role == "model_rotator":
        hermes_rotate()
    elif role == "self_healer":
        hermes_fix()
    elif role == "data_sync":
        hermes_sync()
    elif role == "reporting":
        hermes_report()


def main():
    if len(sys.argv) > 1:
        run_single(sys.argv[1])
    else:
        run_agent_loop()


if __name__ == "__main__":
    main()
