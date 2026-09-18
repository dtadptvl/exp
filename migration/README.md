# OneDrive -> Google Drive via rclone

The current recommended path is the home-server workflow. Colab notebooks remain in this folder only as earlier experiments.

## 1. Windows authentication

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-auth.ps1
```

This creates `rclone.conf` with:

- `onedrive-src:` — Microsoft OneDrive source, read-only scopes;
- `gdrive-dst:` — personal Google Drive destination.

Keep `rclone.conf` private. It is git-ignored.

## 2. Run on the home server

Requirements on Windows: built-in OpenSSH `ssh` and `scp`.

From the folder containing `rclone.conf`, `home-server-migrate.ps1`, and `home-server-migrate.sh`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\home-server-migrate.ps1
```

Default SSH target is `home@minipc`. The launcher:

1. connects to the Linux home server;
2. uploads the private `rclone.conf` and the migration shell script;
3. installs a portable rclone under `~/.local/share/onedrive-gdrive-migration/bin/` if needed, without sudo;
4. validates both remotes;
5. checks `onedrive-src:` against `gdrive-dst:OneDrive Migration`;
6. if complete, exits without copying;
7. if files are missing or have a different size, resumes with `rclone copy --size-only`;
8. verifies again.

It never uses `sync`, `move`, or source deletion.

To use another SSH target:

```powershell
.\home-server-migrate.ps1 -Server user@host
```

### Verification semantics

Cross-cloud verification uses `rclone check --one-way --size-only`. Every source file must exist at the destination with the same size. Extra files already present in Google Drive do not cause failure.

The resume copy also uses `--size-only`, so same-size files are skipped and missing/different-size files are transferred again. This matches the verification criterion and avoids unnecessary retransfers.

### OneNote limitation

rclone hides OneNote notebook packages by default because they cannot be copied as normal files through the OneDrive backend. Export OneNote notebooks separately if the account contains them.
