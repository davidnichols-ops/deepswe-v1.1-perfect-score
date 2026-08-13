#!/usr/bin/env python3
"""
Devin bridge client — used by the interactive Devin session to communicate
with the DevinBridgeAgent running inside Pier.

Usage:
    from devin_bridge_client import DevinBridgeClient
    client = DevinBridgeClient(session_id)
    instruction = client.wait_for_instruction()
    output = client.run_command("ls -la")
    client.signal_done()
"""

import json
import time
from pathlib import Path

BRIDGE_ROOT = Path("/tmp/pier-bridge")


class DevinBridgeClient:
    def __init__(self, session_id: str, timeout: float = 7200.0):
        self.session_id = session_id
        self.bridge_dir = BRIDGE_ROOT / session_id
        self.timeout = timeout

    def wait_for_instruction(self) -> str:
        """Wait for the agent to write the instruction."""
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            status_file = self.bridge_dir / "status"
            if status_file.exists():
                status = status_file.read_text().strip()
                if status == "INSTRUCTION_READY":
                    return (self.bridge_dir / "instruction.txt").read_text()
            time.sleep(0.5)
        raise TimeoutError("No instruction received from bridge agent")

    def run_command(self, command: str, timeout: float = 300.0) -> dict:
        """Send a command to the agent and wait for the output."""
        # Write the command
        (self.bridge_dir / "command.txt").write_text(command)
        (self.bridge_dir / "status").write_text("COMMAND_READY")

        # Wait for output
        deadline = time.time() + timeout
        while time.time() < deadline:
            status_file = self.bridge_dir / "status"
            if status_file.exists():
                status = status_file.read_text().strip()
                if status == "OUTPUT_READY":
                    output = json.loads(
                        (self.bridge_dir / "output.json").read_text()
                    )
                    return output
            time.sleep(0.5)
        raise TimeoutError(f"No output received for command within {timeout}s")

    def signal_done(self) -> None:
        """Signal to the agent that the task is complete."""
        (self.bridge_dir / "done").touch()
        (self.bridge_dir / "status").write_text("DONE")

    def cleanup(self) -> None:
        """Remove the bridge directory."""
        import shutil
        if self.bridge_dir.exists():
            shutil.rmtree(self.bridge_dir)
