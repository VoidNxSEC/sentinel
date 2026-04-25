# voidnxlabs — Announcement Templates

---

## Hacker News — Show HN

**Title:** Show HN: Sovereign AI stack on NixOS — event bus, RAG, zero-trust LLM proxy, network SIEM

---

I've been building a self-hosted AI infrastructure stack for the past 6 months. Everything runs on NixOS, everything talks over NATS, everything is open source (Apache-2.0).

**What it is:**

- **spectre** — NATS event bus backbone with NKey auth, TLS, JetStream (Rust)
- **phantom** — Document intelligence: upload files → DAG sanitization pipeline → FAISS RAG → chat (Python/FastAPI)
- **cerebro** — Knowledge extraction: consumes sanitized files from NATS, runs HermeticAnalyzer, feeds insights back into phantom's vector store (Python)
- **securellm-bridge** — Zero-trust LLM proxy: rate limiting, audit log, provider fallback chain (local llama.cpp → cloud), Prometheus metrics (Rust)
- **owasaka** — Network SIEM: asset discovery, DNS threat detection, publishes to event bus (Go)
- **ai-agent-os** — System monitoring agent, publishes system.metrics.v1 to NATS (Rust)
- **phantom-soc** — SOC dashboard consuming all events (Rust/GTK4 + Python data-plane)
- **neoland** — AI assistant TUI with local LLM (Rust)
- **sentinel** — Integration test orchestrator: E2E, chaos, performance suites (Python/pytest)

All services are wired on a single NATS event bus using a `{domain}.{entity}.{action}.v{version}` subject schema. NixOS flakes for each project, unified docker-compose with profiles.

The whole thing took about 6 months working solo. Not trying to be a startup — just wanted sovereign AI infra that I actually control.

GitHub: https://github.com/VoidNxSEC

Happy to answer questions about any part of the stack.

---

## NixOS Discourse

**Title:** voidnxlabs — sovereign AI infrastructure stack, fully packaged as NixOS flakes

---

Hey NixOS community,

I've been building a suite of AI infrastructure tools over the past 6 months, all packaged as Nix flakes. Wanted to share it here because a lot of the design decisions were driven by NixOS.

**Why NixOS-first:**

- Reproducible ML environments (no pip hell)
- `nix develop` drops you into a shell with Rust + Go + Python + natscli + sops — no global installs
- `nix run .#nats` spins up NATS with JetStream and auth config loaded from Nix store
- `nix run .#nkeys-gen` regenerates all NKey seeds and encrypts with SOPS

**The stack:**

Each project is its own flake with a `devShell`, `packages`, and optionally a NixOS module:

- `spectre` — NATS backbone (`spectre#spectre-proxy`)
- `phantom` — Document RAG API (`phantom#phantom-api`)
- `cerebro` — Knowledge extraction (`cerebro#cerebro`)
- `securellm-bridge` — LLM proxy (`securellm-bridge#bridge`)
- `owasaka` — Network SIEM (`owasaka#owasaka`)
- `ai-agent-os` — System agent (`ai-agent-os#ai-agent`)

**What I'd love feedback on:**

- NixOS module design (currently a draft, not yet on nixpkgs)
- Cross-compilation targets (aarch64 is partially working)
- Any obvious Nix antipatterns I've introduced

GitHub org: https://github.com/VoidNxSEC

---

## r/selfhosted

**Title:** I built a sovereign AI stack for self-hosting — document RAG, network SIEM, LLM proxy, all on a single event bus. MIT/Apache-2.0.

---

Been building this for 6 months. The goal: AI infrastructure that runs entirely on your own hardware, no cloud dependency, no external APIs required (cloud providers are optional fallbacks, not requirements).

**Core components:**

| Service          | What it does                                                  | Language  |
| ---------------- | ------------------------------------------------------------- | --------- |
| spectre          | NATS event bus (all services talk through this)               | Rust      |
| phantom          | Upload documents → RAG pipeline → chat with your files        | Python    |
| cerebro          | Extracts knowledge from documents, feeds back into RAG        | Python    |
| securellm-bridge | Routes LLM requests: local llama.cpp first, cloud as fallback | Rust      |
| owasaka          | Network SIEM — scans assets, detects DNS threats              | Go        |
| ai-agent-os      | System monitoring agent                                       | Rust      |
| phantom-soc      | SOC dashboard, shows all events in real time                  | Rust/GTK4 |
| spooknix         | Local Whisper STT (GPU optional)                              | Python    |
| neoland          | TUI AI assistant, works offline                               | Rust      |

