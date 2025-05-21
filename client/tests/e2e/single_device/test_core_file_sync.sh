#!/bin/bash
#===================================================================================
# Firebox Client Test Core File Synchronization
#===================================================================================
# Description: This script tests the core file synchronization functionality:
# - Automatic file upload
# - Real-time detection using inotify
# - Metadata storage in SQLite database
#
# The script follows these steps:
# 1. Create: Creates multiple files of different sizes
# 2. Upload: Copies the files to the Firebox sync directory
# 3. Verify: Confirms the files are processed and metadata is stored correctly
# 4. API: Verifies the files are accessible via the API
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
CONTAINER_NAME="firebox-client"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_firebox}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/firebox.db}"
API_URL="http://localhost:8000"
TEMP_DIR="/tmp/firebox_test_${TIMESTAMP}"
WAIT_TIME=3  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox Core File Synchronization Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Create test files of different sizes
echo -e "${YELLOW}Step 1: Creating test files of different sizes...${NC}"

# Small file (10KB)
SMALL_FILE="${TEMP_DIR}/small_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1K count=10 | base64 > $SMALL_FILE 2>/dev/null
echo -e "${GREEN}Created small file: $SMALL_FILE ($(du -h $SMALL_FILE | cut -f1))${NC}"

# Medium file (1MB)
MEDIUM_FILE="${TEMP_DIR}/medium_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1K count=1024 | base64 > $MEDIUM_FILE 2>/dev/null
echo -e "${GREEN}Created medium file: $MEDIUM_FILE ($(du -h $MEDIUM_FILE | cut -f1))${NC}"

# Large file (10MB) - should create multiple chunks
LARGE_FILE="${TEMP_DIR}/large_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1M count=10 | base64 > $LARGE_FILE 2>/dev/null
echo -e "${GREEN}Created large file: $LARGE_FILE ($(du -h $LARGE_FILE | cut -f1))${NC}"

# Step 2: Copy files to the sync directory
echo -e "\n${YELLOW}Step 2: Copying files to the sync directory...${NC}"

# Copy small file
docker cp $SMALL_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied small file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy small file${NC}"
    exit 1
fi

# Copy medium file
docker cp $MEDIUM_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied medium file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy medium file${NC}"
    exit 1
fi

# Copy large file
docker cp $LARGE_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied large file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy large file${NC}"
    exit 1
fi

# Step 3: Wait for files to be processed
echo -e "\n${YELLOW}Step 3: Waiting for files to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 4: Verify files exist in the container
echo -e "\n${YELLOW}Step 4: Verifying files exist in the container...${NC}"
SMALL_FILENAME=$(basename $SMALL_FILE)
MEDIUM_FILENAME=$(basename $MEDIUM_FILE)
LARGE_FILENAME=$(basename $LARGE_FILE)

# Check small file
if docker exec $CONTAINER_NAME ls -la $CONTAINER_SYNC_DIR/$SMALL_FILENAME >/dev/null 2>&1; then
    echo -e "${GREEN}Small file exists in container${NC}"
else
    echo -e "${RED}Small file not found in container${NC}"
    exit 1
fi

# Check medium file
if docker exec $CONTAINER_NAME ls -la $CONTAINER_SYNC_DIR/$MEDIUM_FILENAME >/dev/null 2>&1; then
    echo -e "${GREEN}Medium file exists in container${NC}"
else
    echo -e "${RED}Medium file not found in container${NC}"
    exit 1
fi

# Check large file
if docker exec $CONTAINER_NAME ls -la $CONTAINER_SYNC_DIR/$LARGE_FILENAME >/dev/null 2>&1; then
    echo -e "${GREEN}Large file exists in container${NC}"
else
    echo -e "${RED}Large file not found in container${NC}"
    exit 1
fi

# Step 5: Check if files are in the database
echo -e "\n${YELLOW}Step 5: Checking if files are in the database...${NC}"

# Check small file
SMALL_FILE_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$SMALL_FILENAME';")
if [ -n "$SMALL_FILE_DB" ]; then
    echo -e "${GREEN}Small file found in database: $SMALL_FILE_DB${NC}"
    SMALL_FILE_ID=$(echo "$SMALL_FILE_DB" | cut -d'|' -f1)
else
    echo -e "${RED}Small file not found in database${NC}"
    exit 1
fi

# Check medium file
MEDIUM_FILE_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$MEDIUM_FILENAME';")
if [ -n "$MEDIUM_FILE_DB" ]; then
    echo -e "${GREEN}Medium file found in database: $MEDIUM_FILE_DB${NC}"
    MEDIUM_FILE_ID=$(echo "$MEDIUM_FILE_DB" | cut -d'|' -f1)
else
    echo -e "${RED}Medium file not found in database${NC}"
    exit 1
fi

# Check large file
LARGE_FILE_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$LARGE_FILENAME';")
if [ -n "$LARGE_FILE_DB" ]; then
    echo -e "${GREEN}Large file found in database: $LARGE_FILE_DB${NC}"
    LARGE_FILE_ID=$(echo "$LARGE_FILE_DB" | cut -d'|' -f1)
else
    echo -e "${RED}Large file not found in database${NC}"
    exit 1
fi

# Step 6: Check API access to files
echo -e "\n${YELLOW}Step 6: Checking API access to files...${NC}"
API_RESPONSE=$(curl -s $API_URL/api/files)

# Check if all files are in the API response
if [[ $API_RESPONSE == *"$SMALL_FILENAME"* && $API_RESPONSE == *"$MEDIUM_FILENAME"* && $API_RESPONSE == *"$LARGE_FILENAME"* ]]; then
    echo -e "${GREEN}All files found in API response${NC}"
else
    echo -e "${RED}Not all files found in API response${NC}"
    echo -e "API Response: $API_RESPONSE"
    exit 1
fi

# Step 7: Clean up
echo -e "\n${YELLOW}Step 7: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Core File Synchronization Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
