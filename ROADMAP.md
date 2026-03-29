# Sovereign Intelligence Platform — Production Roadmap

**Owner**: kernelcore
**Created**: 2026-03-28
**Updated**: 2026-03-29
**Target**: Production-ready event-driven AI operations platform

---

## Current State

All projects build. Umbrella Delivery (ADR-0050) completed the wiring layer.
Spectre events flow from owasaka → NATS → phantom-soc data-plane → control-plane GTK4 UI.
ai-agent-os publishes `system.metrics.v1`. Phantom API has all 7 endpoints. Spooknix has MCP tool.

**Orchestration layer (sentinel) is now complete**: unified compose with profiles, full integration
test suite (scenarios, chaos, performance), CI/CD pipelines, release workflow, and cross-platform
packaging scripts are all in place.

**Blocking**: services are wired in code but have not been validated against each other in a live
environment. M3 (security) and M4 (observability) are the next hard gates before production.

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

## Milestone 1 — Unified Compose & Local Dev (DONE)

**Goal**: `docker compose up` boots the entire platform locally.

### 1.1 — Top-level docker-compose.yml ✅
- [x] `/home/kernelcore/master/docker-compose.yml` — profiles: core, intelligence, gpu, observability, compliance, full
- [x] Service: **nats** (nats:2.10-alpine, ports 4222/8222/6222, JetStream)
- [x] Service: **phantom-api** (port 8008, depends_on nats healthy)
- [x] Service: **owasaka** (port 8080, depends_on nats healthy, NET_RAW cap)
- [x] Service: **ai-agent-os** (depends_on nats, profile: core)
- [x] Service: **cerebro** (profile: intelligence)
- [x] Service: **securellm-bridge** (port 8081, profile: intelligence)
- [x] Service: **spooknix** (port 8000, GPU profile, CUDA)
- [x] Service: **prometheus + grafana + jaeger** (profile: observability)
- [x] Service: **neotron** (temporal + postgres, profile: compliance)
- [x] Shared network `spectre-net` (172.28.0.0/16) for all services
- [x] `.env.example` with all required variables (consolidated)

### 1.2 — Nix flake for local dev
- [x] `sentinel/flake.nix` — remote flake inputs for all projects, custom test runner
- [ ] Top-level `flake.nix` in `/home/kernelcore/master/` composing all project shells
- [ ] `nix run .#nats` / `nix run .#phantom-api` / `nix run .#owasaka` app outputs
- [ ] `nix develop` — unified shell with all tools (cargo, go, python, bun)

### 1.3 — Smoke test script ✅
- [x] `sentinel/scripts/smoke-test.sh` — boots compose, health checks all endpoints, exit 1 on failure
- [x] Validates: NATS healthz/varz, phantom `/health` + `/ready` + `/metrics`

---

## Milestone 2 — Integration Tests (DONE — suite written, live validation pending)

**Goal**: Prove events flow across service boundaries.

### 2.1 — Spectre E2E ✅ (suite written)
- [x] Test: owasaka → NATS `network.asset.discovered.v1` → schema validation (`scenarios/test_spectre_e2e.py`)
- [x] Test: ai-agent-os → NATS `system.metrics.v1` → CPU/memory field validation
- [x] Test: DNS query event flow (`network.dns.query.v1`)
- [x] Test: All event subjects follow `{domain}.{entity}.{action}.v{version}` format
- [ ] **Live validation**: run against real stack (blocked on M1.2 flake + reconnect fixes)

### 2.2 — Phantom API E2E ✅ (suite written)
- [x] Test: upload file → `/vectors/search` returns it (`scenarios/test_phantom_e2e.py`)
- [x] Test: `/api/chat` with indexed context → sources in response
- [x] Test: multi-file upload
- [x] Test: `/metrics` returns Prometheus format
- [ ] Test: cortex-desktop → phantom-api proxy round-trip (Playwright — deferred)

### 2.3 — phantom-soc E2E
- [ ] Test: publish mock event to NATS → GTK4 LogViewer receives it (headless)
- [ ] Test: scheduler dequeues tasks when enqueued

### 2.4 — NATS reconnect
- [x] Test: kill NATS → owasaka/ai-agent-os survive + reconnect (`chaos/test_nats_reconnect.py`)
- [x] Test: partial boot → intelligence services gracefully unavailable (`chaos/test_partial_boot.py`)
- [x] Test: phantom degraded → cached responses served (`chaos/test_phantom_degraded.py`)
- [ ] **Fix**: add reconnect logic to owasaka `Publisher` (currently one-shot connect)
- [ ] **Fix**: add reconnect logic to ai-agent-os `nats_client` (currently one-shot connect)

### 2.5 — Performance / SLO ✅ (suite written)
- [x] Test: phantom-api P99 < 500ms (`performance/test_phantom_latency.py`)
- [x] Test: ≥20 req/s sustained throughput (`performance/test_throughput.py`)
- [x] Test: spooknix transcribe < 30s/min-audio (`performance/test_spooknix_latency.py`)

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
- [ ] Route all LLM calls through securellm-bridge (phantom providers → bridge → model)
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
- [ ] Thermal threshold alert from ai-agent-os → NATS → phantom-soc UI
- [ ] NATS consumer lag alert (data-plane falling behind)
- [ ] Phantom API error rate alert (>5% 5xx in 5min window)

---

## Milestone 5 — CI/CD (DONE)

**Goal**: Every push is tested and deployable.

