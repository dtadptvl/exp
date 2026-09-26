from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    count = 0
    for path in sorted(HERE.glob("test_*.py")):
        mod = load(path)
        for name in sorted(dir(mod)):
            fn = getattr(mod, name)
            if name.startswith("test_") and callable(fn):
                fn(); count += 1; print(f"PASS {path.name}::{name}")
    print(f"PASS {count} tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
