import json
import time
import logging
import requests
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s %(message)s")
logger = logging.getLogger("cross-platform-bridge")

CONTABO_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"

PLATFORM_ENDPOINTS = {
    "open-connect": {
        "base_url": "http://localhost:3000",
        "health": "http://localhost:3000/api/health",
        "models": "http://localhost:3000/api/models",
        "chat": "http://localhost:3000/api/chat",
    },
    "open-command": {
        "base_url": "http://localhost:8000",
        "health": "http://localhost:8000/api/health",
        "agents": "http://localhost:8000/api/agents",
        "task": "http://localhost:8000/api/task",
        "swarm": "http://localhost:8000/api/swarm/status",
    },
    "open-worker": {
        "base_url": "http://localhost:9000",
        "health": "http://localhost:9000/api/health",
        "workers": "http://localhost:9000/api/workers",
        "task": "http://localhost:9000/api/task",
        "status": "http://localhost:9000/api/worker/status",
    },
}

OLLAMA_URL = "http://localhost:11434"

class CrossPlatformBridge:
    def __init__(self):
        self.endpoints = PLATFORM_ENDPOINTS
        self.request_queue = []
        self.response_cache = {}
        self.executor = ThreadPoolExecutor(max_workers=10)

    def health_check_all(self):
        results = {}
        for name, urls in self.endpoints.items():
            try:
                r = requests.get(urls["health"], timeout=5)
                results[name] = {"healthy": r.status_code == 200, "latency_ms": r.elapsed.total_seconds() * 1000}
            except Exception as e:
                results[name] = {"healthy": False, "error": str(e)}
        return results

    def broadcast_request(self, endpoint, payload, platforms=None):
        if platforms is None:
            platforms = list(self.endpoints.keys())
        
        futures = {}
        results = {}
        
        for platform in platforms:
            if platform not in self.endpoints:
                results[platform] = {"error": f"Unknown platform: {platform}"}
                continue
            
            url = self.endpoints[platform].get(endpoint)
            if not url:
                results[platform] = {"error": f"Unknown endpoint: {endpoint} for {platform}"}
                continue
            
            future = self.executor.submit(self._make_request, platform, url, payload)
            futures[future] = platform
        
        for future in as_completed(futures):
            platform = futures[future]
            try:
                results[platform] = future.result()
            except Exception as e:
                results[platform] = {"error": str(e)}
        
        return results

    def _make_request(self, platform, url, payload):
        try:
            r = requests.post(url, json=payload, timeout=60)
            r.raise_for_status()
            return {"platform": platform, "status": "success", "data": r.json()}
        except Exception as e:
            return {"platform": platform, "status": "failed", "error": str(e)}

    def chain_request(self, chain):
        results = []
        current_payload = None
        
        for step in chain:
            platform = step["platform"]
            endpoint = step["endpoint"]
            payload = step.get("payload", {})
            
            if current_payload is not None:
                payload.update(current_payload)
            
            url = self.endpoints.get(platform, {}).get(endpoint)
            if not url:
                results.append({"step": step, "error": f"Unknown endpoint: {endpoint} on {platform}"})
                break
            
            try:
                r = requests.post(url, json=payload, timeout=60)
                r.raise_for_status()
                current_payload = r.json()
                results.append({"step": step, "status": "success", "result": current_payload})
            except Exception as e:
                results.append({"step": step, "status": "failed", "error": str(e)})
                break
        
        return results

    def route_task_to_best_platform(self, task_type, payload):
        routing = {
            "chat": ["open-connect"],
            "code_generation": ["open-command"],
            "code_review": ["open-command"],
            "task_execution": ["open-worker"],
            "task_validation": ["open-worker"],
            "formatting": ["open-worker"],
            "research": ["open-connect", "open-command"],
            "agent_coordination": ["open-command"],
            "worker_dispatch": ["open-worker"],
        }
        
        platforms = routing.get(task_type, ["open-connect"])
        return self.broadcast_request("task" if task_type != "chat" else "chat", payload, platforms)

    def sync_all_platforms(self):
        health = self.health_check_all()
        for platform, status in health.items():
            if status["healthy"]:
                logger.info(f"{platform}: healthy ({status.get('latency_ms', 0):.1f}ms)")
            else:
                logger.warning(f"{platform}: unhealthy - {status.get('error', 'unknown')}")
        return health

def main():
    bridge = CrossPlatformBridge()
    logger.info("Cross-Platform API Bridge starting...")
    
    while True:
        health = bridge.sync_all_platforms()
        logger.info(f"Platform status: {sum(1 for s in health.values() if s.get('healthy'))}/{len(health)} healthy")
        time.sleep(60)

if __name__ == "__main__":
    main()
