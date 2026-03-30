# Go-Live Goals — Operational Baseline

**Audience**: Operators, maintainers, and release owners
**Scope**: Production deployment readiness for the voidnxlabs stack
**Last updated**: 2026-03-30

---

## Purpose

This document is the base operational checklist for go-live. It turns the roadmap into release
gates that can be executed, verified, and documented across the participating projects.

Use this file as the source of truth for:
- deployment readiness gates
- operational validation order
- documentation updates required before production rollout

---

## Release Goal

The platform is ready for production only when:
- the real stack boots cleanly
- critical event flows pass against the live stack
- NATS auth and TLS/mTLS are validated in the deployment environment
- production secrets are managed through SOPS
- logs and tracing are sufficient for incident response
- rollback and recovery procedures are documented and exercised
- project documentation matches the real operating model

---

## Operational Gates

### 1. Stack Bring-Up

**Goal**: The deployed stack starts cleanly and remains stable.

**Success criteria**
- `docker compose` or NixOS services start without crash loops
- all critical healthchecks become green
- service dependencies resolve in the expected order

**Blocks go-live if**
- NATS, phantom, owasaka, securellm-bridge, or other core services remain degraded
- restart policies mask startup instability
- the stack only boots in partial or manual order

### 2. Smoke Validation

**Goal**: Critical service endpoints respond correctly immediately after bring-up.

**Success criteria**
- NATS health endpoints respond
- phantom `/health`, `/ready`, and `/metrics` succeed
- smoke tests pass without manual intervention

**Blocks go-live if**
- readiness is inconsistent
- essential endpoints fail intermittently
- the smoke path depends on hidden local state

### 3. Event Flow Validation

**Goal**: Critical cross-service flows work on the live stack.

**Success criteria**
- Spectre E2E passes against the running environment
- phantom-soc E2E passes against the running environment
- critical event schemas, routing, and ordering remain intact

**Blocks go-live if**
- events do not traverse producers, NATS, and consumers correctly
- consumers start but fail to process real traffic
- ordering or envelope validation breaks under live conditions

### 4. Security Validation

**Goal**: Service-to-service communication is authenticated and encrypted.

**Success criteria**
- NATS auth E2E passes with the real auth configuration loaded
- TLS/mTLS validation succeeds with trusted CA material
- ACLs reflect least-privilege behavior in practice

**Blocks go-live if**
- unauthorized publish or subscribe paths are possible
- clients connect without the required certificates or credentials
- production deployment falls back to insecure transport

### 5. Secrets Gate

**Goal**: Production secrets are not managed manually or in plaintext.

**Success criteria**
- `HF_TOKEN`, `DATABASE_URL`, and remaining API keys are handled through SOPS
- operators can rotate and recover secrets through documented procedures
- no required production secret depends on an ad hoc shell export

**Blocks go-live if**
- secrets still live in plaintext env files
- secret injection is inconsistent across services
- recovery depends on undocumented local operator knowledge

### 6. Observability Gate

**Goal**: Operators can diagnose failures quickly and correlate events across the stack.

**Success criteria**
- structured JSON logs are emitted by the required services
- centralized log aggregation is available
- correlation IDs propagate across requests and NATS events

**Blocks go-live if**
- production debugging depends on container-local log scraping only
- operators cannot trace one incident across multiple services
- alerts fire without enough context to triage the source

### 7. Rollback And Recovery Gate

**Goal**: The stack can be reverted and restored safely during an incident.

**Success criteria**
- rollback steps are documented and current
- rollback has been exercised, not only written down
- database and JetStream recovery procedures are validated

**Blocks go-live if**
- rollback exists only in theory
- restore steps are incomplete or stale
- operators cannot recover to a known-good version quickly

### 8. Documentation Gate

**Goal**: Operational reality is reflected in project documentation.

**Success criteria**
- each participating project documents the current bring-up path
- required environment variables and secrets are documented
- auth, TLS, observability, troubleshooting, and rollback docs are current

**Blocks go-live if**
- docs diverge from code or deployment behavior
- critical operational steps exist only in chat or memory
- project readmes omit production-critical requirements

---

## Execution Order

Run the gates in this order:
1. stack bring-up
2. smoke validation
3. event flow validation
4. security validation
5. secrets gate
6. observability gate
7. rollback and recovery gate
8. documentation gate
9. final go or no-go decision

## Batch Runbooks

- Batch 1: `sentinel/docs/runbooks/batch-1-bringup-smoke.md`

---

## Final Decision Rule

Declare `GO` only when all gates above pass in the same operational window and evidence is captured
for each one.

Declare `NO-GO` when any gate fails, is skipped, or depends on undocumented manual recovery.

---

## Documentation Update Targets

The following projects should be reviewed before production rollout:
- `sentinel`
- `phantom`
- `owasaka`
- `ai-agent-os`
- `phantom-soc`
- `securellm-bridge`
- `spooknix` if included in the production profile

Each project should cover:
- current startup and deployment path
- required environment variables
- SOPS-managed secrets
- NATS auth and TLS expectations
- observability endpoints and log behavior
- troubleshooting guidance
- rollback or recovery references

---

## Working Rule

No operationally relevant change is complete until:
- the validation path exists
- the rollback path exists
- the documentation is updated
