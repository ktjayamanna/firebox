#!/bin/bash
#===================================================================================
# Firebox Client Test File Modification Behavior
#===================================================================================
# Description: This script tests how the system handles file modifications,
# particularly focusing on file record creation and chunk processing.
# It reveals that when a file is modified, the system creates a new file record
# with a new ID rather than updating the existing record.
#
# The script follows these steps:
# 1. Create: Creates a test file
# 2. Upload: Copies the file to the sync directory
# 3. Verify: Confirms the file is processed and chunks are created
# 4. Modify: Changes the file content
# 5. Verify: Checks how the system handles the modification at different time intervals
#            (1s, 5s, 10s, 30s) to observe file record creation and chunk processing
#
# Key Insight: When a file is modified, the system:
# - Creates a new file record with a new file ID
# - Processes chunks immediately (not asynchronously)
# - Reuses chunks that haven't changed (content-based deduplication)
# - Only creates new chunks for the parts of the file that have changed
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
FILE_SIZE_MB=10  # Create a 10MB file to ensure multiple chunks
INITIAL_WAIT_TIME=5  # seconds to wait for initial file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox File Modification Behavior Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Create a test file
echo -e "${YELLOW}Step 1: Creating a ${FILE_SIZE_MB}MB test file...${NC}"
TEST_FILE="${TEMP_DIR}/test_file_${TIMESTAMP}.bin"
dd if=/dev/urandom bs=1M count=$FILE_SIZE_MB of=$TEST_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created test file: $TEST_FILE ($(du -h $TEST_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Calculate file hash for later verification
ORIGINAL_HASH=$(sha256sum $TEST_FILE | awk '{print $1}')
echo -e "${CYAN}Original file SHA-256 hash: $ORIGINAL_HASH${NC}"

# Step 2: Copy the file to the sync directory
echo -e "\n${YELLOW}Step 2: Copying file to the sync directory...${NC}"
TEST_FILENAME=$(basename $TEST_FILE)
docker cp $TEST_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy file to sync directory${NC}"
    exit 1
fi

# Step 3: Wait for file to be processed
echo -e "\n${YELLOW}Step 3: Waiting for file to be processed (${INITIAL_WAIT_TIME} seconds)...${NC}"
sleep $INITIAL_WAIT_TIME

# Step 4: Check if file is in the database
echo -e "\n${YELLOW}Step 4: Checking if file is in the database...${NC}"
DB_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$DB_RESULT" ]; then
    echo -e "${GREEN}File found in database:${NC}"
    echo -e "$DB_RESULT"

    # Extract file_id and hash for later use
    FILE_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    DB_ORIGINAL_HASH=$(echo "$DB_RESULT" | cut -d'|' -f4)
    echo -e "${CYAN}File ID: $FILE_ID${NC}"
    echo -e "${CYAN}Database file hash: $DB_ORIGINAL_HASH${NC}"
else
    echo -e "${RED}File not found in database${NC}"
    exit 1
fi

# Step 5: Check for initial chunks
echo -e "\n${YELLOW}Step 5: Checking for initial chunks...${NC}"
ORIGINAL_CHUNKS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")
if [ "$ORIGINAL_CHUNKS" -gt 0 ]; then
    echo -e "${GREEN}Found $ORIGINAL_CHUNKS original chunks in database${NC}"

    # Get original chunk fingerprints
    echo -e "${YELLOW}Original chunk fingerprints:${NC}"
    ORIGINAL_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$FILE_ID';")
    echo -e "$ORIGINAL_FINGERPRINTS"
else
    echo -e "${RED}No original chunks found in database${NC}"
    exit 1
fi

# Step 6: Modify the file
echo -e "\n${YELLOW}Step 6: Modifying the file...${NC}"
MODIFIED_FILE="${TEMP_DIR}/modified_${TEST_FILENAME}"
# Create a modified version by appending some data
cat $TEST_FILE > $MODIFIED_FILE
dd if=/dev/urandom bs=1M count=2 >> $MODIFIED_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created modified file: $MODIFIED_FILE ($(du -h $MODIFIED_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create modified file${NC}"
    exit 1
fi

# Calculate modified file hash
MODIFIED_HASH=$(sha256sum $MODIFIED_FILE | awk '{print $1}')
echo -e "${CYAN}Modified file SHA-256 hash: $MODIFIED_HASH${NC}"

# Step 7: Replace the file in the sync directory
echo -e "\n${YELLOW}Step 7: Replacing the file in the sync directory...${NC}"
docker cp $MODIFIED_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/$TEST_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Replaced file in sync directory${NC}"
else
    echo -e "${RED}Failed to replace file in sync directory${NC}"
    exit 1
fi

# Step 8: Check for chunks at different time intervals
echo -e "\n${YELLOW}Step 8: Checking for chunks at different time intervals...${NC}"

# Function to check for chunks
check_chunks() {
    local wait_time=$1
    echo -e "\n${CYAN}Checking for chunks after ${wait_time} seconds...${NC}"

    # Check if file still exists by name
    DB_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
    if [ -n "$DB_RESULT" ]; then
        echo -e "${GREEN}File found in database by name: $DB_RESULT${NC}"
        CURRENT_FILE_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
        CURRENT_HASH=$(echo "$DB_RESULT" | cut -d'|' -f2)

        echo -e "${CYAN}Current File ID: $CURRENT_FILE_ID (Original: $FILE_ID)${NC}"
        echo -e "${CYAN}Current Hash: $CURRENT_HASH${NC}"

        if [ "$CURRENT_HASH" = "$MODIFIED_HASH" ]; then
            echo -e "${GREEN}File hash has been updated to match the modified file - GOOD!${NC}"
        else
            echo -e "${RED}File hash does not match the modified file!${NC}"
            echo -e "Expected: $MODIFIED_HASH, Got: $CURRENT_HASH"
        fi

        # Check if the file ID has changed
        if [ "$CURRENT_FILE_ID" != "$FILE_ID" ]; then
            echo -e "${YELLOW}File ID has changed from $FILE_ID to $CURRENT_FILE_ID${NC}"
            echo -e "${YELLOW}This suggests the system is creating a new file record instead of updating the existing one${NC}"

            # Update the file ID for subsequent checks
            FILE_ID=$CURRENT_FILE_ID
        fi
    else
        echo -e "${RED}File not found in database by name!${NC}"

        # Check if the original file still exists by ID
        DB_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_hash FROM files_metadata WHERE file_id='$FILE_ID';")
        if [ -n "$DB_RESULT" ]; then
            echo -e "${GREEN}Original file still exists by ID: $DB_RESULT${NC}"
        else
            echo -e "${RED}Original file not found by ID either!${NC}"
        fi
    fi

    # Check for chunks using the current file ID
    CHUNKS_COUNT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")
    echo -e "${CYAN}Found $CHUNKS_COUNT chunks for file ID $FILE_ID${NC}"

    if [ "$CHUNKS_COUNT" -gt 0 ]; then
        echo -e "${GREEN}Chunks found after ${wait_time} seconds - GOOD!${NC}"

        # Get chunk fingerprints
        echo -e "${YELLOW}Chunk fingerprints:${NC}"
        CHUNK_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$FILE_ID';")
        echo -e "$CHUNK_FINGERPRINTS"

        # Check if fingerprints have changed
        if [ "$CHUNK_FINGERPRINTS" != "$ORIGINAL_FINGERPRINTS" ]; then
            echo -e "${GREEN}Chunk fingerprints have changed - GOOD!${NC}"
        else
            echo -e "${RED}Chunk fingerprints have not changed!${NC}"
        fi
    else
        echo -e "${YELLOW}No chunks found after ${wait_time} seconds${NC}"

        # Check for any chunks in the database
        TOTAL_CHUNKS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks;")
        echo -e "${CYAN}Total chunks in database: $TOTAL_CHUNKS${NC}"

        # List all file IDs in the database
        echo -e "${YELLOW}All file IDs in the database:${NC}"
        ALL_FILES=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata;")
        echo -e "$ALL_FILES"
    fi
}

# Check after 1 second
sleep 1
check_chunks 1

# Check after 5 seconds
sleep 4  # Already waited 1 second
check_chunks 5

# Check after 10 seconds
sleep 5  # Already waited 5 seconds
check_chunks 10

# Check after 30 seconds
sleep 20  # Already waited 10 seconds
check_chunks 30

# Step 9: Clean up
echo -e "\n${YELLOW}Step 9: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}File Modification Behavior Test Completed!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
