#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing Dropbox File Synchronization...${NC}"

# Navigate to the docker directory
cd "$(dirname "$0")/../../deployment/docker" || {
    echo -e "${RED}Failed to navigate to docker directory${NC}"
    exit 1
}

# Check if the container is already running
if ! docker ps | grep -q "dropbox-client"; then
    echo -e "${YELLOW}Container not running. Starting it...${NC}"
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
fi

echo -e "${GREEN}API is up and running!${NC}"

# Create a test directory for our local files
TEST_DIR="/tmp/dropbox_test"
mkdir -p "$TEST_DIR"

# Function to create a test file of a specific size
create_test_file() {
    local filename=$1
    local size=$2
    local path="$TEST_DIR/$filename"
    
    echo -e "${YELLOW}Creating test file: $filename (size: $size)${NC}"
    dd if=/dev/urandom of="$path" bs=1M count="$size" 2>/dev/null
    echo -e "${GREEN}Created: $path${NC}"
    
    return 0
}

# Function to copy a file to the my_dropbox directory in the container
copy_to_dropbox() {
    local filename=$1
    local source="$TEST_DIR/$filename"
    
    echo -e "${YELLOW}Copying $filename to my_dropbox directory...${NC}"
    docker cp "$source" "dropbox-client:/app/my_dropbox/$filename"
    echo -e "${GREEN}File copied to my_dropbox${NC}"
    
    return 0
}

# Function to check if a file exists in the database
check_file_in_db() {
    local filename=$1
    local max_retries=10
    local retry_count=0
    
    echo -e "${YELLOW}Checking if $filename is in the database...${NC}"
    
    while [ $retry_count -lt $max_retries ]; do
        response=$(curl -s "http://localhost:8000/api/files")
        if echo "$response" | grep -q "$filename"; then
            echo -e "${GREEN}File found in database!${NC}"
            return 0
        fi
        
        retry_count=$((retry_count+1))
        echo -e "${YELLOW}File not found yet, retrying ($retry_count/$max_retries)...${NC}"
        sleep 1
    done
    
    echo -e "${RED}File not found in database after $max_retries attempts${NC}"
    return 1
}

# Test with different file sizes
echo -e "\n${YELLOW}=== Testing with small file (1MB) ===${NC}"
create_test_file "small_file.bin" 1
copy_to_dropbox "small_file.bin"
check_file_in_db "small_file.bin"

echo -e "\n${YELLOW}=== Testing with medium file (5MB) ===${NC}"
create_test_file "medium_file.bin" 5
copy_to_dropbox "medium_file.bin"
check_file_in_db "medium_file.bin"

# Uncomment for larger file testing
# echo -e "\n${YELLOW}=== Testing with large file (20MB) ===${NC}"
# create_test_file "large_file.bin" 20
# copy_to_dropbox "large_file.bin"
# check_file_in_db "large_file.bin"

# Test file modification
echo -e "\n${YELLOW}=== Testing file modification ===${NC}"
echo "Modified content" >> "$TEST_DIR/small_file.bin"
copy_to_dropbox "small_file.bin"
sleep 2
echo -e "${GREEN}File modified and synced${NC}"

# Clean up
echo -e "\n${YELLOW}=== Cleaning up ===${NC}"
echo -e "${YELLOW}Removing test directory: $TEST_DIR${NC}"
rm -rf "$TEST_DIR"
echo -e "${GREEN}Test directory removed${NC}"

# Optional: Stop the container
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
