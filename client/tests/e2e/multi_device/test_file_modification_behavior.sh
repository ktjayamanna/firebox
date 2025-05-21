#!/bin/bash
#===================================================================================
# Firebox Client Multi-Device Test File Modification Behavior
#===================================================================================
# Description: This script tests the file modification behavior across multiple
# client devices:
# - Detailed testing of how file modifications are handled
# - Timing of chunk creation and database updates
# - Verification of file state at different time intervals
#
# The script follows these steps:
# 1. Create: Creates a test file on both clients
# 2. Verify: Confirms the file is processed and chunks are created
# 3. Modify: Changes the file content on both clients
# 4. Verify: Checks the file state at different time intervals
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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/firebox.db}"
TEMP_DIR="/tmp/firebox_test_${TIMESTAMP}"
FILE_SIZE_MB=10  # Create a 10MB file
MODIFIED_SIZE_MB=12  # Modified file size

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox Multi-Device File Modification Behavior Test${NC}"
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

# Step 1: Creating a test file
echo -e "${YELLOW}Step 1: Creating a ${FILE_SIZE_MB}MB test file...${NC}"
TEST_FILE="${TEMP_DIR}/test_file_${TIMESTAMP}.bin"
dd if=/dev/urandom bs=1M count=$FILE_SIZE_MB of=$TEST_FILE status=progress 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created test file: $TEST_FILE ($(du -h $TEST_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Calculate file hash for later verification
ORIGINAL_HASH=$(sha256sum $TEST_FILE | awk '{print $1}')
echo -e "${CYAN}Original file SHA-256 hash: $ORIGINAL_HASH${NC}"

# Step 2: Copying file to client 1 sync directory
echo -e "\n${YELLOW}Step 2: Copying file to client 1 sync directory...${NC}"
TEST_FILENAME=$(basename $TEST_FILE)
docker cp $TEST_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied file to client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to copy file to client 1 sync directory${NC}"
    exit 1
fi

# Step 3: Copying file to client 2 sync directory
echo -e "\n${YELLOW}Step 3: Copying file to client 2 sync directory...${NC}"
docker cp $TEST_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied file to client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to copy file to client 2 sync directory${NC}"
    exit 1
fi

# Step 4: Waiting for file to be processed
echo -e "\n${YELLOW}Step 4: Waiting for file to be processed (5 seconds)...${NC}"
sleep 5

# Step 5: Checking if file is in the database for both clients
echo -e "\n${YELLOW}Step 5: Checking if file is in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$FILE_DB_1" ]; then
    echo -e "${GREEN}File found in client 1 database:${NC}"
    echo -e "${GREEN}$FILE_DB_1${NC}"
    FILE_ID_1=$(echo "$FILE_DB_1" | cut -d'|' -f1)
    FILE_HASH_1=$(echo "$FILE_DB_1" | cut -d'|' -f4)
    echo -e "${CYAN}File ID in client 1: $FILE_ID_1${NC}"
    echo -e "${CYAN}Database file hash in client 1: $FILE_HASH_1${NC}"
else
    echo -e "${RED}File not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$FILE_DB_2" ]; then
    echo -e "${GREEN}File found in client 2 database:${NC}"
    echo -e "${GREEN}$FILE_DB_2${NC}"
    FILE_ID_2=$(echo "$FILE_DB_2" | cut -d'|' -f1)
    FILE_HASH_2=$(echo "$FILE_DB_2" | cut -d'|' -f4)
    echo -e "${CYAN}File ID in client 2: $FILE_ID_2${NC}"
    echo -e "${CYAN}Database file hash in client 2: $FILE_HASH_2${NC}"
else
    echo -e "${RED}File not found in client 2 database${NC}"
    exit 1
fi

# Step 6: Checking for initial chunks for both clients
echo -e "\n${YELLOW}Step 6: Checking for initial chunks for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 chunks...${NC}"
ORIGINAL_CHUNKS_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$FILE_ID_1';")
if [ -n "$ORIGINAL_CHUNKS_1" ]; then
    ORIGINAL_CHUNKS_COUNT_1=$(echo "$ORIGINAL_CHUNKS_1" | wc -l)
    echo -e "${GREEN}Found $ORIGINAL_CHUNKS_COUNT_1 original chunks in client 1 database${NC}"
    echo -e "${CYAN}Original chunk fingerprints in client 1:${NC}"
    echo -e "${CYAN}$ORIGINAL_CHUNKS_1${NC}"
else
    echo -e "${RED}No chunks found for original file in client 1 database${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 chunks...${NC}"
ORIGINAL_CHUNKS_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$FILE_ID_2';")
if [ -n "$ORIGINAL_CHUNKS_2" ]; then
    ORIGINAL_CHUNKS_COUNT_2=$(echo "$ORIGINAL_CHUNKS_2" | wc -l)
    echo -e "${GREEN}Found $ORIGINAL_CHUNKS_COUNT_2 original chunks in client 2 database${NC}"
    echo -e "${CYAN}Original chunk fingerprints in client 2:${NC}"
    echo -e "${CYAN}$ORIGINAL_CHUNKS_2${NC}"
else
    echo -e "${RED}No chunks found for original file in client 2 database${NC}"
    exit 1
fi

