# voidnxlabs — AI Infrastructure & Security Engineering

> Boutique engineering firm specializing in AI infrastructure, security systems, and DevOps.
> Cloud-agnostic. On-prem or multi-cloud. We design, build, and operate production-grade intelligent infrastructure.

**Maintainer**: kernelcore
**License**: MIT / Apache-2.0 (per project)
**GitHub**: github.com/voidnxlabs

---

## 🗂️ Project Catalog

| Project | Lang | Purpose | Port | Nix Output | Status |
|---------|------|---------|------|------------|--------|
| spectre | Rust | Event bus (NATS backbone) | 4222 | `spectre#spectre-proxy` | Prod |
| owasaka | Go | Network SIEM + asset discovery | 8080 | `owasaka#oswaka` | Prod |
| phantom | Python | Document intelligence + RAG | 8008 | `phantom#phantom-api` | Prod |
| phantom-soc/control | Rust/GTK4 | SOC dashboard | — | `phantom-soc#control-plane` | Beta |
| phantom-soc/data | Python | NATS event consumer | — | — | Beta |
| ai-agent-os | Rust | System monitoring agent | — | `ai-agent-os#ai-agent` | Beta |
| neoland | Rust | AI assistant TUI | — | `neoland#neoland` | Beta |
| spooknix | Python | Privacy-first STT | 8000 | — | Beta |
| cerebro | Python | Knowledge extraction + RAG | — | `cerebro#cerebro` | Beta |
| securellm-bridge | Rust | Zero-trust LLM proxy | 8080 | `securellm-bridge#bridge` | Prod |
| securellm-mcp | TS | MCP server for IDEs | — | `securellm-mcp#mcp` | Prod |
| neotron | Solidity/Py | Compliance engine | 7233 | — | Alpha |
| cortex-desktop | TS/Rust | Tauri desktop UI | 1420 | — | Beta |
| sentinel | Python | Security monitoring | — | — | Beta |
| spider-nix | Python | Nix dependency analysis | — | — | Beta |
| adr-ledger | — | Architecture decisions | — | — | Active |

### Projects in `~/arch` (not in compose/CI yet)

swissknife, matrix, chainscope, astrix, actions-tv, algo-dev, phishyx, low_level, portfolio

---

## 🏗️ Architecture

```
                    ┌──────────────┐
                    │  NATS 4222   │  ← Spectre event bus
                    └──────┬───────┘
           ┌───────────────┼───────────────┐
           │               │               │
    ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
    │  owasaka    │ │ ai-agent-os │ │ phantom-soc │
    │  (Go)       │ │  (Rust)     │ │  data-plane │
    │ network.*   │ │ system.*    │ │  (Python)   │
    └─────────────┘ └─────────────┘ └──────┬──────┘
                                           │
                                    ┌──────▼──────┐
                                    │ phantom-soc │
                                    │ control-pln │
                                    │  (GTK4 UI)  │
                                    └─────────────┘

    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │  phantom    │ │  cerebro    │ │  spooknix   │
    │  (FastAPI)  │ │ (knowledge) │ │  (Whisper)  │
    │  :8008      │ │             │ │  :8000      │
    └──────┬──────┘ └─────────────┘ └─────────────┘
           │
    ┌──────▼──────┐
    │   cortex    │
    │  desktop    │
    │ (Tauri+Sv5) │
    └─────────────┘

    ┌─────────────┐ ┌─────────────┐
    │ securellm   │ │ securellm   │
    │  bridge     │ │    mcp      │
    │  (Rust)     │ │   (TS)      │
    └─────────────┘ └─────────────┘
```

---

## 📏 Development Rules

1. **Nix-first**: All commands via `nix develop --command <tool>`. No global installs.
2. **Build before commit**: Every change must pass `cargo build` / `go build ./...` / `python -c "import phantom"`.
3. **Sequential delivery**: Work one project at a time, following dependency order.
4. **Real services for tests**: Integration tests use `docker compose up -d`, never mocks for external deps.
5. **Spectre schema**: All inter-service events use `{domain}.{entity}.{action}.v{version}` subjects.
6. **No dead code**: If you remove a feature, delete the code. No `// removed` comments, no `_unused` vars.
7. **Minimal changes**: Don't refactor surrounding code when fixing a bug. Don't add features that weren't asked for.

---

## 🔌 Port Registry

| Port | Service | Protocol | Notes |
|------|---------|----------|-------|
| 4222 | NATS client | TCP | Spectre event bus |
| 8222 | NATS monitoring | HTTP | JetStream stats |
| 6222 | NATS cluster | TCP | Internal routing |
| 8008 | phantom-api | HTTP | FastAPI REST |
| 8000 | spooknix | HTTP | Whisper STT |
| 8080 | securellm-bridge | HTTP | LLM proxy |
| 8081 | llama.cpp | HTTP | Local LLM inference |
| 1420 | cortex-desktop | HTTP | Tauri dev server |
| 5432 | TimescaleDB | TCP | Observability DB |
| 9090 | Prometheus | HTTP | Metrics |
| 3001 | Grafana | HTTP | Dashboards |
| 7474 | Neo4j HTTP | HTTP | Graph DB browser |
| 7687 | Neo4j Bolt | TCP | Graph DB driver |
| 16686 | Jaeger | HTTP | Tracing UI |

