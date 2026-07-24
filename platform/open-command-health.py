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
        elif self.path == '/api/agents':
            agents = self._list_agents()
            self._send_json(200, agents)
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
            "platform": "open-command",
            "status": "running",
            "version": "1.0.0",
            "uptime_seconds": int(time.time() - self._start_time),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "agent_types": ["coder", "debugger", "planner", "reviewer", "researcher"],
            "api_endpoints": {
                "health": "/api/health",
                "status": "/api/status",
                "agents": "/api/agents",
                "task": "/api/task",
                "swarm": "/api/swarm/status",
            },
        }

    def _list_agents(self):
        return {
            "agents": [
                {"id": "coder-1", "type": "coder", "status": "active"},
                {"id": "debugger-1", "type": "debugger", "status": "active"},
                {"id": "planner-1", "type": "planner", "status": "active"},
                {"id": "reviewer-1", "type": "reviewer", "status": "active"},
                {"id": "researcher-1", "type": "researcher", "status": "active"},
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
    server = HTTPServer(("0.0.0.0", 5000), handler)
    print("Open Command health server running on port 5000")
    server.serve_forever()

if __name__ == "__main__":
    main()
