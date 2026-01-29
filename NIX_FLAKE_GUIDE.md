# 📦 Nix Flake Integration Guide

> **Reproducible development environment powered by Nix Flakes**

<div align="center">

![Nix](https://img.shields.io/badge/Nix-Flakes-5277C3?style=for-the-badge&logo=nixos&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Integrated-2496ED?style=for-the-badge&logo=docker&logoColor=white)

</div>

---

## 🎯 Overview

This project provides a **fully declarative Nix flake** that:
- ✅ Manages all Python dependencies (Poetry, pytest, httpx, etc.)
- ✅ Provides Docker and docker-compose in the environment
- ✅ Exposes executable apps via `nix run`
- ✅ Integrates with other project components (Neoland, Phantom, etc.)
- ✅ Works with direnv for automatic environment activation

---

## 🚀 Quick Start

### Prerequisites

```bash
# Install Nix with flakes enabled
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Or enable flakes manually in ~/.config/nix/nix.conf
experimental-features = nix-command flakes
```

### Instant Development Environment

```bash
# Enter development shell
cd /home/kernelcore/arch/integration-tests
nix develop

# Your shell now has:
# ✅ Python 3.13 with all test dependencies
# ✅ Poetry and uv package managers
# ✅ Docker and docker-compose
# ✅ All testing tools (pytest, curl, jq)
```

---

## 📦 Available Apps

Run tests without entering the dev shell:

```bash
# Run full test suite
nix run .#test

# Run quick tests (skip slow/performance tests)
nix run .#quick

# Run chaos engineering tests only
nix run .#chaos

# Check service health
nix run .#health

# Run mock AI agent simulation
nix run .#mock-agent
```

### With Custom Arguments

```bash
# Pass arguments to scripts
nix run .#test -- --verbose --no-cleanup

# Run mock agent with custom workload
nix run .#mock-agent -- --workload=nixos_rebuild
```

---

## 🔧 Development Workflow

### Option 1: Nix Develop Shell (Recommended)

```bash
# Enter development environment
nix develop

# Now all tools are available:
pytest test_comprehensive_integration.py -v
poetry run pytest -v
./run_comprehensive_test.sh --quick

# Exit shell
exit
```

### Option 2: Direnv Integration (Auto-activation)

```bash
# Install direnv
nix-env -iA nixpkgs.direnv

# Hook into shell (~/.bashrc or ~/.zshrc)
eval "$(direnv hook bash)"  # or zsh

# Allow this directory
cd /home/kernelcore/arch/integration-tests
direnv allow

# Now the environment activates automatically when you cd into this directory!
```

### Option 3: One-off Commands

```bash
# Run command in Nix environment without entering shell
nix develop -c pytest test_comprehensive_integration.py -v
nix develop -c poetry install
nix develop -c ./run_comprehensive_test.sh
```

---

## 🏗️ Flake Structure

### Inputs

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  flake-utils.url = "github:numtide/flake-utils";

  # Component Flakes (GitHub URIs)
  neoland = {
    url = "github:marcosfpina/neoland";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  phantom = {
    url = "github:marcosfpina/phantom";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  neutron = {
    url = "github:marcosfpina/neutron";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  cerebro = {
    url = "github:marcosfpina/cerebro";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  spectre = {
    url = "github:marcosfpina/spectre";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  adr-ledger = {
    url = "github:marcosfpina/adr-ledger";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### Outputs

| Output | Description | Usage |
|--------|-------------|-------|
| **packages.default** | Test environment package | `nix build` |
| **apps.test** | Full test suite | `nix run .#test` |
| **apps.quick** | Quick tests | `nix run .#quick` |
| **apps.chaos** | Chaos tests | `nix run .#chaos` |
| **apps.health** | Health check | `nix run .#health` |
| **apps.mock-agent** | Mock AI agent | `nix run .#mock-agent` |
| **devShells.default** | Development environment | `nix develop` |
| **checks** | Automated checks | `nix flake check` |

---

## 🧪 Running Tests

### Full Suite

```bash
# With Nix app
nix run .#test

# In dev shell
nix develop
./run_comprehensive_test.sh
```

### Quick Tests (CI/CD)

```bash
nix run .#quick

# Equivalent to:
./run_comprehensive_test.sh --quick
```

### Chaos Engineering

```bash
nix run .#chaos

# Equivalent to:
./run_comprehensive_test.sh --chaos-only
```

### Specific Scenarios

```bash
nix develop
pytest test_comprehensive_integration.py::test_scenario_01_thermal_spike_happy_path -v
pytest -m chaos  # All chaos tests
pytest -m performance  # All performance tests
```

---

## 🔍 Service Health Monitoring

```bash
# Check all services
nix run .#health

# Output:
# 🏥 Checking Service Health
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ✅ Phantom is healthy
# ✅ NATS is healthy
# ❌ Cerebro is not responding
#
# ⚠️  Some services are not healthy
```

---

## 🐳 Docker Management

### Via Nix Apps

```bash
# Start services
nix run .#docker-env

# Stop services
nix run .#docker-down
```

### Manual (in dev shell)

```bash
nix develop

# Start services
docker-compose -f docker-compose.test.yml up -d

# Check status
docker-compose -f docker-compose.test.yml ps

# View logs
docker-compose -f docker-compose.test.yml logs phantom

# Stop services
docker-compose -f docker-compose.test.yml down -v
```

---

## 🤖 Mock AI Agent

Simulate workload patterns from Neoland AI agent:

```bash
# Run with default progression (idle → development → compilation → nixos_rebuild)
nix run .#mock-agent

# In dev shell with custom workload
nix develop
cd mocks
python mock_ai_agent.py

# Or directly
nix develop -c python mocks/mock_ai_agent.py
```

---

## ✅ Quality Checks

### Flake Validation

```bash
# Check flake structure
nix flake check

# This runs:
# ✅ Flake structure validation
# ✅ Python syntax check
# ✅ YAML syntax check (docker-compose.test.yml)
```

### Manual Checks

```bash
nix develop

# Python syntax
python -m py_compile test_comprehensive_integration.py

# Linting
ruff check .

# Formatting
black --check .

# Type checking (if mypy is added)
mypy test_comprehensive_integration.py
```

---

## 🔄 Updating Dependencies

### Update Flake Inputs

```bash
# Update all inputs to latest
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
nix flake lock --update-input neoland

# Check what would be updated
nix flake update --dry-run
```

### Update Python Dependencies

```bash
nix develop

# With Poetry
poetry update
poetry show --outdated

# With pip (fallback)
pip list --outdated
```

---

## 🌐 Integration with Other Components

### Neoland (AI Agent)

```bash
# Neoland is available as an input
nix develop

# Access Neoland package (if built)
ls -la ${neoland}

# Run Neoland from integration tests
neoland client --ml-api-url http://localhost:9000
```

### Using Local Development Versions

For local development, you can override to use local paths:

```bash
# Override with local path
nix develop --override-input neoland path:../neoland

# Or for all components
nix develop \
  --override-input neoland path:../neoland \
  --override-input phantom path:../phantom \
  --override-input neutron path:../neutron
```

Or add to `flake.nix` temporarily:

```nix
inputs = {
  # Use local development version
  neoland.url = "path:../neoland";
  # Or keep GitHub version
  # neoland.url = "github:marcosfpina/neoland";
};
```

---

## 🎯 Tips & Tricks

### Fast Iteration

```bash
# Use direnv to auto-activate environment
direnv allow

# Now when you cd into the directory:
cd /home/kernelcore/arch/integration-tests
# Environment activates automatically!
```

### CI/CD Integration

```yaml
# GitHub Actions
- name: Run integration tests
  run: |
    nix run .#quick

# GitLab CI
script:
  - nix --extra-experimental-features 'nix-command flakes' run .#quick
```

### Offline Development

```bash
# Build all dependencies once
nix build --no-link

# Now you can work offline (dependencies cached)
nix develop --offline
```

### Inspecting the Environment

```bash
# See what's in PATH
nix develop -c bash -c 'echo $PATH'

# Check Python version
nix develop -c python --version

# List all available packages
nix develop -c env
```

---

## 🐛 Troubleshooting

### "experimental-features" Error

```bash
# Add to ~/.config/nix/nix.conf
experimental-features = nix-command flakes

# Or use flag
nix --extra-experimental-features 'nix-command flakes' develop
```

### Python Package Not Found

```bash
# Rebuild flake
nix flake update
nix develop --rebuild

# Check if package is in nixpkgs
nix search nixpkgs python313Packages.yourpackage
```

### Docker Not Available

```bash
# Ensure Docker daemon is running
systemctl status docker  # Linux
open -a Docker  # macOS

# Test Docker access
nix develop -c docker ps
```

### Direnv Not Working

```bash
# Reload direnv
direnv reload

# Debug direnv
direnv status

# Re-allow
direnv allow .
```

---

## 📊 Benefits of Nix Flakes

| Benefit | Description |
|---------|-------------|
| **Reproducibility** | Same environment on any machine |
| **Isolation** | No pollution of global environment |
| **Declarative** | All dependencies in one file |
| **Fast** | Cached builds, instant activation |
| **Composable** | Integrate with other flakes |
| **Rollback** | Switch between versions easily |

---

## 📚 Additional Resources

- [Nix Flakes Manual](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)
- [Nixpkgs Python Guide](https://nixos.org/manual/nixpkgs/stable/#python)
- [Zero to Nix](https://zero-to-nix.com/) - Learn Nix from scratch
- [Nix Pills](https://nixos.org/guides/nix-pills/) - Deep dive into Nix

---

<div align="center">

**Last Updated**: 2026-01-28 | **Nix Version**: 2.18+

[![Nix](https://img.shields.io/badge/Nix-Flakes_Enabled-5277C3?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org/)

</div>
