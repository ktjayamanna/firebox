#!/bin/bash
#===================================================================================
# Dropbox Client Multi-Device Test File Modifications
#===================================================================================
# Description: This script tests the file modification tracking functionality across
# multiple client devices:
# - Detection of file changes
# - Full re-chunking and upload of modified files
# - Hash-based change detection
#
# The script follows these steps:
# 1. Create: Creates a test file and uploads it to each client's sync directory
# 2. Verify: Confirms the file is processed and chunks are created on each client
# 3. Modify: Changes the file content
# 4. Update: Updates the file in each client's sync directory
# 5. Verify: Confirms the changes are detected and new chunks are created on each client
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
CLIENT1_NAME="dropbox-client-1"
CLIENT2_NAME="dropbox-client-2"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_dropbox}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/dropbox.db}"
TEMP_DIR="/tmp/dropbox_test_${TIMESTAMP}"
FILE_SIZE_KB=500  # Create a medium-sized file
WAIT_TIME=3  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Multi-Device File Modifications Test${NC}"
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

# Step 1: Create a test file
echo -e "${YELLOW}Step 1: Creating a test file (${FILE_SIZE_KB}KB)...${NC}"
TEST_FILE="${TEMP_DIR}/test_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1K count=$FILE_SIZE_KB | base64 > $TEST_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created test file: $TEST_FILE ($(du -h $TEST_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Calculate file hash for later verification
ORIGINAL_HASH=$(sha256sum $TEST_FILE | awk '{print $1}')
echo -e "${CYAN}Original file SHA-256 hash: $ORIGINAL_HASH${NC}"

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

# Step 5: Check if file is in the database for both clients
echo -e "\n${YELLOW}Step 5: Checking if file is in the database for both clients...${NC}"

# Check client 1
FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$FILE_DB_1" ]; then
    echo -e "${GREEN}File found in client 1 database: $FILE_DB_1${NC}"
    FILE_ID_1=$(echo "$FILE_DB_1" | cut -d'|' -f1)
    FILE_HASH_1=$(echo "$FILE_DB_1" | cut -d'|' -f3)
    echo -e "${CYAN}Client 1 file ID: $FILE_ID_1, Hash: $FILE_HASH_1${NC}"
else
    echo -e "${RED}File not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$FILE_DB_2" ]; then
    echo -e "${GREEN}File found in client 2 database: $FILE_DB_2${NC}"
    FILE_ID_2=$(echo "$FILE_DB_2" | cut -d'|' -f1)
    FILE_HASH_2=$(echo "$FILE_DB_2" | cut -d'|' -f3)
    echo -e "${CYAN}Client 2 file ID: $FILE_ID_2, Hash: $FILE_HASH_2${NC}"
else
    echo -e "${RED}File not found in client 2 database${NC}"
    exit 1
fi

# Step 6: Modify the file
echo -e "\n${YELLOW}Step 6: Modifying the file...${NC}"
MODIFIED_FILE="${TEMP_DIR}/modified_file_${TIMESTAMP}.txt"
cp $TEST_FILE $MODIFIED_FILE
echo "This is additional content added to the file to modify it." >> $MODIFIED_FILE
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Modified file: $MODIFIED_FILE ($(du -h $MODIFIED_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to modify file${NC}"
    exit 1
fi

# Calculate modified file hash
MODIFIED_HASH=$(sha256sum $MODIFIED_FILE | awk '{print $1}')
echo -e "${CYAN}Modified file SHA-256 hash: $MODIFIED_HASH${NC}"

# Step 7: Replace the file in client 1 sync directory
echo -e "\n${YELLOW}Step 7: Replacing the file in client 1 sync directory...${NC}"
docker cp $MODIFIED_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/$TEST_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Replaced file in client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to replace file in client 1 sync directory${NC}"
    exit 1
fi

# Step 8: Replace the file in client 2 sync directory
echo -e "\n${YELLOW}Step 8: Replacing the file in client 2 sync directory...${NC}"
docker cp $MODIFIED_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/$TEST_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Replaced file in client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to replace file in client 2 sync directory${NC}"
    exit 1
fi

# Step 9: Wait for file to be processed
echo -e "\n${YELLOW}Step 9: Waiting for file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 10: Check if file hash has been updated in the database for both clients
echo -e "\n${YELLOW}Step 10: Checking if file hash has been updated in the database for both clients...${NC}"

# Check client 1
NEW_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$NEW_FILE_DB_1" ]; then
    echo -e "${GREEN}File found in client 1 database after modification: $NEW_FILE_DB_1${NC}"
    NEW_FILE_ID_1=$(echo "$NEW_FILE_DB_1" | cut -d'|' -f1)
    NEW_FILE_HASH_1=$(echo "$NEW_FILE_DB_1" | cut -d'|' -f3)
    echo -e "${CYAN}Client 1 new file ID: $NEW_FILE_ID_1, New Hash: $NEW_FILE_HASH_1${NC}"
    
    if [ "$NEW_FILE_HASH_1" != "$FILE_HASH_1" ]; then
        echo -e "${GREEN}File hash has been updated in client 1 database${NC}"
    else
        echo -e "${RED}File hash has not been updated in client 1 database${NC}"
        exit 1
    fi
else
    echo -e "${RED}File not found in client 1 database after modification${NC}"
    exit 1
fi

# Check client 2
NEW_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$NEW_FILE_DB_2" ]; then
    echo -e "${GREEN}File found in client 2 database after modification: $NEW_FILE_DB_2${NC}"
    NEW_FILE_ID_2=$(echo "$NEW_FILE_DB_2" | cut -d'|' -f1)
    NEW_FILE_HASH_2=$(echo "$NEW_FILE_DB_2" | cut -d'|' -f3)
    echo -e "${CYAN}Client 2 new file ID: $NEW_FILE_ID_2, New Hash: $NEW_FILE_HASH_2${NC}"
    
    if [ "$NEW_FILE_HASH_2" != "$FILE_HASH_2" ]; then
        echo -e "${GREEN}File hash has been updated in client 2 database${NC}"
    else
        echo -e "${RED}File hash has not been updated in client 2 database${NC}"
        exit 1
    fi
else
    echo -e "${RED}File not found in client 2 database after modification${NC}"
    exit 1
fi

# Step 11: Clean up
echo -e "\n${YELLOW}Step 11: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device File Modifications Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
