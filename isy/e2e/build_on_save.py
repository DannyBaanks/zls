#!/usr/bin/env python3
"""ISY end-to-end checks for build-on-save (what an agent sees right after editing a file).

Scenarios (each runs zls on a fresh temp copy of fixtures/no_check_step):
  flat     workspace = the project, which declares no "check" step.
           Expect the type error exactly once (synthetic check + dedupe) and no zig-out,
           published in a single publishDiagnostics notification per build cycle even
           though several artifacts fail and share the same source file.
  monorepo workspace = a folder WITHOUT build.zig holding the project in app/,
           a dependency package in zig-pkg/dep/ and a loose file in loose/.
           Expect the error for app/ (nested build-on-save), and NO watcher started
           for zig-pkg/dep/ or loose/ (checked through zls log messages).
  limit    five nested projects: at most 4 watchers, least recently used one stopped.

usage: build_on_save.py [path/to/zls] [timeout_seconds] [scenario...]
exit 0 = every scenario PASS, 1 = any FAIL
"""
import json, pathlib, shutil, subprocess, sys, tempfile, threading, time
from typing import IO

HERE = pathlib.Path(__file__).resolve().parent
ZLS = sys.argv[1] if len(sys.argv) > 1 else str(HERE.parents[1] / "zig-out/bin/zls")
TIMEOUT = float(sys.argv[2]) if len(sys.argv) > 2 else 120.0
SCENARIOS = sys.argv[3:] or ["flat", "monorepo", "limit"]
EXPECTED = "expected type 'u32', found '*const [21:0]u8'"
FIXTURE = HERE / "fixtures/no_check_step"


class Session:
    """Minimal LSP client: one zls process, one workspace folder."""

    def __init__(self, workspace: pathlib.Path):
        self.proc = subprocess.Popen([ZLS], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        assert self.proc.stdin is not None and self.proc.stdout is not None
        self.stdin: IO[bytes] = self.proc.stdin
        self.stdout: IO[bytes] = self.proc.stdout
        self.changed = threading.Condition()
        self.diagnostics: dict[str, list[str]] = {}
        # every publishDiagnostics notification, in arrival order: (uri, messages)
        self.notifications: list[tuple[str, list[str]]] = []
        self.logs: list[str] = []
        threading.Thread(target=self._reader, daemon=True).start()
        uri = workspace.as_uri()
        self.send({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {
            "processId": None, "rootUri": uri,
            "workspaceFolders": [{"uri": uri, "name": workspace.name}],
            "capabilities": {"textDocument": {"synchronization": {"didSave": True}, "publishDiagnostics": {}}}}})
        self.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

    def send(self, message):
        body = json.dumps(message).encode()
        self.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.stdin.flush()

    def _reader(self):
        while True:
            header = b""
            while not header.endswith(b"\r\n\r\n"):
                byte = self.stdout.read(1)
                if not byte:
                    return
                header += byte
            length = int([l for l in header.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
            message = json.loads(self.stdout.read(length))
            method = message.get("method")
            with self.changed:
                if method == "textDocument/publishDiagnostics":
                    messages = [d["message"] for d in message["params"]["diagnostics"]]
                    self.diagnostics[message["params"]["uri"]] = messages
                    self.notifications.append((message["params"]["uri"], messages))
                elif method == "window/logMessage":
                    self.logs.append(message["params"]["message"])
                self.changed.notify_all()
            if "id" in message and method:
                self.send({"jsonrpc": "2.0", "id": message["id"], "result": None})

    def open(self, file: pathlib.Path):
        self.send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
            "uri": file.as_uri(), "languageId": "zig", "version": 1, "text": file.read_text()}}})

    def wait_for_error(self, file: pathlib.Path, timeout: float):
        deadline = time.monotonic() + timeout
        with self.changed:
            while EXPECTED not in self.diagnostics.get(file.as_uri(), []):
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None
                self.changed.wait(remaining)
            return list(self.diagnostics[file.as_uri()])

    def close(self):
        self.send({"jsonrpc": "2.0", "id": 1, "method": "shutdown"})
        self.send({"jsonrpc": "2.0", "method": "exit"})
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def flat(work: pathlib.Path) -> list[str]:
    shutil.copytree(FIXTURE, work, dirs_exist_ok=True)
    source = work / "src/main.zig"
    session = Session(work)
    session.open(source)
    messages = session.wait_for_error(source, TIMEOUT)
    time.sleep(1.0)  # let the whole build cycle settle before counting notifications
    session.close()
    failures = []
    if messages is None:
        failures.append(f"no build-on-save diagnostic within {TIMEOUT:.0f}s")
    elif messages.count(EXPECTED) != 1:
        failures.append(f"expected the error once, got {messages.count(EXPECTED)}: {messages}")
    uri = source.as_uri()
    notifications = sum(1 for u, m in session.notifications if u == uri and EXPECTED in m)
    if notifications != 1:
        failures.append(
            f"expected exactly 1 notification carrying the error per build cycle "
            f"(one publish per cycle, not one per failing artifact), got {notifications}")
    if (work / "zig-out").exists():
        failures.append("zig-out was created: the synthetic check built or installed a binary")
    return failures


