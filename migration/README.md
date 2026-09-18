# OneDrive -> Google Drive via rclone

The recommended path is now the home-server workflow. Colab notebooks remain only as earlier experiments.

## Windows authentication

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-auth.ps1
```

This creates `rclone.conf` with a read-only OneDrive source and personal Google Drive destination.

## Fresh migration on home server

Put these files together on Windows:

- `rclone.conf`
- `home-server-migrate.ps1`
- `home-server-migrate.sh`

Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\home-server-migrate.ps1
```

Defaults:

- SSH server: `home@minipc`
- source: `onedrive-src:`
- destination: `gdrive-dst:OneDrive Migration 2`

The old `OneDrive Migration` folder is untouched.

The migration runs in the foreground through an SSH TTY. Press **Ctrl+C** at any time to cancel. The remote shell traps the interrupt and terminates the foreground migration; source data is never modified.

After a successful copy, the script runs `rclone check --one-way --size-only`.

To use another fresh destination folder:

```powershell
.\home-server-migrate.ps1 -DestinationFolder "OneDrive Migration 3"
```

The launcher keeps `rclone.conf` only in a private temporary directory on the home server during the run, retrieves refreshed OAuth tokens afterward, then removes the temporary remote config.

No `sync`, `move`, source deletion, or destination deletion is used.

### Interrupted run

If you cancel with Ctrl+C, already completed uploads may remain in the new destination folder. Running the same command again is safe: `rclone copy --size-only` skips matching completed files and continues the rest. If you truly want another completely clean attempt, choose another new `-DestinationFolder`.

### OneNote limitation

rclone hides OneNote notebook packages by default because they cannot be copied as normal files through the OneDrive backend. Export OneNote notebooks separately if the account contains them.
