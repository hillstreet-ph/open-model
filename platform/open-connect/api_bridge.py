from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import requests
import json
from datetime import datetime

app = FastAPI(title="Open Connect API Bridge")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

OLLAMA_BASE = "http://localhost:11434"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY = ""

@app.get("/api/models")
async def list_models():
    r = requests.get(f"{OLLAMA_BASE}/api/tags")
    return r.json()

@app.post("/api/chat")
async def chat(request: dict):
    r = requests.post(f"{OLLAMA_BASE}/api/chat", json=request)
    return r.json()

@app.post("/api/generate")
async def generate(request: dict):
    r = requests.post(f"{OLLAMA_BASE}/api/generate", json=request)
    return r.json()

@app.post("/api/embeddings")
async def embeddings(request: dict):
    r = requests.post(f"{OLLAMA_BASE}/api/embeddings", json=request)
    return r.json()

@app.get("/api/health")
async def health():
    try:
        r = requests.get(f"{OLLAMA_BASE}/api/tags", timeout=5)
        return {"status": "ok", "ollama": "connected", "timestamp": datetime.utcnow().isoformat()}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

@app.get("/api/platform/status")
async def platform_status():
    return {
        "platform": "open-connect",
        "ollama_base": OLLAMA_BASE,
        "supabase": "connected",
        "models_endpoint": "/api/models",
        "chat_endpoint": "/api/chat",
        "health_endpoint": "/api/health",
        "timestamp": datetime.utcnow().isoformat(),
    }