---

## 📡 Spectre Event Registry

All events follow the `{domain}.{entity}.{action}.v{version}` subject schema.
Source: `spectre/crates/spectre-events/src/event.rs`

| Subject | Source | Consumer |
|---------|--------|----------|
| `network.asset.discovered.v1` | owasaka | phantom-soc data-plane |
| `network.dns.query.v1` | owasaka | phantom-soc data-plane |
| `network.dns.threat.v1` | owasaka | — |
| `network.service.detected.v1` | owasaka | — |
| `network.topology.updated.v1` | owasaka | — |
| `system.metrics.v1` | ai-agent-os | phantom-soc data-plane |
| `ingest.file.created.v1` | phantom | — |
| `ingest.file.sanitized.v1` | phantom | — |
| `cognition.query.received.v1` | cerebro | — |
| `cognition.insight.generated.v1` | cerebro | — |
| `llm.request.v1` | securellm-bridge | spectre |
| `llm.response.v1` | securellm-bridge | spectre |
| `analysis.request.v1` | phantom | spectre |
| `analysis.response.v1` | phantom | spectre |

---

## 🚀 Quick Start

```bash
# 1. Clone
git clone git@github.com:voidnxlabs/master.git && cd master

# 2. Boot infrastructure
docker compose up -d   # NATS + phantom-api + owasaka

# 3. Verify
curl localhost:8008/health  # → {"status": "operational"}
curl localhost:8222/healthz  # → (NATS ok)

# 4. Enter any project shell
cd spectre && nix develop   # Rust + cargo + clippy
cd phantom && nix develop   # Python + pytest + ruff
cd owasaka && nix develop   # Go + golangci-lint

# 5. Run tests
nix develop --command cargo test    # Rust projects
nix develop --command go test ./... # Go projects
nix develop --command pytest        # Python projects
```

### Makefile Targets

```bash
make dev          # Boot core services (NATS + phantom-api + owasaka)
make down         # Stop all services
make smoke-test   # Validate all services are healthy
make build-all    # Build spectre + owasaka + phantom
make clean        # Remove all containers and volumes
make help         # Show all targets
```

---

## 🔐 Environment Variables

```bash
# NATS (required for event bus)
NATS_URL=nats://localhost:4222

# Phantom API
PHANTOM_PORT=8008

# Spooknix (optional, GPU)
MODEL_SIZE=large-v3
CUDA_VISIBLE_DEVICES=0
HF_TOKEN=                    # Required for diarization (pyannote)

# Observability (optional)
POSTGRES_PASSWORD=            # TimescaleDB
NEO4J_PASSWORD=               # Graph DB
GRAFANA_PASSWORD=             # Dashboards

# LLM (optional)
DEEPSEEK_API_KEY=
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
```

---

## 🧪 Testing Strategy

| Language | Runner | Command | CI Enforcement |
|----------|--------|---------|----------------|
| Rust | cargo test | `nix develop --command cargo test` | clippy -D warnings + fmt |
| Go | go test | `nix develop --command go test -race ./...` | golangci-lint |
| Python | pytest | `nix develop --command pytest` | ruff + mypy + 70% coverage |
| TypeScript | vitest/bun | `bun run test` | eslint + tsc |

### Test Principles

- Unit tests live next to source code or in `tests/` directories
- Integration tests require `docker compose up -d` for real services
- Never mock NATS, databases, or external services in integration tests
- Coverage minimums: Python 70%, Rust (clippy clean), Go (race detector clean)

---

## 📁 Key File Locations

| What | Where |
|------|-------|
| Root compose | `docker-compose.yml` |
| Full infra (TimescaleDB, Neo4j, etc.) | `spectre/docker-compose.yml` |
| Smoke tests | `scripts/smoke-test.sh` |
| CI pipeline | `.github/workflows/ci.yml` |
| Brand guide | `brand/README.md` |
| ADR ledger | `adr-ledger/` |
| Event definitions | `spectre/crates/spectre-events/src/event.rs` |
| Website | `website/` |

---

## 🔧 Project-Specific Dev Guides

Each project has its own `CLAUDE.md` with detailed architecture, testing, and development instructions:

- `phantom/CLAUDE.md` — FastAPI, CORTEX engine, RAG pipeline
- `cerebro/CLAUDE.md` — Knowledge extraction, GCP integration
- `securellm-bridge/CLAUDE.md` — LLM proxy, security architecture

---

## 🏷️ Brand

**Name**: voidnxlabs — lowercase, no spaces, no hyphens
**Tagline**: "Sovereign Intelligence for NixOS"
**Author field**: `voidnxlabs <dev@voidnxlabs.io>` (all manifests)
**Prefix convention**: spectre-* (event bus), phantom-* (ML/intelligence), securellm-* (LLM security)
