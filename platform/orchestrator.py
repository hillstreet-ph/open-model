import json
import time
import logging
import requests
from datetime import datetime

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s %(message)s")
logger = logging.getLogger("platform-orchestrator")

CONTABO_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"

PLATFORMS = {
    "open-connect": {
        "url": "http://localhost:3000",
        "health_url": "http://localhost:3000/api/health",
        "description": "Open Web UI integration",
        "port": 3000,
    },
    "open-command": {
        "url": "http://localhost:8000",
        "health_url": "http://localhost:8000/api/health",
        "description": "SwarmClaw agent swarm orchestration",
        "port": 8000,
    },
    "open-worker": {
        "url": "http://localhost:9000",
        "health_url": "http://localhost:9000/api/health",
        "description": "Hermes Agent task execution workers",
        "port": 9000,
    },
}

OLLAMA_URL = "http://localhost:11434"

class PlatformOrchestrator:
    def __init__(self):
        self.platforms = PLATFORMS

    def check_platform_health(self, name, config):
        try:
            r = requests.get(config["health_url"], timeout=10)
            return r.status_code == 200, r.json() if r.status_code == 200 else {"error": f"HTTP {r.status_code}"}
        except Exception as e:
            return False, {"error": str(e)}

    def get_all_status(self):
        status = {
            "platform": "open-platform",
            "mode": "multi-project",
            "timestamp": datetime.utcnow().isoformat(),
            "container_ip": CONTABO_IP,
            "platforms": {},
        }
        for name, config in self.platforms.items():
            healthy, info = self.check_platform_health(name, config)
            status["platforms"][name] = {
                "healthy": healthy,
                "url": config["url"],
                "description": config["description"],
                "port": config["port"],
                "info": info,
            }
        try:
            r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
            r.raise_for_status()
            models = r.json().get("models", [])
            status["ollama"] = {"healthy": True, "model_count": len(models), "models": [m.get("name") for m in models]}
        except:
            status["ollama"] = {"healthy": False}
        return status

    def route_task(self, platform, task):
        config = self.platforms.get(platform)
        if not config:
            return {"error": f"Unknown platform: {platform}"}
        try:
            r = requests.post(f"{config['url']}/api/task", json=task, timeout=120)
            r.raise_for_status()
            return {"platform": platform, "result": r.json()}
        except Exception as e:
            return {"platform": platform, "error": str(e)}

def main():
    orchestrator = PlatformOrchestrator()
    logger.info("Platform Orchestrator starting...")
    while True:
        try:
            status = orchestrator.get_all_status()
            healthy = sum(1 for p in status["platforms"].values() if p["healthy"])
            total = len(status["platforms"])
            logger.info(f"Platform health: {healthy}/{total} healthy")
        except Exception as e:
            logger.error(f"Orchestrator error: {e}")
        time.sleep(60)

if __name__ == "__main__":
    main()
