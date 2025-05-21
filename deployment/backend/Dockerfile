FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements file
COPY backend/firebox/files_service/requirements.txt /app/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY backend/firebox/files_service/ /app/

# Create a tmp directory for any temporary processing
RUN mkdir -p /app/tmp

# Copy startup script
COPY deployment/backend/deployment_scripts/start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Expose the FastAPI port
EXPOSE 8001

# Command to run the application
CMD ["/bin/bash", "/app/start.sh"]
