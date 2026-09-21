#!/usr/bin/env python3
import argparse
import html
import http.client
import http.server
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.parse
import webbrowser
from datetime import datetime
from pathlib import Path

DEFAULT_DIR = Path.home() / ".artifacts"
DEFAULT_PORT = 8642
PID_FILE_NAME = ".serve.pid"
SERVED_DIR_HEADER = "X-Artifacts-Dir"
HEAD_SCAN_BYTES = 16384
FAVICON_SVG = (
    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32' fill='none' "
    "stroke='#28c3c5' stroke-width='1.7' stroke-linecap='round'>"
    "<path d='M13.47 11.77 7.96 19.91M18.53 11.77 24.04 19.91M9.93 23.63h12.11'/>"
    "<circle cx='16' cy='8.05' r='3.65'/>"
    "<circle cx='5.43' cy='23.63' r='3.65'/>"
    "<circle cx='26.54' cy='23.63' r='3.65'/>"
    "<g fill='#28c3c5' stroke='none'>"
    "<circle cx='16' cy='8.05' r='1.1'/>"
    "<circle cx='5.43' cy='23.63' r='1.1'/>"
    "<circle cx='26.54' cy='23.63' r='1.1'/>"
    "</g></svg>"
)
TITLE_PATTERN = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
DESCRIPTION_PATTERN = re.compile(
    r"<meta\s+[^>]*name=[\"']description[\"'][^>]*content=[\"'](.*?)[\"']", re.IGNORECASE | re.DOTALL
)
DESCRIPTION_PATTERN_REVERSED = re.compile(
    r"<meta\s+[^>]*content=[\"'](.*?)[\"'][^>]*name=[\"']description[\"']", re.IGNORECASE | re.DOTALL
)

