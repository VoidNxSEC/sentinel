# Sovereign Intelligence Platform — Production Roadmap

**Owner**: kernelcore
**Created**: 2026-03-28
**Target**: Production-ready event-driven AI operations platform

---

## Current State

All projects build. Umbrella Delivery (ADR-0050) completed the wiring layer:
Spectre events flow from owasaka -> NATS -> phantom-soc data-plane -> control-plane GTK4 UI.
ai-agent-os publishes `system.metrics.v1`. Phantom API has all 7 endpoints. Spooknix has MCP tool.

What's missing: **nothing talks to each other yet in a real environment**.
There is no unified compose, no integration tests across services, no TLS, no auth.

---

## Milestone 0 — Foundation (DONE)

- [x] Spectre event types defined (9 variants + `system.metrics.v1`)
- [x] Owasaka publishes `network.asset.discovered.v1` / `network.dns.query.v1` to NATS
- [x] phantom-soc data-plane consumes NATS events
- [x] phantom-soc control-plane GTK4 LogViewer wired to EventBus
- [x] phantom-soc scheduler fix (`dequeue(&self)` via tokio Mutex)
- [x] ai-agent-os publishes `system.metrics.v1` to NATS
- [x] Phantom API: all 7 endpoints + `/api/upload` multi-file
- [x] Spooknix MCP tool (`spooknix_health`, `spooknix_transcribe`, `spooknix_diarize`)
- [x] Domain Manifest v2.1.0 updated

---

## Milestone 1 — Unified Compose & Local Dev

**Goal**: `docker compose up` (or `nix run .#dev-stack`) boots the entire platform locally.

### 1.1 — Top-level docker-compose.yml
- [ ] Create `/home/kernelcore/master/docker-compose.yml`
- [ ] Service: **nats** (nats:2.11-alpine, ports 4222/8222)
- [ ] Service: **phantom-api** (uvicorn, port 8008, depends_on nats)
- [ ] Service: **spooknix-server** (GPU, port 8000)
- [ ] Service: **owasaka** (Go binary, depends_on nats)
- [ ] Service: **cortex-desktop** (dev server, port 1420, proxies to phantom-api)
- [ ] Shared network `spectre-net` for all services
- [ ] `.env.example` with all required variables

### 1.2 — Nix flake for local dev
- [ ] Top-level `flake.nix` in `/home/kernelcore/master/` that composes all project shells
- [ ] `nix run .#nats` — start NATS standalone
- [ ] `nix run .#phantom-api` — start API
- [ ] `nix run .#owasaka` — start network sensor
- [ ] `nix develop` — enters shell with all tools available

### 1.3 — Smoke test script
- [ ] `scripts/smoke-test.sh`: boots compose, waits for health, curls all endpoints, tears down
- [ ] Validates: NATS reachable, phantom `/health` 200, spooknix `/health` 200, owasaka running

---

## Milestone 2 — Integration Tests (End-to-End)

**Goal**: Prove events flow across service boundaries.

### 2.1 — Spectre E2E
- [ ] Test: owasaka ARP scan -> NATS `network.asset.discovered.v1` -> data-plane consumer receives it
- [ ] Test: ai-agent-os collect -> NATS `system.metrics.v1` -> verify payload schema
- [ ] Test: phantom `/extract` -> data-plane gets `ingest.file.created.v1` (when wired)

### 2.2 — Phantom API E2E
- [ ] Test: upload file via `/api/upload` -> verify `/vectors/search` returns it
- [ ] Test: `/api/chat` with indexed context -> verify sources in response
- [ ] Test: cortex-desktop -> phantom-api proxy round-trip (Playwright or similar)

### 2.3 — phantom-soc E2E
- [ ] Test: publish mock event to NATS -> verify GTK4 LogViewer receives it (headless)
- [ ] Test: scheduler dequeues tasks when enqueued

### 2.4 — NATS reconnect
- [ ] Test: kill NATS, verify owasaka/ai-agent-os survive, reconnect when NATS returns
- [ ] Add reconnect logic to owasaka `Publisher` (currently one-shot connect)
- [ ] Add reconnect logic to ai-agent-os `nats_client` (currently one-shot connect)

---

## Milestone 3 — Security Hardening

**Goal**: Zero-trust between services. No plaintext secrets.

### 3.1 — NATS Auth
- [ ] Generate NATS NKey credentials per service (owasaka, ai-agent-os, phantom-soc, phantom)
- [ ] Configure NATS server with per-subject ACLs (owasaka can only publish `network.*`, etc.)
- [ ] Update all publishers/consumers to use NKey auth

### 3.2 — TLS everywhere
- [ ] NATS TLS (mTLS between services)
- [ ] Phantom API behind TLS (caddy or nginx reverse proxy in compose)
- [ ] Spooknix server TLS (currently plain HTTP)

### 3.3 — Secrets management
- [ ] Move all secrets to SOPS/Vault (HF_TOKEN, DATABASE_URL, NKey seeds)
- [ ] No secrets in `.env` files committed to git
- [ ] Document secret rotation procedure

### 3.4 — SecureLLM Bridge integration
- [ ] Route all LLM calls through securellm-bridge (phantom providers -> bridge -> model)
- [ ] Rate limiting and audit logging via bridge
- [ ] Bridge health check in phantom `/ready` endpoint

---

## Milestone 4 — Observability

**Goal**: Know what's happening across the platform in real-time.

