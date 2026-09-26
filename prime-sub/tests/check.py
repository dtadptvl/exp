import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('state', ROOT / 'state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)
spec = importlib.util.spec_from_file_location('watch', ROOT / 'watch.py')
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

assert state.impact({'M1': {'produces': ['one']}, 'M2': {'depends_on': ['M1']},
                     'M3': {'produces': ['three'], 'depends_on': ['M2']},
                     'M4': {'depends_on': ['M3']}, 'M5': {'depends_on': ['M4']},
                     'other': {'produces': ['other']}}, ['three']) == ['M3', 'M4', 'M5']
original = os.getcwd()
with tempfile.TemporaryDirectory() as folder:
    os.chdir(folder)
    subprocess.run(['git', 'init', '-q'], check=True)
    subprocess.run(['git', 'config', 'user.email', 'test@example.org'], check=True)
    subprocess.run(['git', 'config', 'user.name', 'Test'], check=True)
    Path('three').write_text('v1')
    Path('other').write_text('v1')
    subprocess.run(['git', 'add', '.'], check=True)
    subprocess.run(['git', 'commit', '-qm', 'fixture'], check=True)
    s = state.load()
    s.update(objective='M1 to M5', active='M3', tasks={
        'M3': {'status': 'completed', 'produces': ['three']},
        'M4': {'status': 'completed', 'depends_on': ['M3']},
        'M5': {'status': 'completed', 'depends_on': ['M4']},
        'other': {'status': 'completed', 'produces': ['other']}})
    s['git'] = state.marker()
    state.save(s)
    assert state.reconcile(state.load())['changed'] == []
    Path('three').write_text('human revision')
    Path('other').write_text('unrelated revision')
    delta = state.reconcile(state.load())
    assert delta['invalidated'] == ['M3', 'M4', 'M5', 'other']
    Path('other').write_text('v1')
    delta = state.reconcile(state.load())
    assert delta['invalidated'] == ['M3', 'M4', 'M5']
    for key in delta['invalidated']:
        s['tasks'][key]['status'] = 'invalidated'
    s['git'] = delta['git']
    state.save(s)
    assert state.load()['objective'] == 'M1 to M5'
    assert state.reconcile(state.load())['changed'] == ['three']  # acknowledged dirty work is still visible
    assert state.load()['tasks']['other']['status'] == 'completed'
    assert watch.run([sys.executable, '-c', 'import time; time.sleep(4)'], 2, .5) == 124
    os.chdir(original)
print('PASS: selective DAG, external change, resume, idle kill')
