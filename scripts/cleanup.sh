#!/bin/bash
set -e

# Script to clean up the Prometheus Push Gateway to OpenTelemetry Lab

# Color codes for better readability
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Cleaning up Prometheus Push Gateway to OpenTelemetry Lab ===${NC}"

# Confirm cleanup
echo -e "${RED}WARNING: This will delete all lab resources!${NC}"
read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup aborted."
    exit 0
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed. Please install kubectl first.${NC}"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed. Please install helm first.${NC}"
    exit 1
fi

# Check if we can connect to the Kubernetes cluster
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Remove the sample application
echo -e "\n${YELLOW}Removing sample application...${NC}"
if kubectl get deployment sample-batch-app -n monitoring &> /dev/null; then
    kubectl delete deployment sample-batch-app -n monitoring
    echo "Deleted sample-batch-app deployment"
fi

if kubectl get configmap sample-app-config -n monitoring &> /dev/null; then
    kubectl delete configmap sample-app-config -n monitoring
    echo "Deleted sample-app-config configmap"
fi

if kubectl get cronjob sample-batch-job -n monitoring &> /dev/null; then
    kubectl delete cronjob sample-batch-job -n monitoring
    echo "Deleted sample-batch-job cronjob"
fi

# Uninstall the Helm release
echo -e "\n${YELLOW}Uninstalling monitoring stack Helm release...${NC}"
if helm list -n monitoring | grep monitoring-stack &> /dev/null; then
    helm uninstall monitoring-stack -n monitoring
    echo "Deleted monitoring-stack helm release"
fi

# Delete PVCs (optional, uncomment if you want to delete persistent data)
echo -e "\n${YELLOW}Deleting persistent volume claims...${NC}"
kubectl delete pvc -n monitoring --all

# Delete the namespace
echo -e "\n${YELLOW}Deleting monitoring namespace...${NC}"
if kubectl get namespace monitoring &> /dev/null; then
    kubectl delete namespace monitoring
    echo "Deleted monitoring namespace"
fi

echo -e "\n${GREEN}Cleanup completed successfully!${NC}"
