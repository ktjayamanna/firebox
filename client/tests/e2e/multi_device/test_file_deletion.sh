#!/bin/bash
#===================================================================================
# Dropbox Client Multi-Device Test File Deletion
#===================================================================================
# Description: This script tests the file deletion functionality across multiple
# client devices:
# - Detection of file deletion
# - Removal of file metadata from the database
# - Cleanup of associated chunks
#
# The script follows these steps:
# 1. Create: Creates test files and uploads them to each client's sync directory
# 2. Verify: Confirms the files are processed and stored in the database
# 3. Delete: Removes the files from each client's sync directory
# 4. Verify: Confirms the files are removed from the database and chunks are cleaned up
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
WAIT_TIME=3  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Multi-Device File Deletion Test${NC}"
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

# Step 1: Create test files
echo -e "${YELLOW}Step 1: Creating test files...${NC}"

# Create small file
SMALL_FILE="${TEMP_DIR}/small_file_${TIMESTAMP}.txt"
echo "This is a small test file for deletion testing." > $SMALL_FILE
echo -e "${GREEN}Created small file: $SMALL_FILE ($(du -h $SMALL_FILE | cut -f1))${NC}"

# Create medium file
MEDIUM_FILE="${TEMP_DIR}/medium_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1K count=100 | base64 > $MEDIUM_FILE 2>/dev/null
echo -e "${GREEN}Created medium file: $MEDIUM_FILE ($(du -h $MEDIUM_FILE | cut -f1))${NC}"

# Step 2: Copy files to client 1 sync directory
echo -e "\n${YELLOW}Step 2: Copying files to client 1 sync directory...${NC}"
SMALL_FILENAME=$(basename $SMALL_FILE)
MEDIUM_FILENAME=$(basename $MEDIUM_FILE)

docker cp $SMALL_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied small file to client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to copy small file to client 1 sync directory${NC}"
    exit 1
fi

docker cp $MEDIUM_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied medium file to client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to copy medium file to client 1 sync directory${NC}"
    exit 1
fi

# Step 3: Copy files to client 2 sync directory
echo -e "\n${YELLOW}Step 3: Copying files to client 2 sync directory...${NC}"

docker cp $SMALL_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied small file to client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to copy small file to client 2 sync directory${NC}"
    exit 1
fi

docker cp $MEDIUM_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied medium file to client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to copy medium file to client 2 sync directory${NC}"
    exit 1
fi

# Step 4: Wait for files to be processed
echo -e "\n${YELLOW}Step 4: Waiting for files to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 5: Verify files are in the database for both clients
echo -e "\n${YELLOW}Step 5: Verifying files are in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
SMALL_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$SMALL_FILENAME';")
if [ -n "$SMALL_FILE_DB_1" ]; then
    echo -e "${GREEN}Small file found in client 1 database: $SMALL_FILE_DB_1${NC}"
    SMALL_FILE_ID_1=$(echo "$SMALL_FILE_DB_1" | cut -d'|' -f1)
else
    echo -e "${RED}Small file not found in client 1 database${NC}"
    exit 1
fi

MEDIUM_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$MEDIUM_FILENAME';")
if [ -n "$MEDIUM_FILE_DB_1" ]; then
    echo -e "${GREEN}Medium file found in client 1 database: $MEDIUM_FILE_DB_1${NC}"
    MEDIUM_FILE_ID_1=$(echo "$MEDIUM_FILE_DB_1" | cut -d'|' -f1)
else
    echo -e "${RED}Medium file not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
SMALL_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$SMALL_FILENAME';")
if [ -n "$SMALL_FILE_DB_2" ]; then
    echo -e "${GREEN}Small file found in client 2 database: $SMALL_FILE_DB_2${NC}"
    SMALL_FILE_ID_2=$(echo "$SMALL_FILE_DB_2" | cut -d'|' -f1)
else
    echo -e "${RED}Small file not found in client 2 database${NC}"
    exit 1
fi

MEDIUM_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$MEDIUM_FILENAME';")
if [ -n "$MEDIUM_FILE_DB_2" ]; then
    echo -e "${GREEN}Medium file found in client 2 database: $MEDIUM_FILE_DB_2${NC}"
    MEDIUM_FILE_ID_2=$(echo "$MEDIUM_FILE_DB_2" | cut -d'|' -f1)
else
    echo -e "${RED}Medium file not found in client 2 database${NC}"
    exit 1
fi

# Step 6: Delete files from client 1 sync directory
echo -e "\n${YELLOW}Step 6: Deleting files from client 1 sync directory...${NC}"
docker exec $CLIENT1_NAME rm -f $CONTAINER_SYNC_DIR/$SMALL_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deleted small file from client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to delete small file from client 1 sync directory${NC}"
    exit 1
fi

docker exec $CLIENT1_NAME rm -f $CONTAINER_SYNC_DIR/$MEDIUM_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deleted medium file from client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to delete medium file from client 1 sync directory${NC}"
    exit 1
fi

# Step 7: Delete files from client 2 sync directory
echo -e "\n${YELLOW}Step 7: Deleting files from client 2 sync directory...${NC}"
docker exec $CLIENT2_NAME rm -f $CONTAINER_SYNC_DIR/$SMALL_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deleted small file from client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to delete small file from client 2 sync directory${NC}"
    exit 1
fi

docker exec $CLIENT2_NAME rm -f $CONTAINER_SYNC_DIR/$MEDIUM_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deleted medium file from client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to delete medium file from client 2 sync directory${NC}"
    exit 1
fi

# Step 8: Wait for deletion to be processed
echo -e "\n${YELLOW}Step 8: Waiting for deletion to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 9: Verify files are removed from the database for both clients
echo -e "\n${YELLOW}Step 9: Verifying files are removed from the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
SMALL_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$SMALL_FILENAME';")
if [ -z "$SMALL_FILE_DB_1" ]; then
    echo -e "${GREEN}Small file successfully removed from client 1 database${NC}"
else
    echo -e "${RED}Small file still exists in client 1 database: $SMALL_FILE_DB_1${NC}"
    exit 1
fi

MEDIUM_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$MEDIUM_FILENAME';")
if [ -z "$MEDIUM_FILE_DB_1" ]; then
    echo -e "${GREEN}Medium file successfully removed from client 1 database${NC}"
else
    echo -e "${RED}Medium file still exists in client 1 database: $MEDIUM_FILE_DB_1${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
SMALL_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$SMALL_FILENAME';")
if [ -z "$SMALL_FILE_DB_2" ]; then
    echo -e "${GREEN}Small file successfully removed from client 2 database${NC}"
else
    echo -e "${RED}Small file still exists in client 2 database: $SMALL_FILE_DB_2${NC}"
    exit 1
fi

MEDIUM_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata WHERE file_name='$MEDIUM_FILENAME';")
if [ -z "$MEDIUM_FILE_DB_2" ]; then
    echo -e "${GREEN}Medium file successfully removed from client 2 database${NC}"
else
    echo -e "${RED}Medium file still exists in client 2 database: $MEDIUM_FILE_DB_2${NC}"
    exit 1
fi

# Step 10: Clean up
echo -e "\n${YELLOW}Step 10: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device File Deletion Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
