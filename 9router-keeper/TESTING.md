# 9Router Keeper test branch

This branch is dedicated to validating the Windows keeper artifact before use.

Artifact: `artifacts/9RouterKeeper-v1.1.zip`

SHA-256: `d702398609c04ee59073ff69ebe303a729a9688281f3da4ab789d7211ca7126a`

The Windows CI validates:

- PowerShell 5.1 parsing for every shipped `.ps1` file.
- JSON configuration parsing and required safety defaults.
- Healthy `/api/health` path exits without recovery.
- An unrelated process owning port 20128 is not killed.
- The exact ZIP committed on this branch is the ZIP tested by CI.

Tunnel process/public URL recovery remains delegated to 9Router; the keeper only escalates by restarting 9Router after configured grace periods.
