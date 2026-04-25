# =============================================================================
# azure-vm.nix — voidnxlabs NixOS configuration for Azure VMs
# Import this module in your flake per-host config
#
# Targets: deploy | test | stream
# =============================================================================

{ config, pkgs, lib, ... }:

let
  role = config.voidnx.azure.role; # "deploy" | "test" | "stream"
in
{
  options.voidnx.azure.role = lib.mkOption {
    type    = lib.types.enum [ "deploy" "test" "stream" ];
    default = "deploy";
    description = "VM role within the voidnxlabs Azure fleet";
  };

  config = lib.mkMerge [

    # ── Base (all roles) ────────────────────────────────────────────────────
    {
      system.stateVersion = "24.11";

      boot.loader.grub = {
        enable  = true;
        device  = "/dev/sda";
        efiSupport = lib.mkDefault false;
      };

      # Azure IMDS / waagent integration
      virtualisation.azure.agent.enable = true;
      services.cloud-init.enable = true;

      networking = {
        hostName      = "voidnx-azure-${role}";
        firewall.enable = true;
        firewall.allowedTCPPorts = [ 22 ];
      };

      users.users.nixadmin = {
        isNormalUser  = true;
        extraGroups   = [ "wheel" "nix-trusted-users" ];
        openssh.authorizedKeys.keyFiles = [ /etc/nixos/authorized_keys ];
      };

      security.sudo.wheelNeedsPassword = false;

      services.openssh = {
        enable        = true;
        settings = {
          PermitRootLogin           = "no";
          PasswordAuthentication    = false;
          KbdInteractiveAuthentication = false;
        };
      };

      nix = {
        settings = {
          trusted-users           = [ "root" "nixadmin" ];
          experimental-features   = [ "nix-command" "flakes" ];
          auto-optimise-store     = true;
        };
        gc = {
          automatic = true;
          dates     = "weekly";
          options   = "--delete-older-than 30d";
        };
      };

      environment.systemPackages = with pkgs; [
        git curl wget jq htop tmux neovim ripgrep
        nix-tree nix-diff nmap
      ];
    }

    # ── Deploy Role ─────────────────────────────────────────────────────────
    (lib.mkIf (role == "deploy") {
      networking.firewall.allowedTCPPorts = [ 22 5000 ];

      # Nix binary cache server (local fleet cache)
      services.nix-serve = {
        enable    = true;
        port      = 5000;
        secretKeyFile = "/run/secrets/nix-serve-key";
      };

      # Remote build host capabilities
      nix.settings = {
        max-jobs       = 4;
        cores          = 0; # use all
        builders-use-substitutes = true;
      };

      # Data disk for Nix store overflow
      fileSystems."/nix/extra" = {
        device  = "/dev/sdb";
        fsType  = "ext4";
        options = [ "defaults" "nofail" ];
      };

      environment.systemPackages = with pkgs; [
        deploy-rs nixos-rebuild
        # securellm-bridge would be a custom pkg overlay
      ];

      # Periodic store signing for binary cache
      systemd.services.nix-sign-paths = {
        description = "Sign Nix store paths for binary cache";
        after       = [ "nix-serve.service" ];
        wantedBy    = [ "multi-user.target" ];
        serviceConfig = {
          Type      = "oneshot";
          ExecStart = "${pkgs.nix}/bin/nix store sign --key-file /run/secrets/nix-serve-key --all";
        };
      };
    })

    # ── Test Role ───────────────────────────────────────────────────────────
    (lib.mkIf (role == "test") {
      networking.firewall.allowedTCPPorts = [ 22 ];

      nix.settings = {
        max-jobs = 8;
        cores    = 0;
      };

      environment.systemPackages = with pkgs; [
        # Load testing
        k6
        # Rust
        cargo rustc clippy rust-analyzer
        # Python / ML
        python3 python3Packages.pytest python3Packages.hypothesis
        # Security
        trufflehog trivy
        # Network
        curl httpie
        # Coverage
        lcov
      ];

      # Ephemeral: aggressive GC
      nix.gc = {
        automatic = true;
        dates     = "daily";
        options   = "--delete-older-than 3d";
      };

      # Test result artifact upload (mounts to Azure Storage via blobfuse2)
      fileSystems."/mnt/test-artifacts" = {
        device  = "test-artifacts";
        fsType  = "fuse";
        options = [ "nofail" "allow_other" "_netdev" ];
      };
    })

    # ── Stream Role ─────────────────────────────────────────────────────────
    (lib.mkIf (role == "stream") {
      networking.firewall.allowedTCPPorts = [ 22 80 443 8080 9000 ];

      # Reverse proxy
      services.caddy = {
        enable     = true;
        configFile = pkgs.writeText "Caddyfile" ''
          :8080 {
            reverse_proxy 127.0.0.1:3000
            log {
              output file /var/log/caddy/access.log
            }
          }
          :9000 {
            @ws {
              header Connection *Upgrade*
              header Upgrade websocket
            }
            reverse_proxy @ws 127.0.0.1:3001
          }
        '';
      };

      # Persistent state disk
      fileSystems."/var/lib/stream-state" = {
        device  = "/dev/sdb";
        fsType  = "ext4";
        options = [ "defaults" "nofail" ];
      };

      environment.systemPackages = with pkgs; [
        ffmpeg-full   # transcoding / HLS
        caddy
        nodejs_22     # app runtime
        # Add your app packages via overlay
      ];

      # Watchdog: restart streaming service on failure
      systemd.services.stream-app = {
        description   = "voidnxlabs stream application";
        after         = [ "network.target" "caddy.service" ];
        wantedBy      = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart   = "${pkgs.nodejs_22}/bin/node /var/lib/stream-state/app/index.js";
          Restart     = "on-failure";
          RestartSec  = "5s";
          WorkingDirectory = "/var/lib/stream-state";
          StateDirectory   = "stream-app";
        };
      };
    })

  ]; # mkMerge
}