### 5.1 — GitHub Actions ✅
- [x] `integration-tests.yml` — quick-tests (PR), full matrix (main), chaos (nightly), benchmarks
- [x] `ci.yml` — per-project build matrix (spectre, owasaka, phantom, ai-agent-os, neoland, website)
- [x] `release.yml` — integration gate → image builds → GHCR push → GitHub Release
- [x] PR template with ROADMAP checklist (`.github/pull_request_template.md`)
- [ ] Nix build cache (cachix `voidnxlabs`)

### 5.2 — Container images ✅
- [x] Images built in `release.yml`: phantom-api, owasaka, cerebro, securellm-bridge, spooknix
- [x] Multi-arch: `linux/amd64` + `linux/arm64`
- [x] Push to `ghcr.io/VoidNxSEC/{service}:{version}` on release

### 5.3 — Deploy
- [x] `packaging/nix/nixos-module.nix` — NixOS systemd services module
- [x] `docker-compose.yml` production profiles with restart policies and healthchecks
- [ ] Rollback procedure documented

---

## Milestone 6 — ML Pipeline (Neutron + Cerebro)

**Goal**: Training and knowledge extraction operational.

### 6.1 — Cerebro knowledge pipeline
- [ ] Cerebro consumes `ingest.file.sanitized.v1` from NATS
- [ ] Extracts knowledge → publishes `cognition.insight.generated.v1`
- [ ] Phantom RAG indexes insights from Cerebro

### 6.2 — Neutron training jobs
- [ ] Neutron consumes `compute.job.submitted.v1`
- [ ] Reports progress via `compute.model.trained.v1`
- [ ] Integration with phantom for model serving

### 6.3 — ml-ops-api
- [ ] Bridge neoland/phantom local inference to remote GPU when available
- [ ] Fallback chain: local candle → ml-ops-api → securellm-bridge

---

## Milestone 7 — Production Deploy

**Goal**: Running on real hardware, serving real users.

### 7.1 — NixOS deployment
- [x] NixOS configuration module for full stack (`packaging/nix/nixos-module.nix`)
- [ ] Systemd services with watchdog and auto-restart (wired in module, needs real deploy test)
- [ ] Firewall rules (only expose: phantom-api 8008, cortex-desktop 1420, spooknix 8000)

### 7.2 — Backup & DR
- [ ] PostgreSQL backup for neoland vector store
- [ ] NATS JetStream persistence for critical events
- [ ] Git-based config backup (ADR ledger is already git-versioned)

### 7.3 — SLO validation ✅ (tests written)
- [x] P99 latency targets: phantom-api < 500ms, spooknix transcribe < 30s/min-audio
- [x] Availability target: 99.5% uptime (tested via chaos suite)
- [ ] Neoland readiness score target: 85/100 (currently 65/100)

---

## Milestone 8 — Distribution (NEW)

**Goal**: Installable on NixOS, Linux, macOS, Windows. Zero manual setup.

### 8.1 — NixOS / nixpkgs upstream
- [x] `packaging/nix/nixos-module.nix` — systemd services + SOPS secrets
- [ ] Submit `spooknix` to nixpkgs (most standalone, good first PR)
- [ ] Submit `cerebro`, `phantom` after spooknix lands

### 8.2 — Linux (Debian/Ubuntu)
- [x] `packaging/deb/build.sh` — builds `.deb` via cargo-deb + fpm
- [x] `packaging/deb/postinst.sh` — service user + systemd unit setup
- [ ] GitHub Releases asset upload (wired in `release.yml`)
- [ ] Optional: Launchpad PPA

### 8.3 — Linux (RHEL/Fedora)
- [x] `packaging/rpm/build.sh` — builds `.rpm` via fpm
- [ ] Copr repository for Fedora users
- [ ] GitHub Releases asset upload

### 8.4 — macOS (Darwin aarch64 + x86_64)
- [x] `packaging/macos/build.sh` — universal binary via `lipo`
- [x] `packaging/macos/homebrew-formula.rb` — Homebrew formula for custom tap
- [ ] Publish tap as `VoidNxSEC/homebrew-voidnxlabs`
- [ ] Submit to Homebrew core (after tap matures)

### 8.5 — Windows (amd64)
- [x] `packaging/windows/build.ps1` — cross-compile + PyInstaller bundles
- [x] `packaging/windows/wix-config.wxs` — `.msi` installer config
- [ ] Submit winget manifest to `microsoft/winget-pkgs`
- [ ] GitHub Releases `.msi` asset upload

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
| **sentinel** | **Orchestrator** | **yes** | **suite complete** | **N/A** | **CI/CD + dist ready** |

---

## Priority Order

```
M1 (compose) ✅  ->  M2 (integration tests) ✅  ->  M3 (security) ← YOU ARE HERE
                                                           |
                                                           v
M4 (observability)  ->  M5 (CI/CD) ✅  ->  M6 (ML pipeline)  ->  M7+M8 (deploy + dist)
```

**Immediate blockers:**
1. NATS reconnect logic in owasaka + ai-agent-os (M2.4 — code fix required)
2. NKey credentials + ACLs (M3.1 — unlocks secure multi-service comms)
3. Live stack validation — run `pytest scenarios/ chaos/ performance/` against real compose

---

## References

- ADR-0050: Umbrella Delivery Roadmap (adr-ledger)
- Domain Manifest v2.1.0: `phantom-ray/phantom-stack/specs/DOMAIN_MANIFEST.md`
- Spectre docker-compose: `spectre/docker-compose.yml` (NATS + TimescaleDB + Neo4j)
- Unified compose: `~/master/docker-compose.yml`
- Sentinel test suite: `sentinel/scenarios/`, `sentinel/chaos/`, `sentinel/performance/`
- Packaging: `sentinel/packaging/` (nix, deb, rpm, macos, windows)
