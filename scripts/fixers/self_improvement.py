#!/usr/bin/env python3
"""Self-Improvement System for Ollama Infrastructure AI Agents."""

import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("self-improve")

METRICS_DIR = Path("/opt/ollama/metrics")
CONFIG_DIR = Path("/opt/ollama/config")
AGENT_LOG = Path("/var/log/ollama-agent.log")


def get_ollama_metrics():
    """Collect current Ollama performance metrics."""
    metrics = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "container_ip": "169.58.68.183",
    }
    
    try:
        result = subprocess.run(
            ["curl", "-s", "http://localhost:11434/api/tags"],
            capture_output=True, text=True, timeout=10,
        )
        models = json.loads(result.stdout)
        metrics["model_count"] = len(models.get("models", []))
        metrics["models"] = [m.get("name") for m in models.get("models", [])]
    except Exception as e:
        metrics["error"] = str(e)
    
    try:
        result = subprocess.run(
            ["ssh", "-i", str(Path.home() / ".ssh/id_ed25519_contabo"),
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             "root@169.58.68.183", "free -m"],
            capture_output=True, text=True, timeout=15,
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) >= 2:
            mem_parts = lines[1].split()
            metrics["memory_total_mb"] = int(mem_parts[1])
            metrics["memory_used_mb"] = int(mem_parts[2])
            metrics["memory_usage_percent"] = round(
                (int(mem_parts[2]) / int(mem_parts[1])) * 100, 1
            )
    except Exception as e:
        metrics["memory_error"] = str(e)
    
    try:
        result = subprocess.run(
            ["ssh", "-i", str(Path.home() / ".ssh/id_ed25519_contabo"),
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             "root@169.58.68.183", "df -h /var/lib/ollama"],
            capture_output=True, text=True, timeout=15,
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) >= 2:
            disk_parts = lines[1].split()
            metrics["disk_total"] = disk_parts[1]
            metrics["disk_used"] = disk_parts[2]
            metrics["disk_usage_percent"] = int(disk_parts[4].replace("%", ""))
    except Exception as e:
        metrics["disk_error"] = str(e)
    
    return metrics


def evaluate_performance(metrics):
    """Evaluate performance and identify improvement areas."""
    issues = []
    recommendations = []
    
    mem_pct = metrics.get("memory_usage_percent", 0)
    if mem_pct > 90:
        issues.append("high_memory_usage")
        recommendations.append("Consider increasing server memory or reducing active models")
    elif mem_pct > 75:
        recommendations.append("Memory usage moderate, monitor for trends")
    
    disk_pct = metrics.get("disk_usage_percent", 0)
    if disk_pct > 90:
        issues.append("critical_disk_usage")
        recommendations.append("立即清理磁盘: 移除不常用模型 or expand storage")
    elif disk_pct > 80:
        issues.append("high_disk_usage")
        recommendations.append("Schedule disk cleanup or model archival")
    
    model_count = metrics.get("model_count", 0)
    if model_count > 10:
        issues.append("too_many_models")
        recommendations.append("Consider reducing active models to free resources")
    
    health_ok = "error" not in metrics
    if not health_ok:
        issues.append("ollama_unreachable")
        recommendations.append("Check Ollama service and network connectivity")
    
    return issues, recommendations


def apply_improvements(issues, recommendations):
    """Apply automated improvements based on identified issues."""
    actions_taken = []
    
    if "high_memory_usage" in issues:
        logger.info("High memory detected, adjusting model queue...")
        ssh_cmd = "systemctl restart ollama"
        result = subprocess.run(
            ["ssh", "-i", str(Path.home() / ".ssh/id_ed25519_contabo"),
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             "root@169.58.68.183", ssh_cmd],
            capture_output=True, text=True, timeout=30,
        )
        actions_taken.append({"action": "restart_ollama", "result": result.returncode == 0})
    
    if "critical_disk_usage" in issues or "high_disk_usage" in issues:
        logger.info("Disk pressure detected, triggering cleanup...")
        cleanup_cmd = "/opt/ollama/scripts/workers/disk_cleanup.sh"
        result = subprocess.run(
            ["ssh", "-i", str(Path.home() / ".ssh/id_ed25519_contabo"),
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             "root@169.58.68.183", f"bash {cleanup_cmd}"],
            capture_output=True, text=True, timeout=120,
        )
        actions_taken.append({"action": "disk_cleanup", "result": result.returncode == 0})
    
    if "ollama_unreachable" in issues:
        logger.info("Ollama unreachable, attempting self-heal...")
        result = subprocess.run(
            ["ssh", "-i", str(Path.home() / ".ssh/id_ed25519_contabo"),
             "-p", "22", "-o", "StrictHostKeyChecking=no",
             "-o", "UserKnownHostsFile=/dev/null",
             "root@169.58.68.183", "systemctl restart ollama"],
            capture_output=True, text=True, timeout=30,
        )
        actions_taken.append({"action": "restart_ollama", "result": result.returncode == 0})
    
    return actions_taken


def record_improvement_cycle(metrics, issues, recommendations, actions):
    """Record the improvement cycle for tracking and analysis."""
    cycle = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "metrics": metrics,
        "issues_identified": issues,
        "recommendations": recommendations,
        "actions_taken": actions,
        "self_improvement_score": calculate_score(issues, actions),
    }
    
    cycle_dir = Path.home() / ".config/hermes/improvements"
    cycle_dir.mkdir(parents=True, exist_ok=True)
    cycle_file = cycle_dir / f"cycle-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
    
    with open(cycle_file, 'w') as f:
        json.dump(cycle, f, indent=2)
    
    logger.info(f"Recorded improvement cycle: {cycle_file}")
    return cycle


def calculate_score(issues, actions):
    """Calculate self-improvement score (0-100)."""
    base_score = 100
    issue_penalty = len(issues) * 10
    action_bonus = sum(1 for a in actions if a.get("result")) * 5
    score = max(0, min(100, base_score - issue_penalty + action_bonus))
    return score


def run_improvement_cycle():
    """Run one complete self-improvement cycle."""
    logger.info("Starting self-improvement cycle...")
    
    metrics = get_ollama_metrics()
    logger.info(f"Metrics collected: {json.dumps(metrics, indent=2)}")
    
    issues, recommendations = evaluate_performance(metrics)
    if issues:
        logger.warning(f"Issues identified: {issues}")
    if recommendations:
        for rec in recommendations:
            logger.info(f"Recommendation: {rec}")
    
    actions = apply_improvements(issues, recommendations)
    if actions:
        logger.info(f"Actions applied: {len(actions)}")
    
    cycle = record_improvement_cycle(metrics, issues, recommendations, actions)
    
    logger.info(f"Self-improvement score: {cycle['self_improvement_score']}/100")
    return cycle


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "cycle"
    
    if mode == "cycle":
        run_improvement_cycle()
    elif mode == "metrics":
        metrics = get_ollama_metrics()
        print(json.dumps(metrics, indent=2))
    elif mode == "evaluate":
        metrics = get_ollama_metrics()
        issues, recommendations = evaluate_performance(metrics)
        result = {"issues": issues, "recommendations": recommendations}
        print(json.dumps(result, indent=2))
    elif mode == "loop":
        logger.info("Starting continuous self-improvement loop...")
        while True:
            try:
                run_improvement_cycle()
            except Exception as e:
                logger.error(f"Cycle failed: {e}")
            time.sleep(3600)
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
