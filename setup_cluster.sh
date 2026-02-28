#!/bin/bash

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-expensy-aks}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-expensy}"
LOCATION="${LOCATION:-westeurope}"
NODE_COUNT="${NODE_COUNT:-1}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D2s_v3}"
WORKSPACE_NAME="${CLUSTER_NAME}-logs"
INGRESS_NAMESPACE="ingress-nginx"

# Secrets configuration (use environment variables or defaults)
MONGO_USER="${MONGO_USER:-root}"
MONGO_PASS="${MONGO_PASS:-example}"
REDIS_PASSWORD="${REDIS_PASSWORD:-someredispassword}"
DATABASE_URI="${DATABASE_URI:-mongodb://root:example@mongo:27017/expensy?authSource=admin}"
API_URL="${API_URL:-http://expensy-backend}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

# Functions
log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
  echo -e "${RED}✗ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

create_log_analytics_workspace() {
  log_info "Creating/Verifying Log Analytics Workspace: $WORKSPACE_NAME"

  WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$WORKSPACE_NAME" \
    --query id -o tsv 2>/dev/null || true)

  if [ -z "$WORKSPACE_ID" ]; then
    log_info "Creating Log Analytics workspace..."
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$LOCATION" || log_warning "Resource group may already exist"

    WORKSPACE_ID=$(az monitor log-analytics workspace create \
      --resource-group "$RESOURCE_GROUP" \
      --workspace-name "$WORKSPACE_NAME" \
      --location "$LOCATION" \
      --retention-time 30 \
      --query id -o tsv)
    log_success "Log Analytics workspace created"
  else
    log_success "Log Analytics workspace already exists"
  fi

  echo "$WORKSPACE_ID"
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  local missing_tools=()

  if ! command -v az &> /dev/null; then
    missing_tools+=("Azure CLI (az)")
  fi

  if ! command -v kubectl &> /dev/null; then
    missing_tools+=("kubectl")
  fi

  if ! command -v helm &> /dev/null; then
    missing_tools+=("helm")
  fi

  if [ ${#missing_tools[@]} -gt 0 ]; then
    log_error "Missing required tools:"
    for tool in "${missing_tools[@]}"; do
      echo "  - $tool"
    done
    exit 1
  fi

  log_success "All prerequisites met"
}

create_aks_cluster() {
  log_info "Creating AKS cluster: $CLUSTER_NAME"

  # Create or get Log Analytics workspace ID
  WORKSPACE_ID=$(create_log_analytics_workspace)

  # Check if cluster already exists
  if az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &> /dev/null; then
    log_warning "Cluster $CLUSTER_NAME already exists in resource group $RESOURCE_GROUP"
    log_info "Enabling Container Insights on existing cluster..."
    az aks enable-addons \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --addons monitoring \
      --workspace-resource-id "$WORKSPACE_ID" || log_warning "Container Insights may already be enabled"
  else
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$LOCATION" || log_warning "Resource group may already exist"

    log_info "Creating AKS cluster..."
    az aks create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --node-count "$NODE_COUNT" \
      --node-vm-size "$NODE_VM_SIZE" \
      --enable-managed-identity \
      --generate-ssh-keys \
      --location "$LOCATION" \
      --enable-addons monitoring \
      --workspace-resource-id "$WORKSPACE_ID"
  fi

  log_success "AKS cluster created/verified"
}

get_cluster_credentials() {
  log_info "Getting cluster credentials..."

  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

  log_success "Credentials configured for kubectl"
}

verify_cluster_connection() {
  log_info "Verifying connection to cluster..."

  kubectl cluster-info || {
    log_error "Failed to connect to cluster"
    exit 1
  }

  log_success "Connected to cluster"
}

verify_container_insights() {
  log_info "Verifying Container Insights..."

  echo ""
  echo "================================"
  echo "Container Insights Status"
  echo "================================"

  echo ""
  log_info "1. Addon Profile Status:"
  az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query "addonProfiles.omsagent" -o json || log_warning "omsagent addon not found"

  echo ""
  log_info "2. Log Analytics Workspace:"
  WORKSPACE_RESOURCE=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query "addonProfiles.omsagent.config.logAnalyticsWorkspaceResourceID" -o tsv 2>/dev/null || true)

  if [ -n "$WORKSPACE_RESOURCE" ]; then
    echo "✓ Workspace: $WORKSPACE_RESOURCE"
  else
    log_warning "Workspace ID not found"
  fi

  echo ""
  log_info "3. oma-logs DaemonSet:"
  kubectl get daemonset -n kube-system | grep -i oma || log_warning "oma-logs not yet deployed (may take a few minutes)"

  echo ""
  log_success "Container Insights verification complete"
}

create_namespace() {
  log_info "Creating expensy namespace..."

  kubectl apply -f ./k8s/namespace.yaml

  log_success "Namespace created"
}

create_secrets() {
  log_info "Creating secrets in the cluster..."

  kubectl create secret generic expensy-secrets \
    --from-literal=mongo_user="$MONGO_USER" \
    --from-literal=mongo_pass="$MONGO_PASS" \
    --from-literal=redis_password="$REDIS_PASSWORD" \
    --from-literal=database_uri="$DATABASE_URI" \
    --from-literal=API_URL="$API_URL" \
    --from-literal=grafana_user="$GRAFANA_USER" \
    --from-literal=grafana_pass="$GRAFANA_PASS" \
    --namespace expensy \
    --dry-run=client -o yaml | kubectl apply -f -

  log_success "Secrets created/updated"
}

install_ingress_controller() {
  log_info "Installing NGINX Ingress Controller..."

  # Add Helm repository
  log_info "Adding ingress-nginx Helm repository..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update

  # Check if ingress controller is already installed
  if helm list -n "$INGRESS_NAMESPACE" 2>/dev/null | grep -q "ingress-nginx"; then
    log_warning "Ingress controller already installed"
    log_info "Skipping installation"
  else
    log_info "Installing ingress-nginx chart..."
    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace "$INGRESS_NAMESPACE" \
      --create-namespace \
      --set controller.resources.requests.cpu=50m \
      --set controller.resources.requests.memory=90Mi \
      --set controller.resources.limits.cpu=200m \
      --set controller.resources.limits.memory=256Mi
  fi

  log_success "Ingress controller installed/verified"
}

get_ingress_ip() {
  log_info "Retrieving ingress controller IP address..."

  # Wait for LoadBalancer service to get an external IP
  local attempts=0
  local max_attempts=30
  local external_ip=""

  while [ -z "$external_ip" ] && [ $attempts -lt $max_attempts ]; do
    external_ip=$(kubectl get svc ingress-nginx-controller \
      -n "$INGRESS_NAMESPACE" \
      --template='{{ range .status.loadBalancer.ingress }}{{ .ip }}{{ end }}' 2>/dev/null || true)

    if [ -z "$external_ip" ]; then
      attempts=$((attempts + 1))
      if [ $attempts -lt $max_attempts ]; then
        log_info "Waiting for external IP (attempt $attempts/$max_attempts)..."
        sleep 10
      fi
    fi
  done

  if [ -z "$external_ip" ]; then
    log_warning "External IP not assigned yet"
    log_info "Service is still pending. Check status with:"
    echo "  kubectl get svc ingress-nginx-controller -n $INGRESS_NAMESPACE"
    return 1
  fi

  return 0
}

print_summary() {
  log_success "Cluster setup completed successfully!"

  echo ""
  echo "================================"
  echo -e "${GREEN}Cluster Summary${NC}"
  echo "================================"
  echo "Resource Group: $RESOURCE_GROUP"
  echo "Cluster Name: $CLUSTER_NAME"
  echo "Location: $LOCATION"
  echo ""
  echo -e "${GREEN}Ingress Controller${NC}"
  echo "Namespace: $INGRESS_NAMESPACE"

  if [ $? -eq 0 ]; then
    echo "External IP: ${BLUE}$external_ip${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Update your DNS records to point to: $external_ip"
    echo "2. Deploy your applications: ./apply_all.sh"
    echo "3. Access the ingress: http://$external_ip"
  else
    echo "Status: Pending external IP assignment"
  fi

  echo ""
  echo "Useful commands:"
  echo "  Get ingress IP: kubectl get svc -n $INGRESS_NAMESPACE"
  echo "  Deploy apps: ./apply_all.sh"
  echo "  View pods: kubectl get pods -n expensy"
  echo "  View services: kubectl get svc -n expensy"
  echo "  Delete cluster: az aks delete --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
  echo ""
}

# Main execution
main() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════╗"
  echo "║   AKS Cluster Setup Script             ║"
  echo "║   Expensy DevOps Project               ║"
  echo "╚════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""

  check_prerequisites
  create_aks_cluster
  get_cluster_credentials
  verify_cluster_connection
  verify_container_insights
  create_namespace
  create_secrets
  install_ingress_controller
  get_ingress_ip
  print_summary
}

main
