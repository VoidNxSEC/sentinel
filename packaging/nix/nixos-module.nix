# NixOS module: voidnxlabs-stack
# Configures systemd services for the core voidnxlabs infrastructure.
#
# Usage in configuration.nix:
#   imports = [ /path/to/nixos-module.nix ];
#   services.voidnxlabs = {
#     enable = true;
#     natsUrl = "nats://localhost:4222";
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.voidnxlabs;
in {

  options.services.voidnxlabs = {
    enable = lib.mkEnableOption "voidnxlabs infrastructure stack";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open firewall ports for user-facing services.
        Only public-facing ports are opened; internal service ports
        (NATS 4222/8222, owasaka 8080, bridge 8081, Prometheus 9090, etc.)
        are intentionally NOT exposed.
      '';
    };

    natsUrl = lib.mkOption {
      type = lib.types.str;
      default = "nats://localhost:4222";
      description = "NATS connection URL for the Spectre event bus.";
    };

    phantomPort = lib.mkOption {
      type = lib.types.port;
      default = 8008;
      description = "Host port for phantom-api (TLS-terminated by Caddy).";
    };

    owasakaPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Host port for owasaka SIEM (internal only — not opened in firewall).";
    };

    spooknixPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Host port for spooknix STT service.";
    };

    cortexPort = lib.mkOption {
      type = lib.types.port;
      default = 1420;
      description = "Host port for cortex-desktop Tauri dev server.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/voidnxlabs";
      description = "State directory for voidnxlabs services.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to SOPS-decrypted secrets file (EnvironmentFile).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── NATS (Spectre event bus) ──────────────────────────────────────────
    services.nats = {
      enable = true;
      port = 4222;
      settings = {
        jetstream = true;
        http_port = 8222;
        cluster = { name = "spectre"; };
      };
    };

    # ── phantom-api ───────────────────────────────────────────────────────
    systemd.services.phantom-api = {
      description = "voidnxlabs phantom document intelligence API";
      after = [ "network.target" "nats.service" ];
      requires = [ "nats.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NATS_URL = cfg.natsUrl;
        PHANTOM_PORT = toString cfg.phantomPort;
      };

      serviceConfig = {
        Type = "simple";
        User = "voidnxlabs";
        Group = "voidnxlabs";
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${pkgs.phantom-api}/bin/phantom-api";
        Restart = "on-failure";
        RestartSec = "5s";
        # Prevent restart storms: max 5 restarts in 60s, then give up until manual intervention
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
        EnvironmentFile = lib.mkIf (cfg.secretsFile != null) cfg.secretsFile;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };

    # ── owasaka ───────────────────────────────────────────────────────────
    systemd.services.owasaka = {
      description = "voidnxlabs owasaka network SIEM";
      after = [ "network.target" "nats.service" ];
      requires = [ "nats.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NATS_URL = cfg.natsUrl;
      };

      serviceConfig = {
        Type = "simple";
        User = "voidnxlabs";
        Group = "voidnxlabs";
        ExecStart = "${pkgs.owasaka}/bin/owasaka";
        Restart = "on-failure";
        RestartSec = "5s";
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
        EnvironmentFile = lib.mkIf (cfg.secretsFile != null) cfg.secretsFile;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        # Network access required for SIEM packet capture
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_PACKET" ];
      };
    };

    # ── ai-agent-os ───────────────────────────────────────────────────────
    systemd.services.ai-agent-os = {
      description = "voidnxlabs ai-agent-os system monitoring";
      after = [ "network.target" "nats.service" ];
      requires = [ "nats.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NATS_URL = cfg.natsUrl;
      };

      serviceConfig = {
        Type = "simple";
        User = "voidnxlabs";
        Group = "voidnxlabs";
        ExecStart = "${pkgs.ai-agent-os}/bin/ai-agent";
        Restart = "on-failure";
        RestartSec = "5s";
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
        EnvironmentFile = lib.mkIf (cfg.secretsFile != null) cfg.secretsFile;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # ── System user + directories ─────────────────────────────────────────
    users.users.voidnxlabs = {
      isSystemUser = true;
      group = "voidnxlabs";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.voidnxlabs = {};

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 voidnxlabs voidnxlabs -"
      "d ${cfg.dataDir}/phantom 0750 voidnxlabs voidnxlabs -"
      "d ${cfg.dataDir}/owasaka 0750 voidnxlabs voidnxlabs -"
    ];

    # ── Firewall ──────────────────────────────────────────────────────────
    # Only user-facing ports are opened. Internal service ports are
    # intentionally not exposed (NATS 4222/8222, owasaka 8080,
    # securellm-bridge 8081, Prometheus 9090, Grafana 3001, etc.).
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.phantomPort    # 8008 — phantom-api (TLS via Caddy reverse proxy)
      cfg.spooknixPort   # 8000 — spooknix STT service
      cfg.cortexPort     # 1420 — cortex-desktop Tauri UI
    ];
  };
}
