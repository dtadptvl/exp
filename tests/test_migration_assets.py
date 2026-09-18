import ast
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PS1 = ROOT / "migration" / "setup-auth.ps1"
NOTEBOOK = ROOT / "migration" / "colab-migrate.ipynb"
GITIGNORE = ROOT / ".gitignore"


def notebook_code() -> str:
    data = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
    return "\n".join(
        "".join(cell.get("source", []))
        for cell in data["cells"]
        if cell.get("cell_type") == "code"
    )


class MigrationAssetsTest(unittest.TestCase):
    def test_notebook_is_valid_json_and_python_cells_compile(self):
        data = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
        self.assertEqual(data["nbformat"], 4)
        for cell in data["cells"]:
            if cell.get("cell_type") == "code":
                source = "".join(cell.get("source", []))
                if source.strip():
                    ast.parse(source)

    def test_transfer_is_copy_only_and_rerunnable(self):
        code = notebook_code()
        self.assertIn('\"copy\"', code)
        self.assertIn('\"check\"', code)
        self.assertIn('\"--one-way\"', code)
        self.assertIn('\"--size-only\"', code)
        self.assertIn('\"--progress\"', code)
        for token in ('\"sync\"', '\"move\"', '\"delete\"', '\"purge\"'):
            self.assertNotIn(token, code)

    def test_expected_remotes_and_read_only_source_config(self):
        ps1 = PS1.read_text(encoding="utf-8")
        code = notebook_code()
        for name in ("onedrive-src", "gdrive-dst"):
            self.assertIn(name, ps1)
            self.assertIn(name, code)
        self.assertIn("Files.Read Files.Read.All Sites.Read.All offline_access", ps1)
        self.assertNotIn("Files.ReadWrite", ps1)

    def test_credentials_are_gitignored(self):
        ignored = GITIGNORE.read_text(encoding="utf-8")
        self.assertIn("rclone.conf", ignored)


if __name__ == "__main__":
    unittest.main()
