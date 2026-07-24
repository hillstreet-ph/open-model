import json
import time
import logging
import requests
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(name)s] %(message)s')
logger = logging.getLogger('open-connect-worker')

OLLAMA_URL = "http://ollama-platform:11434"
PLATFORM_URL = "http://open-connect:3000"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_KEY = ""
PLATFORM_NAME = "open-connect"
PLATFORM_TYPE = "webui"

def sync_models():
    models = get_ollama_models()
    sync_to_supabase(models)
    sync_to_platform(models)

def get_ollama_models():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=10)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        logger.error(f"Failed to get Ollama models: {e}")
        return {"models": []}

def sync_to_supabase(models):
    try:
        r = requests.post(
            f"{SUPABASE_URL}/rest/v1/ollama_models",
            headers={
                "Authorization": f"Bearer {SUPABASE_KEY}",
                "apikey": SUPABASE_KEY,
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates",
            },
            json={"platform": PLATFORM_NAME, "models": models.get("models", []), "synced_at": datetime.utcnow().isoformat()},
            timeout=10,
        )
        logger.info(f"Synced {len(models.get('models', []))} models to Supabase")
    except Exception as e:
        logger.error(f"Supabase sync failed: {e}")

def sync_to_platform(models):
    try:
        r = requests.post(
            f"{PLATFORM_URL}/api/models/sync",
            json={"models": models.get("models", []), "source": "ollama-platform"},
            timeout=10,
        )
        logger.info(f"Synced {len(models.get('models', []))} models to {PLATFORM_NAME}")
    except Exception as e:
        logger.error(f"{PLATFORM_NAME} sync failed: {e}")

def health_check():
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        return r.status_code == 200
    except:
        return False

def main():
    logger.info(f"Open Connect worker starting for {PLATFORM_NAME}")
    while True:
        if health_check():
            sync_models()
        else:
            logger.warning("Ollama not reachable, retrying in 60s")
        time.sleep(300)

if __name__ == "__main__":
    main()
