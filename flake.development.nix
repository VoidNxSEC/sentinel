{
  description = "Comprehensive Integration Test Suite - LOCAL DEVELOPMENT VERSION";

  # This is an alternative flake configuration for local development.
  # Use this when you want to test changes in local repositories before pushing.
  #
  # Usage:
  #   mv flake.nix flake.github.nix
  #   mv flake.development.nix flake.nix
  #   nix develop

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # LOCAL Development Paths
    # Use these when working on components locally
    neoland = {
      url = "path:../neoland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    phantom = {
      url = "path:../phantom";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neutron = {
      url = "path:../neutron";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cerebro = {
      url = "path:../cerebro";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spectre = {
      url = "path:../spectre";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    adr-ledger = {
      url = "path:../adr-ledger";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Rest of the configuration is the same as flake.nix
  # See flake.nix for the full implementation
  outputs = { self, ... }: {
    # Import from main flake
  };
}
