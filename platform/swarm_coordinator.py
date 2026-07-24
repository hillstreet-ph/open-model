import json
import time
import logging
import threading
import requests
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s %(message)s")
logger = logging.getLogger("swarm-coordinator")

CONTABO_IP = "169.58.68.183"
SUPABASE_URL = "https://olhtxibbyhucxcmhzblq.supabase.co"
OLLAMA_URL = "http://localhost:11434"

class SwarmCoordinator:
    def __init__(self):
        self.agents = {}
        self.max_agents = 10
        self.task_queue = []
        self.executor = ThreadPoolExecutor(max_workers=10)
        self.assigned_tasks = {}

    def register_agent(self, agent_id, agent_type, platform, capabilities):
        agent = {
            "agent_id": agent_id,
            "agent_type": agent_type,
            "platform": platform,
            "capabilities": capabilities,
            "status": "active",
            "registered_at": datetime.now(timezone.utc).isoformat(),
            "last_heartbeat": datetime.now(timezone.utc).isoformat(),
            "task_count": 0,
        }
        self.agents[agent_id] = agent
        logger.info(f"Registered agent {agent_id} (type: {agent_type}, platform: {platform})")
        return agent

    def spawn_agents(self, count, agent_type="general"):
        spawned = []
        for i in range(min(count, self.max_agents - len(self.agents))):
            agent_id = f"{agent_type}-agent-{len(self.agents) + 1}"
            platform = self._assign_platform(agent_type)
            capabilities = self._get_capabilities(agent_type)
            agent = self.register_agent(agent_id, agent_type, platform, capabilities)
            spawned.append(agent)
        return spawned

    def _assign_platform(self, agent_type):
        agent_platforms = {
            "coder": "open-command",
            "debugger": "open-command",
            "planner": "open-command",
            "reviewer": "open-command",
            "researcher": "open-connect",
            "executor": "open-worker",
            "reviewer_worker": "open-worker",
            "formatter": "open-worker",
            "validator": "open-worker",
            "optimizer": "open-worker",
            "general": "open-connect",
        }
        return agent_platforms.get(agent_type, "open-connect")

    def _get_capabilities(self, agent_type):
        caps = {
            "coder": ["code_generation", "code_refactoring", "bug_fixing"],
            "debugger": ["error_analysis", "root_cause_analysis", "fix_suggestion"],
            "planner": ["task_decomposition", "dependency_analysis", "execution_planning"],
            "reviewer": ["code_review", "quality_check", "security_analysis"],
            "researcher": ["information_gathering", "synthesis", "reporting"],
            "executor": ["task_execution", "command_execution", "automation"],
            "reviewer_worker": ["output_validation", "quality_control"],
            "formatter": ["output_formatting", "consistency_check"],
            "validator": ["result_validation", "criteria_checking"],
            "optimizer": ["workflow_optimization", "performance_improvement"],
        }
        return caps.get(agent_type, [])

    def assign_task(self, task_type, payload, agent_type=None):
        if agent_type:
            agents = [a for a in self.agents.values() if a["agent_type"] == agent_type and a["status"] == "active"]
        else:
            agents = [a for a in self.agents.values() if a["status"] == "active"]
        
        if not agents:
            return {"error": "No active agents available"}

        selected = min(agents, key=lambda a: a.get("task_count", 0))
        task_id = f"swarm-task-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}-{hash(str(payload)) % 10000}"
        
        selected["task_count"] += 1
        self.assigned_tasks[task_id] = {"agent_id": selected["agent_id"], "task_type": task_type, "payload": payload}
        
        logger.info(f"Task {task_id} assigned to {selected['agent_id']} ({selected['agent_type']})")
        return {"task_id": task_id, "agent_id": selected["agent_id"], "platform": selected["platform"]}

    def broadcast_task(self, task_type, payload):
        active_agents = [a for a in self.agents.values() if a["status"] == "active"]
        results = []
        
        def execute(agent):
            try:
                platform_url = self._get_platform_url(agent["platform"])
                r = requests.post(f"{platform_url}/api/task", json={"task_type": task_type, "payload": payload}, timeout=120)
                r.raise_for_status()
                return {"agent_id": agent["agent_id"], "platform": agent["platform"], "status": "success", "result": r.json()}
            except Exception as e:
                return {"agent_id": agent["agent_id"], "platform": agent["platform"], "status": "failed", "error": str(e)}
        
        with ThreadPoolExecutor(max_workers=len(active_agents)) as executor:
            futures = [executor.submit(execute, agent) for agent in active_agents]
            for future in futures:
                try:
                    results.append(future.result())
                except Exception as e:
                    results.append({"error": str(e)})
        
        return {"task_type": task_type, "results": results, "count": len(results)}

    def get_swarm_status(self):
        return {
            "swarm_mode": True,
            "total_agents": len(self.agents),
            "active_agents": sum(1 for a in self.agents.values() if a["status"] == "active"),
            "busy_agents": sum(1 for a in self.agents.values() if a["task_count"] > 0),
            "assigned_tasks": len(self.assigned_tasks),
            "agent_types": list(set(a["agent_type"] for a in self.agents.values())),
            "agents": {aid: agent for aid, agent in self.agents.items()},
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    def scale_swarm(self, target_count):
        current = len(self.agents)
        if target_count > self.max_agents:
            return {"error": f"Cannot exceed {self.max_agents} agents"}
        
        if target_count > current:
            return self.spawn_agents(target_count - current)
        return {"swarm_size": current, "target": target_count, "no_change_needed": True}

def main():
    coordinator = SwarmCoordinator()
    
    # Spawn initial agents
    coordinator.spawn_agents(2, "coder")
    coordinator.spawn_agents(1, "debugger")
    coordinator.spawn_agents(1, "planner")
    coordinator.spawn_agents(1, "reviewer")
    coordinator.spawn_agents(1, "researcher")
    coordinator.spawn_agents(1, "executor")
    
    logger.info(f"Swarm initialized with {len(coordinator.agents)} agents")
    
    while True:
        status = coordinator.get_swarm_status()
        healthy = sum(1 for a in status["agents"].values() if a["status"] == "active")
        logger.info(f"Swarm: {healthy}/{len(status['agents'])} agents active, {status['assigned_tasks']} tasks assigned")
        time.sleep(60)

if __name__ == "__main__":
    main()
