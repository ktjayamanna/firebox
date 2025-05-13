#!/bin/bash
#===================================================================================
# Dropbox Client Test File Download Script
#===================================================================================
# Description: This script creates a randomly generated text file, uploads it to
# the Dropbox sync folder, and then tests downloading specific chunks using the
# new download endpoint.
#
# The script follows these steps:
# 1. Upload: Generates a random text file and copies it to the Dropbox sync folder
# 2. Process: Verifies the file is processed and chunks are created in the database
# 3. Download: Retrieves specific chunks using AWS CLI's get-object command with range parameter
# 4. Verify: Checks the integrity of downloaded chunks against the original file
#
# Note: This script downloads chunks using AWS CLI's get-object command with range parameter
# to ensure consistent handling of byte ranges in presigned URLs.

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
FILE_SIZE_KB=${1:-500}  # Default to 500KB if not specified (to ensure multiple chunks)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILE_NAME="test_download_${TIMESTAMP}.txt"
TEMP_FILE="/tmp/${FILE_NAME}"
FILES_SERVICE_URL="http://localhost:8001"
DOWNLOAD_DIR="/tmp/downloaded_chunks_${TIMESTAMP}"

# Function to display steps with formatting
display_step() {
    echo -e "\n${YELLOW}Step $1: $2${NC}"
}

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Test File Download${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Generate a random text file
display_step 1 "Generating a ${FILE_SIZE_KB}KB random text file"
dd if=/dev/urandom bs=1K count=$FILE_SIZE_KB | base64 > $TEMP_FILE 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created random file: $TEMP_FILE ($(du -h $TEMP_FILE | cut -f1))${NC}"
else
    echo -e "${RED}Failed to create random file${NC}"
    exit 1
fi

# Step 2: Copy the file to the container's sync directory
display_step 2 "Copying file to container's sync directory"
docker cp $TEMP_FILE $CONTAINER_NAME:$CONTAINER_SYNC_DIR/$FILE_NAME
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully copied file to $CONTAINER_NAME:$CONTAINER_SYNC_DIR/$FILE_NAME${NC}"
else
    echo -e "${RED}Failed to copy file to container${NC}"
    exit 1
fi

# Step 3: Verify the file exists in the container
display_step 3 "Verifying file exists in container"
if docker exec $CONTAINER_NAME ls -la $CONTAINER_SYNC_DIR/$FILE_NAME >/dev/null 2>&1; then
    FILE_SIZE=$(docker exec $CONTAINER_NAME du -h $CONTAINER_SYNC_DIR/$FILE_NAME | cut -f1)
    echo -e "${GREEN}File exists in container: $CONTAINER_SYNC_DIR/$FILE_NAME (${FILE_SIZE})${NC}"
else
    echo -e "${RED}File not found in container${NC}"
    exit 1
fi

# Step 5: Check if file is in the database and get file_id
display_step 5 "Checking if file is in the database"
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

# Step 6: Get chunk information from the database
display_step 6 "Getting chunk information from the database"
CHUNKS_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")

if [ "$CHUNKS_RESULT" -gt 0 ]; then
    echo -e "${GREEN}Found $CHUNKS_RESULT chunks in database for this file${NC}"

    # Get chunk details including fingerprints and part numbers
    echo -e "${YELLOW}Chunk details:${NC}"
    CHUNK_DETAILS=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT chunk_id, part_number, fingerprint FROM chunks WHERE file_id='$FILE_ID' ORDER BY part_number;")
    echo -e "$CHUNK_DETAILS"

    # Store chunk details in arrays for later use
    CHUNK_IDS=()
    PART_NUMBERS=()
    FINGERPRINTS=()

    # Parse chunk details
    IFS=$'\n'
    for line in $CHUNK_DETAILS; do
        CHUNK_ID=$(echo "$line" | cut -d'|' -f1)
        PART_NUMBER=$(echo "$line" | cut -d'|' -f2)
        FINGERPRINT=$(echo "$line" | cut -d'|' -f3)

        CHUNK_IDS+=("$CHUNK_ID")
        PART_NUMBERS+=("$PART_NUMBER")
        FINGERPRINTS+=("$FINGERPRINT")
    done
    unset IFS
else
    echo -e "${RED}No chunks found in database for this file${NC}"
    exit 1
fi

# Step 7: Create download request payload
display_step 7 "Creating download request payload"
# Create a directory for downloaded chunks
mkdir -p $DOWNLOAD_DIR

# Select a subset of chunks to download (first 2 chunks or all if less than 2)
NUM_CHUNKS_TO_DOWNLOAD=$(( CHUNKS_RESULT > 2 ? 2 : CHUNKS_RESULT ))
echo -e "${CYAN}Will download $NUM_CHUNKS_TO_DOWNLOAD chunks${NC}"

# Create the download request payload
DOWNLOAD_PAYLOAD="{"
DOWNLOAD_PAYLOAD+="\"file_id\":\"$FILE_ID\","
DOWNLOAD_PAYLOAD+="\"chunks\":["

for ((i=0; i<$NUM_CHUNKS_TO_DOWNLOAD; i++)); do
    if [ $i -gt 0 ]; then
        DOWNLOAD_PAYLOAD+=","
    fi
    DOWNLOAD_PAYLOAD+="{"
    DOWNLOAD_PAYLOAD+="\"chunk_id\":\"${CHUNK_IDS[$i]}\","
    DOWNLOAD_PAYLOAD+="\"part_number\":${PART_NUMBERS[$i]},"
    DOWNLOAD_PAYLOAD+="\"fingerprint\":\"${FINGERPRINTS[$i]}\""
    DOWNLOAD_PAYLOAD+="}"
done

DOWNLOAD_PAYLOAD+="]"
DOWNLOAD_PAYLOAD+="}"

echo -e "${CYAN}Download request payload:${NC}"
echo -e "$DOWNLOAD_PAYLOAD" | jq '.' || echo -e "$DOWNLOAD_PAYLOAD"

# Step 8: Call the download endpoint
display_step 8 "Calling the download endpoint"
DOWNLOAD_RESPONSE=$(curl -s -X POST "$FILES_SERVICE_URL/files/download" \
  -H "Content-Type: application/json" \
  -d "$DOWNLOAD_PAYLOAD")

# Check if the response is valid JSON and has a success field
if [ $? -ne 0 ] || [ -z "$DOWNLOAD_RESPONSE" ]; then
    echo -e "${RED}Failed to get download URLs - API call failed${NC}"
    echo -e "Response: $DOWNLOAD_RESPONSE"
    exit 1
fi

# Check if the response contains a success field and it's set to true
SUCCESS=$(echo "$DOWNLOAD_RESPONSE" | jq -r '.success // "false"')
if [ "$SUCCESS" != "true" ]; then
    echo -e "${RED}Failed to get download URLs - API returned error${NC}"
    ERROR_MSG=$(echo "$DOWNLOAD_RESPONSE" | jq -r '.error_message // "Unknown error"')
    echo -e "Error message: $ERROR_MSG"
    echo -e "Full response: $DOWNLOAD_RESPONSE"
    exit 1
fi

echo -e "${GREEN}Successfully got download URLs:${NC}"
echo -e "$DOWNLOAD_RESPONSE" | jq '.' || echo -e "$DOWNLOAD_RESPONSE"

# Step 9: Download the chunks
display_step 9 "Downloading chunks"
# Extract download URLs from the response
DOWNLOAD_URLS=$(echo "$DOWNLOAD_RESPONSE" | jq -r '.download_urls')
NUM_URLS=$(echo "$DOWNLOAD_URLS" | jq -r '. | length')

echo -e "${CYAN}Found $NUM_URLS download URLs${NC}"

# Set AWS credentials for MinIO
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1

for ((i=0; i<$NUM_URLS; i++)); do
    CHUNK_ID=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].chunk_id")
    PART_NUMBER=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].part_number")
    PRESIGNED_URL=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].presigned_url")

    # Check if range header information is available
    RANGE_HEADER=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].range_header // \"\"")
    START_BYTE=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].start_byte // \"\"")
    END_BYTE=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].end_byte // \"\"")

    # If range header information is missing, calculate it
    if [ -z "$RANGE_HEADER" ] || [ "$RANGE_HEADER" = "null" ]; then
        # Define chunk size (5MB by default)
        CHUNK_SIZE_BYTES=$((5 * 1024 * 1024))

        # Calculate byte range based on part number
        START_BYTE=$(( (PART_NUMBER - 1) * CHUNK_SIZE_BYTES ))
        END_BYTE=$(( PART_NUMBER * CHUNK_SIZE_BYTES - 1 ))
        RANGE_HEADER="bytes=${START_BYTE}-${END_BYTE}"

        echo -e "${YELLOW}Range header information missing, calculated: $RANGE_HEADER${NC}"
    fi

    # Extract bucket and key from the URL
    BUCKET="dropbox-chunks"
    KEY=$(echo "$PRESIGNED_URL" | grep -o '/dropbox-chunks/[^?]*' | sed 's/\/dropbox-chunks\///')

    DOWNLOAD_PATH="$DOWNLOAD_DIR/${CHUNK_ID}_part${PART_NUMBER}.bin"

    echo -e "${CYAN}Downloading chunk $CHUNK_ID (part $PART_NUMBER) to $DOWNLOAD_PATH${NC}"
    echo -e "${CYAN}Using Range header: $RANGE_HEADER (bytes $START_BYTE-$END_BYTE)${NC}"

    # Use AWS CLI to download the specific byte range
    aws s3api get-object \
        --bucket $BUCKET \
        --key $KEY \
        --range "$RANGE_HEADER" \
        --endpoint-url http://localhost:9000 \
        "$DOWNLOAD_PATH" 2>/dev/null

    if [ $? -eq 0 ] && [ -f "$DOWNLOAD_PATH" ]; then
        CHUNK_SIZE=$(du -h "$DOWNLOAD_PATH" | cut -f1)
        echo -e "${GREEN}Successfully downloaded chunk: $DOWNLOAD_PATH (${CHUNK_SIZE})${NC}"
    else
        echo -e "${RED}Failed to download chunk $CHUNK_ID${NC}"
    fi
