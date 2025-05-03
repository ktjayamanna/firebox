#!/bin/bash
# Run all smoke tests

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Running All Dropbox Smoke Tests${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q dropbox-client; then
    echo -e "${RED}Error: dropbox-client container is not running${NC}"
    echo -e "Starting container..."
    cd deployment/docker && docker-compose up -d
    cd ../../

    # Wait for container to start
    echo -e "${YELLOW}Waiting for container to start (10 seconds)...${NC}"
    sleep 10

    if ! docker ps | grep -q dropbox-client; then
        echo -e "${RED}Failed to start container. Please check docker logs.${NC}"
        exit 1
    fi
fi

# Make all test scripts executable
chmod +x client/tests/smoke/test_*.sh

# Clean up the sync directory before running tests
echo -e "\n${YELLOW}Cleaning up sync directory...${NC}"
docker exec dropbox-client bash -c "rm -rf /app/my_dropbox/*"
echo -e "${GREEN}Sync directory cleaned${NC}"

# Wait for cleanup to be processed
sleep 2

# Run each test script
echo -e "\n${YELLOW}Running file sync test...${NC}"
./client/tests/smoke/test_file_sync.sh

echo -e "\n${YELLOW}Running file modifications test...${NC}"
./client/tests/smoke/test_file_modifications.sh

echo -e "\n${YELLOW}Running folder operations test...${NC}"
./client/tests/smoke/test_folder_operations.sh

echo -e "\n${YELLOW}Running API endpoints test...${NC}"
./client/tests/smoke/test_api_endpoints.sh

echo -e "\n${GREEN}All smoke tests completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
