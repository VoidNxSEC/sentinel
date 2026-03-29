# NixOS module: voidnxlabs-backup
# Configures a systemd timer to run the PostgreSQL backup script daily at 02:00.
#
# Usage in configuration.nix:
#   imports = [ ./backup.nix ];
#   services.voidnxlabs-backup = {
#     enable = true;
#     backupDir = "/var/lib/voidnxlabs/backups/postgres";
#     postgresPassword = "changeme";   # or use secretsFile
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.voidnxlabs-backup;
in {

  options.services.voidnxlabs-backup = {
    enable = lib.mkEnableOption "voidnxlabs PostgreSQL backup timer";

    backupDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/voidnxlabs/backups/postgres";
      description = "Directory where backup files are stored.";
    };

    postgresHost = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "PostgreSQL host.";
    };

    postgresPort = lib.mkOption {
      type = lib.types.port;
      default = 5432;
      description = "PostgreSQL port.";
    };

    postgresUser = lib.mkOption {
      type = lib.types.str;
      default = "postgres";
      description = "PostgreSQL user.";
    };

    postgresPassword = lib.mkOption {
      type = lib.types.str;
      default = "voidnx";
      description = "PostgreSQL password. Use secretsFile for production.";
    };

    postgresDb = lib.mkOption {
      type = lib.types.str;
      default = "neotron";
      description = "Database name to back up.";
    };

    dailyRetention = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7;
      description = "Number of daily backups to retain.";
    };

    weeklyRetention = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Number of weekly backups to retain.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "02:00:00";
      description = "Systemd OnCalendar expression for backup schedule.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional SOPS-decrypted EnvironmentFile with POSTGRES_PASSWORD=...";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Backup directory ──────────────────────────────────────────────────

    systemd.tmpfiles.rules = [
      "d ${cfg.backupDir}        0750 voidnxlabs voidnxlabs -"
      "d ${cfg.backupDir}/daily  0750 voidnxlabs voidnxlabs -"
      "d ${cfg.backupDir}/weekly 0750 voidnxlabs voidnxlabs -"
    ];

    # ── Backup service ────────────────────────────────────────────────────

    systemd.services.voidnxlabs-backup = {
      description = "voidnxlabs PostgreSQL backup";
      after = [ "network.target" "postgresql.service" ];
      wants = [ "network.target" ];

      environment = {
        POSTGRES_HOST     = cfg.postgresHost;
        POSTGRES_PORT     = toString cfg.postgresPort;
        POSTGRES_USER     = cfg.postgresUser;
        POSTGRES_PASSWORD = cfg.postgresPassword;
        POSTGRES_DB       = cfg.postgresDb;
        BACKUP_DIR        = cfg.backupDir;
        DAILY_RETENTION   = toString cfg.dailyRetention;
        WEEKLY_RETENTION  = toString cfg.weeklyRetention;
        FORCE             = "yes";
      };

      serviceConfig = {
        Type = "oneshot";
        User = "voidnxlabs";
        Group = "voidnxlabs";
        ExecStart = pkgs.writeShellScript "voidnxlabs-backup" ''
          set -euo pipefail
          export PGPASSWORD="$POSTGRES_PASSWORD"

          TIMESTAMP=$(date +%Y%m%d_%H%M%S)
          DATESTAMP=$(date +%Y%m%d)
          DOW=$(date +%u)

          DAILY_FILE="$BACKUP_DIR/daily/neotron_daily_$TIMESTAMP.sql.gz"

          echo "[backup-pg] Backing up $POSTGRES_DB → $DAILY_FILE"
          ${pkgs.postgresql}/bin/pg_dump \
            -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
            --format=plain --no-owner --no-privileges --clean --if-exists \
            | ${pkgs.gzip}/bin/gzip -9 > "$DAILY_FILE"

          echo "[backup-pg] Backup complete: $DAILY_FILE"

          if [[ "$DOW" == "7" ]]; then
            WEEKLY_FILE="$BACKUP_DIR/weekly/neotron_weekly_$DATESTAMP.sql.gz"
            cp "$DAILY_FILE" "$WEEKLY_FILE"
            echo "[backup-pg] Weekly snapshot: $WEEKLY_FILE"
          fi

          find "$BACKUP_DIR/daily"  -name "neotron_daily_*.sql.gz"  -mtime "+$DAILY_RETENTION"   -delete
          find "$BACKUP_DIR/weekly" -name "neotron_weekly_*.sql.gz" -mtime "+$(( WEEKLY_RETENTION * 7 ))" -delete

          echo "[backup-pg] Done"
        '';

        EnvironmentFile = lib.mkIf (cfg.secretsFile != null) cfg.secretsFile;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.backupDir ];
      };
    };

    # ── Backup timer ──────────────────────────────────────────────────────

    systemd.timers.voidnxlabs-backup = {
      description = "voidnxlabs PostgreSQL backup timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;      # Run missed backup if system was off at 02:00
        RandomizedDelaySec = "300";  # Spread load: ±5 minute jitter
      };
    };
  };
}
