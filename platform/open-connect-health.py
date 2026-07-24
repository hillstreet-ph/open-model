import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

OLLAMA_URL = "http://localhost:11434"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            health = self._check_ollama()
            self._send_json(200, health)
        elif self.path == '/api/status':
            status = self._full_status()
            self._send_json(200, status)
        elif self.path == '/api/models':
            models = self._list_models()
            self._send_json(200, models)
        elif self.path == '/api/metrics':
            metrics = self._get_metrics()
            self._send_json(200, metrics)
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
        models = self._list_models()
        return {
            "platform": "open-connect",
            "status": "running",
            "version": "1.0.0",
            "uptime_seconds": int(time.time() - self._start_time),
            "models": models.get("models", []),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "api_endpoints": {
                "health": "/api/health",
                "status": "/api/status",
                "models": "/api/models",
                "metrics": "/api/metrics",
                "chat": "/api/chat",
            },
        }

    def _list_models(self):
        try:
            import urllib.request
            req = urllib.request.Request(f"{OLLAMA_URL}/api/tags")
            req.add_header("Accept", "application/json")
            with urllib.request.urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode())
        except Exception:
            return {"models": []}

    def _get_metrics(self):
        return {
            "requests_total": 0,
            "request_latency_avg_ms": 0,
            "error_rate_percent": 0,
            "active_models": [],
            "uptime_seconds": int(time.time() - self._start_time),
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
    server = HTTPServer(("0.0.0.0", 3000), handler)
    print("Open Connect health server running on port 3000")
    server.serve_forever()

if __name__ == "__main__":
    main()
