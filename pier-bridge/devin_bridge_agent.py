"""
DevinBridgeAgent — a cooperative Pier agent that bridges to an interactive Devin session.

Protocol (file-based, host filesystem at /tmp/pier-bridge/<session_id>/):
  - instruction.txt : agent writes the task instruction
  - command.txt     : Devin writes a shell command to run in the container
  - output.json     : agent writes {"stdout", "stderr", "return_code"}
  - status          : single line: INSTRUCTION_READY, COMMAND_READY, OUTPUT_READY, DONE
  - done            : empty file Devin creates to signal completion

The agent polls for commands, executes them in the container via environment.exec(),
records each as an ATIF Step, and saves the full trajectory when done.
"""

import json
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from pier.agents.base import BaseAgent
from pier.environments.base import BaseEnvironment
from pier.models.agent.context import AgentContext
from pier.models.trajectories import (
    Agent,
    FinalMetrics,
    Metrics,
    Observation,
    ObservationResult,
    Step,
    ToolCall,
    Trajectory,
)
from pier.utils.logger import logger


BRIDGE_ROOT = Path("/tmp/pier-bridge")


class DevinBridgeAgent(BaseAgent):
    """Cooperative agent that bridges to an interactive Devin session via files."""

    SUPPORTS_ATIF: bool = True
    SUPPORTS_WINDOWS: bool = False

    def __init__(
        self,
        logs_dir: Path,
        model_name: str | None = None,
        agent_timeout_sec: float | None = None,
        **kwargs,
    ):
        super().__init__(logs_dir=logs_dir, model_name=model_name, **kwargs)
        self._timeout_sec = agent_timeout_sec
        self._steps: list[Step] = []
        self._step_id = 0
        self._session_id = str(uuid.uuid4())[:8]
        self._bridge_dir = BRIDGE_ROOT / self._session_id
        self._start_time: float | None = None

    @staticmethod
    def name() -> str:
        return "devin-bridge"

    def version(self) -> str | None:
        return "1.0.0"

    async def setup(self, environment: BaseEnvironment) -> None:
        """No setup needed — the bridge is file-based on the host."""
        self.logger.info(f"DevinBridgeAgent setup, bridge_dir={self._bridge_dir}")
        return

    def _write_status(self, status: str) -> None:
        (self._bridge_dir / "status").write_text(status)

    def _wait_for_status(self, expected: str, timeout: float) -> bool:
        """Poll for a specific status. Returns True if found, False on timeout."""
        status_file = self._bridge_dir / "status"
        deadline = time.time() + timeout
        while time.time() < deadline:
            if status_file.exists():
                content = status_file.read_text().strip()
                if content == expected:
                    return True
            time.sleep(0.5)
        return False

    def _record_step(
        self,
        command: str,
        stdout: str,
        stderr: str,
        return_code: int,
        timestamp: str,
    ) -> None:
        """Record a single command+output as an ATIF Step."""
        self._step_id += 1

        # ToolCall: the shell command
        tool_call = ToolCall(
            tool_call_id=f"call-{self._step_id}",
            function_name="shell",
            arguments={"command": command},
        )

        # Observation: the command output
        obs_result = ObservationResult(
            content=f"exit_code={return_code}\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}",
        )
        observation = Observation(results=[obs_result])

        # Step
        step = Step(
            step_id=self._step_id,
            timestamp=timestamp,
            source="agent",
            model_name=self.model_name or "devin-bridge",
            message=command,
            tool_calls=[tool_call],
            observation=observation,
            llm_call_count=0,  # No LLM API call — cooperative execution
        )
        self._steps.append(step)

    async def run(
        self,
        instruction: str,
        environment: BaseEnvironment,
        context: AgentContext,
    ) -> None:
        """Bridge loop: write instruction, poll for commands, execute, record."""
        self._start_time = time.time()
        self._bridge_dir.mkdir(parents=True, exist_ok=True)

        # Write instruction for Devin to read
        (self._bridge_dir / "instruction.txt").write_text(instruction)
        self._write_status("INSTRUCTION_READY")
        self.logger.info(f"DevinBridge: instruction written to {self._bridge_dir}/instruction.txt")

        # Determine timeout
        timeout = self._timeout_sec or 5400.0  # Default 90 min
        deadline = time.time() + timeout

        # Main loop: poll for commands, execute, record
        while time.time() < deadline:
            # Check for done signal
            done_file = self._bridge_dir / "done"
            if done_file.exists():
                self.logger.info("DevinBridge: done signal received")
                break

            # Wait for a command (poll with 2s timeout, then re-check done/deadline)
            if not self._wait_for_status("COMMAND_READY", timeout=2.0):
                continue

            # Read the command
            command_file = self._bridge_dir / "command.txt"
            if not command_file.exists():
                continue

            command = command_file.read_text()
            command_file.unlink()  # Consume the command

            self.logger.info(f"DevinBridge: executing command ({len(command)} chars)")

            # Execute in the container
            try:
                result = await environment.exec(command)
                stdout = result.stdout or ""
                stderr = result.stderr or ""
                return_code = result.return_code
            except Exception as e:
                stdout = ""
                stderr = f"Bridge execution error: {e}"
                return_code = -1

            # Write output for Devin to read
            output_data = {
                "stdout": stdout,
                "stderr": stderr,
                "return_code": return_code,
            }
            (self._bridge_dir / "output.json").write_text(json.dumps(output_data))
            self._write_status("OUTPUT_READY")

            # Record the step
            ts = datetime.now(timezone.utc).isoformat()
            self._record_step(command, stdout, stderr, return_code, ts)

        # Save the trajectory
        self._save_trajectory()

        # Populate context
        self._populate_context(context)

        self._write_status("DONE")

    def _save_trajectory(self) -> None:
        """Build and save the ATIF trajectory to logs_dir/trajectory.json."""
        if not self._steps:
            # Create a minimal step if no commands were run
            self._step_id += 1
            self._steps.append(
                Step(
                    step_id=self._step_id,
                    timestamp=datetime.now(timezone.utc).isoformat(),
                    source="agent",
                    model_name=self.model_name or "devin-bridge",
                    message="(no commands executed)",
                    llm_call_count=0,
                )
            )

        elapsed = time.time() - (self._start_time or time.time())

        agent = Agent(
            name="devin-bridge",
            version="1.0.0",
            model_name=self.model_name or "devin-bridge",
        )

        final_metrics = FinalMetrics(
            total_steps=len(self._steps),
            total_prompt_tokens=None,  # Not applicable — cooperative, no API
            total_completion_tokens=None,
            total_cached_tokens=None,
            total_cost_usd=None,  # No API cost — flat-rate session
            extra={
                "harness": "Devin",
                "bridge_protocol": "file-based-cooperative",
                "wall_clock_seconds": round(elapsed, 2),
                "note": "Token counts and cost not applicable — cooperative agent driven by interactive Devin session, not LLM API calls.",
            },
        )

        trajectory = Trajectory(
            schema_version="ATIF-v1.7",
            session_id=self._session_id,
            agent=agent,
            steps=self._steps,
            final_metrics=final_metrics,
            notes="Cooperative Devin-Pier bridge trajectory. Agent executed commands in container via file-based protocol with interactive Devin session. Step counts and wall-clock timing are real; token/cost metrics are not applicable (no LLM API calls).",
        )

        trajectory_path = self.logs_dir / "trajectory.json"
        trajectory_path.parent.mkdir(parents=True, exist_ok=True)
        trajectory_path.write_text(
            json.dumps(trajectory.to_json_dict(), indent=2)
        )
        self.logger.info(f"DevinBridge: trajectory saved to {trajectory_path} ({len(self._steps)} steps)")

    def populate_context_post_run(self, context: AgentContext) -> None:
        """Populate AgentContext with metrics from the bridge run."""
        self._populate_context(context)

    def _populate_context(self, context: AgentContext) -> None:
        """Fill in the AgentContext with what we know."""
        context.n_agent_steps = len(self._steps)
        context.n_input_tokens = None  # Not applicable
        context.n_cache_tokens = None
        context.n_output_tokens = None
        context.cost_usd = None  # No API cost
        context.peak_context_tokens = None
        context.summarization_count = None
        if self._start_time:
            elapsed = time.time() - self._start_time
            context.metadata = {
                "harness": "Devin",
                "bridge_protocol": "file-based-cooperative",
                "wall_clock_seconds": round(elapsed, 2),
                "note": "Cooperative agent — token/cost metrics not applicable.",
            }
