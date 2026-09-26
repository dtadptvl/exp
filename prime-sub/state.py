#!/usr/bin/env python3
"""Small Git-backed Prime checkpoint. Run from a project root; no agent transcript stored."""
import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

FILE = Path('.prime/state.json')


def git(*args):
    return subprocess.check_output(['git', *args], text=True, encoding='utf-8').rstrip('\r\n')


def marker():
    return {'branch': git('branch', '--show-current'), 'head': git('rev-parse', 'HEAD'),
            'paths': sorted(set(git('status', '--porcelain=v1', '-uall', '--', '.', ':!.prime/state.json').splitlines()))}


def changed_paths(old):
    now = marker()
    paths = set()
    if old and old['head'] != now['head']:
        paths.update(git('diff', '--name-only', old['head'], now['head']).splitlines())
    # porcelain rename records both path names; do not interpret content as a commit.
    for line in (old or {}).get('paths', []) + now['paths']:
        paths.add(line[3:].split(' -> ')[-1])
    return now, sorted(paths)


def load():
    if not FILE.exists():
        return {'objective': '', 'phase': '', 'active': None, 'tasks': {},
                'decisions': {}, 'assumptions': {}, 'acceptance': [], 'git': None}
    return json.loads(FILE.read_text(encoding='utf-8'))


def save(state):
    FILE.parent.mkdir(exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.state-', dir=FILE.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(state, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, FILE)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def impact(tasks, paths):
    # An edge means the consumer depends on the producer. Validate dependency IDs at entry.
    bad = {key for key, task in tasks.items()
           if set(task.get('produces', [])) & set(paths)
           or set(task.get('consumes', [])) & set(paths)}
    while True:
        more = {key for key, task in tasks.items()
                if set(task.get('depends_on', [])) & bad}
        if more <= bad:
            return sorted(bad)
        bad |= more


def reconcile(state):
    old = state.get('git')
    now, paths = changed_paths(old)
    if old and old['branch'] != now['branch']:
        raise ValueError('branch changed: inspect before reconciling')
    affected = impact(state['tasks'], paths) if old else []
    # Never silently accept an external delta; Prime must review and explicitly acknowledge.
    return {'git': now, 'changed': paths, 'invalidated': affected,
            'unknown': bool(old and paths and not affected)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['refresh', 'ack', 'check'])
    args = parser.parse_args()
    state = load()
    delta = reconcile(state)
    if args.action == 'ack':
        for key in delta['invalidated']:
            state['tasks'][key]['status'] = 'invalidated'
        state['git'] = delta['git']
        save(state)
    elif args.action == 'check' and (delta['changed'] or delta['git'] != state.get('git')):
        print(json.dumps(delta, ensure_ascii=False))
        return 1
    if args.action != 'check':
        packet = {key: state[key] for key in ('objective', 'phase', 'active', 'decisions', 'assumptions', 'acceptance')}
        active = state['active']
        packet['tasks'] = {key: task for key, task in state['tasks'].items()
                           if key == active or key in delta['invalidated'] or task.get('status') not in ('completed', 'success')}
        packet['delta'] = delta
        print(json.dumps(packet, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
