FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn requests python-multipart aiohttp httpx
RUN apt-get update && apt-get install -y jq curl && rm -rf /var/lib/apt/lists/*
COPY orchestrator.py /app/orchestrator.py
COPY api_server.py /app/api_server.py
COPY docker-compose.yml /app/docker-compose.yml
EXPOSE 8080 3000 8000 9000
CMD ["python3", "/app/orchestrator.py"]
