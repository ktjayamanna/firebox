FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    inotify-tools \
    sqlite3 \
    curl \
    unzip \
    nano \
    iputils-ping \
    net-tools \
    dnsutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Set working directory
WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/my_firebox
RUN mkdir -p /app/data
RUN mkdir -p /app/tmp/chunk

# Copy requirements file
COPY client/requirements.txt /app/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY client/ /app/

# Make start script executable
COPY deployment/client/deployment_scripts/start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Expose the FastAPI port
EXPOSE 8000

# Command to run the application
CMD ["/bin/bash", "/app/start.sh"]
