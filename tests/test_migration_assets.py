import ast
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PS1 = ROOT / "migration" / "setup-auth.ps1"
MIGRATE_NOTEBOOK = ROOT / "migration" / "colab-migrate.ipynb"
RESUME_NOTEBOOK = ROOT / "migration" / "colab-check-resume.ipynb"
GITIGNORE = ROOT / ".gitignore"


def notebook_code(path: Path) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    return "\n".join(
        "".join(cell.get("source", []))
        for cell in data["cells"]
        if cell.get("cell_type") == "code"
    )


class MigrationAssetsTest(unittest.TestCase):
    def test_notebooks_are_valid_json_and_python_cells_compile(self):
        for notebook in (MIGRATE_NOTEBOOK, RESUME_NOTEBOOK):
            data = json.loads(notebook.read_text(encoding="utf-8"))
            self.assertEqual(data["nbformat"], 4)
            for cell in data["cells"]:
                if cell.get("cell_type") == "code":
                    source = "".join(cell.get("source", []))
                    if source.strip():
                        ast.parse(source)

    def test_transfer_is_copy_only_and_rerunnable(self):
        for notebook in (MIGRATE_NOTEBOOK, RESUME_NOTEBOOK):
            code = notebook_code(notebook)
            self.assertIn('"copy"', code)
            self.assertIn('"check"', code)
            self.assertIn('"--one-way"', code)
            self.assertIn('"--size-only"', code)
            for token in ('"sync"', '"move"', '"delete"', '"purge"'):
                self.assertNotIn(token, code)

    def test_resume_notebook_checks_before_copying(self):
        code = notebook_code(RESUME_NOTEBOOK)
        self.assertIn("before_code, before_reports = verify", code)
        self.assertIn("if before_code == 0:", code)
        self.assertIn("No copy needed", code)
        self.assertIn('"--stats-one-line"', code)

    def test_expected_remotes_and_read_only_source_config(self):
        ps1 = PS1.read_text(encoding="utf-8")
        combined_code = notebook_code(MIGRATE_NOTEBOOK) + "\n" + notebook_code(RESUME_NOTEBOOK)
        for name in ("onedrive-src", "gdrive-dst"):
            self.assertIn(name, ps1)
            self.assertIn(name, combined_code)
        self.assertIn("Files.Read Files.Read.All Sites.Read.All offline_access", ps1)
        self.assertNotIn("Files.ReadWrite", ps1)

    def test_credentials_are_gitignored(self):
        ignored = GITIGNORE.read_text(encoding="utf-8")
        self.assertIn("rclone.conf", ignored)


if __name__ == "__main__":
    unittest.main()
