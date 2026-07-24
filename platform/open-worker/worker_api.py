from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import json
import requests
from datetime import datetime

app = FastAPI(title="Open Worker API - Hermes Agent Fork")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

OLLAMA_URL = "http://localhost:11434"
CONTABO_IP = "169.58.68.183"

class Task(BaseModel):
    worker: str
    prompt: str
    model: Optional[str] = None
    type: str = "executor"

@app.get("/api/workers")
async def list_workers():
    worker_types = {
        "executor": {"model": "codellama:7b", "role": "executes tasks"},
        "reviewer": {"model": "mistral:7b", "role": "reviews output"},
        "formatter": {"model": "llama3.2:1b", "role": "formats output"},
        "validator": {"model": "qwen2.5:1.5b", "role": "validates results"},
        "optimizer": {"model": "gemma4:latest", "role": "optimizes workflows"},
    }
    workers = []
    for wtype, config in worker_types.items():
        workers.append({
            "type": wtype,
            "model": config["model"],
            "role": config["role"],
            "status": "available",
        })
    return {"workers": workers, "total": len(workers), "worker_mode": True}

@app.post("/api/task")
async def execute_task(task: Task):
    model = task.model or WORKER_TYPES.get(task.type, {}).get("model", "qwen2.5:7b")
    payload = {"model": model, "prompt": task.prompt, "stream": False}
    r = requests.post(f"{OLLAMA_URL}/api/generate", json=payload, timeout=120)
    r.raise_for_status()
    return {"worker": task.worker, "type": task.type, "response": r.json().get("response", ""), "timestamp": datetime.utcnow().isoformat()}

@app.get("/api/worker/status")
async def worker_status():
    return {
        "platform": "open-worker",
        "worker_mode": True,
        "container_ip": CONTABO_IP,
        "ollama_url": OLLAMA_URL,
        "worker_types": ["executor", "reviewer", "formatter", "validator", "optimizer"],
        "max_workers": 5,
        "timestamp": datetime.utcnow().isoformat(),
    }

@app.get("/api/health")
async def health():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        return {"status": "ok", "ollama": "connected", "platform": "open-worker"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))