def monorepo(work: pathlib.Path) -> list[str]:
    shutil.copytree(FIXTURE, work / "app")
    shutil.copytree(FIXTURE, work / "zig-pkg/dep")
    (work / "loose").mkdir()
    (work / "loose/solo.zig").write_text((FIXTURE / "src/main.zig").read_text())
    session = Session(work)
    time.sleep(1.0)  # let initialization finish so didOpen sees status == initialized
    dependency = work / "zig-pkg/dep/src/main.zig"
    app = work / "app/src/main.zig"
    session.open(dependency)
    session.open(work / "loose/solo.zig")
    session.open(app)
    messages = session.wait_for_error(app, TIMEOUT)
    time.sleep(1.0)
    session.close()
    started = [line for line in session.logs if "nested Build-On-Save" in line]
    failures = []
    if messages is None:
        failures.append(f"no nested build-on-save diagnostic for app/ within {TIMEOUT:.0f}s")
    elif messages.count(EXPECTED) != 1:
        failures.append(f"expected the error once, got {messages.count(EXPECTED)}: {messages}")
    if any("zig-pkg" in line for line in started):
        failures.append(f"watcher started inside zig-pkg: {started}")
    if any("loose" in line for line in started):
        failures.append(f"watcher started for a loose file: {started}")
    if len(started) != 1:
        failures.append(f"expected exactly one nested watcher, got {started}")
    if EXPECTED in session.diagnostics.get(dependency.as_uri(), []):
        failures.append("the dependency package was type-checked")
    return failures


def limit(work: pathlib.Path) -> list[str]:
    """Five nested projects opened in turn: at most 4 watchers, the least recently used is stopped."""
    for index in range(5):
        shutil.copytree(FIXTURE, work / f"app{index}")
    session = Session(work)
    time.sleep(1.0)
    session.open(work / "app0/src/main.zig")
    for index in range(1, 4):
        session.open(work / f"app{index}/src/main.zig")
    session.open(work / "app0/src/main.zig")  # reuse: app0 becomes most recently used
    session.open(work / "app4/src/main.zig")  # fifth project: must evict app1, not app0
    messages = session.wait_for_error(work / "app4/src/main.zig", TIMEOUT)
    time.sleep(1.0)
    session.close()
    started = [line for line in session.logs if line.startswith("started nested")]
    stopped = [line for line in session.logs if line.startswith("stopped nested")]
    failures = []
    if messages is None:
        failures.append("no diagnostic for app4")
    if len(started) != 5:
        failures.append(f"expected 5 starts (reuse must not restart), got {len(started)}")
    if len(stopped) != 1 or "/app1'" not in stopped[0]:
        failures.append(f"expected exactly app1 to be stopped, got {stopped}")
    return failures


failed = False
for name in SCENARIOS:
    work = pathlib.Path(tempfile.mkdtemp(prefix=f"zls-isy-e2e-{name}-"))
    started = time.monotonic()
    try:
        failures = {"flat": flat, "monorepo": monorepo, "limit": limit}[name](work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    elapsed = time.monotonic() - started
    if failures:
        failed = True
        print(f"FAIL {name}: " + "; ".join(failures))
    else:
        print(f"PASS {name} ({elapsed:.1f}s)")
sys.exit(1 if failed else 0)
