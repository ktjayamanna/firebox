#!/bin/bash
#===================================================================================
# Dropbox Client Test File Upload Script
#===================================================================================
# Description: This script creates a randomly generated text file and moves it to
# the Dropbox sync folder, then confirms the upload by listing the files.
#
# Usage: ./client/scripts/bash/test_file_upload.sh [file_size_kb]
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
CONTAINER_NAME="dropbox-client"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_dropbox}"
FILE_SIZE_KB=${1:-100}  # Default to 100KB if not specified
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILE_NAME="test_file_${TIMESTAMP}.txt"
TEMP_FILE="/tmp/${FILE_NAME}"

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Test File Upload${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Generate a random text file
echo -e "${YELLOW}Step 1: Generating a ${FILE_SIZE_KB}KB random text file...${NC}"
dd if=/dev/urandom bs=1K count=$FILE_SIZE_KB | base64 > $TEMP_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created random file: $TEMP_FILE ($(du -h $TEMP_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create random file${NC}"
    exit 1
fi

# Step 2: Copy the file to the container's sync directory
echo -e "\n${YELLOW}Step 2: Copying file to container's sync directory...${NC}"
docker cp $TEMP_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/$FILE_NAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully copied file to $CONTAINER_NAME:$CONTAINER_SYNC_DIR/$FILE_NAME${NC}"
else
    echo -e "${RED}Failed to copy file to container${NC}"
    exit 1
fi

# Step 3: Verify the file exists in the container
echo -e "\n${YELLOW}Step 3: Verifying file exists in container...${NC}"
if docker exec $CONTAINER_NAME ls -la $CONTAINER_SYNC_DIR/$FILE_NAME >/dev/null 2>&1; then
    FILE_SIZE=$(docker exec $CONTAINER_NAME du -h $CONTAINER_SYNC_DIR/$FILE_NAME | cut -f1)
    echo -e "${GREEN}File exists in container: $CONTAINER_SYNC_DIR/$FILE_NAME (${FILE_SIZE})${NC}"
else
    echo -e "${RED}File not found in container${NC}"
    exit 1
fi

# Step 4: Wait for file processing
echo -e "\n${YELLOW}Step 4: Waiting for file processing (15 seconds)...${NC}"
echo -e "${CYAN}This allows time for the Dropbox client to detect and process the file.${NC}"
sleep 15

# Step 5: Check if file is in the database
echo -e "\n${YELLOW}Step 5: Checking if file is in the database...${NC}"
DB_PATH="${DB_FILE_PATH:-/app/data/dropbox.db}"
DB_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, file_hash FROM files_metadata WHERE file_name='$FILE_NAME';")

if [ -n "$DB_RESULT" ]; then
    echo -e "${GREEN}File found in database:${NC}"
    echo -e "$DB_RESULT"
    
    # Extract file_id for later use
    FILE_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    echo -e "${CYAN}File ID: $FILE_ID${NC}"
else
    echo -e "${RED}File not found in database${NC}"
    # List all files in the database for debugging
    echo -e "${YELLOW}Listing all files in database:${NC}"
    docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path FROM files_metadata;"
    exit 1
fi

# Step 6: Check if chunks are in the database and verify fingerprints
echo -e "\n${YELLOW}Step 6: Checking chunks and fingerprints...${NC}"
CHUNKS_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")

if [ "$CHUNKS_RESULT" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNKS_RESULT chunks in database for this file${NC}"
    
    # Show chunk details including fingerprints
    echo -e "${YELLOW}Chunk details:${NC}"
    CHUNK_DETAILS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint, last_synced FROM chunks WHERE file_id='$FILE_ID';")
    echo -e "$CHUNK_DETAILS"
    
    # Check if any chunks are missing fingerprints
    MISSING_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID' AND (fingerprint IS NULL OR fingerprint = '');")
    
    if [ "$MISSING_FINGERPRINTS" -gt 0 ]; then
        echo -e "${RED}WARNING: $MISSING_FINGERPRINTS chunks are missing fingerprints!${NC}"
        # Show the problematic chunks
        echo -e "${YELLOW}Chunks missing fingerprints:${NC}"
        docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, created_at FROM chunks WHERE file_id='$FILE_ID' AND (fingerprint IS NULL OR fingerprint = '');"
    else
        echo -e "${GREEN}All chunks have fingerprints - GOOD!${NC}"
        
        # Verify fingerprint format (should be SHA-256 hash - 64 hex characters)
        INVALID_FINGERPRINTS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID' AND length(fingerprint) != 64;")
        
        if [ "$INVALID_FINGERPRINTS" -gt 0 ]; then
            echo -e "${RED}WARNING: $INVALID_FINGERPRINTS chunks have invalid fingerprint format!${NC}"
            # Show the problematic chunks
            echo -e "${YELLOW}Chunks with invalid fingerprints:${NC}"
            docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, fingerprint FROM chunks WHERE file_id='$FILE_ID' AND length(fingerprint) != 64;"
        else
            echo -e "${GREEN}All fingerprints have valid format (64 hex characters) - GOOD!${NC}"
        fi
    fi
    
    # Check if chunks have been synced (last_synced is not NULL)
    UNSYNCED_CHUNKS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID' AND last_synced IS NULL;")
    
    if [ "$UNSYNCED_CHUNKS" -gt 0 ]; then
        echo -e "${RED}WARNING: $UNSYNCED_CHUNKS chunks have not been synced!${NC}"
        # Show the unsynced chunks
        echo -e "${YELLOW}Unsynced chunks:${NC}"
        docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, created_at FROM chunks WHERE file_id='$FILE_ID' AND last_synced IS NULL;"
    else
        echo -e "${GREEN}All chunks have been synced - GOOD!${NC}"
    fi
else
    echo -e "${RED}No chunks found in database for this file${NC}"
fi

# Step 7: Check chunk files on disk
echo -e "\n${YELLOW}Step 7: Checking chunk files on disk...${NC}"
CHUNK_DIR="${CHUNK_DIR:-/app/chunks}"
CHUNK_FILES=$(docker exec $CONTAINER_NAME bash -c "find $CHUNK_DIR -name \"${FILE_ID}_*\" | wc -l")

if [ "$CHUNK_FILES" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNK_FILES chunk files on disk for this file${NC}"
    # List the chunk files
    echo -e "${YELLOW}Chunk files:${NC}"
    docker exec $CONTAINER_NAME bash -c "find $CHUNK_DIR -name \"${FILE_ID}_*\" -ls"
else
    echo -e "${RED}No chunk files found on disk for this file${NC}"
fi

# Step 8: Clean up the temporary file
echo -e "\n${YELLOW}Step 8: Cleaning up temporary file...${NC}"
rm $TEMP_FILE
echo -e "${GREEN}Removed temporary file: $TEMP_FILE${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}File uploaded: $FILE_NAME${NC}"
echo -e "${CYAN}Location: $CONTAINER_SYNC_DIR/$FILE_NAME${NC}"
echo -e "${CYAN}Size: $FILE_SIZE${NC}"
echo -e "${CYAN}Chunks: $CHUNKS_RESULT${NC}"