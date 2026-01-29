"""
Mock AI Agent - Simula Neoland/AI-OS-Agent enviando bundles para Phantom

Este módulo simula o comportamento do Neoland (AI-OS-Agent) gerando
bundles de telemetria do sistema e enviando para o Phantom Judge API
para análise e recomendações.

Arquitetura:
    Neoland (Agent) → Bundle Generator → PhantomGate (HTTP) → Judge API

Features:
- Geração de bundles baseados em cenários reais
- Simulação de workloads (idle, compilation, stress)
- Integração com métricas do sistema real (psutil)
- Rate limiting e backoff
- Logging estruturado
"""

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, Any, List, Optional
import random

import httpx


# ========================================
# Configuration
# ========================================

PHANTOM_BASE_URL = "http://localhost:8000"
DEFAULT_TIMEOUT = 30.0
MAX_RETRIES = 3
RETRY_BACKOFF = [1, 2, 4]  # seconds

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("mock_ai_agent")


# ========================================
# Workload Scenarios
# ========================================

class WorkloadType(Enum):
    """Tipos de workload que o agente pode simular."""
    IDLE = "idle"
    DEVELOPMENT = "development"
    COMPILATION = "compilation"
    NIXOS_REBUILD = "nixos_rebuild"
    DOCKER_BUILD = "docker_build"
    STRESS_TEST = "stress_test"


@dataclass
class WorkloadProfile:
    """Perfil de carga de trabalho com características específicas."""
    name: str
    cpu_range: tuple[float, float]  # (min, max) percentage
    memory_range: tuple[float, float]  # (min, max) percentage
    temp_range: tuple[float, float]  # (min, max) celsius
    load_avg_range: tuple[float, float]  # (min, max) load
    alert_probability: float  # 0.0 - 1.0


# Profiles baseados em observações reais do Neoland
WORKLOAD_PROFILES = {
    WorkloadType.IDLE: WorkloadProfile(
        name="idle",
        cpu_range=(5.0, 20.0),
        memory_range=(30.0, 50.0),
        temp_range=(45.0, 55.0),
        load_avg_range=(0.5, 1.5),
        alert_probability=0.0
    ),
    WorkloadType.DEVELOPMENT: WorkloadProfile(
        name="development",
        cpu_range=(30.0, 60.0),
        memory_range=(50.0, 75.0),
        temp_range=(55.0, 68.0),
        load_avg_range=(2.0, 4.0),
        alert_probability=0.1
    ),
    WorkloadType.COMPILATION: WorkloadProfile(
        name="compilation",
        cpu_range=(70.0, 95.0),
        memory_range=(60.0, 85.0),
        temp_range=(70.0, 80.0),
        load_avg_range=(6.0, 10.0),
        alert_probability=0.4
    ),
    WorkloadType.NIXOS_REBUILD: WorkloadProfile(
        name="nixos_rebuild",
        cpu_range=(85.0, 98.0),
        memory_range=(75.0, 92.0),
        temp_range=(78.0, 85.0),
        load_avg_range=(8.0, 14.0),
        alert_probability=0.7
    ),
    WorkloadType.DOCKER_BUILD: WorkloadProfile(
        name="docker_build",
        cpu_range=(75.0, 90.0),
        memory_range=(70.0, 88.0),
        temp_range=(72.0, 82.0),
        load_avg_range=(7.0, 12.0),
        alert_probability=0.5
    ),
    WorkloadType.STRESS_TEST: WorkloadProfile(
        name="stress_test",
        cpu_range=(95.0, 100.0),
        memory_range=(85.0, 95.0),
        temp_range=(82.0, 90.0),
        load_avg_range=(12.0, 20.0),
        alert_probability=0.95
    )
}


# ========================================
# Bundle Generator
# ========================================

