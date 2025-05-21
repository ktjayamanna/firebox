#!/bin/bash
#===================================================================================
# Firebox Client Test Content Deduplication
#===================================================================================
# Description: This script tests the content deduplication functionality:
# - File-level deduplication using SHA-256 hashes
# - Skipping unchanged files during sync operations
#
# The script follows these steps:
# 1. Create: Creates a test file with specific content
# 2. Upload: Copies the file to the sync directory
# 3. Verify: Confirms the file is processed and chunks are created
# 4. Duplicate: Creates a duplicate file with the same content but different name
# 5. Upload: Copies the duplicate file to the sync directory
# 6. Verify: Confirms deduplication is working by checking chunk reuse
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
CONTAINER_NAME="firebox-client-1"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_firebox}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/firebox.db}"
TEMP_DIR="/tmp/firebox_test_${TIMESTAMP}"
FILE_SIZE_KB=500  # Create a medium-sized file
WAIT_TIME=3  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox Content Deduplication Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Create a test file with specific content
echo -e "${YELLOW}Step 1: Creating a test file with specific content...${NC}"
ORIGINAL_FILE="${TEMP_DIR}/original_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1K count=$FILE_SIZE_KB | base64 > $ORIGINAL_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created original file: $ORIGINAL_FILE ($(du -h $ORIGINAL_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create original file${NC}"
    exit 1
fi

# Calculate file hash for later verification
FILE_HASH=$(sha256sum $ORIGINAL_FILE | awk '{print $1}')
echo -e "${CYAN}File SHA-256 hash: $FILE_HASH${NC}"

# Step 2: Copy the original file to the sync directory
echo -e "\n${YELLOW}Step 2: Copying the original file to the sync directory...${NC}"
ORIGINAL_FILENAME=$(basename $ORIGINAL_FILE)
docker cp $ORIGINAL_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied original file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy original file to sync directory${NC}"
    exit 1
fi

# Step 3: Wait for file to be processed
echo -e "\n${YELLOW}Step 3: Waiting for file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 4: Verify original file is in the database
echo -e "\n${YELLOW}Step 4: Verifying original file is in the database...${NC}"
ORIGINAL_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$ORIGINAL_FILENAME';")
if [ -n "$ORIGINAL_DB" ]; then
    echo -e "${GREEN}Original file found in database: $ORIGINAL_DB${NC}"
    ORIGINAL_ID=$(echo "$ORIGINAL_DB" | cut -d'|' -f1)
    DB_ORIGINAL_HASH=$(echo "$ORIGINAL_DB" | cut -d'|' -f4)
    echo -e "${CYAN}Original file ID: $ORIGINAL_ID${NC}"
    echo -e "${CYAN}Database file hash: $DB_ORIGINAL_HASH${NC}"
else
    echo -e "${RED}Original file not found in database${NC}"
    exit 1
fi

# Step 5: Get original chunk information
echo -e "\n${YELLOW}Step 5: Getting original chunk information...${NC}"
ORIGINAL_CHUNKS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$ORIGINAL_ID';")
if [ "$ORIGINAL_CHUNKS" -gt 0 ]; then
    echo -e "${GREEN}Found $ORIGINAL_CHUNKS chunks for original file${NC}"
    
    # Get original chunk fingerprints
    echo -e "${YELLOW}Original chunk fingerprints:${NC}"
    ORIGINAL_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$ORIGINAL_ID';")
    echo -e "$ORIGINAL_FINGERPRINTS"
else
    echo -e "${RED}No chunks found for original file${NC}"
    exit 1
fi

