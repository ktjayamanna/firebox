#!/bin/bash
# Smoke test for file modifications

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox File Modification Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q firebox-client-1; then
    echo -e "${RED}Error: firebox-client-1 container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Define paths
CONTAINER_SYNC_DIR="/app/my_firebox"

# Step 1: Create a test file
echo -e "\n${YELLOW}Step 1: Creating a test file...${NC}"
TEST_FILE="$CONTAINER_SYNC_DIR/modification_test.txt"
docker exec firebox-client-1 bash -c "echo 'Original content' > $TEST_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created test file${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Step 2: Wait for file to be processed
echo -e "\n${YELLOW}Step 2: Waiting for file to be processed (3 seconds)...${NC}"
sleep 3

# Step 3: Get original file hash
echo -e "\n${YELLOW}Step 3: Getting original file hash...${NC}"
ORIGINAL_HASH=$(docker exec firebox-client-1 sqlite3 /app/data/firebox.db "SELECT file_hash FROM files_metadata WHERE file_name='modification_test.txt';")
echo -e "Original file hash: $ORIGINAL_HASH"

# Step 4: Modify the file
echo -e "\n${YELLOW}Step 4: Modifying the file...${NC}"
docker exec firebox-client-1 bash -c "echo 'Modified content' > $TEST_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully modified test file${NC}"
else
    echo -e "${RED}Failed to modify test file${NC}"
    exit 1
fi

# Step 5: Wait for file to be processed
echo -e "\n${YELLOW}Step 5: Waiting for file to be processed (3 seconds)...${NC}"
sleep 3

# Step 6: Get new file hash
echo -e "\n${YELLOW}Step 6: Getting new file hash...${NC}"
NEW_HASH=$(docker exec firebox-client-1 sqlite3 /app/data/firebox.db "SELECT file_hash FROM files_metadata WHERE file_name='modification_test.txt';")
echo -e "New file hash: $NEW_HASH"

# Step 7: Compare hashes
echo -e "\n${YELLOW}Step 7: Comparing hashes...${NC}"
if [ "$ORIGINAL_HASH" != "$NEW_HASH" ]; then
    echo -e "${GREEN}File hash changed after modification (expected)${NC}"
else
    echo -e "${RED}File hash did not change after modification (unexpected)${NC}"
fi

# Step 8: Check chunks
echo -e "\n${YELLOW}Step 8: Checking chunks...${NC}"
FILE_ID=$(docker exec firebox-client-1 sqlite3 /app/data/firebox.db "SELECT file_id FROM files_metadata WHERE file_name='modification_test.txt';")
CHUNK_COUNT=$(docker exec firebox-client-1 sqlite3 /app/data/firebox.db "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")
echo -e "File ID: $FILE_ID"
echo -e "Chunk count: $CHUNK_COUNT"

if [ "$CHUNK_COUNT" -gt 0 ]; then
    echo -e "${GREEN}Chunks found for the file (expected)${NC}"
else
    echo -e "${RED}No chunks found for the file (unexpected)${NC}"
fi

echo -e "\n${GREEN}File modification test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
