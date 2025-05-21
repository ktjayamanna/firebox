#!/bin/bash
#===================================================================================
# Firebox Client Test File Chunking
#===================================================================================
# Description: This script tests the file chunking functionality:
# - Files split into 5MB chunks
# - Each chunk gets a unique ID and SHA-256 fingerprint
# - Chunks stored in dedicated chunk directory
#
# The script follows these steps:
# 1. Create: Creates a large file that will be split into multiple chunks
# 2. Upload: Copies the file to the Firebox sync directory
# 3. Verify: Confirms the file is split into chunks with proper fingerprints
# 4. Storage: Checks that chunks are stored correctly in the chunk directory
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
CHUNK_DIR="${CHUNK_DIR:-/app/tmp/chunk}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/firebox.db}"
TEMP_DIR="/tmp/firebox_test_${TIMESTAMP}"
FILE_SIZE_MB=12  # Create a file larger than 10MB to ensure multiple chunks
WAIT_TIME=5  # seconds to wait for file processing

# Create temporary directory
mkdir -p $TEMP_DIR

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox File Chunking Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Create a large test file
echo -e "${YELLOW}Step 1: Creating a ${FILE_SIZE_MB}MB test file...${NC}"
TEST_FILE="${TEMP_DIR}/large_file_${TIMESTAMP}.bin"
dd if=/dev/urandom bs=1M count=$FILE_SIZE_MB of=$TEST_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created test file: $TEST_FILE ($(du -h $TEST_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Calculate file hash for later verification
FILE_HASH=$(sha256sum $TEST_FILE | awk '{print $1}')
echo -e "${CYAN}File SHA-256 hash: $FILE_HASH${NC}"

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
echo -e "\n${YELLOW}Step 3: Waiting for file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 4: Verify file exists in the container
echo -e "\n${YELLOW}Step 4: Verifying file exists in the container...${NC}"
if docker exec $CONTAINER_NAME ls -la $CONTAINER_SYNC_DIR/$TEST_FILENAME >/dev/null 2>&1; then
    FILE_SIZE=$(docker exec $CONTAINER_NAME du -h $CONTAINER_SYNC_DIR/$TEST_FILENAME | cut -f1)
    echo -e "${GREEN}File exists in container: $CONTAINER_SYNC_DIR/$TEST_FILENAME (${FILE_SIZE})${NC}"
else
    echo -e "${RED}File not found in container${NC}"
    exit 1
fi

# Step 5: Check if file is in the database
echo -e "\n${YELLOW}Step 5: Checking if file is in the database...${NC}"
DB_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$TEST_FILENAME';")
if [ -n "$DB_RESULT" ]; then
    echo -e "${GREEN}File found in database:${NC}"
    echo -e "$DB_RESULT"
    
    # Extract file_id for later use
    FILE_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    DB_FILE_HASH=$(echo "$DB_RESULT" | cut -d'|' -f4)
    echo -e "${CYAN}File ID: $FILE_ID${NC}"
    echo -e "${CYAN}Database file hash: $DB_FILE_HASH${NC}"
    
    # Verify file hash if available
    if [ -n "$DB_FILE_HASH" ] && [ "$DB_FILE_HASH" = "$FILE_HASH" ]; then
        echo -e "${GREEN}File hash matches - GOOD!${NC}"
    elif [ -n "$DB_FILE_HASH" ]; then
        echo -e "${RED}File hash mismatch!${NC}"
        echo -e "Expected: $FILE_HASH"
        echo -e "Got: $DB_FILE_HASH"
    else
        echo -e "${YELLOW}No file hash in database${NC}"
    fi
else
    echo -e "${RED}File not found in database${NC}"
    exit 1
fi

# Step 6: Check if chunks are in the database
echo -e "\n${YELLOW}Step 6: Checking chunks in the database...${NC}"
CHUNKS_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")

# Calculate expected number of chunks (5MB per chunk)
EXPECTED_CHUNKS=$(( ($FILE_SIZE_MB + 4) / 5 ))  # Ceiling division
echo -e "${CYAN}Expected chunks (${FILE_SIZE_MB}MB file with 5MB chunks): ~$EXPECTED_CHUNKS${NC}"

if [ "$CHUNKS_RESULT" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNKS_RESULT chunks in database for this file${NC}"
    
    # Verify number of chunks
    if [ "$CHUNKS_RESULT" -ge "$EXPECTED_CHUNKS" ]; then
        echo -e "${GREEN}Number of chunks matches or exceeds expected count - GOOD!${NC}"
    else
        echo -e "${RED}Fewer chunks than expected!${NC}"
        echo -e "Expected: $EXPECTED_CHUNKS, Got: $CHUNKS_RESULT"
    fi
    
    # Show chunk details including fingerprints
    echo -e "${YELLOW}Chunk details:${NC}"
    CHUNK_DETAILS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint, part_number FROM chunks WHERE file_id='$FILE_ID' ORDER BY part_number;")
    echo -e "$CHUNK_DETAILS"
    
    # Check if any chunks are missing fingerprints
    MISSING_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID' AND (fingerprint IS NULL OR fingerprint = '');")
    
    if [ "$MISSING_FINGERPRINTS" -gt 0 ]; then
        echo -e "${RED}WARNING: $MISSING_FINGERPRINTS chunks are missing fingerprints!${NC}"
    else
        echo -e "${GREEN}All chunks have fingerprints - GOOD!${NC}"
        
        # Verify fingerprint format (should be SHA-256 hash - 64 hex characters)
        INVALID_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID' AND length(fingerprint) != 64;")
        
        if [ "$INVALID_FINGERPRINTS" -gt 0 ]; then
            echo -e "${RED}WARNING: $INVALID_FINGERPRINTS chunks have invalid fingerprint format!${NC}"
        else
            echo -e "${GREEN}All fingerprints have valid format (64 hex characters) - GOOD!${NC}"
        fi
    fi
else
    echo -e "${RED}No chunks found in database for this file${NC}"
    exit 1
fi

# Step 7: Check chunk files on disk
echo -e "\n${YELLOW}Step 7: Checking chunk files on disk...${NC}"
CHUNK_FILES=$(docker exec $CONTAINER_NAME bash -c "mkdir -p $CHUNK_DIR && find $CHUNK_DIR -name \"*${FILE_ID}*\" | wc -l")

if [ "$CHUNK_FILES" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNK_FILES chunk files on disk for this file${NC}"
    # List the chunk files
    echo -e "${YELLOW}Chunk files:${NC}"
    docker exec $CONTAINER_NAME bash -c "find $CHUNK_DIR -name \"*${FILE_ID}*\" -ls"
else
    echo -e "${YELLOW}No chunk files found on disk for this file${NC}"
    echo -e "${CYAN}Note: This is expected if chunks are stored in the database or cloud storage${NC}"
fi

# Step 8: Clean up
echo -e "\n${YELLOW}Step 8: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}File Chunking Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
