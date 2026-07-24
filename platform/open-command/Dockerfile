FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn requests python-multipart aiohttp httpx
COPY command_center.py /app/command_center.py
COPY docker-compose.yml /app/docker-compose.yml
COPY agents/ /app/agents/
EXPOSE 5000 5001
CMD ["python3", "/app/command_center.py"]
