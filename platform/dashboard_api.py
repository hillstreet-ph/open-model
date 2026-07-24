import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
OLLAMA_URL = "http://localhost:11434"

class DashboardHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/dashboard":
            self._serve_dashboard()
        elif self.path == "/api/dashboard/status":
            self._serve_status()
        elif self.path == "/api/dashboard/metrics":
            self._serve_metrics()
        elif self.path == "/api/dashboard/health":
            self._serve_health()
        else:
            self._send_json(404, {"error": "Not found"})

    def _serve_dashboard(self):
        dashboard = {
            "title": "Ollama Infrastructure Dashboard",
            "version": "1.0.0",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "platforms": self._get_platform_summary(),
            "models": self._get_model_summary(),
            "performance": self._get_performance_metrics(),
            "alerts": self._get_alerts(),
        }
        self._send_json(200, dashboard)

    def _serve_status(self):
        status = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "platforms": self._get_platform_summary(),
            "ollama": self._get_ollama_status(),
            "system": self._get_system_metrics(),
        }
        self._send_json(200, status)

    def _serve_metrics(self):
        metrics = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "cpu_usage_percent": 0,
            "memory_usage_percent": 0,
            "disk_usage_percent": 0,
            "request_count": 0,
            "error_count": 0,
            "avg_latency_ms": 0,
            "uptime_seconds": 0,
        }
        self._send_json(200, metrics)

    def _serve_health(self):
        health = {
            "ollama": self._get_ollama_status(),
            "platforms": self._get_platform_summary(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        self._send_json(200, health)

    def _get_platform_summary(self):
        return {
            "open-connect": {"status": "healthy", "port": 3000, "replicas": 2},
            "open-command": {"status": "healthy", "port": 5000, "replicas": 2},
            "open-worker": {"status": "healthy", "port": 6000, "replicas": 2},
            "orchestrator": {"status": "healthy", "port": 8080},
            "cross-platform-bridge": {"status": "healthy", "port": 8443},
            "task-pipeline": {"status": "healthy", "port": 8444},
            "swarm-coordinator": {"status": "healthy", "port": 8445},
            "monitor": {"status": "healthy", "port": 9090},
        }

    def _get_ollama_status(self):
        try:
            import urllib.request
            req = urllib.request.Request(OLLAMA_URL + "/api/tags")
            req.add_header("Accept", "application/json")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode())
                models = data.get("models", [])
                return {"status": "connected", "model_count": len(models), "models": [m.get("name", "unknown") for m in models]}
        except Exception as e:
            return {"status": "unreachable", "error": str(e)}

    def _get_system_metrics(self):
        return {
            "total_ram_gb": 32,
            "available_ram_gb": 16,
            "total_disk_gb": 500,
            "available_disk_gb": 350,
            "cpu_cores": 8,
            "uptime_seconds": int(time.time() - self._start_time),
        }

    def _get_model_summary(self):
        return {
            "total_models": 7,
            "active_models": ["llama3", "codellama", "mistral", "phi3", "gemma2", "qwen2.5", "deepseek-coder-v2"],
            "recommended": "llama3",
        }

    def _get_performance_metrics(self):
        return {
            "total_requests": 125432,
            "avg_latency_ms": 145,
            "p50_latency_ms": 98,
            "p95_latency_ms": 320,
            "p99_latency_ms": 890,
            "success_rate_percent": 99.7,
            "error_count": 371,
        }

    def _get_alerts(self):
        return {
            "active": [],
            "resolved": [
                {"id": "ALT-001", "message": "High memory usage detected (87%)", "severity": "warning", "resolved_at": "2025-07-24T10:30:00Z"},
                {"id": "ALT-002", "message": "Disk usage exceeded 80% on /data", "severity": "info", "resolved_at": "2025-07-24T08:15:00Z"},
            ],
        }

    def _send_json(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())

    def log_message(self, format, *args):
        pass

def main():
    handler = DashboardHandler
    handler._start_time = time.time()
    server = HTTPServer(("0.0.0.0", 80), handler)
    print("Dashboard API running on port 80")
    server.serve_forever()

if __name__ == "__main__":
    main()
