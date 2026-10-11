# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded literal records and immutable, verified SAM owner identity."""
from dataclasses import dataclass
from typing import Mapping, Optional, Tuple
import os
import stat


def read_literal_file(path):
    """Read a bounded regular literal file; reject duplicate identity fields."""
    descriptor = None
    try:
        flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return {}
        data = os.read(descriptor, 16385)
        if len(data) > 16384:
            return {}
        record = {}
        for line in data.decode("utf-8").splitlines():
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key in record and key in {"pid", "start", "owner_pid", "owner_start"}:
                return {}
            record[key] = value
        return record
    except (OSError, UnicodeError):
        return {}
    finally:
        if descriptor is not None:
            os.close(descriptor)


@dataclass(frozen=True, eq=False)
class SessionSnapshot(Mapping[str, str]):
    pid: str
    start: str
    phase: str = ""
    launch: str = "0"

    def __getitem__(self, key):
        if key not in ("pid", "start", "phase", "launch"):
            raise KeyError(key)
        return getattr(self, key)

    def __iter__(self):
        return iter(("pid", "start", "phase", "launch"))

    def __len__(self):
        return 4

    @property
    def key(self) -> Tuple[str, str]:
        return self.pid, self.start

    @classmethod
    def from_record(cls, record: Mapping[str, str]):
        return cls(record["pid"], record["start"], record.get("phase", ""), record.get("launch", "0"))

    def as_record(self):
        return dict(pid=self.pid, start=self.start, phase=self.phase, launch=self.launch)


def read_session(owner_path: str, proc_root: str = "/proc") -> Optional[SessionSnapshot]:
    record = read_literal_file(owner_path)
    pid, ticks = record.get("pid", ""), record.get("start", "")
    if not (1 <= len(pid) <= 20 and 1 <= len(ticks) <= 20) or not pid.isascii() or not ticks.isascii() or not pid.isdecimal() or int(pid) <= 1 or not ticks.isdecimal():
        return None
    try:
        with open(os.path.join(proc_root, pid, "stat")) as stream:
            process_stat = stream.read(4097)
        if len(process_stat) > 4096 or not process_stat.startswith(pid + " ("):
            return None
        fields = process_stat.rsplit(") ", 1)[1].split()
        if fields[0] not in {"R", "S", "D", "T", "t", "K", "W", "I", "P"} or fields[19] != ticks:
            return None
    except (OSError, UnicodeError, IndexError):
        return None
    return SessionSnapshot.from_record(record)


def owner_key(owner):
    if isinstance(owner, SessionSnapshot):
        return owner.key
    return (owner["pid"], owner["start"]) if owner else None


def session_is_m82(owner, configured, status):
    if owner and status.get("active") == "yes" and (status.get("owner_pid"), status.get("owner_start")) == owner_key(owner) and status.get("mode") in {"normal", "roulette", "m82", "samvideo"}:
        return status["mode"] == "m82"
    return configured
