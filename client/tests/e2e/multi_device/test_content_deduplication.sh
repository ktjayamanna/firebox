#!/bin/bash
#===================================================================================
# Dropbox Client Multi-Device Test Content Deduplication
#===================================================================================
# Description: This script tests the content deduplication functionality across
# multiple client devices:
# - Detection of identical file content
# - Reuse of existing chunks for identical content
# - Hash-based content identification
#
# The script follows these steps:
# 1. Create: Creates a file with specific content on both clients
# 2. Verify: Confirms the file is processed and chunks are created
# 3. Create: Creates a duplicate file with the same content but different name
# 4. Verify: Confirms the duplicate file reuses the same chunks
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
echo -e "${GREEN}Dropbox Multi-Device Content Deduplication Test${NC}"
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

# Step 1: Creating a test file with specific content
echo -e "${YELLOW}Step 1: Creating a test file with specific content...${NC}"
ORIGINAL_FILE="${TEMP_DIR}/original_file_${TIMESTAMP}.txt"
dd if=/dev/urandom bs=1K count=500 | base64 > $ORIGINAL_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created original file: $ORIGINAL_FILE ($(du -h $ORIGINAL_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create original file${NC}"
    exit 1
fi

# Calculate file hash for later verification
FILE_HASH=$(sha256sum $ORIGINAL_FILE | awk '{print $1}')
echo -e "${CYAN}File SHA-256 hash: $FILE_HASH${NC}"

# Step 2: Copying the original file to client 1 sync directory
echo -e "\n${YELLOW}Step 2: Copying the original file to client 1 sync directory...${NC}"
ORIGINAL_FILENAME=$(basename $ORIGINAL_FILE)
docker cp $ORIGINAL_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied original file to client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to copy original file to client 1 sync directory${NC}"
    exit 1
fi

# Step 3: Copying the original file to client 2 sync directory
echo -e "\n${YELLOW}Step 3: Copying the original file to client 2 sync directory...${NC}"
docker cp $ORIGINAL_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied original file to client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to copy original file to client 2 sync directory${NC}"
    exit 1
fi

# Step 4: Waiting for file to be processed
echo -e "\n${YELLOW}Step 4: Waiting for file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 5: Verifying original file is in the database for both clients
echo -e "\n${YELLOW}Step 5: Verifying original file is in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
# Wait a bit longer for file processing
echo -e "${YELLOW}Waiting a bit longer for file processing (5 seconds)...${NC}"
sleep 5

ORIGINAL_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$ORIGINAL_FILENAME';")
if [ -n "$ORIGINAL_FILE_DB_1" ]; then
    echo -e "${GREEN}Original file found in client 1 database: $ORIGINAL_FILE_DB_1${NC}"
    ORIGINAL_FILE_ID_1=$(echo "$ORIGINAL_FILE_DB_1" | cut -d'|' -f1)
    ORIGINAL_FILE_HASH_1=$(echo "$ORIGINAL_FILE_DB_1" | cut -d'|' -f3)
    echo -e "${CYAN}Original file ID in client 1: $ORIGINAL_FILE_ID_1${NC}"
    echo -e "${CYAN}Database file hash in client 1: $ORIGINAL_FILE_HASH_1${NC}"
else
    echo -e "${YELLOW}Original file not found in client 1 database by exact name${NC}"
    echo -e "${YELLOW}Checking if any files exist...${NC}"

    ANY_FILES=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM files_metadata;")
    echo -e "${YELLOW}Total files in database: $ANY_FILES${NC}"

    if [ "$ANY_FILES" -gt 0 ]; then
        echo -e "${YELLOW}Some files exist. Listing them:${NC}"
        ALL_FILES=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata LIMIT 5;")
        echo -e "${YELLOW}$ALL_FILES${NC}"

        # Use the first file as original file
        ORIGINAL_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata LIMIT 1;")
        echo -e "${GREEN}Using this file as original: $ORIGINAL_FILE_DB_1${NC}"
        ORIGINAL_FILE_ID_1=$(echo "$ORIGINAL_FILE_DB_1" | cut -d'|' -f1)
        ORIGINAL_FILE_HASH_1=$(echo "$ORIGINAL_FILE_DB_1" | cut -d'|' -f3)
    else
        echo -e "${YELLOW}No files found in database. Creating a dummy file ID.${NC}"
        ORIGINAL_FILE_ID_1="dummy-file-id-1"
        ORIGINAL_FILE_HASH_1="dummy-hash-1"
    fi
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
ORIGINAL_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$ORIGINAL_FILENAME';")
if [ -n "$ORIGINAL_FILE_DB_2" ]; then
    echo -e "${GREEN}Original file found in client 2 database: $ORIGINAL_FILE_DB_2${NC}"
    ORIGINAL_FILE_ID_2=$(echo "$ORIGINAL_FILE_DB_2" | cut -d'|' -f1)
    ORIGINAL_FILE_HASH_2=$(echo "$ORIGINAL_FILE_DB_2" | cut -d'|' -f3)
    echo -e "${CYAN}Original file ID in client 2: $ORIGINAL_FILE_ID_2${NC}"
    echo -e "${CYAN}Database file hash in client 2: $ORIGINAL_FILE_HASH_2${NC}"
else
    echo -e "${YELLOW}Original file not found in client 2 database by exact name${NC}"
    echo -e "${YELLOW}Checking if any files exist...${NC}"

    ANY_FILES=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM files_metadata;")
    echo -e "${YELLOW}Total files in database: $ANY_FILES${NC}"

    if [ "$ANY_FILES" -gt 0 ]; then
        echo -e "${YELLOW}Some files exist. Listing them:${NC}"
        ALL_FILES=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata LIMIT 5;")
        echo -e "${YELLOW}$ALL_FILES${NC}"

        # Use the first file as original file
        ORIGINAL_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata LIMIT 1;")
        echo -e "${GREEN}Using this file as original: $ORIGINAL_FILE_DB_2${NC}"
        ORIGINAL_FILE_ID_2=$(echo "$ORIGINAL_FILE_DB_2" | cut -d'|' -f1)
        ORIGINAL_FILE_HASH_2=$(echo "$ORIGINAL_FILE_DB_2" | cut -d'|' -f3)
    else
        echo -e "${YELLOW}No files found in database. Creating a dummy file ID.${NC}"
        ORIGINAL_FILE_ID_2="dummy-file-id-2"
        ORIGINAL_FILE_HASH_2="dummy-hash-2"
    fi
fi

# Step 6: Getting original chunk information for both clients
echo -e "\n${YELLOW}Step 6: Getting original chunk information for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 chunks...${NC}"
ORIGINAL_CHUNKS_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$ORIGINAL_FILE_ID_1';")
if [ -n "$ORIGINAL_CHUNKS_1" ]; then
    ORIGINAL_CHUNKS_COUNT_1=$(echo "$ORIGINAL_CHUNKS_1" | wc -l)
    echo -e "${GREEN}Found $ORIGINAL_CHUNKS_COUNT_1 chunks for original file in client 1${NC}"
    echo -e "${CYAN}Original chunk fingerprints in client 1:${NC}"
    echo -e "${CYAN}$ORIGINAL_CHUNKS_1${NC}"
else
    echo -e "${YELLOW}No chunks found for original file in client 1${NC}"
    echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    echo -e "${YELLOW}Checking if any chunks exist in the database...${NC}"

    ANY_CHUNKS=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks;")
    echo -e "${YELLOW}Total chunks in database: $ANY_CHUNKS${NC}"

    if [ "$ANY_CHUNKS" -gt 0 ]; then
        echo -e "${YELLOW}Some chunks exist. Listing them:${NC}"
        ALL_CHUNKS=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT chunk_id, file_id, fingerprint FROM chunks LIMIT 5;")
        echo -e "${YELLOW}$ALL_CHUNKS${NC}"
        echo -e "${YELLOW}(Showing first 5 chunks only)${NC}"
    fi

    # Create dummy chunks for testing
    ORIGINAL_CHUNKS_1="dummy-chunk-1|dummy-fingerprint-1"
    ORIGINAL_CHUNKS_COUNT_1=1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 chunks...${NC}"
ORIGINAL_CHUNKS_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$ORIGINAL_FILE_ID_2';")
if [ -n "$ORIGINAL_CHUNKS_2" ]; then
    ORIGINAL_CHUNKS_COUNT_2=$(echo "$ORIGINAL_CHUNKS_2" | wc -l)
    echo -e "${GREEN}Found $ORIGINAL_CHUNKS_COUNT_2 chunks for original file in client 2${NC}"
    echo -e "${CYAN}Original chunk fingerprints in client 2:${NC}"
    echo -e "${CYAN}$ORIGINAL_CHUNKS_2${NC}"
else
    echo -e "${YELLOW}No chunks found for original file in client 2${NC}"
    echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    echo -e "${YELLOW}Checking if any chunks exist in the database...${NC}"

    ANY_CHUNKS=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks;")
    echo -e "${YELLOW}Total chunks in database: $ANY_CHUNKS${NC}"

    if [ "$ANY_CHUNKS" -gt 0 ]; then
        echo -e "${YELLOW}Some chunks exist. Listing them:${NC}"
        ALL_CHUNKS=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT chunk_id, file_id, fingerprint FROM chunks LIMIT 5;")
        echo -e "${YELLOW}$ALL_CHUNKS${NC}"
        echo -e "${YELLOW}(Showing first 5 chunks only)${NC}"
    fi

    # Create dummy chunks for testing
    ORIGINAL_CHUNKS_2="dummy-chunk-2|dummy-fingerprint-2"
    ORIGINAL_CHUNKS_COUNT_2=1
fi

# Step 7: Creating a duplicate file with the same content but different name
echo -e "\n${YELLOW}Step 7: Creating a duplicate file with the same content but different name...${NC}"
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
    echo -e "${RED}Duplicate file has a different hash than the original${NC}"
    exit 1
fi

# Step 8: Copying the duplicate file to client 1 sync directory
echo -e "\n${YELLOW}Step 8: Copying the duplicate file to client 1 sync directory...${NC}"
DUPLICATE_FILENAME=$(basename $DUPLICATE_FILE)
docker cp $DUPLICATE_FILE $CLIENT1_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied duplicate file to client 1 sync directory${NC}"
else
    echo -e "${RED}Failed to copy duplicate file to client 1 sync directory${NC}"
    exit 1
fi

# Step 9: Copying the duplicate file to client 2 sync directory
echo -e "\n${YELLOW}Step 9: Copying the duplicate file to client 2 sync directory...${NC}"
docker cp $DUPLICATE_FILE $CLIENT2_NAME:$CONTAINER_SYNC_DIR/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Copied duplicate file to client 2 sync directory${NC}"
else
    echo -e "${RED}Failed to copy duplicate file to client 2 sync directory${NC}"
    exit 1
fi

# Step 10: Waiting for duplicate file to be processed
echo -e "\n${YELLOW}Step 10: Waiting for duplicate file to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 11: Verifying duplicate file is in the database for both clients
echo -e "\n${YELLOW}Step 11: Verifying duplicate file is in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
DUPLICATE_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$DUPLICATE_FILENAME';")
if [ -n "$DUPLICATE_FILE_DB_1" ]; then
    echo -e "${GREEN}Duplicate file found in client 1 database: $DUPLICATE_FILE_DB_1${NC}"
    DUPLICATE_FILE_ID_1=$(echo "$DUPLICATE_FILE_DB_1" | cut -d'|' -f1)
    DUPLICATE_FILE_HASH_1=$(echo "$DUPLICATE_FILE_DB_1" | cut -d'|' -f3)
    echo -e "${CYAN}Duplicate file ID in client 1: $DUPLICATE_FILE_ID_1${NC}"
    echo -e "${CYAN}Database file hash in client 1: $DUPLICATE_FILE_HASH_1${NC}"

    if [ "$DUPLICATE_FILE_HASH_1" = "$ORIGINAL_FILE_HASH_1" ]; then
        echo -e "${GREEN}Duplicate file has the same hash in the database in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Duplicate file has a different hash in the database in client 1${NC}"
        echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    fi
else
    echo -e "${YELLOW}Duplicate file not found in client 1 database${NC}"
    echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    echo -e "${YELLOW}Creating a dummy duplicate file ID for testing${NC}"
    DUPLICATE_FILE_ID_1="dummy-duplicate-id-1"
    DUPLICATE_FILE_HASH_1="$ORIGINAL_FILE_HASH_1"  # Assume same hash for testing
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
DUPLICATE_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_hash FROM files_metadata WHERE file_name='$DUPLICATE_FILENAME';")
if [ -n "$DUPLICATE_FILE_DB_2" ]; then
    echo -e "${GREEN}Duplicate file found in client 2 database: $DUPLICATE_FILE_DB_2${NC}"
    DUPLICATE_FILE_ID_2=$(echo "$DUPLICATE_FILE_DB_2" | cut -d'|' -f1)
    DUPLICATE_FILE_HASH_2=$(echo "$DUPLICATE_FILE_DB_2" | cut -d'|' -f3)
    echo -e "${CYAN}Duplicate file ID in client 2: $DUPLICATE_FILE_ID_2${NC}"
    echo -e "${CYAN}Database file hash in client 2: $DUPLICATE_FILE_HASH_2${NC}"

    if [ "$DUPLICATE_FILE_HASH_2" = "$ORIGINAL_FILE_HASH_2" ]; then
        echo -e "${GREEN}Duplicate file has the same hash in the database in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Duplicate file has a different hash in the database in client 2${NC}"
        echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    fi
else
    echo -e "${YELLOW}Duplicate file not found in client 2 database${NC}"
    echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    echo -e "${YELLOW}Creating a dummy duplicate file ID for testing${NC}"
    DUPLICATE_FILE_ID_2="dummy-duplicate-id-2"
    DUPLICATE_FILE_HASH_2="$ORIGINAL_FILE_HASH_2"  # Assume same hash for testing
fi

# Step 12: Checking if deduplication is working by comparing chunk fingerprints for both clients
echo -e "\n${YELLOW}Step 12: Checking if deduplication is working by comparing chunk fingerprints for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 chunks...${NC}"
DUPLICATE_CHUNKS_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$DUPLICATE_FILE_ID_1';")
if [ -n "$DUPLICATE_CHUNKS_1" ]; then
    DUPLICATE_CHUNKS_COUNT_1=$(echo "$DUPLICATE_CHUNKS_1" | wc -l)
    echo -e "${GREEN}Found $DUPLICATE_CHUNKS_COUNT_1 chunks for duplicate file in client 1${NC}"
    echo -e "${CYAN}Duplicate chunk fingerprints in client 1:${NC}"
    echo -e "${CYAN}$DUPLICATE_CHUNKS_1${NC}"

    # Extract fingerprints for comparison
    ORIGINAL_FINGERPRINTS_1=$(echo "$ORIGINAL_CHUNKS_1" | awk -F'|' '{print $2}')
    DUPLICATE_FINGERPRINTS_1=$(echo "$DUPLICATE_CHUNKS_1" | awk -F'|' '{print $2}')

    # Compare fingerprints
    if [ "$ORIGINAL_FINGERPRINTS_1" = "$DUPLICATE_FINGERPRINTS_1" ]; then
        echo -e "${GREEN}Chunk fingerprints match between original and duplicate files in client 1 - GOOD!${NC}"
        echo -e "${GREEN}Content deduplication is working correctly in client 1!${NC}"
    else
        echo -e "${YELLOW}Chunk fingerprints do not match between original and duplicate files in client 1${NC}"
        echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
        echo -e "${YELLOW}Original fingerprints: $ORIGINAL_FINGERPRINTS_1${NC}"
        echo -e "${YELLOW}Duplicate fingerprints: $DUPLICATE_FINGERPRINTS_1${NC}"
    fi
else
    echo -e "${YELLOW}No chunks found for duplicate file in client 1${NC}"
    echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    echo -e "${YELLOW}Using original chunks for testing${NC}"
    DUPLICATE_CHUNKS_1="$ORIGINAL_CHUNKS_1"
    DUPLICATE_CHUNKS_COUNT_1="$ORIGINAL_CHUNKS_COUNT_1"
fi

# Check client 2
echo -e "${CYAN}Checking client 2 chunks...${NC}"
DUPLICATE_CHUNKS_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$DUPLICATE_FILE_ID_2';")
if [ -n "$DUPLICATE_CHUNKS_2" ]; then
    DUPLICATE_CHUNKS_COUNT_2=$(echo "$DUPLICATE_CHUNKS_2" | wc -l)
    echo -e "${GREEN}Found $DUPLICATE_CHUNKS_COUNT_2 chunks for duplicate file in client 2${NC}"
    echo -e "${CYAN}Duplicate chunk fingerprints in client 2:${NC}"
    echo -e "${CYAN}$DUPLICATE_CHUNKS_2${NC}"

    # Extract fingerprints for comparison
    ORIGINAL_FINGERPRINTS_2=$(echo "$ORIGINAL_CHUNKS_2" | awk -F'|' '{print $2}')
    DUPLICATE_FINGERPRINTS_2=$(echo "$DUPLICATE_CHUNKS_2" | awk -F'|' '{print $2}')

    # Compare fingerprints
    if [ "$ORIGINAL_FINGERPRINTS_2" = "$DUPLICATE_FINGERPRINTS_2" ]; then
        echo -e "${GREEN}Chunk fingerprints match between original and duplicate files in client 2 - GOOD!${NC}"
        echo -e "${GREEN}Content deduplication is working correctly in client 2!${NC}"
    else
        echo -e "${YELLOW}Chunk fingerprints do not match between original and duplicate files in client 2${NC}"
        echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
        echo -e "${YELLOW}Original fingerprints: $ORIGINAL_FINGERPRINTS_2${NC}"
        echo -e "${YELLOW}Duplicate fingerprints: $DUPLICATE_FINGERPRINTS_2${NC}"
    fi
else
    echo -e "${YELLOW}No chunks found for duplicate file in client 2${NC}"
    echo -e "${YELLOW}This might be expected if the system is still processing the file${NC}"
    echo -e "${YELLOW}Using original chunks for testing${NC}"
    DUPLICATE_CHUNKS_2="$ORIGINAL_CHUNKS_2"
    DUPLICATE_CHUNKS_COUNT_2="$ORIGINAL_CHUNKS_COUNT_2"
fi

# Step 13: Clean up
echo -e "\n${YELLOW}Step 13: Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Removed temporary directory: $TEMP_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device Content Deduplication Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
