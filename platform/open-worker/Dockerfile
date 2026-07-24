FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn requests python-multipart aiohttp httpx
COPY worker_manager.py /app/worker_manager.py
COPY worker_api.py /app/worker_api.py
COPY docker-compose.yml /app/docker-compose.yml
EXPOSE 6000 6001
CMD ["python3", "/app/worker_manager.py"]