# Step 6: Create a duplicate file with the same content but different name
echo -e "\n${YELLOW}Step 6: Creating a duplicate file with the same content but different name...${NC}"
DUPLICATE_FILE="${TEMP_DIR}/duplicate_file_${TIMESTAMP}.txt"
cp $ORIGINAL_FILE $DUPLICATE_FILE
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created duplicate file: $DUPLICATE_FILE ($(du -h $DUPLICATE_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create duplicate file${NC}"
    exit 1
fi

# Verify duplicate file has the same hash
DUPLICATE_HASH=$(sha256sum $DUPLICATE_FILE | awk '{print $1}')
echo -e "${CYAN}Duplicate file SHA-256 hash: $DUPLICATE_HASH${NC}"
if [ "$DUPLICATE_HASH" = "$FILE_HASH" ]; then
    echo -e "${GREEN}Duplicate file has the same hash as the original - GOOD!${NC}"
else
    echo -e "${RED}Duplicate file has a different hash than the original!${NC}"
    exit 1
fi

# Step 7: Copy the duplicate file to the sync directory
echo -e "\n${YELLOW}Step 7: Copying the duplicate file to the sync directory...${NC}"
DUPLICATE_FILENAME=$(basename $DUPLICATE_FILE)
docker cp $DUPLICATE_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied duplicate file to sync directory${NC}"
else
    echo -e "${RED}Failed to copy duplicate file to sync directory${NC}"
    exit 1
fi

# Step 8: Wait for duplicate file to be processed
echo -e "\n${YELLOW}Step 8: Waiting for duplicate file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 9: Verify duplicate file is in the database
echo -e "\n${YELLOW}Step 9: Verifying duplicate file is in the database...${NC}"
DUPLICATE_DB=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$DUPLICATE_FILENAME';")
if [ -n "$DUPLICATE_DB" ]; then
    echo -e "${GREEN}Duplicate file found in database: $DUPLICATE_DB${NC}"
    DUPLICATE_ID=$(echo "$DUPLICATE_DB" | cut -d'|' -f1)
    DB_DUPLICATE_HASH=$(echo "$DUPLICATE_DB" | cut -d'|' -f4)
    echo -e "${CYAN}Duplicate file ID: $DUPLICATE_ID${NC}"
    echo -e "${CYAN}Database file hash: $DB_DUPLICATE_HASH${NC}"
    
    # Verify hash is the same as the original
    if [ "$DB_DUPLICATE_HASH" = "$DB_ORIGINAL_HASH" ]; then
        echo -e "${GREEN}Duplicate file has the same hash in the database - GOOD!${NC}"
    else
        echo -e "${RED}Duplicate file has a different hash in the database!${NC}"
        echo -e "Original: $DB_ORIGINAL_HASH"
        echo -e "Duplicate: $DB_DUPLICATE_HASH"
        exit 1
    fi
else
    echo -e "${RED}Duplicate file not found in database${NC}"
    exit 1
fi

# Step 10: Check if deduplication is working by comparing chunk fingerprints
echo -e "\n${YELLOW}Step 10: Checking if deduplication is working by comparing chunk fingerprints...${NC}"
DUPLICATE_CHUNKS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$DUPLICATE_ID';")
if [ "$DUPLICATE_CHUNKS" -gt 0 ]; then
    echo -e "${GREEN}Found $DUPLICATE_CHUNKS chunks for duplicate file${NC}"
    
    # Get duplicate chunk fingerprints
    echo -e "${YELLOW}Duplicate chunk fingerprints:${NC}"
    DUPLICATE_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$DUPLICATE_ID';")
    echo -e "$DUPLICATE_FINGERPRINTS"
    
    # Compare fingerprints
    # Note: The chunk IDs will be different, but the fingerprints should be the same
    ORIGINAL_FINGERPRINT_LIST=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT fingerprint FROM chunks WHERE file_id='$ORIGINAL_ID' ORDER BY fingerprint;")
    DUPLICATE_FINGERPRINT_LIST=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT fingerprint FROM chunks WHERE file_id='$DUPLICATE_ID' ORDER BY fingerprint;")
    
    if [ "$ORIGINAL_FINGERPRINT_LIST" = "$DUPLICATE_FINGERPRINT_LIST" ]; then
        echo -e "${GREEN}Chunk fingerprints match between original and duplicate files - GOOD!${NC}"
        echo -e "${GREEN}Content deduplication is working correctly!${NC}"
    else
        echo -e "${RED}Chunk fingerprints do not match between original and duplicate files!${NC}"
        echo -e "This suggests that content deduplication is not working correctly."
        exit 1
    fi
else
    echo -e "${RED}No chunks found for duplicate file${NC}"
    exit 1
fi

# Step 11: Clean up
echo -e "\n${YELLOW}Step 11: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Content Deduplication Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