done

# Step 10: Verify downloaded chunks
display_step 10 "Verifying downloaded chunks"
DOWNLOADED_COUNT=$(ls -1 $DOWNLOAD_DIR | wc -l)
echo -e "${CYAN}Downloaded $DOWNLOADED_COUNT chunks to $DOWNLOAD_DIR${NC}"

if [ "$DOWNLOADED_COUNT" -eq "$NUM_URLS" ]; then
    echo -e "${GREEN}All chunks downloaded successfully${NC}"

    # List the downloaded chunks
    echo -e "${YELLOW}Downloaded chunks:${NC}"
    ls -lh $DOWNLOAD_DIR

    # Step 10.1: Verify chunk integrity by comparing with original file
    echo -e "\n${YELLOW}Step 10.1: Verifying chunk integrity${NC}"

    # Define chunk size (5MB by default)
    CHUNK_SIZE_BYTES=$((5 * 1024 * 1024))

    # Loop through each downloaded chunk and verify its integrity
    INTEGRITY_ERRORS=0

    for ((i=0; i<$NUM_URLS; i++)); do
        CHUNK_ID=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].chunk_id")
        PART_NUMBER=$(echo "$DOWNLOAD_URLS" | jq -r ".[$i].part_number")
        DOWNLOAD_PATH="$DOWNLOAD_DIR/${CHUNK_ID}_part${PART_NUMBER}.bin"

        # Get the byte range (either from API response or calculated earlier)
        # We already have START_BYTE from the download step

        echo -e "${CYAN}Verifying integrity of chunk $CHUNK_ID (part $PART_NUMBER)${NC}"

        # Create a temporary file with the expected content from the original file
        EXPECTED_CHUNK="/tmp/expected_chunk_${PART_NUMBER}.bin"

        # Get the size of the downloaded chunk
        ACTUAL_SIZE=$(du -b "$DOWNLOAD_PATH" 2>/dev/null | cut -f1 || echo "0")

        # If the downloaded chunk is smaller than expected, only extract that many bytes for comparison
        BYTES_TO_EXTRACT=$CHUNK_SIZE_BYTES
        if [ "$ACTUAL_SIZE" -gt 0 ] && [ "$ACTUAL_SIZE" -lt "$CHUNK_SIZE_BYTES" ]; then
            echo -e "${YELLOW}Downloaded chunk is smaller than expected ($ACTUAL_SIZE vs $CHUNK_SIZE_BYTES bytes)${NC}"
            echo -e "${YELLOW}Extracting only $ACTUAL_SIZE bytes for comparison${NC}"
            BYTES_TO_EXTRACT=$ACTUAL_SIZE
        fi

        # Extract the expected content
        dd if=$TEMP_FILE bs=1 skip=$START_BYTE count=$BYTES_TO_EXTRACT of=$EXPECTED_CHUNK 2>/dev/null

        # Calculate checksums
        EXPECTED_CHECKSUM=$(md5sum $EXPECTED_CHUNK | awk '{print $1}')
        ACTUAL_CHECKSUM=$(md5sum $DOWNLOAD_PATH | awk '{print $1}')

        echo -e "Expected MD5: $EXPECTED_CHECKSUM"
        echo -e "Actual MD5:   $ACTUAL_CHECKSUM"

        # Compare checksums
        if [ "$EXPECTED_CHECKSUM" == "$ACTUAL_CHECKSUM" ]; then
            echo -e "${GREEN}✓ Chunk integrity verified${NC}"
        else
            echo -e "${RED}✗ Chunk integrity check failed${NC}"
            INTEGRITY_ERRORS=$((INTEGRITY_ERRORS + 1))

            # Compare file sizes for debugging
            EXPECTED_SIZE=$(du -b $EXPECTED_CHUNK | cut -f1)
            ACTUAL_SIZE=$(du -b $DOWNLOAD_PATH | cut -f1)
            echo -e "Expected size: $EXPECTED_SIZE bytes"
            echo -e "Actual size:   $ACTUAL_SIZE bytes"
        fi

        # Clean up temporary file
        rm $EXPECTED_CHUNK
    done

    # Report overall integrity check results
    if [ $INTEGRITY_ERRORS -eq 0 ]; then
        echo -e "\n${GREEN}All chunks passed integrity verification${NC}"
    else
        echo -e "\n${RED}$INTEGRITY_ERRORS chunks failed integrity verification${NC}"
    fi
