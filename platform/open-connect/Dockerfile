FROM python:3.11-slim

WORKDIR /app

RUN pip install fastapi uvicorn requests python-multipart aiohttp

COPY api_bridge.py /app/api_bridge.py
COPY worker.py /app/worker.py
COPY docker-compose.yml /app/docker-compose.yml

EXPOSE 8000 3000

CMD ["sh", "-c", "uvicorn api_bridge:app --host 0.0.0.0 --port 8000 & python worker.py"]
