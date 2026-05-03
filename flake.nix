{
  description = "Comprehensive Integration Test Suite - Neutron + Cerebro + Spectre + Phantom + adr-ledger";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Component Flakes (GitHub URIs)
    neoland = {
      url = "git+https://github.com/marcosfpina/neoland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    phantom = {
      url = "git+https://github.com/marcosfpina/phantom";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neutron = {
      url = "git+https://github.com/marcosfpina/neutron";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cerebro = {
      url = "git+https://github.com/marcosfpina/cerebro";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spectre = {
      url = "git+https://github.com/marcosfpina/spectre";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ADR Ledger (knowledge base)
    adr-ledger = {
      url = "git+https://github.com/marcosfpina/adr-ledger";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      neoland,
      phantom,
      neutron,
      cerebro,
      spectre,
      adr-ledger,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; # For Docker Desktop if needed
        };

        # Python 3.13 environment with all test dependencies
        pythonEnv = pkgs.python313.withPackages (
          ps: with ps; [
            # Testing framework
            pytest
            pytest-asyncio
            pytest-timeout
            pytest-xdist

            # HTTP client
            httpx

            # Event bus (optional)
            # nats-py  # Uncomment if available in nixpkgs

            # Performance & monitoring
            psutil

            # Data validation
            pydantic

            # Utilities
            python-dotenv

            # Code quality
            black
            ruff
          ]
        );

        # Test runner script
        runTestsScript = pkgs.writeShellScriptBin "run-integration-tests" ''
          set -euo pipefail

          cd ${self}

          echo "🧪 Running Comprehensive Integration Tests"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

          # Check if services are running
          if ! ${pkgs.docker}/bin/docker ps > /dev/null 2>&1; then
            echo "❌ Docker daemon is not running"
            exit 1
          fi

          # Run test script
          ${pkgs.bash}/bin/bash ./run_comprehensive_test.sh "$@"
        '';

        # Quick test runner
        quickTestsScript = pkgs.writeShellScriptBin "run-quick-tests" ''
          ${runTestsScript}/bin/run-integration-tests --quick
        '';

        # Chaos test runner
        chaosTestsScript = pkgs.writeShellScriptBin "run-chaos-tests" ''
          ${runTestsScript}/bin/run-integration-tests --chaos-only
        '';

        # Service health checker
        healthCheckScript = pkgs.writeShellScriptBin "check-services-health" ''
          set -euo pipefail

          echo "🏥 Checking Service Health"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

          services=(
            "Phantom:http://localhost:8000/health"
            "NATS:http://localhost:8222/healthz"
            "Cerebro:http://localhost:8002/health"
          )

          all_healthy=true

          for service in "''${services[@]}"; do
            name="''${service%%:*}"
            url="''${service#*:}"

            if ${pkgs.curl}/bin/curl -sf "$url" > /dev/null 2>&1; then
              echo "✅ $name is healthy"
            else
              echo "❌ $name is not responding"
              all_healthy=false
            fi
          done

          if [ "$all_healthy" = true ]; then
            echo ""
            echo "✅ All services are healthy"
            exit 0
          else
            echo ""
            echo "⚠️  Some services are not healthy"
            exit 1
          fi
        '';

        # Mock AI agent runner
        mockAgentScript = pkgs.writeShellScriptBin "run-mock-agent" ''
          cd ${self}/mocks
          ${pythonEnv}/bin/python mock_ai_agent.py "$@"
        '';

      in
      {
        # Packages
        packages = {
          default = self.packages.${system}.integration-tests;

          # Test environment package
          integration-tests = pkgs.stdenv.mkDerivation {
            pname = "integration-tests";
            version = "1.0.0";

            src = ./.;

            dontBuild = true;

            installPhase = ''
              mkdir -p $out/bin
              cp -r . $out/

              # Make scripts executable
              chmod +x $out/run_comprehensive_test.sh
              chmod +x $out/*.sh
            '';

            meta = with pkgs.lib; {
              description = "Comprehensive Integration Test Suite for Distributed AI Systems";
              license = licenses.unfree;
              maintainers = [ "VoidNxSEC Team" ];
              platforms = platforms.unix;
            };
          };

          # Docker compose environment
          docker-env = pkgs.writeShellScriptBin "integration-tests-docker-up" ''
            cd ${self}
            ${pkgs.docker-compose}/bin/docker-compose -f docker-compose.test.yml up -d
            echo "⏳ Waiting for services to be ready..."
            sleep 30
            ${healthCheckScript}/bin/check-services-health
          '';

          docker-down = pkgs.writeShellScriptBin "integration-tests-docker-down" ''
            cd ${self}
            ${pkgs.docker-compose}/bin/docker-compose -f docker-compose.test.yml down -v
          '';
        };

        # Apps (executable via `nix run`)
        apps = {
          default = self.apps.${system}.test;

          # Run full test suite
          test = {
            type = "app";
            program = "${runTestsScript}/bin/run-integration-tests";
          };

          # Quick tests
          quick = {
            type = "app";
            program = "${quickTestsScript}/bin/run-quick-tests";
          };

          # Chaos engineering tests
          chaos = {
            type = "app";
            program = "${chaosTestsScript}/bin/run-chaos-tests";
          };

          # Health check
          health = {
            type = "app";
            program = "${healthCheckScript}/bin/check-services-health";
          };

          # Mock AI agent
          mock-agent = {
            type = "app";
            program = "${mockAgentScript}/bin/run-mock-agent";
          };
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          name = "integration-tests-dev";

          nativeBuildInputs = with pkgs; [
            # Python environment
            pythonEnv
            poetry
            uv

            # Docker tools
            docker
            docker-compose

            # Testing tools
            curl
            jq

            # Code quality
            prettier

            # Optional: Neoland binary (if available)
            # neoland.packages.${system}.default
          ];

          shellHook = ''
            echo ""
            echo "╔════════════════════════════════════════════════════════════════╗"
            echo "║  🧪 Comprehensive Integration Test Suite                      ║"
            echo "║  Neutron • Cerebro • Spectre • Phantom                        ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "📦 Environment: Nix Flake"
            echo "🐍 Python: ${pythonEnv}/bin/python ($(${pythonEnv}/bin/python --version))"
            echo "🐳 Docker: $(${pkgs.docker}/bin/docker --version)"
            echo ""
            echo "🚀 Quick Commands:"
            echo "  nix run .#test             # Run full test suite"
            echo "  nix run .#quick            # Run quick tests (skip slow)"
            echo "  nix run .#chaos            # Run chaos engineering tests"
            echo "  nix run .#health           # Check service health"
            echo "  nix run .#mock-agent       # Run mock AI agent"
            echo ""
            echo "🔧 Manual Testing:"
            echo "  ./run_comprehensive_test.sh        # Full suite with script"
            echo "  ./run_comprehensive_test.sh --quick"
            echo "  poetry run pytest -v               # Using Poetry"
            echo "  pytest test_comprehensive_integration.py -v"
            echo ""
            echo "🐳 Docker Management:"
            echo "  docker-compose -f docker-compose.test.yml up -d"
            echo "  docker-compose -f docker-compose.test.yml down -v"
            echo "  docker-compose -f docker-compose.test.yml logs phantom"
            echo ""
            echo "📊 Test Categories:"
            echo "  pytest -m e2e              # End-to-end tests"
            echo "  pytest -m chaos            # Chaos engineering"
            echo "  pytest -m performance      # Performance benchmarks"
            echo "  pytest -m compliance       # Compliance validation"
            echo "  pytest -m \"not slow\"      # Skip slow tests"
            echo ""
            echo "🧪 Individual Scenarios:"
            echo "  pytest test_comprehensive_integration.py::test_scenario_01_thermal_spike_happy_path -v"
            echo "  pytest test_comprehensive_integration.py::test_scenario_08_performance_load_testing -v"
            echo ""
            echo "📝 Debugging:"
            echo "  pytest -vv -s             # Verbose with stdout"
            echo "  pytest --tb=long          # Detailed tracebacks"
            echo "  pytest --lf               # Run last failed tests"
            echo "  pytest --pdb              # Drop into debugger on failure"
            echo ""
            echo "🔍 Service Health:"
            echo "  curl http://localhost:8000/health  # Phantom"
            echo "  curl http://localhost:8222/healthz # NATS"
            echo "  curl http://localhost:8002/health  # Cerebro"
            echo ""
            echo "📚 Documentation:"
            echo "  cat README.md             # Comprehensive guide"
            echo "  cat DEMO.md               # Live examples"
            echo "  cat SHOWCASE.md           # Portfolio highlights"
            echo ""
            echo "💡 Integration with Other Components:"
            echo "  Neoland (AI Agent):  github:marcosfpina/neoland"
            echo "  Phantom (Judge API): github:marcosfpina/phantom"
            echo "  Neutron (ML):        github:marcosfpina/neutron"
            echo "  Cerebro (RAG):       github:marcosfpina/cerebro"
            echo "  Spectre (Event Bus): github:marcosfpina/spectre"
            echo "  ADR Ledger:          github:marcosfpina/adr-ledger"
            echo ""
            echo "🎯 Tips:"
            echo "  - Run 'nix run .#health' before testing"
            echo "  - Use '--no-cleanup' flag to inspect services after tests"
            echo "  - Check reports/ directory for JUnit XML output"
            echo "  - Use 'docker logs <container>' for debugging"
            echo ""
          '';

          # Environment variables
          PYTHONPATH = "${self}/mocks:${self}";
          INTEGRATION_TESTS_DIR = "${self}";
        };

        # Checks (run with `nix flake check`)
        checks = {
          build-package = self.packages.${system}.default;

          formatting = pkgs.runCommand "fmt-check" {
            nativeBuildInputs = [ pkgs.findutils pkgs.nixfmt-rfc-style ];
          } ''
            cd ${self}
            find . -name '*.nix' -print0 | xargs -0 nixfmt --check
            touch $out
          '';

          # Python syntax check
          python-syntax = pkgs.runCommand "python-syntax-check" {
            nativeBuildInputs = [ pkgs.findutils pythonEnv ];
          } ''
            cd ${self}
            find . -type f -name '*.py' -print0 | xargs -0 -n1 ${pythonEnv}/bin/python -m py_compile
            touch $out
          '';

          # YAML syntax check
          yaml-check = pkgs.runCommand "yaml-check" { } ''
            ${pkgs.python313Packages.pyyaml}/bin/python -c "
            import yaml
            with open('${self}/docker-compose.test.yml') as f:
                yaml.safe_load(f)
            print('✅ YAML syntax valid')
            "
            touch $out
          '';
        };

        # Formatter
        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
