FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    inotify-tools \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/my_dropbox
RUN mkdir -p /app/data
RUN mkdir -p /app/tmp/chunk

# Copy requirements file
COPY client/requirements.txt /app/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY client/ /app/

# Make start script executable
RUN chmod +x /app/scripts/bash/start.sh

# Expose the FastAPI port
EXPOSE 8000

# Command to run the application
CMD ["/bin/bash", "/app/scripts/bash/start.sh"]
