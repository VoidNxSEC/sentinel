#!/usr/bin/env bash
# =============================================================================
# azure-nix-template.sh
# voidnxlabs — Azure CLI template for NixOS VM fleet
#
# Roles:
#   nix-deploy  — NixOS infra deploy node (nixos-infect, remote builds)
#   test        — Ephemeral test runners (CI/CD, pytest, cargo test, k6)
#   stream      — App streaming / long-running service hosts
#
# Usage:
#   ./azure-nix-template.sh [deploy|test|stream|all|teardown]
#
# Requirements:
#   az CLI >= 2.55, jq, ssh-keygen
# =============================================================================

set -euo pipefail

# ─── CONFIG ──────────────────────────────────────────────────────────────────

PROJECT="voidnxlabs"
ENV="${ENV:-dev}"                          # dev | staging | prod
LOCATION="eastus2"                    # closest to Feira de Santana
RESOURCE_GROUP="${PROJECT}-${ENV}-rg"

# VM sizes
SIZE_DEPLOY="Standard_B2s"               # 2 vCPU / 4 GB — nix remote builds
SIZE_TEST="Standard_B4ms"                # 4 vCPU / 16 GB — parallel test runs
SIZE_STREAM="Standard_D4s_v5"            # 4 vCPU / 16 GB — app streaming

# NixOS via nixos-infect (Ubuntu 22.04 base → converted)
IMAGE_URN="Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
ADMIN_USER="nixadmin"
SSH_KEY_PATH="${HOME}/.ssh/azure_nix_${ENV}.pub"

# Networking
VNET_NAME="${PROJECT}-${ENV}-vnet"
VNET_PREFIX="10.10.0.0/16"
SUBNET_DEPLOY="10.10.1.0/24"
SUBNET_TEST="10.10.2.0/24"
SUBNET_STREAM="10.10.3.0/24"
NSG_NAME="${PROJECT}-${ENV}-nsg"

# Storage (for Nix store cache, test artifacts, stream state)
STORAGE_ACCOUNT="${PROJECT}${ENV}sa"     # must be globally unique, lowercase

# Tags
TAGS="project=${PROJECT} env=${ENV} managed-by=azure-cli"

# ─── HELPERS ─────────────────────────────────────────────────────────────────

log()  { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[✓]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

az_exists() {
  # az_exists <resource-type> <name> [--resource-group <rg>]
  az "$1" show --name "$2" "${@:3}" &>/dev/null
}

ensure_ssh_key() {
  if [[ ! -f "${SSH_KEY_PATH}" ]]; then
    log "Generating SSH key pair for ${ENV}..."
    ssh-keygen -t ed25519 -f "${SSH_KEY_PATH%.pub}" -N "" -C "azure-nix-${ENV}"
  fi
  SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}")
}

# ─── PHASE 1: FOUNDATION ─────────────────────────────────────────────────────

