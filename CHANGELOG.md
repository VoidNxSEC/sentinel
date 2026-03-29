# Changelog

All notable changes to voidnxlabs infrastructure stack.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Unified `docker-compose.yml` at repo root with profile-based bring-up
- Sentinel integration test suites: scenarios/, chaos/, performance/
- Release pipeline workflow (`sentinel/.github/workflows/release.yml`)
- Cross-platform packaging: NixOS module, .deb, .rpm, Homebrew, winget
- Branch governance: CODEOWNERS, PR template, branch-protection docs
- CI matrix extended: cerebro, securellm-bridge, securellm-mcp, spooknix

---

## [0.1.0-beta] - 2026-03-29

### Added
- Initial public release of voidnxlabs infrastructure stack
- spectre: NATS event bus backbone (production)
- owasaka: Network SIEM + asset discovery (production)
- phantom: Document intelligence + RAG API (production)
- securellm-bridge: Zero-trust LLM proxy (production)
- securellm-mcp: MCP server for IDE integration (production)
- ai-agent-os: System monitoring agent (beta)
- neoland: AI assistant TUI (beta)
- phantom-soc: SOC dashboard control + data plane (beta)
- cerebro: Knowledge extraction + RAG (beta)
- spooknix: Privacy-first STT (beta)
- sentinel: Security monitoring + integration test orchestrator (beta)
- Apache-2.0 license with VoidNXLabs copyright
