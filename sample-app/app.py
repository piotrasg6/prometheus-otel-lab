import time
import random
import os
import socket
from datetime import datetime
import threading
import logging
from prometheus_client import CollectorRegistry, Counter, Gauge, push_to_gateway
import kubernetes as k8s

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('metric-pusher')

# Configuration - read from environment variables with defaults
PUSH_GATEWAY_URL = os.getenv("PUSH_GATEWAY_URL", "prometheus-pushgateway:9091")
INSTANCE_NAME = os.getenv("INSTANCE_NAME", socket.gethostname())
APP_NAME = os.getenv("APP_NAME", "sample-batch-app")
PUSH_INTERVAL = int(os.getenv("PUSH_INTERVAL", "15"))  # seconds
METRICS_PREFIX = os.getenv("METRICS_PREFIX", "batch_app")

# Try to get pod name and namespace from Kubernetes environment
# This works when running inside a Kubernetes pod
try:
    POD_NAME = os.getenv("POD_NAME", "unknown")
    NAMESPACE = os.getenv("POD_NAMESPACE", "default")
except:
    POD_NAME = "unknown"
    NAMESPACE = "default"

def create_metrics():
    """Create a registry with metrics"""
    registry = CollectorRegistry()

    # CPU Utilization (0-100%)
    cpu_metric = Gauge(
        f'{METRICS_PREFIX}_cpu_utilization',
        'CPU utilization percentage',
        ['instance', 'app', 'pod', 'namespace'],
        registry=registry
    )

    # Memory Usage (in MB)
    memory_metric = Gauge(
        f'{METRICS_PREFIX}_memory_usage_mb',
        'Memory usage in megabytes',
        ['instance', 'app', 'pod', 'namespace'],
        registry=registry
    )

    # Task Counter
    task_counter = Counter(
        f'{METRICS_PREFIX}_tasks_processed_total',
        'Number of tasks processed',
        ['instance', 'app', 'pod', 'namespace', 'status'],
        registry=registry
    )

    # Error Counter
    error_counter = Counter(
        f'{METRICS_PREFIX}_errors_total',
        'Number of errors encountered',
        ['instance', 'app', 'pod', 'namespace', 'error_type'],
        registry=registry
    )

    # Latency Gauge
    latency_metric = Gauge(
        f'{METRICS_PREFIX}_task_latency_ms',
        'Task processing latency in milliseconds',
        ['instance', 'app', 'pod', 'namespace', 'task_type'],
        registry=registry
    )

    return {
        'registry': registry,
        'cpu': cpu_metric,
        'memory': memory_metric,
        'tasks': task_counter,
        'errors': error_counter,
        'latency': latency_metric
    }

def update_metrics(metrics):
    """Update metrics with simulated values"""
    # Get label values
    labels = {
        'instance': INSTANCE_NAME,
        'app': APP_NAME,
        'pod': POD_NAME,
        'namespace': NAMESPACE
    }

    # Update CPU utilization (0-100%)
    metrics['cpu'].labels(**labels).set(random.uniform(5, 95))

    # Update Memory usage (50-500 MB)
    metrics['memory'].labels(**labels).set(random.uniform(50, 500))

    # Update task counter
    successful_tasks = random.randint(10, 100)
    failed_tasks = random.randint(0, 10)
    metrics['tasks'].labels(**labels, status="success").inc(successful_tasks)
    metrics['tasks'].labels(**labels, status="failed").inc(failed_tasks)

    # Update error counter (occasionally)
    if random.random() < 0.3:  # 30% chance of errors
        error_labels = labels.copy()
        error_types = ["connection", "timeout", "validation"]
        for error_type in error_types:
            if random.random() < 0.5:  # 50% chance for each error type
                metrics['errors'].labels(**error_labels, error_type=error_type).inc(random.randint(1, 5))

    # Update latency metrics
    task_types = ["processing", "validation", "storage"]
    for task_type in task_types:
        latency_labels = labels.copy()
        metrics['latency'].labels(**latency_labels, task_type=task_type).set(random.uniform(10, 500))

def push_metrics_job():
    """Job that continuously pushes metrics to the Push Gateway"""
    logger.info(f"Starting metrics push job. Pushing to {PUSH_GATEWAY_URL} every {PUSH_INTERVAL}s")
    logger.info(f"Instance: {INSTANCE_NAME}, App: {APP_NAME}, Pod: {POD_NAME}, Namespace: {NAMESPACE}")

    # Create metrics
    metrics = create_metrics()

    job_id = int(time.time())  # Unique job ID based on timestamp

    while True:
        try:
            # Update metrics with new values
            update_metrics(metrics)

            # Push to gateway
            push_to_gateway(
                PUSH_GATEWAY_URL,
                job=f'{APP_NAME}-{job_id}',
                registry=metrics['registry'],
                grouping_key={
                    'instance': INSTANCE_NAME,
                    'pod': POD_NAME
                }
            )
            logger.info(f"Successfully pushed metrics to {PUSH_GATEWAY_URL}")

        except Exception as e:
            logger.error(f"Error pushing metrics: {str(e)}")

        # Wait for next interval
        time.sleep(PUSH_INTERVAL)

def simulate_batch_job():
    """Simulate a one-time batch job that pushes metrics at the end"""
    job_id = int(time.time())
    logger.info(f"Starting one-time batch job {job_id}")

    # Create registry and metrics
    registry = CollectorRegistry()
    duration = Gauge('batch_job_duration_seconds', 'Duration of batch job',
                    ['instance', 'job_id', 'pod'], registry=registry)
    records = Counter('batch_job_records_processed', 'Records processed',
                     ['instance', 'job_id', 'pod'], registry=registry)

    # Simulate job execution
    start_time = time.time()
    job_duration = random.randint(5, 20)  # 5-20 seconds

    # Simulate processing
    time.sleep(job_duration)

    # Update metrics
    duration.labels(instance=INSTANCE_NAME, job_id=str(job_id), pod=POD_NAME).set(time.time() - start_time)
    records.labels(instance=INSTANCE_NAME, job_id=str(job_id), pod=POD_NAME).inc(random.randint(1000, 10000))

    # Push to gateway
    try:
        push_to_gateway(
            PUSH_GATEWAY_URL,
            job=f'batch-job-{job_id}',
            registry=registry
        )
        logger.info(f"Batch job {job_id} completed and metrics pushed")
    except Exception as e:
        logger.error(f"Error pushing batch job metrics: {str(e)}")

if __name__ == "__main__":
    # Choose job mode based on environment variable
    JOB_MODE = os.getenv("JOB_MODE", "continuous")

    if JOB_MODE == "continuous":
        # Start the continuous metrics push job
        push_metrics_job()
    elif JOB_MODE == "batch":
        # Run a single batch job
        simulate_batch_job()
    elif JOB_MODE == "both":
        # Start the continuous job in a thread
        metrics_thread = threading.Thread(target=push_metrics_job, daemon=True)
        metrics_thread.start()

        # Run batch jobs periodically
        while True:
            simulate_batch_job()
            time.sleep(random.randint(30, 60))  # Wait 30-60 seconds between jobs
    else:
        logger.error(f"Unknown JOB_MODE: {JOB_MODE}. Use 'continuous', 'batch', or 'both'")
