#!/usr/bin/env python3
"""ISY end-to-end check for build-on-save without a "check" step.

Starts zls on a copy of fixtures/no_check_step, opens src/main.zig and expects the
type error to arrive exactly once (synthetic check step + diagnostic dedupe), and
expects nothing to be installed (zig-out absent: analysis only, no Run steps).

usage: build_on_save.py [path/to/zls] [timeout_seconds]
exit 0 = PASS, 1 = FAIL
"""
import json, pathlib, shutil, subprocess, sys, tempfile, threading, time

ZLS = sys.argv[1] if len(sys.argv) > 1 else str(pathlib.Path(__file__).resolve().parents[2] / "zig-out/bin/zls")
TIMEOUT = float(sys.argv[2]) if len(sys.argv) > 2 else 120.0
EXPECTED = "expected type 'u32', found '*const [21:0]u8'"

work = pathlib.Path(tempfile.mkdtemp(prefix="zls-isy-e2e-"))
shutil.copytree(pathlib.Path(__file__).parent / "fixtures/no_check_step", work, dirs_exist_ok=True)
source = work / "src/main.zig"

proc = subprocess.Popen([ZLS], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
found = threading.Event()
result: dict = {}

def send(message):
    body = json.dumps(message).encode()
    proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    proc.stdin.flush()

def reader():
    while True:
        header = b""
        while not header.endswith(b"\r\n\r\n"):
            byte = proc.stdout.read(1)
            if not byte:
                return
            header += byte
        length = int([l for l in header.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
        message = json.loads(proc.stdout.read(length))
        if message.get("method") == "textDocument/publishDiagnostics" and message["params"]["uri"] == source.as_uri():
            messages = [d["message"] for d in message["params"]["diagnostics"]]
            if EXPECTED in messages:
                result["messages"] = messages
                found.set()
        elif "id" in message and "method" in message:
            send({"jsonrpc": "2.0", "id": message["id"], "result": None})

threading.Thread(target=reader, daemon=True).start()
started = time.monotonic()
send({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {
    "processId": None, "rootUri": work.as_uri(),
    "workspaceFolders": [{"uri": work.as_uri(), "name": work.name}],
    "capabilities": {"textDocument": {"synchronization": {"didSave": True}, "publishDiagnostics": {}}}}})
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
    "uri": source.as_uri(), "languageId": "zig", "version": 1, "text": source.read_text()}}})

ok = found.wait(TIMEOUT)
elapsed = time.monotonic() - started
send({"jsonrpc": "2.0", "id": 1, "method": "shutdown"})
send({"jsonrpc": "2.0", "method": "exit"})
try:
    proc.wait(10)
except subprocess.TimeoutExpired:
    proc.kill()

failures = []
if not ok:
    failures.append(f"no build-on-save diagnostic within {TIMEOUT:.0f}s")
elif result["messages"].count(EXPECTED) != 1:
    failures.append(f"expected the error once, got {result['messages'].count(EXPECTED)}: {result['messages']}")
if (work / "zig-out").exists():
    failures.append("zig-out was created: the synthetic check installed or built a binary")
shutil.rmtree(work, ignore_errors=True)

if failures:
    print("FAIL " + "; ".join(failures))
    sys.exit(1)
print(f"PASS diagnostic once after {elapsed:.1f}s, nothing installed")
