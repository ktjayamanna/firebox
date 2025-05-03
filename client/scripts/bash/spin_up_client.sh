#!/bin/bash
# Script to spin up the Dropbox client container

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Starting Dropbox Client Container${NC}"
echo -e "${BLUE}=========================================${NC}"

# Navigate to the docker directory
cd deployment/docker || {
    echo "Error: deployment/docker directory not found"
    exit 1
}

# Build and start the container
echo -e "${GREEN}Building and starting container...${NC}"
docker compose up -d

# Check if container is running
if [ "$(docker ps -q -f name=dropbox-client)" ]; then
    echo -e "${GREEN}Container started successfully!${NC}"
    echo -e "${GREEN}API is available at: http://localhost:8000${NC}"
else
    echo "Error: Container failed to start"
    exit 1
fi

echo -e "${BLUE}=========================================${NC}"