### 4.1 — Metrics
- [ ] Prometheus scrape config for: phantom-api `/metrics`, spooknix `/metrics`, NATS `/varz`
- [ ] Grafana dashboard: API latency, NATS throughput, event counts by type
- [ ] ai-agent-os system metrics dashboard (CPU/mem/thermal from `system.metrics.v1`)

### 4.2 — Logging
- [ ] Structured JSON logs from all services (tracing-subscriber for Rust, python-json-logger for Python)
- [ ] Loki or similar log aggregation
- [ ] Correlation IDs propagated across NATS events (spectre `correlation_id` field)

### 4.3 — Alerting
- [ ] Thermal threshold alert from ai-agent-os -> NATS -> phantom-soc UI
- [ ] NATS consumer lag alert (data-plane falling behind)
- [ ] Phantom API error rate alert (>5% 5xx in 5min window)

---

## Milestone 5 — CI/CD

**Goal**: Every push is tested and deployable.

### 5.1 — GitHub Actions
- [ ] Matrix build: spectre (cargo), owasaka (go), phantom (python), ai-agent-os (cargo), spooknix (python)
- [ ] Integration test job: boots compose, runs smoke-test.sh
- [ ] Nix build cache (cachix or attic)

### 5.2 — Container images
- [ ] Multi-stage Dockerfiles for: phantom-api, owasaka, ai-agent-os
- [ ] Image pushed to GHCR on merge to main
- [ ] Spooknix CUDA image (already has Dockerfile, verify it builds in CI)

### 5.3 — Deploy
- [ ] NixOS module for the full stack (systemd services + NATS + certs)
- [ ] Or: docker-compose production profile with restart policies and healthchecks
- [ ] Rollback procedure documented

---

## Milestone 6 — ML Pipeline (Neutron + Cerebro)

**Goal**: Training and knowledge extraction operational.

### 6.1 — Cerebro knowledge pipeline
- [ ] Cerebro consumes `ingest.file.sanitized.v1` from NATS
- [ ] Extracts knowledge -> publishes `cognition.insight.generated.v1`
- [ ] Phantom RAG indexes insights from Cerebro

### 6.2 — Neutron training jobs
- [ ] Neutron consumes `compute.job.submitted.v1`
- [ ] Reports progress via `compute.model.trained.v1`
- [ ] Integration with phantom for model serving

### 6.3 — ml-offload-api
- [ ] Bridge neoland/phantom local inference to remote GPU when available
- [ ] Fallback chain: local candle -> ml-offload-api -> securellm-bridge

---

## Milestone 7 — Production Deploy

**Goal**: Running on real hardware, serving real users.

### 7.1 — NixOS deployment
- [ ] NixOS configuration module for full stack
- [ ] Systemd services with watchdog and auto-restart
- [ ] Firewall rules (only expose: phantom-api 8008, cortex-desktop 1420, spooknix 8000)

### 7.2 — Backup & DR
- [ ] PostgreSQL backup for neoland vector store
- [ ] NATS JetStream persistence for critical events
- [ ] Git-based config backup (ADR ledger is already git-versioned)

### 7.3 — SLO validation
- [ ] P99 latency targets: phantom-api < 500ms, spooknix transcribe < 30s/min-audio
- [ ] Availability target: 99.5% uptime for core services (phantom-api, NATS)
- [ ] Neoland readiness score target: 85/100 (currently 65/100)

---

## Project Status Matrix

| Project | Phase | Builds | Tests | NATS Wired | Prod Ready |
|---------|-------|--------|-------|------------|------------|
| spectre | Phase 0 done | yes | 11/11 | N/A (is the bus) | infra yes |
| owasaka | All 6 phases | yes | 35 pass | publishes | needs reconnect |
| phantom | Phase 1 done | yes | 70%+ cov | not yet | API yes, needs TLS |
| phantom-soc/control | A5 done | yes | — | subscribes (EventBus) | dev only |
| phantom-soc/data | A4 done | yes | — | consumes | dev only |
| ai-agent-os | Phase 1 done | yes | 2/2 | publishes | needs reconnect |
| neoland | 65/100 | yes | 118 pass | no | needs SLO |
| spooknix | Sprint 3 done | yes | — | no | needs TLS |
| cerebro | Phase 4 done | — | 112 pass | no | needs NATS wire |
| securellm-bridge | Core done | yes | — | no | needs phantom wire |
| securellm-mcp | Phase 1 done | yes | — | N/A | prod ready |
| intelagent | Foundation | yes | core only | no | scaffolding, ADR-0054 decoupled |
| phantom-soc-kernel | Kernel done | yes | — | no | backend complete, needs UI wire |
| adr-ledger | Alpha | — | — | N/A | docs only |

---

## Priority Order

```
M1 (compose)  ->  M2 (integration tests)  ->  M3 (security)
      |                    |                         |
      v                    v                         v
M4 (observability)  ->  M5 (CI/CD)  ->  M6 (ML pipeline)  ->  M7 (deploy)
```

**Blocking path**: M1 unblocks everything. Without a unified compose, no integration tests are possible.

**Quick wins**: M1.1 (compose) + M2.1 (spectre E2E) can be done in a single session.

---

## References

- ADR-0050: Umbrella Delivery Roadmap (adr-ledger)
- Domain Manifest v2.1.0: `phantom-ray/phantom-stack/specs/DOMAIN_MANIFEST.md`
- Spectre docker-compose: `spectre/docker-compose.yml` (NATS + TimescaleDB + Neo4j)
