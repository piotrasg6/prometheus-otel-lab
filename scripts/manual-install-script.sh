#!/bin/bash
set -e

# Script to install the complete Prometheus Push Gateway to OpenTelemetry Lab
# This version installs components individually without ServiceMonitor CRDs

# Color codes for better readability
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Prometheus Push Gateway to OpenTelemetry Lab Installer ===${NC}"
echo "This script will set up the complete monitoring stack and sample application"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

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

# Check if Docker is installed (for building the sample app)
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed. Please install docker first.${NC}"
    exit 1
fi

# Check if we can connect to the Kubernetes cluster
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}All prerequisites satisfied!${NC}"

# Create the monitoring namespace
echo -e "\n${YELLOW}Creating monitoring namespace...${NC}"
kubectl apply -f ../sample-app/k8s/namespace.yaml
echo -e "${GREEN}Namespace created successfully.${NC}"

# Install Helm repositories
echo -e "\n${YELLOW}Adding Helm repositories...${NC}"
# Reset helm repositories to avoid any issues with private repos
helm repo remove edp-observability 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
echo -e "${GREEN}Helm repositories added successfully.${NC}"

# Deploy components individually
echo -e "\n${YELLOW}Deploying monitoring stack components...${NC}"

# 1. Deploy Prometheus Push Gateway
echo "Deploying Prometheus Push Gateway..."
helm install prometheus-pushgateway prometheus-community/prometheus-pushgateway \
  --namespace monitoring \
  --set serviceMonitor.enabled=false

# 2. Deploy OpenTelemetry Collector
echo "Deploying OpenTelemetry Collector..."
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  --set mode=deployment \
  --set serviceMonitor.enabled=false \
  --values ../helm/values/opentelemetry-collector.yaml

# 3. Deploy Prometheus
echo "Deploying Prometheus..."
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --values ../helm/values/prometheus.yaml

# 4. Deploy Grafana
echo "Deploying Grafana..."
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values ../helm/values/grafana.yaml

echo -e "${GREEN}Monitoring stack deployed successfully.${NC}"

# Wait for pods to be ready
echo -e "\n${YELLOW}Waiting for monitoring pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=prometheus-pushgateway" --namespace monitoring --timeout=120s || echo "Warning: Push Gateway pods not ready in time, continuing..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/component=opentelemetry-collector" --namespace monitoring --timeout=120s || echo "Warning: OpenTelemetry Collector pods not ready in time, continuing..."
kubectl wait --for=condition=ready pod -l "app=prometheus,component=server" --namespace monitoring --timeout=120s || echo "Warning: Prometheus pods not ready in time, continuing..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=grafana" --namespace monitoring --timeout=120s || echo "Warning: Grafana pods not ready in time, continuing..."
echo -e "${GREEN}Monitoring deployment completed.${NC}"

# Update configmap with correct service names for individual installations
echo -e "\n${YELLOW}Updating sample application configuration...${NC}"
# Get the current content of the ConfigMap
cat > ../sample-app/k8s/configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-app-config
  namespace: monitoring
data:
  PUSH_GATEWAY_URL: "prometheus-pushgateway.monitoring.svc.cluster.local:9091"
  PUSH_INTERVAL: "15"
  APP_NAME: "sample-batch-app"
  JOB_MODE: "both"
  METRICS_PREFIX: "k8s_batch_app"
EOF

# Build and deploy the sample application
echo -e "\n${YELLOW}Building sample application...${NC}"
cd ../sample-app

# Build the Docker image
IMAGE_NAME="sample-batch-app:latest"
docker build -t ${IMAGE_NAME} .

# Option 1: If using Minikube, load the image directly
if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    echo "Loading image into Minikube..."
    minikube image load ${IMAGE_NAME}
    # Update the image reference in the deployment file
    sed -i "s|\${YOUR_REGISTRY}/sample-batch-app:latest|sample-batch-app:latest|g" k8s/deployment.yaml
    sed -i "s|\${YOUR_REGISTRY}/sample-batch-app:latest|sample-batch-app:latest|g" k8s/cronjob.yaml
# Option 2: If using a remote registry, push the image
else
    echo "To push to your registry, run:"
    echo "docker tag ${IMAGE_NAME} YOUR_REGISTRY/${IMAGE_NAME}"
    echo "docker push YOUR_REGISTRY/${IMAGE_NAME}"
    echo "Then update k8s/deployment.yaml and k8s/cronjob.yaml with your registry path"
    echo "Press Enter to continue or Ctrl+C to abort"
    read
fi

echo -e "\n${YELLOW}Deploying sample application...${NC}"
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/cronjob.yaml

echo -e "${GREEN}Sample application deployed successfully.${NC}"

# Set up port forwarding for accessing Grafana
echo -e "\n${YELLOW}Setting up port forwarding for services...${NC}"
echo "Run these commands in separate terminals to access the services:"
echo ""
echo "For Grafana:"
echo "kubectl port-forward svc/grafana 3000:80 -n monitoring"
echo "Then open http://localhost:3000 in your browser"
echo "Default login: admin / adminPassword"
echo ""
echo "For Prometheus:"
echo "kubectl port-forward svc/prometheus-server 9090:80 -n monitoring"
echo "Then open http://localhost:9090 in your browser"
echo ""
echo "For Push Gateway:"
echo "kubectl port-forward svc/prometheus-pushgateway 9091:9091 -n monitoring"
echo "Then open http://localhost:9091 in your browser"

# Instructions for testing
echo -e "\n${YELLOW}Lab setup complete!${NC}"
echo "To verify metrics flow, follow these steps:"
echo "1. Access Grafana and configure a dashboard for Prometheus metrics"
echo "2. Run the test script to generate additional metrics: ./test-metrics.sh"
echo "3. Observe the metrics flowing in the dashboard"

echo -e "\n${GREEN}Enjoy your Prometheus Push Gateway to OpenTelemetry Lab!${NC}"
