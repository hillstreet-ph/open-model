from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict
import requests
from datetime import datetime

app = FastAPI(title="Open Platform - Multi-Project Ollama Hub")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

CONTABO_IP = "169.58.68.183"
PLATFORMS = {
    "open-connect": {"url": "http://localhost:3000", "type": "webui", "port": 3000},
    "open-command": {"url": "http://localhost:8000", "type": "swarm", "port": 8000},
    "open-worker": {"url": "http://localhost:9000", "type": "worker", "port": 9000},
}
OLLAMA_URL = "http://localhost:11434"

class TaskRequest(BaseModel):
    platform: str
    prompt: str
    model: Optional[str] = None
    agent: Optional[str] = None

class BatchRequest(BaseModel):
    tasks: List[TaskRequest]

@app.get("/")
async def root():
    return {
        "platform": "open-platform",
        "mode": "multi-project",
        "container_ip": CONTABO_IP,
        "projects": list(PLATFORMS.keys()),
        "ollama": OLLAMA_URL,
        "endpoints": {k: f"/platform/{k}" for k in PLATFORMS},
    }

@app.get("/platforms")
async def list_platforms():
    result = {}
    for name, config in PLATFORMS.items():
        try:
            r = requests.get(f"{config['url']}/api/health", timeout=3)
            result[name] = {"status": "healthy", "port": config["port"]}
        except:
            result[name] = {"status": "unreachable", "port": config["port"]}
    return {"platforms": result, "timestamp": datetime.utcnow().isoformat()}

@app.post("/task")
async def route_task(task: TaskRequest):
    config = PLATFORMS.get(task.platform)
    if not config:
        raise HTTPException(status_code=404, detail=f"Unknown platform: {task.platform}")
    try:
        r = requests.post(f"{config['url']}/api/task", json={"prompt": task.prompt}, timeout=120)
        r.raise_for_status()
        return {"platform": task.platform, "result": r.json()}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

@app.post("/tasks/batch")
async def route_batch(batch: BatchRequest):
    from concurrent.futures import ThreadPoolExecutor
    results = []
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = []
        for t in batch.tasks:
            futures.append(executor.submit(_exec, t))
        for f in futures:
            try:
                results.append(f.result())
            except Exception as e:
                results.append({"error": str(e)})
    return {"results": results, "count": len(results)}

@app.get("/health")
async def health():
    return {"status": "ok", "platform": "open-platform", "container_ip": CONTABO_IP}

def _exec(task):
    config = PLATFORMS.get(task.platform)
    r = requests.post(f"{config['url']}/api/task", json={"prompt": task.prompt}, timeout=120)
    r.raise_for_status()
    return {"platform": task.platform, "result": r.json()}
