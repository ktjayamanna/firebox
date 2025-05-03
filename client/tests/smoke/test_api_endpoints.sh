#!/bin/bash
# Smoke test for API endpoints

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox API Endpoints Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q dropbox-client; then
    echo -e "${RED}Error: dropbox-client container is not running${NC}"
    echo -e "Please start the container first with: cd deployment/docker && docker-compose up -d"
    exit 1
fi

# Define API base URL
API_BASE="http://localhost:8000"

# Step 1: Test root endpoint
echo -e "\n${YELLOW}Step 1: Testing root endpoint...${NC}"
ROOT_RESPONSE=$(curl -s $API_BASE)
if [[ $ROOT_RESPONSE == *"Welcome to Dropbox Client API"* ]]; then
    echo -e "${GREEN}Root endpoint working correctly${NC}"
else
    echo -e "${RED}Root endpoint not working correctly${NC}"
    echo -e "Response: $ROOT_RESPONSE"
fi

# Step 2: Test health endpoint
echo -e "\n${YELLOW}Step 2: Testing health endpoint...${NC}"
HEALTH_RESPONSE=$(curl -s $API_BASE/health)
if [[ $HEALTH_RESPONSE == *"healthy"* ]]; then
    echo -e "${GREEN}Health endpoint working correctly${NC}"
else
    echo -e "${RED}Health endpoint not working correctly${NC}"
    echo -e "Response: $HEALTH_RESPONSE"
fi

# Step 3: Test folders endpoint
echo -e "\n${YELLOW}Step 3: Testing folders endpoint...${NC}"
FOLDERS_RESPONSE=$(curl -s $API_BASE/api/folders)
if [[ $FOLDERS_RESPONSE == *"folder_id"* && $FOLDERS_RESPONSE == *"folder_path"* ]]; then
    echo -e "${GREEN}Folders endpoint working correctly${NC}"
    echo -e "Found folders:"
    echo $FOLDERS_RESPONSE | grep -o '"folder_name":"[^"]*"' | cut -d':' -f2 | tr -d '"'
else
    echo -e "${RED}Folders endpoint not working correctly${NC}"
    echo -e "Response: $FOLDERS_RESPONSE"
fi

# Step 4: Create a test file for API testing
echo -e "\n${YELLOW}Step 4: Creating a test file for API testing...${NC}"
TEST_FILE="/app/my_dropbox/api_test_file.txt"
docker exec dropbox-client bash -c "echo 'This is a test file for API testing' > $TEST_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created test file${NC}"
else
    echo -e "${RED}Failed to create test file${NC}"
    exit 1
fi

# Step 5: Wait for file to be processed
echo -e "\n${YELLOW}Step 5: Waiting for file to be processed (3 seconds)...${NC}"
sleep 3

# Step 6: Test files endpoint
echo -e "\n${YELLOW}Step 6: Testing files endpoint...${NC}"
FILES_RESPONSE=$(curl -s $API_BASE/api/files)
if [[ $FILES_RESPONSE == *"file_id"* && $FILES_RESPONSE == *"file_path"* ]]; then
    echo -e "${GREEN}Files endpoint working correctly${NC}"
    echo -e "Found files:"
    echo $FILES_RESPONSE | grep -o '"file_name":"[^"]*"' | cut -d':' -f2 | tr -d '"'
else
    echo -e "${RED}Files endpoint not working correctly${NC}"
    echo -e "Response: $FILES_RESPONSE"
fi

# Step 7: Test file details endpoint
echo -e "\n${YELLOW}Step 7: Testing file details endpoint...${NC}"
# Get the file_id of the test file
FILE_ID=$(docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_id FROM files_metadata WHERE file_name='api_test_file.txt';")
if [ -z "$FILE_ID" ]; then
    echo -e "${RED}Could not find file_id for test file${NC}"
else
    echo -e "File ID: $FILE_ID"
    FILE_DETAILS_RESPONSE=$(curl -s $API_BASE/api/files/$FILE_ID)
    if [[ $FILE_DETAILS_RESPONSE == *"file_id"* && $FILE_DETAILS_RESPONSE == *"api_test_file.txt"* ]]; then
        echo -e "${GREEN}File details endpoint working correctly${NC}"
    else
        echo -e "${RED}File details endpoint not working correctly${NC}"
        echo -e "Response: $FILE_DETAILS_RESPONSE"
    fi
fi

# Step 8: Check if chunks exist in the database
echo -e "\n${YELLOW}Step 8: Checking if chunks exist in the database...${NC}"
if [ -z "$FILE_ID" ]; then
    echo -e "${RED}Skipping chunks check as file_id is not available${NC}"
else
    CHUNK_COUNT=$(docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT COUNT(*) FROM chunks WHERE file_id='$FILE_ID';")
    if [ "$CHUNK_COUNT" -gt 0 ]; then
        echo -e "${GREEN}Found $CHUNK_COUNT chunks for file $FILE_ID in the database${NC}"
        # Display chunk details
        echo -e "Chunk details:"
        docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT chunk_id, created_at FROM chunks WHERE file_id='$FILE_ID';"
    else
        echo -e "${YELLOW}No chunks found for file $FILE_ID in the database${NC}"
    fi
fi

echo -e "\n${GREEN}API endpoints test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
