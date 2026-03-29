#!/bin/bash
# Post-install script for voidnxlabs Debian packages
set -e

# Create system user if missing
if ! id voidnxlabs &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin voidnxlabs
fi

# Create config directory
mkdir -p /etc/voidnxlabs
chown root:voidnxlabs /etc/voidnxlabs
chmod 750 /etc/voidnxlabs

# Create env file placeholder if missing
if [ ! -f /etc/voidnxlabs/env ]; then
  cat > /etc/voidnxlabs/env <<'EOF'
# voidnxlabs environment — fill in secrets
NATS_URL=nats://localhost:4222
EOF
  chown root:voidnxlabs /etc/voidnxlabs/env
  chmod 640 /etc/voidnxlabs/env
fi

systemctl daemon-reload || true
