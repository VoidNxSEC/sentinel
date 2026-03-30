# Batch 5 Runbook — Recovery & Documentation

**Owner**: release engineering  
**Scope**: gate 5 recovery + docs (see `sentinel/docs/go-live-goals.md`)

## Objective

Demonstrate that the platform can be rolled back, restored from backup, and documented before the final go/no-go decision. This block closes only after:

- a guarded backup of critical configs (`spectre/config`, TLS certs, secrets bundle) is produced and verified;
- the core stack can be stopped, restarted from the existing files, and passes healthchecks;
- the documentation describing the recovery steps is updated and referenced.

## Prerequisites

- Operating root: `/home/kernelcore/master`.
- `docker compose` profiles `core` and observability services can be controlled locally.
- `secrets/runtime.env.enc`, `secrets/nkeys.env.enc`, `secrets/tls/*.crt,key` exist.
- `sentinel/scripts/batch-5-recovery-check.sh` is executable (`chmod +x` already applied).

## Steps

1. **Backup configs**  
   Run `sentinel/scripts/batch-5-recovery-check.sh` to produce tarballs under `tmp/batch-5-backup`. It already archives `spectre/config`, TLS secrets, runtime bundle, and NKey bundle. Capture the tarball names for traceability.

2. **Exercise rollback**  
   The script also brings the core stack down cleanly with `docker compose --profile core down --remove-orphans`. This validates that a clean stop works without manual cleanup.

3. **Restore and verify**  
   The script then brings the stack back up (`docker compose --profile core up -d`), waits 10 s, prints `docker compose --profile core ps`, and calls the NATS and Phantom TLS health endpoints. Confirm both health checks return HTTP 200.

4. **Record evidence**  
   Save the `tmp/batch-5-backup` filenames in the release log along with the timestamp. Mention any deviations (e.g., services requiring longer startup) in the runbook notes.

5. **Documentation**  
   Update `sentinel/docs/go-live-goals.md` and `sentinel/ROADMAP.md` with:
   - Link to this runbook + script.
   - Mention that the rollback exercise passed on the current date.
   - Reference the health endpoints used for verification.

## Verification

- `docker compose --profile core ps` shows `healthy` state for nats, phantom-api, and ai-agent-os.
- `curl -fsS http://localhost:8222/healthz` and `curl -fsS --cacert secrets/tls/ca.crt https://localhost:8008/health` both exit 0.
- `tmp/batch-5-backup` contains tarballs with creation timestamps matching the run.

## Latest Result

Local validation passed on 2026-03-30.

- backup archives were created under `tmp/batch-5-backup`
- core rollback completed with `docker compose --profile core down --remove-orphans`
- post-restore health checks passed for NATS and Phantom TLS proxy

## After-action

- Tag the backup tarballs with the release identifier and move them to a durable archive (e.g., `~/backups/batch-5/`) if required.
- Link the backup evidence in `sentinel/docs/go-live-goals.md` under recovery gate notes.
