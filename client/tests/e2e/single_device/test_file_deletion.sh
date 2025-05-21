#!/bin/bash
#===================================================================================
# Firebox Client Test File Deletion
#===================================================================================
# Description: This script tests the file deletion functionality:
# - Detection when files are removed from sync directory
# - Database records updated accordingly
#
# The script follows these steps:
# 1. Create: Creates test files and uploads them to the sync directory
# 2. Verify: Confirms the files are processed and in the database
# 3. Delete: Removes one of the files from the sync directory
# 4. Verify: Confirms the file is removed from the database
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
TEMP_DIR="/tmp/firebox_test_${TIMESTAMP}"
WAIT_TIME=3  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox File Deletion Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Create test files
echo -e "${YELLOW}Step 1: Creating test files...${NC}"

# Create first test file
FILE1="${TEMP_DIR}/file1_${TIMESTAMP}.txt"
echo "This is the first test file that will remain in the sync directory." > $FILE1
echo -e "${GREEN}Created first test file: $FILE1${NC}"

# Create second test file (to be deleted)
FILE2="${TEMP_DIR}/file2_${TIMESTAMP}.txt"
echo "This is the second test file that will be deleted from the sync directory." > $FILE2
echo -e "${GREEN}Created second test file: $FILE2${NC}"

# Step 2: Copy files to the sync directory
echo -e "\n${YELLOW}Step 2: Copying files to the sync directory...${NC}"
FILE1_NAME=$(basename $FILE1)
FILE2_NAME=$(basename $FILE2)

# Copy first file
docker cp $FILE1 $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied first file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy first file${NC}"
    exit 1
fi

# Copy second file
docker cp $FILE2 $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied second file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy second file${NC}"
    exit 1
fi

# Step 3: Wait for files to be processed
echo -e "\n${YELLOW}Step 3: Waiting for files to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 4: Verify files exist in the database
echo -e "\n${YELLOW}Step 4: Verifying files exist in the database...${NC}"

# Check first file
FILE1_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$FILE1_NAME';")
if [ -n "$FILE1_DB" ]; then
    echo -e "${GREEN}First file found in database: $FILE1_DB${NC}"
    FILE1_ID=$(echo "$FILE1_DB" | cut -d'|' -f1)
else
    echo -e "${RED}First file not found in database${NC}"
    exit 1
fi

# Check second file
FILE2_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$FILE2_NAME';")
if [ -n "$FILE2_DB" ]; then
    echo -e "${GREEN}Second file found in database: $FILE2_DB${NC}"
    FILE2_ID=$(echo "$FILE2_DB" | cut -d'|' -f1)
else
    echo -e "${RED}Second file not found in database${NC}"
    exit 1
fi

# Step 5: Delete the second file from the sync directory
echo -e "\n${YELLOW}Step 5: Deleting the second file from the sync directory...${NC}"
docker exec $CONTAINER_NAME rm $CONTAINER_SYNC_DIR/$FILE2_NAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deleted second file from sync directory${NC}"
else
    echo -e "${RED}Failed to delete second file${NC}"
    exit 1
fi

# Step 6: Wait for deletion to be processed
echo -e "\n${YELLOW}Step 6: Waiting for deletion to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 7: Verify first file still exists in the database
echo -e "\n${YELLOW}Step 7: Verifying first file still exists in the database...${NC}"
FILE1_DB_AFTER=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$FILE1_NAME';")
if [ -n "$FILE1_DB_AFTER" ]; then
    echo -e "${GREEN}First file still exists in database: $FILE1_DB_AFTER${NC}"
else
    echo -e "${RED}First file no longer exists in database!${NC}"
    exit 1
fi

# Step 8: Verify second file is removed from the database
echo -e "\n${YELLOW}Step 8: Verifying second file is removed from the database...${NC}"
FILE2_DB_AFTER=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata WHERE file_name='$FILE2_NAME';")
if [ -z "$FILE2_DB_AFTER" ]; then
    echo -e "${GREEN}Second file successfully removed from database - GOOD!${NC}"
else
    echo -e "${RED}Second file still exists in database: $FILE2_DB_AFTER${NC}"
    exit 1
fi

# Step 9: Verify chunks for the second file are removed
echo -e "\n${YELLOW}Step 9: Verifying chunks for the second file are removed...${NC}"
FILE2_CHUNKS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE2_ID';")
if [ "$FILE2_CHUNKS" -eq 0 ]; then
    echo -e "${GREEN}All chunks for the second file have been removed - GOOD!${NC}"
else
    echo -e "${RED}Chunks for the second file still exist in database: $FILE2_CHUNKS chunks${NC}"
    exit 1
fi

# Step 10: Clean up
echo -e "\n${YELLOW}Step 10: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}File Deletion Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
