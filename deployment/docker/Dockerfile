FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    inotify-tools \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create my_dropbox directory for file synchronization
RUN mkdir -p /app/my_dropbox

# Copy requirements file
COPY client/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY client/ .

# Make start script executable
RUN chmod +x /app/scripts/bash/start.sh

# Expose the FastAPI port
EXPOSE 8000

# Command to run the application
CMD ["/bin/bash", "/app/scripts/bash/start.sh"]
