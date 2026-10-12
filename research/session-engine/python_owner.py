#!/usr/bin/env python3
"""RESEARCH mock: replace the Bash owner, keeping the same mailbox and mode data.

The two child roles execute only this file's fixed mock functions. No hardware,
physical-input, arbitrary-command, network, or production-module path exists.
"""
import os
import signal
import stat
import sys
import time

SOURCE_ROOT = os.path.dirname(os.path.abspath(__file__))
SAFE = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-")
MODES = ("normal", "m82", "commercial")


def literal(value, limit=96):
    return bool(value) and len(value) <= limit and all(c in SAFE for c in value)


def number(value, limit=6):
    return bool(value) and len(value) <= limit and all(c in "0123456789" for c in value)


def read_data(path, limit=512):
    """Bound the read; reject FIFO/symlink before opening or parsing data."""
    fd = None
    try:
        info = os.lstat(path)
        if not stat.S_ISREG(info.st_mode):
            return None
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        data = os.read(fd, limit + 1)
        if len(data) > limit:
            return None
        return data.decode("ascii")
    except (OSError, UnicodeError):
        return None
    finally:
        if fd is not None:
            os.close(fd)


def row(path, fields):
    text = read_data(path)
    if text is None or not text.endswith("\n") or text.count("\n") != 1:
        return None
    values = text[:-1].split("\t")
    return values if len(values) == fields else None


def write_data(path, text, atomic=False):
    target = path + ".tmp." + str(os.getpid()) if atomic else path
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    fd = os.open(target, flags, 0o600)
    try:
        data = text.encode("ascii")
        while data:
            data = data[os.write(fd, data):]
    finally:
        os.close(fd)
    if atomic:
        os.replace(target, path)


