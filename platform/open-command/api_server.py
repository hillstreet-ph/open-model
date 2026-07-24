from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List
import json
import requests
from datetime import datetime

app = FastAPI(title="Open Command API - SwarmClaw Platform")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

OLLAMA_URL = "http://localhost:11434"
CONTABO_IP = "169.58.68.183"

class Task(BaseModel):
    agent: str
    prompt: str
    model: Optional[str] = None
    stream: bool = False

class TaskBatch(BaseModel):
    tasks: List[Task]

class SwarmConfig(BaseModel):
    max_agents: int = 10
    agent_types: list = ["coder", "debugger", "planner", "reviewer", "researcher"]

@app.get("/api/agents")
async def list_agents():
    r = requests.get(f"{OLLAMA_URL}/api/tags")
    models = r.json().get("models", [])
    agent_types = ["coder", "debugger", "planner", "reviewer", "researcher"]
    agents = []
    for atype in agent_types:
        agent_info = {
            "type": atype,
            "status": "available",
            "model": _get_agent_model(atype),
            "system_prompt": _get_agent_prompt(atype),
        }
        agents.append(agent_info)
    return {"agents": agents, "total": len(agents), "swarm_mode": True}

@app.post("/api/task")
async def execute_task(task: Task):
    model = task.model or "qwen2.5:7b"
    payload = {
        "model": model,
        "prompt": task.prompt,
        "stream": task.stream,
    }
    r = requests.post(f"{OLLAMA_URL}/api/generate", json=payload, timeout=120)
    r.raise_for_status()
    return {"agent": task.agent, "response": r.json().get("response", ""), "timestamp": datetime.utcnow().isoformat()}

@app.post("/api/tasks/batch")
async def execute_batch(batch: TaskBatch):
    from concurrent.futures import ThreadPoolExecutor
    results = []
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for task in batch.tasks:
            futures.append(executor.submit(_execute_single_task, task))
        for future in futures:
            try:
                results.append(future.result())
            except Exception as e:
                results.append({"error": str(e)})
    return {"results": results, "count": len(results)}

@app.get("/api/swarm/status")
async def swarm_status():
    return {
        "platform": "open-command",
        "swarm_mode": True,
        "container_ip": CONTABO_IP,
        "ollama_url": OLLAMA_URL,
        "max_agents": 10,
        "agent_types": ["coder", "debugger", "planner", "reviewer", "researcher"],
        "timestamp": datetime.utcnow().isoformat(),
    }

@app.get("/api/health")
async def health():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        return {"status": "ok", "ollama": "connected", "platform": "open-command"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

def _get_agent_model(agent_type):
    models = {"coder": "qwen2.5:7b", "debugger": "qwen2.5:1.5b", "planner": "gemma4:latest", "reviewer": "mistral:7b", "researcher": "llama3.2:3b"}
    return models.get(agent_type, "qwen2.5:7b")

def _get_agent_prompt(agent_type):
    prompts = {
        "coder": "Write clean, efficient code with proper documentation.",
        "debugger": "Analyze errors systematically and provide fixes.",
        "planner": "Break down tasks into steps with dependencies.",
        "reviewer": "Review for bugs, security, and best practices.",
        "researcher": "Investigate and synthesize findings accurately.",
    }
    return prompts.get(agent_type, "")

def _execute_single_task(task):
    payload = {"model": task.model or "qwen2.5:7b", "prompt": task.prompt, "stream": False}
    r = requests.post(f"{OLLAMA_URL}/api/generate", json=payload, timeout=120)
    r.raise_for_status()
    return {"agent": task.agent, "response": r.json().get("response", "")}
