#!/bin/bash
set -e

# Script to test metrics flow in the Push Gateway to OpenTelemetry Lab

# Color codes for better readability
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Prometheus Push Gateway Metrics Test ===${NC}"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed. Please install kubectl first.${NC}"
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is not installed. Please install curl first.${NC}"
    exit 1
fi

# Check if we can connect to the Kubernetes cluster
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Check if the monitoring namespace exists
if ! kubectl get namespace monitoring &> /dev/null; then
    echo -e "${RED}Error: monitoring namespace not found. Please run install-lab.sh first.${NC}"
    exit 1
fi

# Check if Push Gateway is running
if ! kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus-pushgateway" &> /dev/null; then
    echo -e "${RED}Error: Push Gateway is not running. Please check your installation.${NC}"
    exit 1
fi

# Set up port forwarding to Push Gateway
echo -e "\n${YELLOW}Setting up port forwarding to Push Gateway...${NC}"
PUSHGATEWAY_POD=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus-pushgateway" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward -n monitoring pod/${PUSHGATEWAY_POD} 9091:9091 &
PORT_FORWARD_PID=$!

# Give port-forwarding time to establish
sleep 3

echo -e "\n${YELLOW}Generating and pushing test metrics...${NC}"

# Define metric job and instance
JOB_NAME="test_job"
INSTANCE_NAME="test_instance"
TIMESTAMP=$(date +%s)

# Create test metrics
echo -e "Pushing CPU metrics..."
curl -s -X POST --data "test_cpu_usage{instance=\"${INSTANCE_NAME}\"} $(awk 'BEGIN {print rand() * 100}')" \
  http://localhost:9091/metrics/job/${JOB_NAME}

echo -e "Pushing memory metrics..."
curl -s -X POST --data "test_memory_mb{instance=\"${INSTANCE_NAME}\"} $(awk 'BEGIN {print rand() * 1024}')" \
  http://localhost:9091/metrics/job/${JOB_NAME}

echo -e "Pushing task metrics..."
curl -s -X POST --data "test_tasks_processed_total{instance=\"${INSTANCE_NAME}\",status=\"success\"} $(( RANDOM % 1000 ))" \
  http://localhost:9091/metrics/job/${JOB_NAME}

echo -e "Pushing error metrics..."
curl -s -X POST --data "test_errors_total{instance=\"${INSTANCE_NAME}\",error_type=\"timeout\"} $(( RANDOM % 10 ))" \
  http://localhost:9091/metrics/job/${JOB_NAME}

echo -e "Pushing batch job metrics..."
curl -s -X POST --data "test_batch_job_duration_seconds{instance=\"${INSTANCE_NAME}\",job_id=\"test-${TIMESTAMP}\"} $(awk 'BEGIN {print rand() * 60}')" \
  http://localhost:9091/metrics/job/test_batch_job

# Terminate port forwarding
kill ${PORT_FORWARD_PID}

echo -e "\n${GREEN}Test metrics pushed successfully!${NC}"

# Verify metrics flow
echo -e "\n${YELLOW}Verifying metrics flow...${NC}"
echo "1. Check that metrics are visible in Push Gateway:"
echo "   kubectl port-forward svc/prometheus-pushgateway-prometheus-pushgateway 9091:9091 -n monitoring"
echo "   Then open http://localhost:9091 in your browser"
echo ""
echo "2. Check that metrics are scraped by Prometheus:"
echo "   kubectl port-forward svc/prometheus-server 9090:80 -n monitoring"
echo "   Then open http://localhost:9090 in your browser and search for 'test_cpu_usage'"
echo ""
echo "3. Check that metrics are displayed in Grafana:"
echo "   kubectl port-forward svc/grafana 3000:80 -n monitoring"
echo "   Then open http://localhost:3000 in your browser and go to the Push Gateway Metrics dashboard"

echo -e "\n${GREEN}Metrics test completed!${NC}"
