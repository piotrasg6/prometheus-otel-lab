FROM python:3.9-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Environment variables with defaults
ENV PUSH_GATEWAY_URL="prometheus-pushgateway:9091"
ENV PUSH_INTERVAL="15"
ENV APP_NAME="sample-batch-app"
ENV JOB_MODE="continuous"

# Run the application
CMD ["python", "app.py"]
