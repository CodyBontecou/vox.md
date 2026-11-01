#!/usr/bin/env python3
"""Wait for Android's asynchronous radio transitions before model qualification."""
import re
import time


def network_state_matches(snapshot: str, online: bool) -> bool:
    active = re.search(r"^Active default network: (none|\d+)\s*$", snapshot, re.M)
    if active is None: return False
    if not online: return active.group(1) == "none"
    if active.group(1) == "none": return False
    prefix = "NetworkAgentInfo{network{" + active.group(1) + "}"
    return any(prefix in line and re.search(r"(?<![A-Z_])INTERNET(?![A-Z_])", line)
               and re.search(r"(?<![A-Z_])VALIDATED(?![A-Z_])", line) for line in snapshot.splitlines())


def wait_for_network_state(read_snapshot, *, online: bool, timeout: float = 45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if network_state_matches(read_snapshot(), online): return
        time.sleep(0.5)
    raise SystemExit("Android model fixture network did not become " + ("validated online" if online else "offline"))
