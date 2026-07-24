import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

OLLAMA_URL = "http://localhost:11434"

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            health = self._check_ollama()
            self._send_json(200, health)
        elif self.path == '/api/status':
            status = self._full_status()
            self._send_json(200, status)
        elif self.path == '/api/workers':
            workers = self._list_workers()
            self._send_json(200, workers)
        else:
            self._send_json(404, {"error": "Not found"})

    def _check_ollama(self):
        try:
            import urllib.request
            req = urllib.request.Request(f"{OLLAMA_URL}/api/tags")
            req.add_header("Accept", "application/json")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode())
                return {"status": "healthy", "ollama": "connected", "models_loaded": len(data.get("models", []))}
        except Exception as e:
            return {"status": "degraded", "ollama": "unreachable", "error": str(e)}

    def _full_status(self):
        return {
            "platform": "open-worker",
            "status": "running",
            "version": "1.0.0",
            "uptime_seconds": int(time.time() - self._start_time),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "worker_types": ["executor", "reviewer", "formatter", "validator", "optimizer"],
            "api_endpoints": {
                "health": "/api/health",
                "status": "/api/status",
                "workers": "/api/workers",
                "task": "/api/task",
            },
        }

    def _list_workers(self):
        return {
            "workers": [
                {"id": "executor-1", "type": "executor", "status": "active", "tasks_processed": 0},
                {"id": "reviewer-1", "type": "reviewer", "status": "active", "tasks_processed": 0},
                {"id": "formatter-1", "type": "formatter", "status": "active", "tasks_processed": 0},
                {"id": "validator-1", "type": "validator", "status": "active", "tasks_processed": 0},
                {"id": "optimizer-1", "type": "optimizer", "status": "active", "tasks_processed": 0},
            ],
            "total": 5,
        }

    def _send_json(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())

    def log_message(self, format, *args):
        pass

def main():
    handler = HealthHandler
    handler._start_time = time.time()
    server = HTTPServer(("0.0.0.0", 6000), handler)
    print("Open Worker health server running on port 6000")
    server.serve_forever()

if __name__ == "__main__":
    main()
