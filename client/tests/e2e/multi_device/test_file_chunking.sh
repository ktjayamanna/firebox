#!/bin/bash
#===================================================================================
# Firebox Client Multi-Device Test File Chunking
#===================================================================================
# Description: This script tests the file chunking functionality across multiple
# client devices:
# - Splitting large files into chunks
# - Storing chunks in the chunk directory
# - Tracking chunks in the database
#
# The script follows these steps:
# 1. Create: Creates a large file that will be split into multiple chunks
# 2. Upload: Copies the file to each client's sync directory
# 3. Verify: Confirms the file is processed and chunks are created on each client
# 4. Database: Verifies chunk metadata is stored correctly in each client's database
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
CLIENT1_NAME="firebox-client-1"
CLIENT2_NAME="firebox-client-2"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_firebox}"
CHUNK_DIR="${CHUNK_DIR:-/app/tmp/chunk}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/firebox.db}"
TEMP_DIR="/tmp/firebox_test_${TIMESTAMP}"
FILE_SIZE_MB=12  # Create a file larger than 10MB to ensure multiple chunks
WAIT_TIME=5  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox Multi-Device File Chunking Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if containers are running
if ! docker ps | grep -q $CLIENT1_NAME; then
    echo -e "${RED}Error: $CLIENT1_NAME container is not running${NC}"
    echo -e "Please start the containers first with: ./client/scripts/bash/start_multi_client_containers.sh"
    exit 1
fi

if ! docker ps | grep -q $CLIENT2_NAME; then
    echo -e "${RED}Error: $CLIENT2_NAME container is not running${NC}"
    echo -e "Please start the containers first with: ./client/scripts/bash/start_multi_client_containers.sh"
    exit 1
fi

# Step 1: Create a large test file
echo -e "${YELLOW}Step 1: Creating a large test file (${FILE_SIZE_MB}MB)...${NC}"
TEST_FILE="${TEMP_DIR}/large_file_${TIMESTAMP}.dat"
dd if=/dev/urandom bs=1M count=$FILE_SIZE_MB of=$TEST_FILE status=progress 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created test file: $TEST_FILE ($(du -h $TEST_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Calculate file hash for later verification
FILE_HASH=$(sha256sum $TEST_FILE | awk '{print $1}')
echo -e "${CYAN}File SHA-256 hash: $FILE_HASH${NC}"

# Step 2: Copy the file to client 1 sync directory
echo -e "\n${YELLOW}Step 2: Copying file to client 1 sync directory...${NC}"
TEST_FILENAME=$(basename $TEST_FILE)
docker cp $TEST_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied file to client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to copy file to client 1 sync directory${NC}"
    exit 1
fi

# Step 3: Copy the file to client 2 sync directory
echo -e "\n${YELLOW}Step 3: Copying file to client 2 sync directory...${NC}"
docker cp $TEST_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied file to client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to copy file to client 2 sync directory${NC}"
    exit 1
fi

# Step 4: Wait for file to be processed
echo -e "\n${YELLOW}Step 4: Waiting for file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 5: Verify file exists in both clients
echo -e "\n${YELLOW}Step 5: Verifying file exists in both clients...${NC}"

# Check client 1
if docker exec $CLIENT1_NAME ls -la $CONTAINER_SYNC_DIR/$TEST_FILENAME >/dev/null 2>&1; then
    echo -e "${GREEN}File exists in client 1${NC}"
else
    echo -e "${RED}File not found in client 1${NC}"
    exit 1
fi

# Check client 2
if docker exec $CLIENT2_NAME ls -la $CONTAINER_SYNC_DIR/$TEST_FILENAME >/dev/null 2>&1; then
    echo -e "${GREEN}File exists in client 2${NC}"
else
    echo -e "${RED}File not found in client 2${NC}"
    exit 1
fi

# Step 6: Check if file is in the database for both clients
echo -e "\n${YELLOW}Step 6: Checking if file is in the database for both clients...${NC}"

# Check client 1
FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$FILE_DB_1" ]; then
    echo -e "${GREEN}File found in client 1 database: $FILE_DB_1${NC}"
    FILE_ID_1=$(echo "$FILE_DB_1" | cut -d'|' -f1)
else
    echo -e "${RED}File not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$FILE_DB_2" ]; then
    echo -e "${GREEN}File found in client 2 database: $FILE_DB_2${NC}"
    FILE_ID_2=$(echo "$FILE_DB_2" | cut -d'|' -f1)
else
    echo -e "${RED}File not found in client 2 database${NC}"
    exit 1
fi

# Step 7: Check if chunks are created for both clients
echo -e "\n${YELLOW}Step 7: Checking if chunks are created for both clients...${NC}"

# Check client 1
CHUNKS_COUNT_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID_1';")
if [ "$CHUNKS_COUNT_1" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNKS_COUNT_1 chunks in client 1 database for file ID $FILE_ID_1${NC}"
else
    echo -e "${RED}No chunks found in client 1 database for file ID $FILE_ID_1${NC}"
    exit 1
fi

# Check client 2
CHUNKS_COUNT_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID_2';")
if [ "$CHUNKS_COUNT_2" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNKS_COUNT_2 chunks in client 2 database for file ID $FILE_ID_2${NC}"
else
    echo -e "${RED}No chunks found in client 2 database for file ID $FILE_ID_2${NC}"
    exit 1
fi

# Step 8: Verify chunks exist in the chunk directory for both clients
echo -e "\n${YELLOW}Step 8: Verifying chunks exist in the chunk directory for both clients...${NC}"

# Check client 1
CHUNK_FILES_1=$(docker exec $CLIENT1_NAME bash -c "ls -la $CHUNK_DIR | grep -c '.chunk'")
if [ "$CHUNK_FILES_1" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNK_FILES_1 chunk files in client 1 chunk directory${NC}"
else
    echo -e "${RED}No chunk files found in client 1 chunk directory${NC}"
    exit 1
fi

# Check client 2
CHUNK_FILES_2=$(docker exec $CLIENT2_NAME bash -c "ls -la $CHUNK_DIR | grep -c '.chunk'")
if [ "$CHUNK_FILES_2" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNK_FILES_2 chunk files in client 2 chunk directory${NC}"
else
    echo -e "${RED}No chunk files found in client 2 chunk directory${NC}"
    exit 1
fi

# Step 9: Clean up
echo -e "\n${YELLOW}Step 9: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device File Chunking Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
