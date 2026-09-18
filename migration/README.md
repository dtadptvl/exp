# OneDrive -> Google Drive via rclone + Colab

This is intentionally a two-step workflow:

1. Run `setup-auth.ps1` on Windows to authenticate `onedrive-src` and `gdrive-dst` and produce `rclone.conf`.
2. Open `colab-migrate.ipynb` in Google Colab, run the cells in order, upload that `rclone.conf`, then let Colab perform the transfer.

## Windows authentication

Open PowerShell in this folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-auth.ps1
```

The script downloads a temporary rclone binary, opens browser-based authentication for Microsoft and Google, validates both remotes, writes `rclone.conf` next to the script, then removes the temporary rclone files.

The OneDrive remote requests read-only scopes. If the Microsoft 365 tenant blocks user consent, rclone will fail clearly; an administrator must allow the rclone OAuth app or the tenant must use its own permitted OAuth app registration.

`rclone.conf` contains OAuth tokens. It is git-ignored and must not be committed or shared.

## Colab migration

Open `colab-migrate.ipynb` in Google Colab and run all cells in order. The notebook:

- installs current rclone in the Colab VM;
- asks you to upload `rclone.conf`;
- validates both remotes;
- copies `onedrive-src:` to `gdrive-dst:OneDrive Migration` with `rclone copy`;
- shows progress;
- verifies every source path exists at the destination with the same size using `rclone check --one-way --size-only`.

A rerun is safe: `rclone copy` skips matching destination files and never deletes destination files. It never writes to or deletes from OneDrive.

### Verification limit

OneDrive and Google Drive do not expose a common checksum suitable for direct cross-cloud verification, so the practical post-copy check verifies path + size. A byte-for-byte `rclone check --download` would download both sides again and is intentionally not used because it roughly doubles transfer traffic.

### OneNote limitation

rclone hides OneNote notebook packages by default because they cannot be opened/copied as normal files through the OneDrive backend. Export OneNote notebooks separately if the account contains them.