def unlink(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    except IsADirectoryError:
        pass  # Never recursively remove malformed fixture paths.


def identity(pid):
    try:
        with open("/proc/{}/stat".format(pid), "r") as stream:
            fields = stream.read(2048).rsplit(") ", 1)[1].split()
        if fields[0] in ("Z", "X", "x"):
            return None
        return (str(fields[19]), int(fields[2]), int(fields[3]), int(fields[1]))
    except (OSError, ValueError, IndexError):
        return None


def fixture_root():
    root = os.environ.get("TMP_ROOT", "")
    suffix = root[len("/tmp/sam-session-research-"):]
    allowed = SAFE - frozenset(".:")
    marker = read_data(root + "/RESEARCH_MOCK_ONLY")
    if (not root.startswith("/tmp/sam-session-research-") or not suffix or
            not all(c in allowed for c in suffix) or os.path.islink(root) or
            not os.path.isdir(root) or marker is None or marker.rstrip("\n") != "SAM_SESSION_RESEARCH_V1"):
        raise ValueError("private marked TMP_ROOT required")
    return root


def delay(value):
    pieces = value.split(".")
    if (len(pieces) > 2 or not number(pieces[0], 2) or
            (len(pieces) == 2 and not number(pieces[1], 3)) or not 0 <= float(value) <= 30):
        raise ValueError("delay must be a literal 0..30")
    return float(value)


def mode_data(mode):
    if mode not in MODES:
        raise ValueError("unknown mode")
    text = read_data(SOURCE_ROOT + "/modes/" + mode + ".tsv", 16384)
    if text is None:
        raise ValueError("unreadable mode")
    policy, items = {}, []
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[0] == "policy":
            policy[parts[1]] = parts[2]
        elif len(parts) == 4 and parts[0] == "item":
            items.append(tuple(parts[1:]))
    for key in ("input_transition", "input_demo", "input_play"):
        if policy.get(key) not in ("ignore", "stop", "play", "advance"):
            raise ValueError("invalid input policy")
    if policy.get("ui") not in ("pause", "continue"):
        raise ValueError("invalid UI policy")
    for key in ("demo_timer", "play_timer"):
        if not number(policy.get(key, "")):
            raise ValueError("invalid timer policy")
    if "PLAY_SECONDS" in os.environ:
        if not number(os.environ["PLAY_SECONDS"]):
            raise ValueError("invalid PLAY_SECONDS")
        policy["play_timer"] = str(int(os.environ["PLAY_SECONDS"]))
    cores = policy.get("cores", "").split(",")
    items = [item for item in items if item[0] in ("game", "bios", "clip") and
             item[1] in cores and item[2].startswith("Fixture_") and literal(item[2])]
    return policy, items


def current(root, owner, ticks, token, epoch):
    ident = identity(int(owner))
    return (ident is not None and ident[0] == ticks and
            row(root + "/owner", 4) == [owner, ticks, token, epoch] and
            read_data(root + "/session") == epoch + ":" + token + "\n")


def child_role(role, args):
    root = fixture_root()
    mode, epoch, token, owner, ticks, wait_seconds, selection = args
    if not number(epoch, 12) or not literal(token) or not number(owner, 12) or not number(ticks, 24):
        raise ValueError("invalid child context")
    policy, items = mode_data(mode)
    wait_seconds = delay(wait_seconds)
    pid = os.getpid()
    ident = identity(pid)
    expected = [role, str(pid), ident[0], str(ident[1]), str(ident[2]), epoch, token, selection]
    gate = root + "/" + role + ".gate"
    until = time.monotonic() + 2
    while row(gate, 8) != expected:
        if time.monotonic() >= until or not current(root, owner, ticks, token, epoch):
            return
        time.sleep(.01)
    if role == "launch":
        time.sleep(wait_seconds)
        if current(root, owner, ticks, token, epoch):
            write_data(root + "/launch.done", "\t".join((epoch, token, selection)) + "\n", True)
            # This fixed role creates no children; the proof is after all its work.
            proof = [epoch, token, selection, str(pid), ident[0], str(ident[1]), str(ident[2])]
            write_data(root + "/launch.finished." + str(pid), "\t".join(proof) + "\n", True)
        return
    if not items:
        write_data(root + "/preparation.failed", "\t".join((epoch, token, "empty_fixture")) + "\n", True)
        return
    index = 0
    while current(root, owner, ticks, token, epoch):
        if index:
            time.sleep(wait_seconds)
        while all(os.path.lexists(root + "/ready/" + str(slot) + ".tsv") for slot in (1, 2)):
            if not current(root, owner, ticks, token, epoch):
                return
            time.sleep(.05)
        if not current(root, owner, ticks, token, epoch):
            return
        slot = 1 if not os.path.lexists(root + "/ready/1.tsv") else 2
        item = items[index % len(items)]
        values = [epoch, token, str(index), epoch + ":" + str(index)] + list(item)
        write_data(root + "/ready/" + str(slot) + ".tsv", "\t".join(values) + "\n", True)
        index += 1


class Job:
    def __init__(self, process, ident, epoch, token, selection):
        self.process, self.pid = process, process.pid
        self.start, self.group, self.sid, self.ppid = ident
        self.epoch, self.token, self.selection = str(epoch), token, selection


class ForkProcess:
    """Only the owner's fixed single-threaded fork jobs; no generic process API."""
    def __init__(self, pid):
        self.pid, self.returncode = pid, None

    def reap(self, flags):
        if self.returncode is None:
            pid, status = os.waitpid(self.pid, flags)
            if pid:
                self.returncode = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -os.WTERMSIG(status)
        return self.returncode

    def poll(self):
        return self.reap(os.WNOHANG)

    def wait(self):
        return self.reap(0)


class Owner:
    def __init__(self, mode, prep_delay, launch_delay):
        self.root = fixture_root()
        self.policy, self.items = mode_data(mode)  # Validate before owner admission.
        self.child_start = os.environ.get("RESEARCH_CHILD_START", "fork")
        if self.child_start not in ("fork", "exec"):
            raise ValueError("invalid RESEARCH_CHILD_START")
        self.mode, self.prep_delay, self.launch_delay = mode, prep_delay, launch_delay
        self.pid = os.getpid()
        self.start_ticks = identity(self.pid)[0]
        self.token = "{}-{}-{}".format(self.pid, self.start_ticks, os.urandom(8).hex())
        os.mkdir(self.root + "/engine.lock", 0o700)
        for directory in ("inbox", "ready", "receipts"):
            os.makedirs(self.root + "/" + directory, mode=0o700, exist_ok=True)
        self.epoch, self.active, self.phase, self.selection = 0, False, "standby", "-"
        self.kind, self.input_role, self.next_pending = "-", "ignore", False
        self.worker, self.launch, self.cleanup = None, None, []
        self.cleanup_blocked, self.running, self.dirty = False, True, True
        self.ui_open, self.ui_lease, self.ui_pid, self.ui_ticks = False, "-", 0, "0"
        self.paused, self.pause_pending, self.closed_leases = False, "-", {}
        self.next_ids, self.plan = [], None
        self.events = open(self.root + "/events.tsv", "w", buffering=1)
        self.publish_owner()
        self.event("engine_ready", mode)
        self.publish_state()

    def event(self, kind, detail="-"):
        self.events.write("{:.6f}\t{}\t{}\t{}\t{}\n".format(time.time(), kind, self.epoch, self.selection, detail))

    def receipt(self, request, stage, status, detail):
        write_data(self.root + "/receipts/" + request + "." + stage,
                   "{:.6f}\t{}\t{}\n".format(time.time(), status, detail))

    def publish_owner(self):
        write_data(self.root + "/owner", "\t".join((str(self.pid), self.start_ticks, self.token, str(self.epoch))) + "\n", True)

    def ready_files(self):
        return [self.root + "/ready/" + name for name in os.listdir(self.root + "/ready") if name.endswith(".tsv")]

    def publish_state(self):
        state = dict(engine_pid=self.pid, engine_start=self.start_ticks, session_token=self.token,
                     session_epoch=self.epoch, mode=self.mode, active=int(self.active), phase=self.phase,
                     selection=self.selection, ready_count=len(self.ready_files()), ui_open=int(self.ui_open),
                     ui_lease=self.ui_lease, paused=int(self.paused), input_role=self.input_role,
                     demo_timer=self.policy["demo_timer"], play_timer=self.policy["play_timer"],
                     worker_pid=self.worker.pid if self.worker else 0, worker_start=self.worker.start if self.worker else 0,
                     launch_pid=self.launch.pid if self.launch else 0, launch_start=self.launch.start if self.launch else 0,
                     cleanup_blocked=int(self.cleanup_blocked))
        write_data(self.root + "/state.tsv", "".join("{}\t{}\n".format(k, v) for k, v in state.items()), True)
        self.dirty = False

    def spawn(self, role, seconds, selection="-"):
        # Fixed internal roles only. Fork experiment avoids interpreter cold start.
        gate = self.root + "/" + role + ".gate"
        unlink(gate)
        context = [self.mode, str(self.epoch), self.token, str(self.pid), self.start_ticks, str(seconds), selection]
        if self.child_start == "exec":
            args = [sys.executable, "-S", os.path.abspath(__file__), "--" + role] + context
            process = subprocess.Popen(args, stdin=subprocess.DEVNULL, start_new_session=True)
        else:
            pid = os.fork()
            if pid == 0:
                try:
                    self.events.close()
                    signal.signal(signal.SIGTERM, signal.SIG_DFL)
                    signal.signal(signal.SIGINT, signal.SIG_DFL)
                    os.setsid()
                    stdin = os.open(os.devnull, os.O_RDONLY)
                    os.dup2(stdin, 0)
                    if stdin != 0:
                        os.close(stdin)
                    child_role(role, context)
                    os._exit(0)
                except BaseException:
                    os._exit(64)
            process = ForkProcess(pid)
        # setsid completes in the child. It cannot publish before this gate;
        # registration waits only a bounded 50 ms, never on preparation work.
        ident = None
        for _ in range(50):
            ident = identity(process.pid)
            if ident is not None and ident[1:] == (process.pid, process.pid, self.pid):
                break
            if process.poll() is not None:
                break
            time.sleep(.001)
        if ident is None or ident[1:] != (process.pid, process.pid, self.pid):
            raise RuntimeError("owned job registration failed")
        job = Job(process, ident, self.epoch, self.token, selection)
        proof = [role, str(job.pid), job.start, str(job.group), str(job.sid), job.epoch, job.token, selection]
        write_data(gate, "\t".join(proof) + "\n", True)
        return job

    def cancel(self, role):
        job = getattr(self, role)
        if job is None:
            return True
        ident = identity(job.pid)
        if ident is not None:
            if ident != (job.start, job.group, job.sid, self.pid):
                self.event("cleanup_identity_rejected", role)
                return False
            try:
                os.killpg(job.group, signal.SIGKILL)
            except OSError:
                self.event("cleanup_signal_failed", role)
                return False
            self.cleanup.append(job)
            self.event("cleanup_signaled", role)
        else:
            expected = [job.epoch, job.token, job.selection, str(job.pid), job.start, str(job.group), str(job.sid)]
            proven = role == "launch" and row(self.root + "/launch.finished." + str(job.pid), 7) == expected
            if not proven:
                for name in os.listdir("/proc"):
                    if name.isdigit():
                        member = identity(int(name))
                        if member is not None and member[1:3] == (job.group, job.sid):
                            self.event("cleanup_identity_rejected", role + ":dead_leader")
                            return False
            job.process.poll()  # Already-dead child only; never a blocking wait.
        unlink(self.root + "/launch.finished." + str(job.pid))
        setattr(self, role, None)
        self.dirty = True
        return True

    def stop(self, reason):
        self.epoch += 1
        write_data(self.root + "/session", "{}:{}\n".format(self.epoch, self.token), True)
        self.next_pending, self.paused, self.pause_pending, self.input_role = False, False, "-", "ignore"
        for request in self.next_ids:
            self.receipt(request, "applied", "rejected", "canceled_by_stop")
        self.next_ids.clear()
        if not self.cancel("launch"):
            self.active, self.phase, self.cleanup_blocked = True, "stopping", True
            self.event("sim_menu_withheld", "unproven_dispatch_cleanup")
            self.publish_owner()
            self.cancel("worker")
            self.dirty = True
            return False
        self.active, self.phase, self.cleanup_blocked = False, "stopped", False
        self.event("sim_menu_intent", reason)
        self.publish_owner()  # Failure and success both publish the recovery epoch.
        if not self.cancel("worker"):
            self.cleanup_blocked, self.dirty = True, True
            return False
        for path in self.ready_files() + [self.root + "/launch.done", self.root + "/preparation.failed"]:
            unlink(path)
        self.dirty = True
        return True

    def start(self):
        if not self.cancel("worker") or not self.cancel("launch"):
            self.cleanup_blocked, self.dirty = True, True
            return False
        if not self.items:
            self.active, self.phase, self.dirty = False, "failed", True
            self.event("preparation_failed", "empty_fixture")
            return False
        for path in self.ready_files() + [self.root + "/launch.done", self.root + "/preparation.failed"]:
            unlink(path)
        self.epoch += 1
        write_data(self.root + "/session", "{}:{}\n".format(self.epoch, self.token), True)
        self.publish_owner()
        self.active, self.phase, self.selection, self.kind = True, "preparing", "-", "-"
        self.input_role, self.next_pending = self.policy["input_transition"], True
        self.pause_pending = self.ui_lease if self.ui_open else "-"
        self.event("session_started", self.mode)
        self.worker = self.spawn("worker", self.prep_delay)
        self.dirty = True
        return True

    def dispatch(self, plan):
        if plan[:3] != [str(self.epoch), self.token, self.selection] or not self.cancel("launch"):
            return False
        self.event("mock_dispatch", ":".join(plan[3:]))
        self.phase, self.input_role = "dispatching", self.policy["input_transition"]
        self.launch = self.spawn("launch", self.launch_delay, self.selection)
        self.dirty = True
        return True

    def launch_next(self):
        candidates = []
        for path in self.ready_files():
            values = row(path, 7)
            if (values is None or values[:2] != [str(self.epoch), self.token] or not number(values[2], 8) or
                    values[3] != values[0] + ":" + values[2] or tuple(values[4:]) not in self.items):
                unlink(path)
                continue
            candidates.append((int(values[2]), path, values))
        if not candidates:
            return
        _, path, values = min(candidates)
        unlink(path)
        self.selection, self.kind = values[3], values[4]
        self.plan = values[:2] + [self.selection] + values[4:]
        self.event("first_ready", ":".join(values[4:]))
        if self.dispatch(self.plan):
            self.next_pending = False
            for request in self.next_ids:
                self.receipt(request, "applied", "ok", self.selection)
            self.next_ids.clear()

    def decision(self, action):
        if action == "timer":
            return "ignore" if self.phase == "playing" and self.policy["play_timer"] == "0" else "advance"
        if self.phase in ("preparing", "dispatching"):
            return self.policy["input_transition"]
        if self.phase in ("demonstration", "commercial"):
            return self.policy["input_demo"]
        return self.policy["input_play"] if self.phase == "playing" else "ignore"

    def request(self, path):
        values = row(path, 9)
        unlink(path)
        if values is None or not literal(values[0]):
            self.event("request_path_rejected", "nonregular_or_malformed")
            return
        request, pid, ticks, token, epoch, action, a, b, c = values
        error = "stale_owner" if [pid, ticks, token] != [str(self.pid), self.start_ticks, self.token] else ""
        error = error or ("stale_epoch" if epoch != str(self.epoch) else "")
        plain = ("start", "next", "stop", "shutdown", "status", "input", "timer", "menu-observed")
        if action in plain:
            valid = (a, b, c) == ("-", "-", "-")
        elif action in ("launch", "ui-close"):
            valid = literal(a) and b == c == "-"
        elif action == "ui-open":
            valid = literal(a) and number(b, 12) and number(c, 24) and int(b) > 0
        else:
            valid = False
        error = error or ("invalid_arguments" if not valid else "")
        if error:
            for stage in ("accepted", "applied"):
                self.receipt(request, stage, "rejected", error)
            self.event("command_rejected", request + ":" + error)
            return
        self.receipt(request, "accepted", "ok", action)
        self.event("accepted", request + ":" + action)
        status, detail = "ok", "-"
        if self.cleanup_blocked and action in ("start", "next", "launch", "input", "timer"):
            status, detail = "rejected", "cleanup_unproven"
        elif action == "start":
            detail = "already_active" if self.active else "preparing"
            if not self.active and not self.start():
                status, detail = "rejected", "preparation_or_cleanup_failed"
        elif action == "next":
            if self.active and len(self.next_ids) < 32:
                self.next_pending = True
                self.next_ids.append(request)
                self.event("next_coalesced", request)
                return
            status, detail = "rejected", "pending_next_full" if self.active else "inactive"
        elif action in ("stop", "shutdown", "menu-observed"):
            if action == "menu-observed":
                self.event("sim_menu_observed", request)
            if self.stop("external_menu" if action == "menu-observed" else action):
                detail = "menu_observed" if action == "menu-observed" else "sim_menu_intent"
                if action == "shutdown":
                    self.running = False
            else:
                status, detail = "rejected", "cleanup_unproven"
        elif action == "status":
            detail = self.phase
        elif action == "launch":
            if self.active and a == self.selection and self.phase != "dispatching" and self.dispatch(self.plan):
                detail = "dispatching"
            else:
                status, detail = "rejected", "stale_selection"
        elif action in ("input", "timer"):
            detail = self.decision(action)
            self.event("mock_" + action, detail)
            if detail == "stop" and not self.stop("mock_input"):
                status, detail = "rejected", "cleanup_unproven"
            elif detail == "play":
                self.phase, self.input_role, self.dirty = "playing", self.policy["input_play"], True
                self.event("play_entered", self.policy["play_timer"])
            elif detail == "advance" and self.active:
                self.next_pending = True
        elif action == "ui-open":
            ident = identity(int(b))
            if a in self.closed_leases:
                status, detail = "rejected", "closed_lease"
            elif ident is None or ident[0] != c:
                status, detail = "rejected", "dead_ui_client"
            else:
                self.ui_open, self.ui_lease, self.ui_pid, self.ui_ticks = True, a, int(b), c
                self.pause_pending, self.paused, self.dirty = a, False, True
                detail = "ui_visible"
                self.event("ui_visible", a)
        elif action == "ui-close":
            self.closed_leases[a] = True
            if len(self.closed_leases) > 32:
                del self.closed_leases[next(iter(self.closed_leases))]
            if a != self.ui_lease:
                status, detail = "rejected", "stale_lease"
            else:
                self.ui_open, self.ui_lease, self.paused, self.pause_pending = False, "-", False, "-"
                self.dirty, detail = True, "closed"
                self.event("ui_closed", a)
        self.receipt(request, "applied", status, detail)

    def tick(self):
        if self.pause_pending != "-":
            if self.ui_open and self.pause_pending == self.ui_lease and self.policy["ui"] == "pause":
                self.paused = True
                self.event("ui_pause_applied", self.ui_lease)
            self.pause_pending, self.dirty = "-", True
        names = os.listdir(self.root + "/inbox")
        names = sorted(n for n in names if n.startswith("urgent.") and n.endswith(".req")) + sorted(n for n in names if n.startswith("control.") and n.endswith(".req"))
        for name in names[:32]:
            self.request(self.root + "/inbox/" + name)
            if not self.running:
                break
        if self.ui_open:
            ident = identity(self.ui_pid)
            if ident is None or ident[0] != self.ui_ticks:
                self.event("ui_client_gone", self.ui_lease)
                self.ui_open, self.ui_lease, self.paused, self.pause_pending, self.dirty = False, "-", False, "-", True
        done = row(self.root + "/launch.done", 3)
        if done is not None:
            unlink(self.root + "/launch.done")
            if self.active and done == [str(self.epoch), self.token, self.selection]:
                self.phase = {"bios": "bios", "clip": "commercial", "game": "demonstration"}[self.kind]
                self.input_role = "ignore" if self.kind == "bios" else self.policy["input_demo"]
                self.event("mock_launch_applied", self.phase)
                self.dirty = True
            else:
                self.event("launch_result_rejected", "stale_selection")
        if self.launch and self.launch.process.poll() is not None:
            if not self.cancel("launch"):
                self.cleanup_blocked, self.phase, self.active, self.dirty = True, "stopping", True, True
        if self.active and self.worker and self.worker.process.poll() is not None and self.phase == "preparing" and not self.ready_files():
            self.active, self.phase, self.next_pending, self.dirty = False, "failed", False, True
            self.event("preparation_failed", "worker_exited_without_candidate")
            for request in self.next_ids:
                self.receipt(request, "applied", "rejected", "preparation_failed")
            self.next_ids.clear()
        if self.active and self.next_pending and not self.paused and self.phase != "dispatching":
            self.launch_next()
        for job in self.cleanup[:]:
            if job.process.poll() is not None:
                self.cleanup.remove(job)
                self.event("cleanup_reaped", str(job.pid))
        count = len(self.ready_files())
        if count != getattr(self, "ready_count", -1):
            self.ready_count, self.dirty = count, True
        if self.dirty:
            self.publish_state()

    def run(self):
        try:
            while self.running:
                if (not self.active and self.worker is None and self.launch is None and not self.ui_open and
                        not self.cleanup and not self.dirty and self.pause_pending == "-" and
                        not os.listdir(self.root + "/inbox")):
                    time.sleep(.05)
                    continue
                self.tick()
                time.sleep(.02)
        finally:
            if self.active or self.worker or self.launch:
                self.stop("engine_exit")
            # Owned helpers have no children; after proven kill, wait only on exit.
            for job in self.cleanup:
                job.process.wait()
            owner = row(self.root + "/owner", 4)
            if owner == [str(self.pid), self.start_ticks, self.token, str(self.epoch)]:
                unlink(self.root + "/owner")
            self.events.close()
            os.rmdir(self.root + "/engine.lock")


def main():
    os.umask(0o077)
    args = sys.argv[1:]
    if args and args[0] in ("--worker", "--launch"):
        if len(args) != 8:
            raise ValueError("invalid child invocation")
        child_role(args[0][2:], args[1:])
        return
    if len(args) > 3:
        raise ValueError("invalid owner invocation")
    mode = args[0] if args else "normal"
    prep = delay(args[1] if len(args) > 1 else "3")
    launch = delay(args[2] if len(args) > 2 else "0")
    if os.environ.get("RESEARCH_CHILD_START", "fork") == "exec":
        global subprocess
        import subprocess  # Fork comparison needs no subprocess/interpreter exec.
    owner = Owner(mode, prep, launch)
    signal.signal(signal.SIGTERM, lambda _signum, _frame: setattr(owner, "running", False))
    signal.signal(signal.SIGINT, lambda _signum, _frame: setattr(owner, "running", False))
    owner.run()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, FileNotFoundError) as error:
        print("research owner: " + str(error), file=sys.stderr)
        sys.exit(64)
    except FileExistsError:
        sys.exit(75)
