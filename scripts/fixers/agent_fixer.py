#!/usr/bin/env python3
"""AI Agent & Fixer for Ollama infrastructure on Contabo."""

import json
import logging
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9saHR4aWJieWh1Y3hjbWh6YmxxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NDg1Mzc3MCwiZXhwIjoyMTAwNDI5NzcwfQ.rz3vITWn504AhSdS52mbGvuOTxBpnAq0dUz7YrgcTsw"
CONTAINER_IP = "169.58.68.183"
OLLAMA_URL = f"http://{CONTAINER_IP}:11434"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("ollama-agent")


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


def health_check():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=10)
        r.raise_for_status()
        return True
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return False


def get_models():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=10)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        logger.error(f"Failed to get models: {e}")
        return {"models": []}


def restart_ollama():
    logger.info("Attempting remote restart of Ollama...")
    try:
        subprocess.run(
            [
                "ssh",
                "-i",
                f"{Path.home()}/.ssh/id_ed25519_contabo",
                "-p",
                "22",
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
                f"root@{CONTAINER_IP}",
                "systemctl restart ollama",
            ],
            timeout=30,
            check=True,
        )
        return True
    except Exception as e:
        logger.error(f"Restart failed: {e}")
        return False


def record_event(event_type, details):
    event = {
        "event_type": event_type,
        "container_ip": CONTAINER_IP,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "details": json.dumps(details),
    }
    try:
        api("/ollama_events", method="POST", payload=event)
        logger.info(f"Recorded event: {event_type}")
    except Exception as e:
        logger.error(f"Failed to record event: {e}")


def run_diagnostics():
    results = {}
    results["timestamp"] = datetime.now(timezone.utc).isoformat()
    results["server_ip"] = CONTAINER_IP

    results["ollama_health"] = health_check()
    models = get_models()
    results["model_count"] = len(models.get("models", []))
    results["models"] = [m.get("name") for m in models.get("models", [])]

    try:
        r = subprocess.run(
            ["ssh", "-i", f"{Path.home()}/.ssh/id_ed25519_contabo",
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             f"root@{CONTAINER_IP}", "df -h /var/lib/ollama"],
            capture_output=True, text=True, timeout=15,
        )
        results["disk"] = r.stdout.strip()
    except Exception as e:
        results["disk"] = f"Error: {e}"

    try:
        r = subprocess.run(
            ["ssh", "-i", f"{Path.home()}/.ssh/id_ed25519_contabo",
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             f"root@{CONTAINER_IP}", "free -h"],
            capture_output=True, text=True, timeout=15,
        )
        results["memory"] = r.stdout.strip()
    except Exception as e:
        results["memory"] = f"Error: {e}"

    try:
        r = subprocess.run(
            ["ssh", "-i", f"{Path.home()}/.ssh/id_ed25519_contabo",
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             f"root@{CONTAINER_IP}", "systemctl is-active ollama"],
            capture_output=True, text=True, timeout=15,
        )
        results["service_status"] = r.stdout.strip()
    except Exception as e:
        results["service_status"] = f"Error: {e}"

    return results


def auto_fix():
    logger.info("Running auto-fixer...")
    record_event("fixer_start", {"reason": "scheduled"})

    if not health_check():
        logger.warning("Ollama is unhealthy, attempting restart...")
        record_event("fixer_action", {"action": "restart"})
        if restart_ollama():
            import time
            time.sleep(10)
            if health_check():
                record_event("fixer_success", {"action": "restart", "result": "healthy"})
                logger.info("Self-heal successful after restart")
                return True
            else:
                record_event("fixer_failure", {"action": "restart", "result": "still unhealthy"})
        else:
            record_event("fixer_failure", {"action": "restart", "result": "ssh failed"})

    models = get_models()
    if not models.get("models"):
        logger.warning("No models installed, triggering model sync...")
        record_event("fixer_action", {"action": "sync_models"})
        try:
            subprocess.run(
                ["ssh", "-i", f"{Path.home()}/.ssh/id_ed25519_contabo",
                 "-p", "22", "-o", "StrictHostKeyChecking=no",
                 "-o", "UserKnownHostsFile=/dev/null",
                 f"root@{CONTAINER_IP}",
                 "bash /opt/ollama/scripts/contabo/install_models.sh"],
                timeout=300,
            )
            record_event("fixer_success", {"action": "sync_models", "result": "completed"})
        except Exception as e:
            record_event("fixer_failure", {"action": "sync_models", "error": str(e)})

    record_event("fixer_complete", {"status": "done"})
    return True


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "diag"

    if mode == "diag":
        results = run_diagnostics()
        print(json.dumps(results, indent=2))
        api("/ollama_diagnostics", method="POST", payload=results)
    elif mode == "fix":
        auto_fix()
    elif mode == "health":
        if health_check():
            print("ALL_OK")
            sys.exit(0)
        else:
            print("UNHEALTHY")
            sys.exit(1)
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()