class BundleGenerator:
    """
    Gera bundles de telemetria baseados em workload profiles.

    Similar ao que o Neoland faria ao monitorar o sistema e
    enviar dados para o Phantom para análise.
    """

    def __init__(self, hostname: str = "neoland-agent"):
        self.hostname = hostname
        self.bundle_counter = 0

    def generate(
        self,
        workload: WorkloadType,
        add_noise: bool = True
    ) -> Dict[str, Any]:
        """
        Gera um bundle baseado no workload type.

        Args:
            workload: Tipo de carga de trabalho
            add_noise: Adiciona variação aleatória às métricas

        Returns:
            Bundle JSON completo pronto para enviar ao Phantom
        """
        profile = WORKLOAD_PROFILES[workload]
        self.bundle_counter += 1

        # Generate metrics with noise
        cpu_usage = self._sample(profile.cpu_range, add_noise)
        memory_usage = self._sample(profile.memory_range, add_noise)
        temperature = self._sample(profile.temp_range, add_noise)
        load_avg = self._sample(profile.load_avg_range, add_noise)

        # Build bundle
        bundle = {
            "timestamp": int(time.time()),
            "hostname": f"{self.hostname}-{self.bundle_counter}",
            "metrics": {
                "cpu": {
                    "usage_percent": cpu_usage,
                    "cores": self._generate_core_usage(cpu_usage, 4),
                    "temperature_celsius": temperature
                },
                "memory": {
                    "total_bytes": 16000000000,
                    "used_bytes": int(16000000000 * memory_usage / 100),
                    "usage_percent": memory_usage,
                    "available_bytes": int(16000000000 * (100 - memory_usage) / 100),
                    "swap_total_bytes": 8000000000,
                    "swap_used_bytes": int(8000000000 * max(0, (memory_usage - 80) / 20)),
                    "swap_usage_percent": max(0, (memory_usage - 80) * 5)
                },
                "thermal": {
                    "max_temp_celsius": temperature,
                    "avg_temp_celsius": temperature - random.uniform(2, 5),
                    "critical_threshold": 75.0,
                    "cores": self._generate_core_temps(temperature, 4)
                },
                "disk": {
                    "total_bytes": 512000000000,
                    "used_bytes": int(512000000000 * random.uniform(0.5, 0.85)),
                    "usage_percent": random.uniform(50.0, 85.0)
                }
            },
            "alerts": self._generate_alerts(profile, cpu_usage, memory_usage, temperature),
            "logs": self._generate_logs(workload, temperature),
            "context": {
                "workload": profile.name,
                "uptime_seconds": random.randint(600, 86400),
                "load_average": [
                    load_avg,
                    load_avg * 0.9,
                    load_avg * 0.8
                ],
                "neoland_active": True,
                "agent_version": "2.0.0"
            }
        }

        return bundle

    def _sample(self, range_tuple: tuple[float, float], add_noise: bool) -> float:
        """Sample value from range with optional noise."""
        min_val, max_val = range_tuple
        base_val = random.uniform(min_val, max_val)

        if add_noise:
            noise = random.uniform(-2, 2)
            return max(min_val, min(max_val, base_val + noise))

        return base_val

    def _generate_core_usage(self, avg_usage: float, num_cores: int) -> List[float]:
        """Generate per-core CPU usage centered around average."""
        return [
            max(0, min(100, avg_usage + random.uniform(-10, 10)))
            for _ in range(num_cores)
        ]

    def _generate_core_temps(self, avg_temp: float, num_cores: int) -> List[float]:
        """Generate per-core temperatures centered around average."""
        return [
            max(30, avg_temp + random.uniform(-3, 3))
            for _ in range(num_cores)
        ]

    def _generate_alerts(
        self,
        profile: WorkloadProfile,
        cpu_usage: float,
        memory_usage: float,
        temperature: float
    ) -> List[Dict[str, Any]]:
        """Generate alerts based on metrics and probability."""
        alerts = []

        # Should we generate an alert?
        if random.random() > profile.alert_probability:
            return alerts

        timestamp = int(time.time())

        # Temperature alert (priority)
        if temperature > 75:
            severity = "Critical" if temperature > 80 else "Warning"
            alerts.append({
                "timestamp": timestamp,
                "severity": severity,
                "category": "Thermal",
                "message": f"Temperature {severity.lower()}: {temperature:.1f}°C",
                "details": f"CPU temperature {'dangerously high' if severity == 'Critical' else 'above threshold'}. System may throttle.",
                "source": "neoland_thermal_monitor"
            })

        # Memory alert
        if memory_usage > 85:
            alerts.append({
                "timestamp": timestamp,
                "severity": "Warning",
                "category": "Memory",
                "message": f"Memory usage high: {memory_usage:.1f}%",
                "details": "Memory pressure detected. Consider closing applications.",
                "source": "neoland_memory_monitor"
            })

        # CPU alert
        if cpu_usage > 90:
            alerts.append({
                "timestamp": timestamp,
                "severity": "Info",
                "category": "CPU",
                "message": f"CPU usage high: {cpu_usage:.1f}%",
                "details": f"High CPU load detected. Workload: {profile.name}",
                "source": "neoland_cpu_monitor"
            })

        return alerts

    def _generate_logs(self, workload: WorkloadType, temperature: float) -> List[Dict[str, str]]:
        """Generate relevant log entries."""
        logs = []
        timestamp = int(time.time())

        if workload == WorkloadType.NIXOS_REBUILD:
            logs.extend([
                {"timestamp": timestamp - 30, "level": "INFO", "message": "Starting nixos-rebuild switch"},
                {"timestamp": timestamp - 15, "level": "WARNING", "message": "Building system configuration..."},
            ])

        if temperature > 75:
            logs.append({
                "timestamp": timestamp,
                "level": "WARNING" if temperature < 80 else "ERROR",
                "message": f"CPU temperature: {temperature:.1f}°C"
            })

        return logs


