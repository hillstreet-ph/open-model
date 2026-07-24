#!/usr/bin/env python3
"""Autopilot - Autonomous DevOps for Ollama Infrastructure."""

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
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("autopilot")

CONTAINER_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9saHR4aWJieWh1Y3hjbWh6YmxxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NDg1Mzc3MCwiZXhwIjoyMTAwNDI5NzcwfQ.rz3vITWn504AhSdS52mbGvuOTxBpnAq0dUz7YrgcTsw"


def ssh(cmd):
    key = str(Path.home() / ".ssh/id_ed25519_contabo")
    result = subprocess.run(
        ["ssh", "-i", key, "-p", "22", "-o", "StrictHostKeyChecking=no",
         "-o", "UserKnownHostsFile=/dev/null", f"root@{CONTAINER_IP}", cmd],
        capture_output=True, text=True, timeout=30,
    )
    return result.stdout.strip(), result.returncode


def log_event(event_type, details):
    event = {
        "event_type": event_type,
        "container_ip": CONTAINER_IP,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "details": json.dumps(details),
    }
    try:
        requests.post(
            f"{SUPABASE_URL}/rest/v1/autopilot_events",
            headers={
                "Authorization": f"Bearer {SUPABASE_KEY}",
                "apikey": SUPABASE_KEY,
                "Content-Type": "application/json",
            },
            json=event,
            timeout=10,
        )
    except Exception as e:
        logger.error(f"Failed to log event: {e}")


def check_all_systems():
    """Run comprehensive health checks across all systems."""
    results = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "checks": {},
    }
    
    # Ollama service health
    ok, out = ssh("systemctl is-active ollama")
    results["checks"]["ollama_service"] = "healthy" if ok == "active" else "unhealthy"
    
    # Ollama API health
    try:
        r = requests.get("http://localhost:11434/api/tags", timeout=10)
        results["checks"]["ollama_api"] = "healthy" if r.status_code == 200 else "unhealthy"
    except Exception:
        results["checks"]["ollama_api"] = "unreachable"
    
    # Disk usage
    ok, out = ssh("df -h /var/lib/ollama | awk 'NR==2{print $5}' | tr -d '%'")
    try:
        disk_pct = int(out)
        results["checks"]["disk_usage"] = "healthy" if disk_pct < 85 else "warning" if disk_pct < 95 else "critical"
        results["checks"]["disk_percent"] = disk_pct
    except ValueError:
        results["checks"]["disk_usage"] = "unknown"
    
    # Memory usage
    ok, out = ssh("free | awk '/Mem:/{printf \"%.0f\", $3/$2*100}'")
    try:
        mem_pct = int(out)
        results["checks"]["memory_usage"] = "healthy" if mem_pct < 80 else "warning" if mem_pct < 95 else "critical"
        results["checks"]["memory_percent"] = mem_pct
    except ValueError:
        results["checks"]["memory_usage"] = "unknown"
    
    # Fail2ban status
    ok, out = ssh("systemctl is-active fail2ban")
    results["checks"]["fail2ban"] = "healthy" if ok == "active" else "inactive"
    
    # Cron service
    ok, out = ssh("systemctl is-active cron")
    results["checks"]["cron"] = "healthy" if ok == "active" else "inactive"
    
    # Monitor service
    ok, out = ssh("systemctl is-active ollama-monitor")
    results["checks"]["monitor"] = "healthy" if ok == "active" else "inactive"
    
    return results


def take_action(results):
    """Take automated actions based on health check results."""
    actions = []
    
    if results["checks"].get("ollama_service") != "healthy":
        logger.warning("Ollama service unhealthy, restarting...")
        _, rc = ssh("systemctl restart ollama")
        actions.append({"action": "restart_ollama", "success": rc == 0})
        log_event("autopilot_action", {"action": "restart_ollama", "success": rc == 0})
    
    if results["checks"].get("ollama_api") == "unreachable":
        logger.warning("Ollama API unreachable, checking service...")
        _, rc = ssh("systemctl restart ollama && sleep 5")
        actions.append({"action": "restart_ollama_api", "success": rc == 0})
    
    disk_pct = results["checks"].get("disk_percent", 0)
    if disk_pct > 90:
        logger.warning(f"Critical disk usage: {disk_pct}%, triggering cleanup...")
        _, rc = ssh("bash /opt/ollama/scripts/workers/disk_cleanup.sh")
        actions.append({"action": "disk_cleanup", "success": rc == 0})
        log_event("autopilot_action", {"action": "disk_cleanup", "disk_pct": disk_pct, "success": rc == 0})
    
    mem_pct = results["checks"].get("memory_percent", 0)
    if mem_pct > 95:
        logger.warning(f"Critical memory usage: {mem_pct}%, restarting...")
        _, rc = ssh("systemctl restart ollama")
        actions.append({"action": "restart_for_memory", "success": rc == 0})
    
    if results["checks"].get("fail2ban") != "healthy":
        logger.warning("Fail2ban inactive, restarting...")
        _, rc = ssh("systemctl restart fail2ban")
        actions.append({"action": "restart_fail2ban", "success": rc == 0})
    
    if results["checks"].get("monitor") != "healthy":
        logger.warning("Monitor service inactive, restarting...")
        _, rc = ssh("systemctl restart ollama-monitor")
        actions.append({"action": "restart_monitor", "success": rc == 0})
    
    return actions


def run_autopilot_cycle():
    """Run one complete autopilot cycle."""
    logger.info("=== Autopilot cycle starting ===")
    
    results = check_all_systems()
    logger.info(f"Health check results: {json.dumps(results, indent=2)}")
    
    any_issue = any(
        v in ("unhealthy", "unreachable", "critical", "warning")
        for v in results["checks"].values()
        if isinstance(v, str)
    )
    
    if any_issue:
        actions = take_action(results)
        if actions:
            logger.info(f"Actions taken: {len(actions)}")
            log_event("autopilot_actions", {"actions": actions})
    else:
        logger.info("All systems healthy, no action needed")
        log_event("autopilot_cycle", {"status": "all_healthy"})
    
    return results


def run_continuous():
    """Run autopilot in continuous mode."""
    logger.info("Autopilot starting in continuous mode...")
    cycle_count = 0
    
    while True:
        cycle_count += 1
        logger.info(f"=== Cycle {cycle_count} ===")
        try:
            run_autopilot_cycle()
        except Exception as e:
            logger.error(f"Cycle failed: {e}")
            log_event("autopilot_error", {"error": str(e), "cycle": cycle_count})
        
        logger.info(f"Cycle {cycle_count} complete, sleeping 300s...")
        time.sleep(300)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "cycle"
    
    if mode == "cycle":
        run_autopilot_cycle()
    elif mode == "continuous":
        run_continuous()
    elif mode == "once":
        run_autopilot_cycle()
    elif mode == "status":
        results = check_all_systems()
        print(json.dumps(results, indent=2))
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
