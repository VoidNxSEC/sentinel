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
- runtime bundle presence for production secrets (`secrets/runtime.env.enc`)

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

## Runtime Bundle

Current baseline bundle:
- `secrets/runtime.env.enc`

Target entries:
- `HF_TOKEN`
- `DATABASE_URL`
- `DEEPSEEK_API_KEY`
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`

This closes the encrypted bundle baseline. Per-service adoption is still only complete when the live
stack consumes these values through documented runtime injection.
