#!/usr/bin/env python3
"""Capture the standard visual-evidence set for a render/presentation change.

Drives an already-running Chrome over CDP and writes, per viewport, a whole-page
screenshot of the viewer: a GENUINE frame at that size (the page is rendered at
the viewport via Emulation.setDeviceMetricsOverride), never a crop of a larger
frame and never a relabeled canvas dump.

    google-chrome --remote-debugging-port=9333 --remote-allow-origins='*' &
    python3 tools/capture_evidence.py http://127.0.0.1:9500/client/global \
        --out /tmp/evidence/after --label after

Default viewports are the two the reviewer looks at: desktop 1440x900 and the
small-embed 640x360. The shutter waits for the board to actually paint and FAILS
rather than writing an all-black lobby/countdown frame (the one way this script
can silently produce worthless evidence). Pass --tick to seek a replay page.

Pair captures by running the same command against the base build's port with
--label before; identical --viewports and --settle keep the pair zoom-matched.
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.request

# An all-black 640x360 lobby frame is <1 KB; a painted board at that size is
# ~250 KB. 20 KB separates them by an order of magnitude either way.
BlankPngBytes = 20_000

try:
    from websockets.sync.client import connect
except ImportError:  # pragma: no cover
    sys.exit("needs the websockets package (python3 -m pip install websockets)")


class CDP:
    def __init__(self, ws_url):
        self.ws = connect(ws_url, max_size=None)
        self.n = 0

    def send(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    def close(self):
        self.ws.close()


def page_target(port, url):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=10) as f:
        targets = json.load(f)
    pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        raise RuntimeError("no page target; is Chrome running with --remote-debugging-port?")
    for t in pages:
        if t.get("url", "").startswith(url):
            return t
    return pages[0]


def wait_for_painted_frame(cdp, timeout, poll=3.0):
    """Shoot only once the board has painted; raise instead of saving a black frame.

    A server sitting in the lobby/countdown serves a page that renders as solid
    black, and a fixed sleep happily captures it — an exit-0 run that produces
    evidence a reviewer will reject. PNG size is a good enough paint signal: a
    black frame compresses to a few KB, a rendered board to tens/hundreds of KB.
    """
    deadline = time.time() + max(timeout, 0)
    while True:
        shot = cdp.send("Page.captureScreenshot", format="png", captureBeyondViewport=False)
        data = base64.b64decode(shot["data"])
        if len(data) >= BlankPngBytes:
            return data
        if time.time() >= deadline:
            raise RuntimeError(
                f"nothing painted: frame is {len(data)} bytes (blank). Check the URL, and "
                "that the match is actually running — a server whose seats are unfilled "
                "sits in the lobby. Re-run once the server log says 'game started'.")
        cdp.send("Runtime.evaluate", awaitPromise=True, returnByValue=True,
                 expression=f"new Promise(r=>setTimeout(r,{int(poll * 1000)}))")


def parse_viewport(text):
    w, _, h = text.lower().partition("x")
    return int(w), int(h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url", help="viewer URL, e.g. http://127.0.0.1:9500/client/global")
    ap.add_argument("--out", default="/tmp/evidence", help="output directory")
    ap.add_argument("--label", default="shot", help="filename prefix, e.g. before/after")
    ap.add_argument("--port", type=int, default=9333, help="Chrome CDP port")
    ap.add_argument("--viewports", default="1440x900,640x360",
                    help="comma-separated WxH list (both reviewer sizes by default)")
    ap.add_argument("--settle", type=float, default=6.0,
                    help="seconds to let the board paint before each shutter")
    ap.add_argument("--ready-timeout", type=float, default=90.0,
                    help="extra seconds to wait for a painted board (lobby countdown)")
    ap.add_argument("--tick", type=int, default=0,
                    help="for replay pages: seek to this tick via the page's viewer hook")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    cdp = CDP(page_target(args.port, args.url)["webSocketDebuggerUrl"])
    written = []
    try:
        cdp.send("Page.enable")
        cdp.send("Runtime.enable")
        for vp in args.viewports.split(","):
            w, h = parse_viewport(vp.strip())
            # Render AT the target size: this is what makes 640x360 a real frame.
            cdp.send("Emulation.setDeviceMetricsOverride",
                     width=w, height=h, deviceScaleFactor=1, mobile=False)
            cdp.send("Page.navigate", url=args.url)
            cdp.send("Runtime.evaluate", expression=f"new Promise(r=>setTimeout(r,{int(args.settle*1000)}))",
                     awaitPromise=True, returnByValue=True)
            if args.tick:
                cdp.send("Runtime.evaluate", awaitPromise=True, returnByValue=True, expression=(
                    f"(async()=>{{const t={args.tick};"
                    "if(window.__viewer&&window.__viewer.seek){window.__viewer.seek(t);}"
                    "await new Promise(r=>setTimeout(r,1500));"
                    "return document.title;})()"))
            data = wait_for_painted_frame(cdp, args.ready_timeout)
            path = os.path.join(args.out, f"{args.label}-{w}x{h}.png")
            with open(path, "wb") as f:
                f.write(data)
            written.append((path, w, h))
        cdp.send("Emulation.clearDeviceMetricsOverride")
    finally:
        cdp.close()

    for path, w, h in written:
        size = os.path.getsize(path)
        print(f"{path}  ({w}x{h}, {size} bytes)")
    print("Check each PNG's pixel dimensions match its filename before using it as evidence.")


if __name__ == "__main__":
    main()