setup_foundation() {
  log "Setting up foundation: RG, VNet, NSG, Storage..."

  # Resource Group
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags ${TAGS} \
    --output none
  ok "Resource group: ${RESOURCE_GROUP}"

  # VNet
  az network vnet create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VNET_NAME}" \
    --address-prefix "${VNET_PREFIX}" \
    --tags ${TAGS} \
    --output none

  # Subnets
  for subnet_name in deploy test stream; do
    eval "prefix=\${SUBNET_${subnet_name^^}}"
    az network vnet subnet create \
      --resource-group "${RESOURCE_GROUP}" \
      --vnet-name "${VNET_NAME}" \
      --name "${subnet_name}-subnet" \
      --address-prefix "${prefix}" \
      --output none
  done
  ok "VNet + subnets ready"

  # NSG
  az network nsg create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${NSG_NAME}" \
    --tags ${TAGS} \
    --output none

  # NSG Rules
  local rules=(
    # priority  name              port  direction  access  desc
    "100        allow-ssh         22    Inbound    Allow   SSH for nixos-deploy"
    "110        allow-nix-serve   5000  Inbound    Allow   nix-serve binary cache"
    "120        allow-stream-http 8080  Inbound    Allow   App streaming HTTP"
    "130        allow-stream-ws   9000  Inbound    Allow   App streaming WebSocket"
    "140        allow-mcp         3000  Inbound    Allow   MCP server"
    "200        deny-all-in       '*'   Inbound    Deny    Default deny"
  )

  for rule in "${rules[@]}"; do
    read -r priority name port direction access desc <<< "${rule}"
    az network nsg rule create \
      --resource-group "${RESOURCE_GROUP}" \
      --nsg-name "${NSG_NAME}" \
      --name "${name}" \
      --priority "${priority}" \
      --protocol Tcp \
      --direction "${direction}" \
      --access "${access}" \
      --destination-port-range "${port}" \
      --description "${desc}" \
      --output none
  done
  ok "NSG rules configured"

  # Attach NSG to subnets
  for subnet_name in deploy test stream; do
    az network vnet subnet update \
      --resource-group "${RESOURCE_GROUP}" \
      --vnet-name "${VNET_NAME}" \
      --name "${subnet_name}-subnet" \
      --network-security-group "${NSG_NAME}" \
      --output none
  done

  # Storage Account (for Nix binary cache + artifacts)
  az storage account create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${STORAGE_ACCOUNT}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access false \
    --tags ${TAGS} \
    --output none

  # Containers
  local STORAGE_KEY
  STORAGE_KEY=$(az storage account keys list \
    --account-name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[0].value" -o tsv)

  for container in nix-cache test-artifacts stream-state; do
    az storage container create \
      --name "${container}" \
      --account-name "${STORAGE_ACCOUNT}" \
      --account-key "${STORAGE_KEY}" \
      --output none
  done
  ok "Storage account + containers ready"
}

# ─── PHASE 2: NIX DEPLOY VM ──────────────────────────────────────────────────

deploy_nix_vm() {
  local VM_NAME="${PROJECT}-${ENV}-deploy"
  log "Provisioning nix-deploy VM: ${VM_NAME}..."
  ensure_ssh_key

  az vm create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --image "${IMAGE_URN}" \
    --size "${SIZE_DEPLOY}" \
    --admin-username "${ADMIN_USER}" \
    --ssh-key-value "${SSH_PUB_KEY}" \
    --vnet-name "${VNET_NAME}" \
    --subnet "deploy-subnet" \
    --nsg "" \
    --public-ip-sku Standard \
    --os-disk-size-gb 60 \
    --os-disk-caching ReadWrite \
    --storage-sku Premium_LRS \
    --tags ${TAGS} role=nix-deploy \
    --output none

  # Attach data disk for Nix store
  az vm disk attach \
    --resource-group "${RESOURCE_GROUP}" \
    --vm-name "${VM_NAME}" \
    --name "${VM_NAME}-nix-store" \
    --new \
    --size-gb 100 \
    --sku Premium_LRS \
    --output none

  local PUBLIC_IP
  PUBLIC_IP=$(az vm show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --show-details \
    --query publicIps -o tsv)

  ok "nix-deploy VM ready: ${PUBLIC_IP}"

  # Bootstrap nixos-infect
  log "Running nixos-infect bootstrap on ${PUBLIC_IP}..."
  ssh -o StrictHostKeyChecking=no \
      -i "${SSH_KEY_PATH%.pub}" \
      "${ADMIN_USER}@${PUBLIC_IP}" \
      bash -s -- < <(_nixos_infect_script)

  ok "NixOS deployed on ${VM_NAME} @ ${PUBLIC_IP}"
  echo "  → ssh -i ${SSH_KEY_PATH%.pub} ${ADMIN_USER}@${PUBLIC_IP}"
}

_nixos_infect_script() {
cat <<'INFECT'
#!/usr/bin/env bash
set -euo pipefail
export NIX_CHANNEL="nixos-24.11"

# Install Nix (multi-user)
curl -L https://nixos.org/nix/install | sh -s -- --daemon
source /etc/profile.d/nix.sh

# Install nixos-infect
nix-env -iA nixpkgs.git
curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
  | NIX_CHANNEL="${NIX_CHANNEL}" bash -x 2>&1 | tee /tmp/nixos-infect.log
INFECT
}

