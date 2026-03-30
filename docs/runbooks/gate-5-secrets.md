# Gate 5 Runbook - Secrets Validation

**Audience**: Operators and release owners
**Scope**: Gate 5 from `sentinel/docs/go-live-goals.md`
**Last updated**: 2026-03-30

---

## Goal

Validate that production-required secrets are managed through SOPS and injected consistently.

This gate covers:
- SOPS baseline and encrypted artifacts
- remaining runtime secret targets (`HF_TOKEN`, `DATABASE_URL`, provider keys)
- plaintext secret regression checks
- runtime bundle presence for production secrets

---

## Run

Preferred helper:

```bash
nix run .#gate-5-secrets
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/gate-5-secrets-check.sh
```

---

## Pass Criteria

Gate 5 is `PASS` only when:
- SOPS baseline files and rotation scripts exist
- remaining production secret targets are documented
- no tracked plaintext secret values exist in the repository
- an encrypted runtime secret bundle exists for the remaining production secrets

If any criterion fails, Gate 5 is `NO-GO`.

---

## Current Expected Failure

This gate is expected to fail until the non-NKey runtime secrets are moved into encrypted bundles
and wired into the live stack.