**Self-hosting setup:**

```bash
git clone https://github.com/VoidNxSEC/master
cd master
docker compose --profile core up -d        # NATS + phantom + owasaka + ai-agent-os
docker compose --profile intelligence up -d # + cerebro + securellm-bridge
```

Or NixOS flakes if that's your thing — each project has one.

Everything talks over NATS with NKey auth and TLS. Prometheus metrics, Grafana dashboards, Jaeger tracing included.

GitHub: https://github.com/VoidNxSEC

---

## r/homelab

**Title:** My homelab AI stack after 6 months: event bus, document RAG, network SIEM, LLM proxy, system monitoring — all wired together. Open source.

---

Been quietly building this. Finally making it public.

The idea was to build homelab-grade AI infra that's actually production-quality — proper auth, TLS everywhere, metrics, structured logging, chaos testing.

**What's in it:**

- **Event bus** (NATS with JetStream) — everything publishes/subscribes here. Kill any service, the others keep running.
- **Document intelligence** — drop a PDF/code file/anything → gets sanitized, embedded, indexed → you can chat with it
- **Network SIEM** — scans your LAN, does DNS threat detection, pushes alerts to the event bus
- **System monitoring agent** — CPU, memory, disk, publishes metrics every 30s
- **LLM proxy** — all LLM requests go through it. Rate limiting, audit log, fallback chain (local GPU → cloud if needed)
- **SOC dashboard** — GTK4 desktop app, shows real-time network + system events
- **STT** — local Whisper, GPU optional

**Setup:**

```bash
docker compose --profile core up -d
# That's it. NATS + all core services.
```

Full NixOS flakes if you're on NixOS. Standard docker-compose if you're not.

**Hardware I'm running it on:** (your specs here)

GitHub: https://github.com/VoidNxSEC — all repos public, MIT/Apache-2.0.

---

## LinkedIn

**Title:** After 6 months of solo engineering: voidnxlabs is public.

---

I've been building AI infrastructure tooling in my spare time. Today I'm making it all public.

**voidnxlabs** is a suite of open-source tools for sovereign AI infrastructure — meaning: AI that runs on your hardware, that you control, with no mandatory cloud dependency.

The stack includes:

→ **spectre** — event bus backbone (NATS/Rust) connecting all services
→ **phantom** — document intelligence platform with RAG pipeline (Python/FastAPI)
→ **cerebro** — knowledge extraction engine feeding back into the RAG index
→ **securellm-bridge** — zero-trust LLM proxy with audit logging and provider fallback
→ **owasaka** — network SIEM with asset discovery and DNS threat detection (Go)
→ **ai-agent-os** — system monitoring agent (Rust)
→ **phantom-soc** — SOC dashboard (Rust/GTK4)
→ **sentinel** — integration test orchestrator with E2E, chaos, and performance suites

Everything is wired on a single event bus using a typed subject schema. NixOS-first, with NixOS flakes for each project. TLS + NKey auth throughout. Real Prometheus metrics, Grafana dashboards, Jaeger tracing.

6 months. Solo. ~18 repositories. Production-grade test coverage.

Not a startup. Not a product. Engineering craft, open source, Apache-2.0.

GitHub → https://github.com/VoidNxSEC

If you're building AI infrastructure, working on NixOS, or interested in self-hosted AI tooling — let's connect.

---

## Dev.to / Hashnode (long-form article)

**Title:** Building sovereign AI infrastructure on NixOS — 6 months, 18 repos, one event bus

**Intro paragraph:**

Six months ago I started building AI infrastructure that I actually control. No mandatory cloud APIs, no vendor lock-in, no black boxes. Everything runs on NixOS, everything talks over NATS, everything is open source.

This is the story of what I built, why I made the decisions I made, and what I'd do differently.

_(fill in sections: motivation, architecture decisions, NATS event schema design, NixOS packaging lessons, what's next)_

**Key sections to cover:**

- Why NATS instead of Kafka/Redis Streams (lightweight, NKey auth built-in, JetStream for persistence)
- Why Rust for the security-critical services (securellm-bridge, ai-agent-os, phantom-soc)
- The NixOS-first development workflow (`nix develop` + flakes)
- The event schema: `{domain}.{entity}.{action}.v{version}` and why it matters
- The test strategy: E2E with real services, chaos injection, performance SLOs
- Lessons from solo multi-repo development

---
