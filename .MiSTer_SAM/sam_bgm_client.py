#!/usr/bin/env python3
"""Bounded optional BGM policy client. State belongs in SAM's RAM directory."""
import argparse
import json
import os
import re
import socket
import sys
import time
import uuid


class ProtocolError(Exception):
    pass


def exchange(path, payload, framed=True, timeout=1.5):
    deadline = time.monotonic() + timeout
    data = bytearray()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(timeout)
        conn.connect(path)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ProtocolError("request deadline exceeded")
        conn.settimeout(remaining)
        conn.sendall(payload)
        conn.shutdown(socket.SHUT_WR)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProtocolError("reply deadline exceeded")
            conn.settimeout(remaining)
            chunk = conn.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > 65536:
                raise ProtocolError("reply too large")
            if framed and b"\n" in data:
                break
    if not data and framed:
        raise ProtocolError("empty reply")
    if framed:
        if b"\n" not in data:
            raise ProtocolError("unterminated reply")
        return json.loads(data.split(b"\n", 1)[0])
    return data.decode("utf-8").strip()


def save(path, state):
    temp = path + ".tmp." + str(os.getpid())
    try:
        with open(temp, "w", encoding="utf-8") as output:
            json.dump(state, output, separators=(",", ":"))
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def policy(path, state_path, identity, owner, mode):
    try:
        with open(state_path, encoding="utf-8") as source:
            state = json.load(source)
    except (OSError, ValueError):
        state = {}
    if state.get("identity") != identity:
        state = {"identity": identity, "revision": 0}
    if "capable" not in state:
        # This readonly legacy command is safe on older BGM implementations.
        try:
            capability = exchange(path, b"capabilities", framed=False)
            advertised = json.loads(capability)
            state["capable"] = (isinstance(advertised, dict) and advertised.get("v") == 2
                                and advertised.get("policy") is True
                                and advertised.get("framing") == "json-line")
        except ValueError:
            state["capable"] = False
        save(state_path, state)
    if not state["capable"]:
        return 3  # Caller must use its existing legacy path.
    if not re.fullmatch(r"[1-9][0-9]*:[0-9]+", owner):
        raise ProtocolError("missing verified SAM session owner")
    previous = state.get("request", {})
    if previous.get("owner") != owner or previous.get("mode") != mode:
        state["revision"] += 1
        state["request"] = {"v": 2, "id": uuid.uuid4().hex, "action": "policy",
                            "owner": owner, "revision": state["revision"], "mode": mode}
        state["acknowledged"] = False
        save(state_path, state)  # Retry lost replies with the same request.
    if state.get("acknowledged"):
        return 0
    request = state["request"]
    response = exchange(path, (json.dumps(request) + "\n").encode("utf-8"))
    if not isinstance(response, dict) or response.get("v") != 2 or response.get("id") != request["id"]:
        raise ProtocolError("mismatched policy reply")
    if response.get("ok") is not True or response.get("applied") is not True:
        raise ProtocolError(str(response.get("error") or "policy was not applied"))
    state["acknowledged"] = True
    save(state_path, state)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--owner", default="")
    parser.add_argument("--mode", required=True, choices=("active", "menu", "game"))
    args = parser.parse_args()
    try:
        return policy(args.socket, args.state, args.identity, args.owner, args.mode)
    except (OSError, ValueError, KeyError, TypeError, ProtocolError) as error:
        print("SAM BGM policy: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
