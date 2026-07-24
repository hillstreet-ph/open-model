import json
import time
import logging
import threading
import requests
from datetime import datetime, timezone
from queue import Queue, Empty
from enum import Enum

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s %(message)s")
logger = logging.getLogger("task-pipeline")

CONTABO_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
OLLAMA_URL = "http://localhost:11434"

class TaskStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    RETRYING = "retrying"
    DEAD_LETTER = "dead_letter"

class TaskPriority(Enum):
    LOW = 1
    NORMAL = 2
    HIGH = 3
    CRITICAL = 4

class Task:
    def __init__(self, task_id, task_type, payload, priority=TaskPriority.NORMAL, max_retries=3):
        self.task_id = task_id
        self.task_type = task_type
        self.payload = payload
        self.priority = priority
        self.max_retries = max_retries
        self.status = TaskStatus.PENDING
        self.retries = 0
        self.created_at = datetime.now(timezone.utc).isoformat()
        self.started_at = None
        self.completed_at = None
        self.result = None
        self.error = None
        self.platform = self._assign_platform()

    def _assign_platform(self):
        platform_routing = {
            "chat_message": "open-connect",
            "code_generation": "open-command",
            "code_review": "open-command",
            "task_execution": "open-worker",
            "task_validation": "open-worker",
            "agent_coordination": "open-command",
            "research_query": "open-connect",
            "format_output": "open-worker",
            "model_inference": "open-command",
        }
        return platform_routing.get(self.task_type, "open-connect")

    def to_dict(self):
        return {
            "task_id": self.task_id,
            "task_type": self.task_type,
            "status": self.status.value,
            "priority": self.priority.value,
            "platform": self.platform,
            "retries": self.retries,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "result": self.result,
            "error": self.error,
        }

class TaskPipeline:
    def __init__(self, max_workers=5):
        self.queue = Queue()
        self.results = {}
        self.workers = []
        self.max_workers = max_workers
        self.dead_letter_queue = []
        self.running = False

    def submit(self, task_type, payload, priority=TaskPriority.NORMAL, max_retries=3):
        task_id = f"task-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}-{hash(str(payload)) % 10000}"
        task = Task(task_id, task_type, payload, priority, max_retries)
        self.queue.put(task)
        self.results[task_id] = task
        logger.info(f"Submitted task {task_id} (type: {task_type}, platform: {task.platform}, priority: {priority.name})")
        return task_id

    def submit_batch(self, tasks):
        task_ids = []
        for task_def in tasks:
            tid = self.submit(
                task_def.get("type", "unknown"),
                task_def.get("payload", {}),
                TaskPriority[task_def.get("priority", "NORMAL")],
                task_def.get("max_retries", 3),
            )
            task_ids.append(tid)
        return task_ids

    def start(self):
        self.running = True
        for i in range(self.max_workers):
            worker = threading.Thread(target=self._worker_loop, args=(i,), daemon=True)
            worker.start()
            self.workers.append(worker)
        logger.info(f"Task pipeline started with {self.max_workers} workers")

    def stop(self):
        self.running = False
        logger.info("Task pipeline stopping...")

    def _worker_loop(self, worker_id):
        while self.running:
            try:
                task = self.queue.get(timeout=1)
                self._execute_task(task, worker_id)
                self.queue.task_done()
            except Empty:
                continue
            except Exception as e:
                logger.error(f"Worker {worker_id} error: {e}")

    def _execute_task(self, task, worker_id):
        task.status = TaskStatus.RUNNING
        task.started_at = datetime.now(timezone.utc).isoformat()
        logger.info(f"Worker {worker_id} executing task {task.task_id} on {task.platform}")

        try:
            result = self._send_to_platform(task)
            task.status = TaskStatus.COMPLETED
            task.result = result
            task.completed_at = datetime.now(timezone.utc).isoformat()
            logger.info(f"Task {task.task_id} completed successfully")
        except Exception as e:
            task.retries += 1
            if task.retries < task.max_retries:
                task.status = TaskStatus.RETRYING
                logger.warning(f"Task {task.task_id} failed (attempt {task.retries}), retrying...")
                self.queue.put(task)
            else:
                task.status = TaskStatus.DEAD_LETTER
                task.error = str(e)
                task.completed_at = datetime.now(timezone.utc).isoformat()
                self.dead_letter_queue.append(task.to_dict())
                logger.error(f"Task {task.task_id} dead-lettered after {task.max_retries} retries: {e}")

    def _send_to_platform(self, task):
        platform_url = self._get_platform_url(task.platform)
        payload = {
            "task_id": task.task_id,
            "task_type": task.task_type,
            "payload": task.payload,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        
        r = requests.post(f"{platform_url}/api/task", json=payload, timeout=120)
        r.raise_for_status()
        return r.json()

    def _get_platform_url(self, platform):
        platform_urls = {
            "open-connect": "http://localhost:3000",
            "open-command": "http://localhost:8000",
            "open-worker": "http://localhost:9000",
        }
        return platform_urls.get(platform, "http://localhost:3000")

    def get_status(self):
        pending = sum(1 for t in self.results.values() if t.status == TaskStatus.PENDING)
        running = sum(1 for t in self.results.values() if t.status == TaskStatus.RUNNING)
        completed = sum(1 for t in self.results.values() if t.status == TaskStatus.COMPLETED)
        failed = sum(1 for t in self.results.values() if t.status == TaskStatus.FAILED)
        dead_letter = len(self.dead_letter_queue)
        
        return {
            "pipeline_status": "running" if self.running else "stopped",
            "queue_size": self.queue.qsize(),
            "total_tasks": len(self.results),
            "pending": pending,
            "running": running,
            "completed": completed,
            "failed": failed,
            "dead_letter": dead_letter,
            "workers": self.max_workers,
        }

def main():
    pipeline = TaskPipeline(max_workers=5)
    pipeline.start()
    
    # Example task submission
    task_id = pipeline.submit("chat_message", {"message": "Hello from pipeline"})
    logger.info(f"Submitted example task: {task_id}")
    
    # Monitor loop
    while True:
        status = pipeline.get_status()
        logger.info(f"Pipeline: {status['pending']} pending, {status['running']} running, {status['completed']} completed")
        time.sleep(30)

if __name__ == "__main__":
    main()