# ─── PHASE 3: TEST VMs (EPHEMERAL) ───────────────────────────────────────────

deploy_test_vms() {
  local COUNT="${TEST_VM_COUNT:-2}"
  log "Provisioning ${COUNT} ephemeral test VM(s)..."
  ensure_ssh_key

  for i in $(seq 1 "${COUNT}"); do
    local VM_NAME="${PROJECT}-${ENV}-test-${i}"

    az vm create \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${VM_NAME}" \
      --image "${IMAGE_URN}" \
      --size "${SIZE_TEST}" \
      --admin-username "${ADMIN_USER}" \
      --ssh-key-value "${SSH_PUB_KEY}" \
      --vnet-name "${VNET_NAME}" \
      --subnet "test-subnet" \
      --nsg "" \
      --public-ip-sku Standard \
      --os-disk-size-gb 80 \
      --os-disk-caching ReadWrite \
      --storage-sku Standard_LRS \
      --eviction-policy Delete \
      --priority Spot \
      --max-price -1 \
      --tags ${TAGS} role=test ephemeral=true \
      --output none &

    ok "Test VM queued: ${VM_NAME} (Spot)"
  done
  wait
  ok "All test VMs provisioned"

  # Custom script: install Nix + testing tools
  for i in $(seq 1 "${COUNT}"); do
    local VM_NAME="${PROJECT}-${ENV}-test-${i}"
    local PUBLIC_IP
    PUBLIC_IP=$(az vm show \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${VM_NAME}" \
      --show-details \
      --query publicIps -o tsv)

    az vm run-command invoke \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${VM_NAME}" \
      --command-id RunShellScript \
      --scripts \
        "curl -L https://nixos.org/nix/install | sh -s -- --daemon" \
        "source /etc/profile.d/nix.sh && nix-env -iA nixpkgs.k6 nixpkgs.cargo nixpkgs.python3" \
      --output none

    ok "Test VM ${i} bootstrapped: ${PUBLIC_IP}"
  done
}

# Teardown test VMs only (keep infra)
teardown_test_vms() {
  log "Deleting ephemeral test VMs..."
  az vm list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?tags.role=='test'].name" \
    -o tsv | while read -r vm; do
      az vm delete \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${vm}" \
        --yes --no-wait --output none
      ok "Deleted: ${vm}"
  done
}

# ─── PHASE 4: STREAM VMs ─────────────────────────────────────────────────────

deploy_stream_vm() {
  local VM_NAME="${PROJECT}-${ENV}-stream"
  log "Provisioning app-stream VM: ${VM_NAME}..."
  ensure_ssh_key

  az vm create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --image "${IMAGE_URN}" \
    --size "${SIZE_STREAM}" \
    --admin-username "${ADMIN_USER}" \
    --ssh-key-value "${SSH_PUB_KEY}" \
    --vnet-name "${VNET_NAME}" \
    --subnet "stream-subnet" \
    --nsg "" \
    --public-ip-sku Standard \
    --os-disk-size-gb 60 \
    --os-disk-caching ReadWrite \
    --storage-sku Premium_LRS \
    --tags ${TAGS} role=stream \
    --output none

  # Attach persistent state disk
  az vm disk attach \
    --resource-group "${RESOURCE_GROUP}" \
    --vm-name "${VM_NAME}" \
    --name "${VM_NAME}-state" \
    --new \
    --size-gb 128 \
    --sku Premium_LRS \
    --output none

  local PUBLIC_IP
  PUBLIC_IP=$(az vm show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --show-details \
    --query publicIps -o tsv)

  # Bootstrap: NixOS + streaming services
  az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts \
      "curl -L https://nixos.org/nix/install | sh -s -- --daemon" \
      "source /etc/profile.d/nix.sh && nix-env -iA nixpkgs.nginx nixpkgs.ffmpeg nixpkgs.caddy" \
    --output none

  ok "stream VM ready: ${PUBLIC_IP}"
  echo "  → HTTP  : http://${PUBLIC_IP}:8080"
  echo "  → WS    : ws://${PUBLIC_IP}:9000"
  echo "  → ssh   : ssh -i ${SSH_KEY_PATH%.pub} ${ADMIN_USER}@${PUBLIC_IP}"
}

