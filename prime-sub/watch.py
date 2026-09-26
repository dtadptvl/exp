#!/usr/bin/env python3
"""Optional CLI watchdog for an unattended kilo run; JSON event output is not the state DB."""
import argparse
import json
import os
import queue
import subprocess
import sys
import threading
import time


def run(command, wall, idle):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, bufsize=1)
    events = queue.Queue()
    threading.Thread(target=lambda: [events.put(line) for line in process.stdout], daemon=True).start()
    start = progress = time.monotonic()
    try:
        while process.poll() is None or not events.empty():
            now = time.monotonic()
            if now - start > wall or now - progress > idle:
                reason = 'wall' if now - start > wall else 'idle'
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                   capture_output=True)
                else:
                    process.kill()
                process.wait()
                print(json.dumps({'status': 'STALLED', 'reason': reason,
                                  'elapsed_seconds': round(now - start, 2)}), file=sys.stderr)
                return 124
            try:
                line = events.get(timeout=0.2)
            except queue.Empty:
                continue
            print(line, end='', flush=True)
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            # ponytail: CLI JSON tool results are the cheapest evidence heartbeat;
            # extend for other event kinds only after observing a missed real progress case.
            if event.get('type') == 'tool_use' and event.get('part', {}).get('state', {}).get('status') == 'completed':
                progress = time.monotonic()
        return process.returncode
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wall', type=float, default=3600)
    parser.add_argument('--idle', type=float, default=600)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command or min(args.wall, args.idle) <= 0:
        parser.error('provide a command and positive wall/idle deadlines')
    raise SystemExit(run(args.command, args.wall, args.idle))