# ========================================
# AI Agent Client
# ========================================

class AIAgentClient:
    """
    Cliente que simula o Neoland enviando bundles para o Phantom.

    Integra com PhantomGate (HTTP client) para comunicação com Judge API.
    """

    def __init__(
        self,
        phantom_url: str = PHANTOM_BASE_URL,
        timeout: float = DEFAULT_TIMEOUT
    ):
        self.phantom_url = phantom_url
        self.timeout = timeout
        self.generator = BundleGenerator()
        self.client = httpx.AsyncClient(
            base_url=phantom_url,
            timeout=timeout
        )

    async def send_bundle(
        self,
        workload: WorkloadType,
        retry: bool = True
    ) -> Optional[Dict[str, Any]]:
        """
        Envia bundle para Phantom Judge API.

        Args:
            workload: Tipo de workload para gerar bundle
            retry: Se deve fazer retry em caso de falha

        Returns:
            Response do Phantom ou None se falhou
        """
        bundle = self.generator.generate(workload)

        logger.info(f"Sending bundle: workload={workload.value}, hostname={bundle['hostname']}")

        attempts = MAX_RETRIES if retry else 1

        for attempt in range(attempts):
            try:
                response = await self.client.post("/judge", json=bundle)

                if response.status_code == 200:
                    logger.info(f"✓ Bundle accepted: {response.status_code}")
                    return response.json()
                else:
                    logger.warning(f"⚠ Bundle rejected: {response.status_code}")

            except httpx.TimeoutException:
                logger.error(f"⏱ Timeout on attempt {attempt + 1}/{attempts}")
            except Exception as e:
                logger.error(f"❌ Error on attempt {attempt + 1}/{attempts}: {e}")

            # Backoff before retry
            if attempt < attempts - 1:
                backoff = RETRY_BACKOFF[attempt]
                logger.info(f"Retrying in {backoff}s...")
                await asyncio.sleep(backoff)

        return None

    async def simulate_workload_sequence(
        self,
        workloads: List[WorkloadType],
        interval: float = 2.0
    ) -> List[Dict[str, Any]]:
        """
        Simula sequência de workloads enviando bundles.

        Args:
            workloads: Lista de workloads para simular em ordem
            interval: Intervalo entre bundles em segundos

        Returns:
            Lista de responses do Phantom
        """
        responses = []

        for workload in workloads:
            response = await self.send_bundle(workload)
            if response:
                responses.append(response)

            await asyncio.sleep(interval)

        return responses

    async def close(self):
        """Fecha cliente HTTP."""
        await self.client.aclose()


# ========================================
# Example Usage
# ========================================

async def main():
    """Exemplo de uso do mock agent."""
    agent = AIAgentClient()

    # Simular workload progressivo: idle → development → compilation → thermal spike
    workload_sequence = [
        WorkloadType.IDLE,
        WorkloadType.DEVELOPMENT,
        WorkloadType.COMPILATION,
        WorkloadType.NIXOS_REBUILD,  # Deve gerar alerta térmico
    ]

    logger.info("Starting workload simulation...")
    responses = await agent.simulate_workload_sequence(workload_sequence, interval=3.0)

    logger.info(f"\nReceived {len(responses)} responses from Phantom:")
    for i, resp in enumerate(responses, 1):
        severity = resp.get("severity", "unknown")
        insights_count = len(resp.get("insights", []))
        logger.info(f"  {i}. Severity: {severity}, Insights: {insights_count}")

    await agent.close()


if __name__ == "__main__":
    asyncio.run(main())
