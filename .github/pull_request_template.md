## Summary

<!-- Describe the change and why it's needed. Link ROADMAP milestone if applicable. -->

## Type of Change

- [ ] Bug fix
- [ ] New feature (ROADMAP milestone: ___)
- [ ] Refactor
- [ ] CI/CD / tooling
- [ ] Documentation
- [ ] Release

## Projects Affected

<!-- Check all that apply -->
- [ ] spectre
- [ ] owasaka
- [ ] phantom
- [ ] phantom-soc
- [ ] ai-agent-os
- [ ] neoland
- [ ] spooknix
- [ ] cerebro
- [ ] securellm-bridge
- [ ] securellm-mcp
- [ ] neotron
- [ ] cortex-desktop
- [ ] sentinel
- [ ] packaging

## Testing

- [ ] Unit tests pass (`cargo test` / `go test ./...` / `pytest`)
- [ ] Integration smoke test passes (`make smoke-test`)
- [ ] New tests added for changed code
- [ ] No mocks used for NATS, databases, or external services

## Spectre Events

<!-- If this PR adds/changes NATS events, document them here -->
- [ ] No event schema changes
- [ ] New events: `{subject}` → added to event registry in CLAUDE.md
- [ ] Modified events: bumped version `v{N}` → `v{N+1}`

## Checklist

- [ ] `nix develop --command cargo build` / `go build ./...` / `python -c "import ..."` passes
- [ ] No dead code left in (removed features are fully deleted)
- [ ] No `// removed` comments or `_unused` variables
- [ ] Port registry in CLAUDE.md updated if new ports introduced
- [ ] ADR created for significant architectural decisions
