import ast
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migration"
PS1 = MIGRATION / "setup-auth.ps1"
HOME_PS1 = MIGRATION / "home-server-migrate.ps1"
HOME_SH = MIGRATION / "home-server-migrate.sh"
MIGRATE_NOTEBOOK = MIGRATION / "colab-migrate.ipynb"
RESUME_NOTEBOOK = MIGRATION / "colab-check-resume.ipynb"
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

    def test_colab_transfer_is_copy_only(self):
        for notebook in (MIGRATE_NOTEBOOK, RESUME_NOTEBOOK):
            code = notebook_code(notebook)
            self.assertIn('"copy"', code)
            self.assertIn('"check"', code)
            self.assertIn('"--one-way"', code)
            self.assertIn('"--size-only"', code)
            for token in ('"sync"', '"move"', '"delete"', '"purge"'):
                self.assertNotIn(token, code)

    def test_home_server_defaults_and_safety(self):
        launcher = HOME_PS1.read_text(encoding="utf-8")
        remote = HOME_SH.read_text(encoding="utf-8")
        self.assertIn('home@minipc', launcher)
        self.assertIn('mktemp -d /tmp/onedrive-gdrive-migration.XXXXXX', launcher)
        self.assertIn("rm -rf '$RemoteRuntime'", launcher)
        self.assertIn('remote-returned', launcher)
        self.assertIn('gdrive-dst:OneDrive Migration', remote)
        self.assertIn('"$RCLONE" check', remote)
        self.assertIn('"$RCLONE" copy', remote)
        self.assertIn('--one-way', remote)
        self.assertIn('--size-only', remote)
        self.assertIn('if (( rc == 0 ))', remote)
        for command in ('"$RCLONE" sync', '"$RCLONE" move', '"$RCLONE" delete', '"$RCLONE" purge'):
            self.assertNotIn(command, remote)

    def test_expected_remotes_and_read_only_source_config(self):
        ps1 = PS1.read_text(encoding="utf-8")
        combined = (
            notebook_code(MIGRATE_NOTEBOOK)
            + "\n"
            + notebook_code(RESUME_NOTEBOOK)
            + "\n"
            + HOME_SH.read_text(encoding="utf-8")
        )
        for name in ("onedrive-src", "gdrive-dst"):
            self.assertIn(name, ps1)
            self.assertIn(name, combined)
        self.assertIn("Files.Read Files.Read.All Sites.Read.All offline_access", ps1)
        self.assertNotIn("Files.ReadWrite", ps1)

    def test_credentials_are_gitignored(self):
        ignored = GITIGNORE.read_text(encoding="utf-8")
        self.assertIn("rclone.conf", ignored)


if __name__ == "__main__":
    unittest.main()
