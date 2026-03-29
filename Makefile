.PHONY: dev down test build smoke-test clean help

dev:                                      ## Boot core services (NATS + phantom-api + owasaka)
	docker compose up -d

down:                                     ## Stop all services
	docker compose down

smoke-test:                               ## Validate all services are healthy
	@bash scripts/smoke-test.sh

test: smoke-test                          ## Run smoke tests (alias)

build-spectre:                            ## Build spectre (Rust)
	cd spectre && nix develop --command cargo build --release

build-owasaka:                            ## Build owasaka (Go)
	cd owasaka && nix develop --command go build ./...

build-phantom:                            ## Verify phantom (Python)
	cd phantom && nix develop --command python -c "from phantom.api.app import create_app; create_app()"

build-all: build-spectre build-owasaka build-phantom  ## Build all projects

clean:                                    ## Remove all containers and volumes
	docker compose down -v --remove-orphans

help:                                     ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
