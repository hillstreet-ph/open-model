import json
import time
import logging
import subprocess
import requests
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(name)s] %(levelname)s %(message)s')
logger = logging.getLogger('open-command')

OLLAMA_URL = "http://ollama-platform-swarm:11434"
CONTABO_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
SWARM_MODE = True
MAX_AGENTS = 10
AGENT_HEARTBEAT = 30

AGENT_TYPES = {
    "coder": {
        "model": "qwen2.5:7b",
        "system_prompt": "You are a code agent. Write, debug, and refactor code. Focus on clean, efficient, and well-documented code.",
        "max_tokens": 4096,
        "temperature": 0.3,
    },
    "debugger": {
        "model": "qwen2.5:1.5b",
        "system_prompt": "You are a debugging agent. Analyze errors, trace bugs, and provide fixes. Be thorough and systematic.",
        "max_tokens": 2048,
        "temperature": 0.1,
    },
    "planner": {
        "model": "gemma4:latest",
        "system_prompt": "You are a planning agent. Break down complex tasks into steps, identify dependencies, and create execution plans.",
        "max_tokens": 2048,
        "temperature": 0.5,
    },
    "reviewer": {
        "model": "mistral:7b",
        "system_prompt": "You are a code reviewer agent. Review code for bugs, security issues, and best practices. Provide constructive feedback.",
        "max_tokens": 2048,
        "temperature": 0.2,
    },
    "researcher": {
        "model": "llama3.2:3b",
        "system_prompt": "You are a research agent. Investigate topics, gather information, and synthesize findings. Be accurate and cite sources.",
        "max_tokens": 4096,
        "temperature": 0.7,
    },
}

class Agent:
    def __init__(self, name, agent_type, ollama_url):
        self.name = name
        self.type = agent_type
        self.ollama_url = ollama_url
        self.config = AGENT_TYPES.get(agent_type, AGENT_TYPES["coder"])
        self.status = "idle"
        self.last_heartbeat = None
        self.task_count = 0

    async def execute_task(self, task):
        self.status = "busy"
        try:
            response = await self._call_ollama(task)
            self.task_count += 1
            self.status = "idle"
            return {"agent": self.name, "type": self.type, "task": task, "response": response, "status": "success"}
        except Exception as e:
            self.status = "error"
            return {"agent": self.name, "type": self.type, "task": task, "error": str(e), "status": "failed"}

    def _call_ollama(self, task):
        payload = {
            "model": self.config["model"],
            "prompt": task,
            "stream": False,
            "options": {
                "temperature": self.config["temperature"],
                "num_predict": self.config["max_tokens"],
            },
        }
        r = requests.post(f"{self.ollama_url}/api/generate", json=payload, timeout=60)
        r.raise_for_status()
        return r.json().get("response", "")

    def heartbeat(self):
        self.last_heartbeat = datetime.utcnow().isoformat()
        return {
            "name": self.name,
            "type": self.type,
            "status": self.status,
            "task_count": self.task_count,
            "last_heartbeat": self.last_heartbeat,
        }

class OpenCommandSwarm:
    def __init__(self):
        self.agents = {}
        self.active_task_count = 0

    def spawn_agent(self, name, agent_type):
        if len(self.agents) >= MAX_AGENTS:
            return {"error": f"Maximum agent count ({MAX_AGENTS}) reached"}
        if name in self.agents:
            return {"error": f"Agent {name} already exists"}
        agent = Agent(name, agent_type, OLLAMA_URL)
        self.agents[name] = agent
        logger.info(f"Spawned agent {name} (type: {agent_type})")
        return {"name": name, "type": agent_type, "status": "spawned"}

    def execute_task(self, agent_name, task):
        if agent_name not in self.agents:
            return {"error": f"Agent {agent_name} not found"}
        agent = self.agents[agent_name]
        self.active_task_count += 1
        result = agent.execute_task(task)
        self.active_task_count -= 1
        return result

    def execute_parallel(self, tasks):
        results = []
        with ThreadPoolExecutor(max_workers=min(len(tasks), MAX_AGENTS)) as executor:
            futures = []
            for task in tasks:
                agent_name = task.get("agent", list(self.agents.keys())[0] if self.agents else "default")
                if agent_name not in self.agents:
                    results.append({"error": f"Agent {agent_name} not found"})
                    continue
                futures.append(executor.submit(self.agents[agent_name].execute_task, task["prompt"]))
            for future in as_completed(futures):
                try:
                    results.append(future.result())
                except Exception as e:
                    results.append({"error": str(e)})
        return results

    def swarm_status(self):
        return {
            "platform": "open-command",
            "mode": "swarm" if SWARM_MODE else "single",
            "agent_count": len(self.agents),
            "max_agents": MAX_AGENTS,
            "active_tasks": self.active_task_count,
            "agents": {name: agent.heartbeat() for name, agent in self.agents.items()},
            "timestamp": datetime.utcnow().isoformat(),
        }

    def scale(self, count):
        current = len(self.agents)
        if count > MAX_AGENTS:
            return {"error": f"Cannot scale to {count}, max is {MAX_AGENTS}"}
        to_add = count - current
        for i in range(to_add):
            name = f"agent-{current + i + 1}"
            agent_type = list(AGENT_TYPES.keys())[i % len(AGENT_TYPES)]
            self.spawn_agent(name, agent_type)
        return {"scaled_to": count, "added": to_add, "total": len(self.agents)}

def main():
    swarm = OpenCommandSwarm()
    logger.info("Open Command Swarm starting...")
    
    # Spawn default agents
    for agent_type in AGENT_TYPES:
        name = f"{agent_type}-agent"
        swarm.spawn_agent(name, agent_type)
    
    logger.info(f"Swarm initialized with {len(swarm.agents)} agents")
    
    # Heartbeat loop
    while True:
        status = swarm.swarm_status()
        logger.info(f"Swarm status: {status['agent_count']} agents, {status['active_tasks']} active tasks")
        
        # Sync to Supabase
        try:
            requests.post(
                f"{SUPABASE_URL}/rest/v1/swarm_status",
                headers={
                    "Authorization": f"Bearer ",
                    "apikey": "",
                    "Content-Type": "application/json",
                },
                json=status,
                timeout=5,
            )
        except Exception as e:
            logger.error(f"Supabase sync failed: {e}")
        
        time.sleep(AGENT_HEARTBEAT)

if __name__ == "__main__":
    main()
