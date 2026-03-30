# Batch 5 Runbook — Recovery & Documentation

**Owner**: release engineering  
**Scope**: gate 5 recovery + docs (see `sentinel/docs/go-live-goals.md`)

## Objective

Demonstrate that the platform can be rolled back, restored from backup, and documented before the final go/no-go decision. This block closes only after:

- a guarded backup of critical configs (`spectre/config`, TLS certs, secrets bundle) is produced and verified;
- a git-based snapshot of the active config repos is captured for audit and rollback reference;
- the core stack can be stopped, restarted from the existing files, and passes healthchecks;
- the documentation describing the recovery steps is updated and referenced.

## Prerequisites

- Operating root: `/home/kernelcore/master`.
- `docker compose` profiles `core` and observability services can be controlled locally.
- `secrets/runtime.env.enc`, `secrets/nkeys.env.enc`, `secrets/tls/*.crt,key` exist.
- `sentinel/scripts/batch-5-recovery-check.sh` and `sentinel/scripts/backup-config-git.sh` are executable.
- `git` is available locally for bundle generation.

## Steps

1. **Backup configs**  
   Run `sentinel/scripts/batch-5-recovery-check.sh` to produce evidence under `tmp/batch-5-backup`. It archives `spectre/config`, TLS secrets, runtime bundle, and NKey bundle, then runs `sentinel/scripts/backup-config-git.sh` to emit `.bundle` snapshots plus tracked-change patches for `master`, `sentinel`, and `spectre`. Capture the tarball names and `git-config-<timestamp>/manifest.tsv` path for traceability.

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
- `tmp/batch-5-backup/git-config-<timestamp>/manifest.tsv` exists and lists the generated git bundles.

## Latest Result

Local validation passed on 2026-03-30.

- backup archives were created under `tmp/batch-5-backup`
- git config bundles were captured for `master`, `sentinel`, and `spectre`
- core rollback completed with `docker compose --profile core down --remove-orphans`
- post-restore health checks passed for NATS and Phantom TLS proxy

## After-action

- Tag the backup tarballs and git bundle directory with the release identifier and move them to a durable archive (e.g., `~/backups/batch-5/`) if required.
- Link the backup evidence in `sentinel/docs/go-live-goals.md` under recovery gate notes.
