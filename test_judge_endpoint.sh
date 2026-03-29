#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing Phantom /judge Endpoint ==="

# 1. Start Phantom API in background
echo "Starting Phantom API..."
cd /home/kernelcore/master/phantom
nix develop -c python -m phantom.api.app &
PHANTOM_PID=$!

# Wait for startup
sleep 15

# 2. Check Health
echo "Checking health..."
curl -s http://localhost:8000/health | jq .

# 3. Send Test Bundle
echo "Sending test bundle..."
curl -X POST http://localhost:8000/judge \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": 1700000000,
    "hostname": "test-host",
    "metrics": {
      "cpu": { "usage_percent": 95.5, "cores": [] },
      "memory": { "total_bytes": 16000000000, "used_bytes": 15000000000, "usage_percent": 93.7 },
      "thermal": { "max_temp_celsius": 82.0, "avg_temp_celsius": 78.0 }
    },
    "alerts": [
      {
        "timestamp": 1700000000,
        "severity": "Warning",
        "category": "Thermal",
        "message": "High temperature detected"
      }
    ],
    "logs": []
  }' | jq .

# 4. Cleanup
echo "Stopping Phantom..."
kill $PHANTOM_PID

echo "✅ Test complete!"
