import ast
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migration"
SETUP = MIGRATION / "setup-auth.ps1"
UPDATE_GOOGLE = MIGRATION / "update-google-client.ps1"
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

    def test_private_google_client_is_required(self):
        setup = SETUP.read_text(encoding="utf-8")
        updater = UPDATE_GOOGLE.read_text(encoding="utf-8")
        remote = HOME_SH.read_text(encoding="utf-8")
        self.assertIn("client_id=$GoogleClientId", setup)
        self.assertIn("client_secret=$GoogleClientSecret", setup)
        self.assertIn("config update gdrive-dst", updater)
        self.assertIn('config reconnect "gdrive-dst:"', updater)
        self.assertIn("shared Google client", remote)

    def test_home_server_rate_limit_and_malware_skip(self):
        remote = HOME_SH.read_text(encoding="utf-8")
        self.assertIn("TPS_ARGS=(--tpslimit 8 --tpslimit-burst 1)", remote)
        self.assertIn("--retries 1", remote)
        self.assertIn("infected with a virus", remote)
        self.assertIn("malware-skipped.txt", remote)
        self.assertIn('comm -23 "$missing_sorted" "$malware_sorted"', remote)
        self.assertNotIn("--onedrive-av-override", remote)
        self.assertNotIn("--ignore-errors", remote)

    def test_home_server_copy_only_ctrl_c_and_resume(self):
        launcher = HOME_PS1.read_text(encoding="utf-8")
        remote = HOME_SH.read_text(encoding="utf-8")
        self.assertIn("home@minipc", launcher)
        self.assertIn("OneDrive Migration 2", launcher)
        self.assertIn("ssh -tt", launcher)
        self.assertIn("trap cancel INT TERM HUP", remote)
        self.assertIn('"$RCLONE" copy', remote)
        self.assertIn('"$RCLONE" check', remote)
        self.assertIn("--size-only", remote)
        for command in ('"$RCLONE" sync', '"$RCLONE" move', '"$RCLONE" delete', '"$RCLONE" purge'):
            self.assertNotIn(command, remote)

    def test_onedrive_source_stays_read_only(self):
        setup = SETUP.read_text(encoding="utf-8")
        self.assertIn("Files.Read Files.Read.All Sites.Read.All offline_access", setup)
        self.assertNotIn("Files.ReadWrite", setup)

    def test_credentials_are_gitignored(self):
        ignored = GITIGNORE.read_text(encoding="utf-8")
        self.assertIn("rclone.conf", ignored)


if __name__ == "__main__":
    unittest.main()