INDEX_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Artifacts</title>
<link rel="icon" type="image/svg+xml" href="@@FAVICON@@">
<style>
:root { color-scheme: light dark; --bg:#f2f5f6; --fg:#23282e; --muted:#6b747d; --card:#ffffff; --line:#d7dde1; --accent:#2f8b86; --accent-strong:#1f6f6b; --accent-soft:#9ccfcb; }
@media (prefers-color-scheme: dark) { :root { --bg:#1c1f26; --fg:#d9dee4; --muted:#7f8791; --card:#232730; --line:#30353f; --accent:#7cc4bf; --accent-strong:#a3dcd7; --accent-soft:#4f8a88; } }
* { box-sizing:border-box; }
body { margin:0; padding:2rem 1rem 4rem; background:var(--bg); color:var(--fg); font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }
main { max-width:56rem; margin:0 auto; }
h1 { font-size:1.5rem; margin:0 0 .25rem; }
.mark { display:block; width:2.25rem; height:2.25rem; margin:0 0 .6rem; }
.meta { color:var(--muted); font-size:.9rem; margin:0 0 1.5rem; }
.meta code { font:inherit; }
input[type=search] { width:100%; padding:.6rem .8rem; border:1px solid var(--line); border-radius:.5rem; background:var(--card); color:var(--fg); font:inherit; margin-bottom:1rem; }
input[type=search]:focus { outline:none; border-color:var(--accent); }
ul { list-style:none; margin:0; padding:0; display:grid; gap:.6rem; }
li { background:var(--card); border:1px solid var(--line); border-radius:.6rem; padding:.8rem 1rem; }
li a { color:var(--accent); font-weight:600; text-decoration:none; font-size:1.05rem; }
li a:hover { text-decoration:underline; color:var(--accent-strong); }
li:hover { border-color:var(--accent-soft); }
li p { margin:.2rem 0 .3rem; }
li small { color:var(--muted); font-size:.8rem; }
li small code { font:inherit; }
.empty { color:var(--muted); padding:2rem 0; text-align:center; }
</style>
</head>
<body>
<main>
@@MARK@@
<h1>Artifacts</h1>
<p class="meta"><code>@@DIRECTORY@@</code> · @@COUNT@@ file(s) · generated @@GENERATED@@</p>
<input type="search" id="filter" placeholder="Filter by title, description, or file name" autofocus>
<ul id="list">
@@ITEMS@@
</ul>
<p class="empty" id="empty" hidden>No artifact matches.</p>
</main>
<script>
const filter = document.getElementById("filter");
const items = Array.from(document.querySelectorAll("#list li"));
const empty = document.getElementById("empty");
filter.addEventListener("input", () => {
  const needle = filter.value.trim().toLowerCase();
  let visible = 0;
  for (const item of items) {
    const match = !needle || item.dataset.search.includes(needle);
    item.hidden = !match;
    visible += match ? 1 : 0;
  }
  empty.hidden = visible !== 0;
});
</script>
</body>
</html>
"""

ITEM_TEMPLATE = """<li data-search="{search}">
<a href="{href}">{title}</a>
<p>{description}</p>
<small><code>{name}</code> · {modified} · {size}</small>
</li>"""


def human_size(size_bytes):
    for unit in ("B", "KB", "MB", "GB"):
        if size_bytes < 1024 or unit == "GB":
            return f"{size_bytes:.0f} {unit}" if unit == "B" else f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} GB"


def read_head(path):
    try:
        with open(path, "rb") as handle:
            return handle.read(HEAD_SCAN_BYTES).decode("utf-8", errors="replace")
    except OSError:
        return ""


def first_match(pattern, text):
    match = pattern.search(text)
    if not match:
        return ""
    return html.unescape(re.sub(r"\s+", " ", match.group(1))).strip()


def collect_artifacts(directory):
    artifacts = []
    for path in sorted(directory.rglob("*.html")):
        relative = path.relative_to(directory)
        if any(part.startswith(".") for part in relative.parts):
            continue
        if relative.as_posix() == "index.html":
            continue
        head = read_head(path)
        stat = path.stat()
        artifacts.append(
            {
                "name": relative.as_posix(),
                "title": first_match(TITLE_PATTERN, head) or path.stem,
                "description": first_match(DESCRIPTION_PATTERN, head)
                or first_match(DESCRIPTION_PATTERN_REVERSED, head),
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),
                "modified_epoch": stat.st_mtime,
                "size_bytes": stat.st_size,
            }
        )
    artifacts.sort(key=lambda entry: entry["modified_epoch"], reverse=True)
    return artifacts


def inline_mark():
    return FAVICON_SVG.replace("<svg ", "<svg class='mark' ", 1)


def favicon_data_uri():
    return "data:image/svg+xml," + urllib.parse.quote(FAVICON_SVG, safe="")


def render_index(directory, artifacts):
    items = []
    for entry in artifacts:
        search_blob = " ".join((entry["title"], entry["description"], entry["name"])).lower()
        items.append(
            ITEM_TEMPLATE.format(
                search=html.escape(search_blob, quote=True),
                href=urllib.parse.quote(entry["name"]),
                title=html.escape(entry["title"]),
                description=html.escape(entry["description"]) or "<em>No description</em>",
                name=html.escape(entry["name"]),
                modified=html.escape(entry["modified"].replace("T", " ")),
                size=human_size(entry["size_bytes"]),
            )
        )
    return (
        INDEX_TEMPLATE.replace("@@DIRECTORY@@", html.escape(str(directory)))
        .replace("@@COUNT@@", str(len(artifacts)))
        .replace("@@GENERATED@@", datetime.now().isoformat(timespec="seconds").replace("T", " "))
        .replace("@@MARK@@", inline_mark())
        .replace("@@FAVICON@@", html.escape(favicon_data_uri(), quote=True))
        .replace("@@ITEMS@@", "\n".join(items))
    )


def make_handler(directory):
    class ArtifactHandler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(directory), **kwargs)

        def end_headers(self):
            self.send_header("Cache-Control", "no-store")
            self.send_header(SERVED_DIR_HEADER, str(directory))
            super().end_headers()

        def do_GET(self):
            route = urllib.parse.urlparse(self.path).path
            if route in ("/", "/index.html"):
                body = render_index(directory, collect_artifacts(directory)).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if route in ("/favicon.ico", "/favicon.svg"):
                body = FAVICON_SVG.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "image/svg+xml")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if route == "/index.json":
                body = json.dumps(collect_artifacts(directory), indent=2).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            super().do_GET()

        def log_message(self, format, *args):
            if os.environ.get("ARTIFACTS_SERVE_VERBOSE"):
                super().log_message(format, *args)

    return ArtifactHandler


def port_is_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.3)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def directory_served_on_port(port):
    try:
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
        connection.request("HEAD", "/")
        response = connection.getresponse()
        served = response.getheader(SERVED_DIR_HEADER)
        connection.close()
        return served
    except OSError:
        return None


def read_pid(pid_file):
    try:
        return int(pid_file.read_text().strip())
    except (OSError, ValueError):
        return None


def pid_is_alive(pid):
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def serve_foreground(directory, port):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), make_handler(directory))
    pid_file = directory / PID_FILE_NAME
    pid_file.write_text(str(os.getpid()))

    def shutdown(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, shutdown)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if read_pid(pid_file) == os.getpid():
            pid_file.unlink(missing_ok=True)


def start_background(directory, port):
    command = [sys.executable, str(Path(__file__).resolve()), "--dir", str(directory), "--port", str(port), "--foreground"]
    log_path = directory / ".serve.log"
    with open(log_path, "ab") as log_handle:
        subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=log_handle,
            start_new_session=True,
            close_fds=True,
        )
    deadline = time.time() + 5
    while time.time() < deadline:
        if port_is_open(port):
            return True
        time.sleep(0.1)
    return False


def stop_server(directory):
    pid_file = directory / PID_FILE_NAME
    pid = read_pid(pid_file)
    if not pid_is_alive(pid):
        pid_file.unlink(missing_ok=True)
        print("not running")
        return 0
    try:
        os.kill(pid, signal.SIGTERM)
    except PermissionError:
        print(f"cannot signal pid {pid}; stop it from a shell: kill {pid}", file=sys.stderr)
        return 1
    deadline = time.time() + 5
    while time.time() < deadline and pid_is_alive(pid):
        time.sleep(0.1)
    pid_file.unlink(missing_ok=True)
    print(f"stopped pid {pid}")
    return 0


def status(directory, port):
    pid = read_pid(directory / PID_FILE_NAME)
    served = directory_served_on_port(port)
    if served == str(directory):
        print(f"running dir={directory} port={port} pid={pid or '-'}")
        return 0
    if served is not None:
        print(f"stopped dir={directory}; port {port} serves {served} instead")
        return 1
    if port_is_open(port):
        print(f"stopped dir={directory}; port {port} is held by another program")
        return 1
    print(f"stopped dir={directory} port={port}")
    return 1


def main():
    parser = argparse.ArgumentParser(description="Serve a directory of HTML artifacts with a generated index.")
    parser.add_argument("--dir", default=str(DEFAULT_DIR), help="artifacts directory (default: ~/.artifacts)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"port to bind on 127.0.0.1 (default: {DEFAULT_PORT})")
    parser.add_argument("--open", action="store_true", help="open the index in the default browser")
    parser.add_argument("--foreground", action="store_true", help="run in the foreground instead of detaching")
    parser.add_argument("--stop", action="store_true", help="stop the background server")
    parser.add_argument("--status", action="store_true", help="report whether the background server is running")
    parser.add_argument("--write-index", action="store_true", help="write a static index.html into the directory and exit")
    args = parser.parse_args()

    directory = Path(args.dir).expanduser().resolve()
    directory.mkdir(parents=True, exist_ok=True)
    url = f"http://127.0.0.1:{args.port}/"

    if args.stop:
        return stop_server(directory)
    if args.status:
        return status(directory, args.port)
    if args.write_index:
        target = directory / "index.html"
        target.write_text(render_index(directory, collect_artifacts(directory)), encoding="utf-8")
        print(target)
        return 0
    if args.foreground:
        print(f"serving {directory} at {url}", flush=True)
        serve_foreground(directory, args.port)
        return 0

    served = directory_served_on_port(args.port) if port_is_open(args.port) else None
    if served == str(directory):
        print(f"already serving at {url}")
    elif served is not None:
        print(
            f"port {args.port} already serves {served}, not {directory}; "
            f"stop that server or rerun with --port",
            file=sys.stderr,
        )
        return 1
    elif port_is_open(args.port):
        print(f"port {args.port} is held by another program; rerun with --port", file=sys.stderr)
        return 1
    elif start_background(directory, args.port):
        print(f"serving {directory} at {url}")
    else:
        print(f"failed to start server on port {args.port}; see {directory / '.serve.log'}", file=sys.stderr)
        return 1
    if args.open:
        webbrowser.open(url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
