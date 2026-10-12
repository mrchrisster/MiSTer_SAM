"""Research-only readiness contract; no MiSTer commands or device access.

These checks identify a fresh transport after a load. They cannot prove that a
game booted, that Main parsed a command, or that volume was applied to FPGA.
"""
from dataclasses import dataclass
from typing import Tuple


@dataclass(frozen=True)
class Observation:
    core: str
    main: Tuple[str, str]
    fifo: Tuple[int, int]
    marker: Tuple[int, int, int]
    writable: bool


def fresh_transport(before, after, expected_core):
    return bool(after.core == expected_core and after.writable
                and after.main != before.main and after.fifo != before.fifo
                and after.marker != before.marker)


def retry_class(action):
    """Only desired states can be retried; do not replay toggles/navigation."""
    if action in ('return_menu', 'set_muted', 'set_unmuted'):
        return 'bounded_desired_state'
    return 'no_blind_retry'