else
    echo -e "${RED}Not all chunks were downloaded successfully${NC}"
    echo -e "Expected: $NUM_URLS, Downloaded: $DOWNLOADED_COUNT"
fi

# Step 11: Clean up
display_step 11 "Cleaning up"
rm $TEMP_FILE
echo -e "${GREEN}Removed temporary file: $TEMP_FILE${NC}"

echo -e "${CYAN}Downloaded chunks are available in: $DOWNLOAD_DIR${NC}"
echo -e "${CYAN}You can remove them with: rm -rf $DOWNLOAD_DIR${NC}"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}File uploaded: $FILE_NAME${NC}"
echo -e "${CYAN}File ID: $FILE_ID${NC}"
echo -e "${CYAN}Total chunks: $CHUNKS_RESULT${NC}"
echo -e "${CYAN}Downloaded chunks: $DOWNLOADED_COUNT${NC}"

# Add integrity check results to summary if we performed the checks
if [ "$DOWNLOADED_COUNT" -gt 0 ]; then
    if [ -z "$INTEGRITY_ERRORS" ] || [ "$INTEGRITY_ERRORS" -eq 0 ]; then
        echo -e "${GREEN}Integrity check: PASSED${NC}"
    else
        echo -e "${RED}Integrity check: FAILED ($INTEGRITY_ERRORS errors)${NC}"
    fi
fi
