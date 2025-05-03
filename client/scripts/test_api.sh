#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Dropbox Client Container...${NC}"

# Navigate to the docker directory
cd "$(dirname "$0")/../../deployment/docker" || {
    echo -e "${RED}Failed to navigate to docker directory${NC}"
    exit 1
}

# Check if the container is already running
if docker ps | grep -q "dropbox-client"; then
    echo -e "${YELLOW}Container already running. Stopping and removing...${NC}"
    docker-compose down
fi

# Start the container in detached mode
echo -e "${YELLOW}Starting container with docker-compose...${NC}"
docker-compose up -d

# Wait for the container to start
echo -e "${YELLOW}Waiting for the API to become available...${NC}"
MAX_RETRIES=30
RETRY_COUNT=0

while ! curl -s http://localhost:8000/health > /dev/null; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo -e "${RED}Failed to connect to the API after $MAX_RETRIES attempts${NC}"
        echo -e "${YELLOW}Stopping container...${NC}"
        docker-compose down
        exit 1
    fi
    echo -e "${YELLOW}Waiting for API to start (attempt $RETRY_COUNT/$MAX_RETRIES)...${NC}"
    sleep 1
done

echo -e "${GREEN}API is up and running!${NC}"

# Function to make a curl request and display the result
function make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4

    echo -e "\n${YELLOW}Testing: $description${NC}"
    echo -e "${YELLOW}$method $endpoint${NC}"
    
    if [ -n "$data" ]; then
        echo -e "${YELLOW}Data: $data${NC}"
        response=$(curl -s -X "$method" "http://localhost:8000$endpoint" -H "Content-Type: application/json" -d "$data")
    else
        response=$(curl -s -X "$method" "http://localhost:8000$endpoint")
    fi
    
    echo -e "${GREEN}Response:${NC}"
    echo "$response" | python -m json.tool 2>/dev/null || echo "$response"
    echo -e "${YELLOW}----------------------------------------${NC}"
}

# Test the API endpoints
make_request "GET" "/" "" "Root endpoint"
make_request "GET" "/health" "" "Health check endpoint"
make_request "GET" "/api/files" "" "Get all files"

# Create a test file in the my_dropbox directory inside the container
echo -e "\n${YELLOW}Creating a test file in the my_dropbox directory...${NC}"
docker exec dropbox-client bash -c "echo 'This is a test file' > /app/my_dropbox/test.txt"
echo -e "${GREEN}Test file created${NC}"

# Wait a moment for the file to be processed
sleep 2

# Check if the file was detected and processed
make_request "GET" "/api/files" "" "Get all files (after creating test file)"

# Optional: Clean up
read -p "Do you want to stop the container? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Stopping container...${NC}"
    docker-compose down
    echo -e "${GREEN}Container stopped${NC}"
else
    echo -e "${GREEN}Container is still running. You can stop it later with 'docker-compose down'${NC}"
fi

exit 0
