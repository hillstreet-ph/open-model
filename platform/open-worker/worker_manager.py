import json
import time
import logging
import threading
import requests
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(name)s] %(levelname)s %(message)s')
logger = logging.getLogger('open-worker')

OLLAMA_URL = "http://ollama-platform-worker:11434"
CONTABO_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
MAX_WORKERS = 5
WORKER_HEARTBEAT = 60

WORKER_TYPES = {
    "executor": {
        "model": "codellama:7b",
        "role": "executes tasks and commands autonomously",
        "max_concurrent": 3,
    },
    "reviewer": {
        "model": "mistral:7b",
        "role": "reviews output quality and correctness",
        "max_concurrent": 2,
    },
    "formatter": {
        "model": "llama3.2:1b",
        "role": "formats output, ensures consistency",
        "max_concurrent": 5,
    },
    "validator": {
        "model": "qwen2.5:1.5b",
        "role": "validates results against expected criteria",
        "max_concurrent": 2,
    },
    "optimizer": {
        "model": "gemma4:latest",
        "role": "optimizes workflows and improves efficiency",
        "max_concurrent": 1,
    },
}

class Worker:
    def __init__(self, name, worker_type, ollama_url):
        self.name = name
        self.type = worker_type
        self.ollama_url = ollama_url
        self.config = WORKER_TYPES[worker_type]
        self.status = "idle"
        self.task_count = 0
        self.error_count = 0
        self.last_heartbeat = None
        self.current_task = None

    def execute(self, task):
        self.status = "busy"
        self.current_task = task
        try:
            payload = {
                "model": self.config["model"],
                "prompt": task.get("prompt", ""),
                "stream": False,
                "options": {"temperature": 0.2},
            }
            r = requests.post(f"{self.ollama_url}/api/generate", json=payload, timeout=120)
            r.raise_for_status()
            result = r.json()
            self.task_count += 1
            self.status = "idle"
            self.current_task = None
            return {"worker": self.name, "type": self.type, "status": "success", "result": result.get("response", "")}
        except Exception as e:
            self.error_count += 1
            self.status = "error"
            self.current_task = None
            return {"worker": self.name, "type": self.type, "status": "failed", "error": str(e)}

    def heartbeat(self):
        self.last_heartbeat = datetime.utcnow().isoformat()
        return {
            "name": self.name,
            "type": self.type,
            "status": self.status,
            "task_count": self.task_count,
            "error_count": self.error_count,
            "current_task": self.current_task,
            "last_heartbeat": self.last_heartbeat,
        }

class WorkerPool:
    def __init__(self):
        self.workers = {}
        self.executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)
        self.task_queue = []
        self.results = []

    def add_worker(self, name, worker_type):
        if worker_type not in WORKER_TYPES:
            return {"error": f"Unknown worker type: {worker_type}"}
        worker = Worker(name, worker_type, OLLAMA_URL)
        self.workers[name] = worker
        return {"name": name, "type": worker_type, "status": "added"}

    def process_task(self, task):
        future = self.executor.submit(self._execute_task, task)
        return future

    def _execute_task(self, task):
        worker_name = task.get("worker")
        if worker_name and worker_name in self.workers:
            worker = self.workers[worker_name]
            return worker.execute(task)
        else:
            for name, worker in self.workers.items():
                if worker.status == "idle":
                    return worker.execute(task)
            return {"error": "No idle workers available"}

    def scale(self, target_count):
        current = len(self.workers)
        if target_count > MAX_WORKERS:
            return {"error": f"Cannot exceed {MAX_WORKERS} workers"}
        if target_count > current:
            for i in range(target_count - current):
                wtype = list(WORKER_TYPES.keys())[i % len(WORKER_TYPES)]
                self.add_worker(f"worker-{current + i + 1}", wtype)
        return {"scaled_to": target_count, "total_workers": len(self.workers)}

    def status(self):
        return {
            "platform": "open-worker",
            "worker_mode": True,
            "worker_count": len(self.workers),
            "max_workers": MAX_WORKERS,
            "idle_workers": sum(1 for w in self.workers.values() if w.status == "idle"),
            "busy_workers": sum(1 for w in self.workers.values() if w.status == "busy"),
            "total_tasks": sum(w.task_count for w in self.workers.values()),
            "total_errors": sum(w.error_count for w in self.workers.values()),
            "workers": {name: w.heartbeat() for name, w in self.workers.items()},
            "timestamp": datetime.utcnow().isoformat(),
        }

def main():
    pool = WorkerPool()
    
    # Initialize default workers
    for wtype in WORKER_TYPES:
        pool.add_worker(f"{wtype}-worker", wtype)
    
    logger.info(f"Worker pool initialized with {len(pool.workers)} workers")
    
    # Heartbeat and task processing loop
    while True:
        status = pool.status()
        logger.info(f"Worker pool: {status['idle_workers']} idle, {status['busy_workers']} busy, {status['total_tasks']} tasks completed")
        
        time.sleep(WORKER_HEARTBEAT)

if __name__ == "__main__":
    main()
