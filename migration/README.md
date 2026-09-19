# OneDrive -> Google Drive via rclone

Recommended workflow: Windows authentication/configuration + Linux home-server transfer.

## Google OAuth client required

Do not use rclone's shared Google Drive OAuth client. Create your own Google Cloud OAuth **Desktop app** client with the Google Drive API enabled, then keep the client ID and client secret handy.

For an existing `rclone.conf`, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\update-google-client.ps1
```

Paste the client ID and secret when prompted, then complete the Google browser sign-in. The script updates only `gdrive-dst`, reconnects it, and validates access.

For a completely new config, `setup-auth.ps1` now asks for the same private Google client credentials during setup.

## Home-server migration

Keep these files together on Windows:

- `rclone.conf`
- `home-server-migrate.ps1`
- `home-server-migrate.sh`

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\home-server-migrate.ps1
```

Defaults:

- SSH: `home@minipc`
- source: `onedrive-src:`
- destination: `gdrive-dst:OneDrive Migration 2`

The transfer uses `rclone copy --size-only`, so rerunning the same command skips matching completed files and continues the rest. It never uses `sync`, `move`, or source deletion.

Google/HTTP API traffic is capped at about 8 transactions/s with a burst of 1 to avoid hammering Drive API quotas.

### Malware-flagged OneDrive files

The script does **not** use `--onedrive-av-override`.

If OneDrive refuses a file because Microsoft flags it as malware, rclone records the path and continues the migration pass. Final verification permits only those exact malware-blocked paths to remain missing. Any other missing file, size mismatch, or verification error still fails the run.

The skipped paths are recorded under:

`~/.local/share/onedrive-gdrive-migration/reports/malware-skipped.txt`

### Ctrl+C

The migration runs through an SSH TTY. Press **Ctrl+C** to cancel the foreground rclone process. Source OneDrive data is never modified.

### Credentials

`rclone.conf` is uploaded only to a private temporary directory on the home server for the duration of a run. Refreshed OAuth tokens are copied back to Windows, then the temporary remote config is removed.

### OneNote

rclone hides OneNote notebook packages by default because they cannot be copied as ordinary files through the OneDrive backend. Export them separately if required.