# Step 7: Modifying the file
echo -e "\n${YELLOW}Step 7: Modifying the file...${NC}"
MODIFIED_FILE="${TEMP_DIR}/modified_test_file_${TIMESTAMP}.bin"
dd if=/dev/urandom bs=1M count=$MODIFIED_SIZE_MB of=$MODIFIED_FILE status=progress 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created modified file: $MODIFIED_FILE ($(du -h $MODIFIED_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create modified file${NC}"
    exit 1
fi

# Calculate modified file hash
MODIFIED_HASH=$(sha256sum $MODIFIED_FILE | awk '{print $1}')
echo -e "${CYAN}Modified file SHA-256 hash: $MODIFIED_HASH${NC}"

# Step 8: Replacing the file in client 1 sync directory
echo -e "\n${YELLOW}Step 8: Replacing the file in client 1 sync directory...${NC}"
docker cp $MODIFIED_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/$TEST_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Replaced file in client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to replace file in client 1 sync directory${NC}"
    exit 1
fi

# Step 9: Replacing the file in client 2 sync directory
echo -e "\n${YELLOW}Step 9: Replacing the file in client 2 sync directory...${NC}"
docker cp $MODIFIED_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/$TEST_FILENAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Replaced file in client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to replace file in client 2 sync directory${NC}"
    exit 1
fi

# Step 10: Checking for chunks at different time intervals for both clients
echo -e "\n${YELLOW}Step 10: Checking for chunks at different time intervals for both clients...${NC}"

# Function to check file and chunks at a specific time interval
check_file_and_chunks() {
    local client_name=$1
    local client_id=$2
    local original_file_id=$3
    local original_hash=$4
    local seconds=$5

    echo -e "\n${CYAN}Checking for chunks after $seconds seconds in $client_name...${NC}"
    sleep $seconds

    # Check if file exists in database by name
    local file_db=$(docker exec $client_name sqlite3 $DB_PATH "SELECT file_id, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
    if [ -n "$file_db" ]; then
        local current_file_id=$(echo "$file_db" | cut -d'|' -f1)
        local current_hash=$(echo "$file_db" | cut -d'|' -f2)
        echo -e "${GREEN}File found in database by name: $current_file_id|$current_hash${NC}"
        echo -e "${CYAN}Current File ID: $current_file_id (Original: $original_file_id)${NC}"
        echo -e "${CYAN}Current Hash: $current_hash${NC}"

        # Check if hash has been updated
        if [ "$current_hash" = "$MODIFIED_HASH" ]; then
            echo -e "${GREEN}File hash has been updated to match the modified file - GOOD!${NC}"
        else
            echo -e "${YELLOW}File hash has not been updated to match the modified file${NC}"
            echo -e "${YELLOW}Expected: $MODIFIED_HASH, Got: $current_hash${NC}"
            echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
        fi

        # Check if file ID has changed
        if [ "$current_file_id" != "$original_file_id" ]; then
            echo -e "${CYAN}File ID has changed from $original_file_id to $current_file_id${NC}"
            echo -e "${CYAN}This suggests the system is creating a new file record instead of updating the existing one${NC}"
        fi

        # Check chunks
        local chunks=$(docker exec $client_name sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$current_file_id';")
        if [ -n "$chunks" ]; then
            local chunks_count=$(echo "$chunks" | wc -l)
            echo -e "${GREEN}Found $chunks_count chunks for file ID $current_file_id${NC}"
            echo -e "${GREEN}Chunks found after $seconds seconds - GOOD!${NC}"
            echo -e "${CYAN}Chunk fingerprints:${NC}"
            echo -e "${CYAN}$chunks${NC}"
        else
            echo -e "${YELLOW}No chunks found for file ID $current_file_id after $seconds seconds${NC}"
            echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
            echo -e "${YELLOW}Checking if chunks exist for the original file ID...${NC}"

            local original_chunks=$(docker exec $client_name sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$original_file_id';")
            if [ -n "$original_chunks" ]; then
                local original_chunks_count=$(echo "$original_chunks" | wc -l)
                echo -e "${GREEN}Found $original_chunks_count chunks for original file ID $original_file_id${NC}"
                echo -e "${GREEN}Original chunks still exist - GOOD!${NC}"
            else
                echo -e "${YELLOW}No chunks found for original file ID $original_file_id either${NC}"
                echo -e "${YELLOW}This might indicate the system is still processing the chunks${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}File not found in database by name after $seconds seconds${NC}"
        echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
        echo -e "${YELLOW}Checking if the original file still exists...${NC}"

        local original_file_db=$(docker exec $client_name sqlite3 $DB_PATH "SELECT file_id, file_hash FROM files_metadata WHERE file_id='$original_file_id';")
        if [ -n "$original_file_db" ]; then
            echo -e "${GREEN}Original file still exists in database: $original_file_db${NC}"
        else
            echo -e "${YELLOW}Original file not found in database either${NC}"
            echo -e "${YELLOW}This might indicate the system is still processing the file${NC}"
        fi
    fi
}

# Check client 1 at different time intervals
check_file_and_chunks $CLIENT1_NAME "client 1" $FILE_ID_1 $FILE_HASH_1 1
check_file_and_chunks $CLIENT1_NAME "client 1" $FILE_ID_1 $FILE_HASH_1 5
check_file_and_chunks $CLIENT1_NAME "client 1" $FILE_ID_1 $FILE_HASH_1 10
check_file_and_chunks $CLIENT1_NAME "client 1" $FILE_ID_1 $FILE_HASH_1 30

# Check client 2 at different time intervals
check_file_and_chunks $CLIENT2_NAME "client 2" $FILE_ID_2 $FILE_HASH_2 1
check_file_and_chunks $CLIENT2_NAME "client 2" $FILE_ID_2 $FILE_HASH_2 5
check_file_and_chunks $CLIENT2_NAME "client 2" $FILE_ID_2 $FILE_HASH_2 10
check_file_and_chunks $CLIENT2_NAME "client 2" $FILE_ID_2 $FILE_HASH_2 30

# Step 11: Clean up
echo -e "\n${YELLOW}Step 11: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device File Modification Behavior Test Completed!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