# ─── PHASE 5: NIX REMOTE BUILD CONFIG ────────────────────────────────────────

print_nix_deploy_config() {
  local DEPLOY_IP
  DEPLOY_IP=$(az vm show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${PROJECT}-${ENV}-deploy" \
    --show-details \
    --query publicIps -o tsv 2>/dev/null || echo "DEPLOY_IP")

  cat <<NIX_CONF

# ── flake.nix snippet ─────────────────────────────────────────────────────────
# Add to your voidnxlabs flake for remote builds on this Azure VM:

nixConfig = {
  extra-substituters = [
    "ssh://${ADMIN_USER}@${DEPLOY_IP}"
    "https://${STORAGE_ACCOUNT}.blob.core.windows.net/nix-cache"
  ];
  extra-trusted-public-keys = [
    # paste output of: nix-store --generate-binary-cache-key azure-${ENV} cache-priv-key.pem cache-pub-key.pem
  ];
};

# ── nixos-rebuild remote deploy ────────────────────────────────────────────────
# nixos-rebuild switch --flake .#azure-${ENV} \
#   --target-host ${ADMIN_USER}@${DEPLOY_IP} \
#   --build-host  ${ADMIN_USER}@${DEPLOY_IP} \
#   --use-remote-sudo

# ── deploy-rs ─────────────────────────────────────────────────────────────────
# deploy .#azure-${ENV} -- --accept-flake-config

NIX_CONF
}

# ─── TEARDOWN ────────────────────────────────────────────────────────────────

teardown_all() {
  warn "Deleting ENTIRE resource group: ${RESOURCE_GROUP}"
  read -rp "Confirm? [yes/N]: " confirm
  [[ "${confirm}" == "yes" ]] || die "Aborted."
  az group delete \
    --name "${RESOURCE_GROUP}" \
    --yes --no-wait \
    --output none
  ok "Resource group deletion initiated (async)"
}

# ─── STATUS ──────────────────────────────────────────────────────────────────

status() {
  log "VM fleet status for ${RESOURCE_GROUP}:"
  az vm list \
    --resource-group "${RESOURCE_GROUP}" \
    --show-details \
    --query "[].{Name:name, State:powerState, IP:publicIps, Size:hardwareProfile.vmSize, Role:tags.role}" \
    --output table
}

# ─── ENTRYPOINT ──────────────────────────────────────────────────────────────

main() {
  local cmd="${1:-help}"

  case "${cmd}" in
    foundation)  setup_foundation ;;
    deploy)      setup_foundation && deploy_nix_vm ;;
    test)        deploy_test_vms ;;
    stream)      deploy_stream_vm ;;
    all)
      setup_foundation
      deploy_nix_vm
      deploy_test_vms
      deploy_stream_vm
      print_nix_deploy_config
      ;;
    config)      print_nix_deploy_config ;;
    status)      status ;;
    clean-test)  teardown_test_vms ;;
    teardown)    teardown_all ;;
    *)
      echo "Usage: $0 [foundation|deploy|test|stream|all|config|status|clean-test|teardown]"
      echo ""
      echo "  foundation  — RG, VNet, NSG, Storage only"
      echo "  deploy      — Foundation + nix-deploy VM (nixos-infect)"
      echo "  test        — Ephemeral Spot test VMs (Nix + k6 + cargo)"
      echo "  stream      — App streaming VM (nginx + caddy + ffmpeg)"
      echo "  all         — Full fleet"
      echo "  config      — Print flake.nix / deploy-rs snippet"
      echo "  status      — VM fleet table"
      echo "  clean-test  — Delete only test VMs"
      echo "  teardown    — Nuke entire resource group"
      ;;
  esac
}

main "$@"
