#!/bin/bash
#===================================================================================
# Dropbox Client Test Folder Move Script
#===================================================================================
# Description: This script creates a nested folder structure outside the sync
# directory, then moves it to the sync folder and verifies that all folder and
# file metadata are properly synced.
#
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
CONTAINER_TEMP_DIR="/tmp/test_folder_move"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FOLDER_NAME="test_folder_${TIMESTAMP}"
DB_PATH="${DB_FILE_PATH:-/app/data/dropbox.db}"

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Test Folder Move${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Step 1: Create a nested folder structure outside the sync directory
echo -e "${YELLOW}Step 1: Creating a nested folder structure outside the sync directory...${NC}"
docker exec $CONTAINER_NAME bash -c "mkdir -p $CONTAINER_TEMP_DIR/$FOLDER_NAME/subfolder1/subfolder2"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created nested folder structure at $CONTAINER_TEMP_DIR/$FOLDER_NAME${NC}"
else
    echo -e "${RED}Failed to create nested folder structure${NC}"
    exit 1
fi

# Step 2: Create files in each folder
echo -e "\n${YELLOW}Step 2: Creating files in each folder...${NC}"
docker exec $CONTAINER_NAME bash -c "echo 'Root folder file' > $CONTAINER_TEMP_DIR/$FOLDER_NAME/root_file.txt"
docker exec $CONTAINER_NAME bash -c "echo 'Subfolder1 file' > $CONTAINER_TEMP_DIR/$FOLDER_NAME/subfolder1/subfolder1_file.txt"
docker exec $CONTAINER_NAME bash -c "echo 'Subfolder2 file' > $CONTAINER_TEMP_DIR/$FOLDER_NAME/subfolder1/subfolder2/subfolder2_file.txt"

# List the created structure
echo -e "${CYAN}Created folder structure:${NC}"
docker exec $CONTAINER_NAME find $CONTAINER_TEMP_DIR/$FOLDER_NAME -type f | sort

# Step 3: Move the folder structure to the sync directory
echo -e "\n${YELLOW}Step 3: Moving the folder structure to the sync directory...${NC}"
docker exec $CONTAINER_NAME bash -c "mv $CONTAINER_TEMP_DIR/$FOLDER_NAME $CONTAINER_SYNC_DIR/"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully moved folder structure to $CONTAINER_SYNC_DIR/$FOLDER_NAME${NC}"
else
    echo -e "${RED}Failed to move folder structure${NC}"
    exit 1
fi

# Step 4: Wait for folder processing
echo -e "\n${YELLOW}Step 4: Waiting for folder processing (20 seconds)...${NC}"
echo -e "${CYAN}This allows time for the Dropbox client to detect and process the moved folder.${NC}"
sleep 20

# Step 5: Check if folders are in the database
echo -e "\n${YELLOW}Step 5: Checking if folders are in the database...${NC}"

# Check root folder
ROOT_FOLDER_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders WHERE folder_name='$FOLDER_NAME';")
if [ -n "$ROOT_FOLDER_RESULT" ]; then
    echo -e "${GREEN}Root folder found in database:${NC}"
    echo -e "$ROOT_FOLDER_RESULT"
    ROOT_FOLDER_ID=$(echo "$ROOT_FOLDER_RESULT" | cut -d'|' -f1)
    echo -e "${CYAN}Root Folder ID: $ROOT_FOLDER_ID${NC}"
else
    echo -e "${RED}Root folder not found in database${NC}"
    exit 1
fi

# Check subfolder1
SUBFOLDER1_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='subfolder1';")
if [ -n "$SUBFOLDER1_RESULT" ]; then
    echo -e "${GREEN}Subfolder1 found in database:${NC}"
    echo -e "$SUBFOLDER1_RESULT"
    SUBFOLDER1_ID=$(echo "$SUBFOLDER1_RESULT" | cut -d'|' -f1)
    SUBFOLDER1_PARENT=$(echo "$SUBFOLDER1_RESULT" | cut -d'|' -f4)
    echo -e "${CYAN}Subfolder1 ID: $SUBFOLDER1_ID${NC}"

    # Verify parent relationship
    if [ "$SUBFOLDER1_PARENT" = "$ROOT_FOLDER_ID" ]; then
        echo -e "${GREEN}Subfolder1 has correct parent folder - GOOD!${NC}"
    else
        echo -e "${RED}Subfolder1 has incorrect parent folder!${NC}"
        echo -e "Expected: $ROOT_FOLDER_ID, Got: $SUBFOLDER1_PARENT"
    fi
else
    echo -e "${RED}Subfolder1 not found in database${NC}"
    exit 1
fi

# Check subfolder2
SUBFOLDER2_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='subfolder2';")
if [ -n "$SUBFOLDER2_RESULT" ]; then
    echo -e "${GREEN}Subfolder2 found in database:${NC}"
    echo -e "$SUBFOLDER2_RESULT"
    SUBFOLDER2_ID=$(echo "$SUBFOLDER2_RESULT" | cut -d'|' -f1)
    SUBFOLDER2_PARENT=$(echo "$SUBFOLDER2_RESULT" | cut -d'|' -f4)
    echo -e "${CYAN}Subfolder2 ID: $SUBFOLDER2_ID${NC}"

    # Verify parent relationship
    if [ "$SUBFOLDER2_PARENT" = "$SUBFOLDER1_ID" ]; then
        echo -e "${GREEN}Subfolder2 has correct parent folder - GOOD!${NC}"
    else
        echo -e "${RED}Subfolder2 has incorrect parent folder!${NC}"
        echo -e "Expected: $SUBFOLDER1_ID, Got: $SUBFOLDER2_PARENT"
    fi
else
    echo -e "${RED}Subfolder2 not found in database${NC}"
    exit 1
fi

# Step 6: Display all folders and their IDs for reference
echo -e "\n${YELLOW}Step 6: Displaying all folders and their IDs for reference...${NC}"
echo -e "${CYAN}Folder structure in database:${NC}"
FOLDER_STRUCTURE=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_path LIKE '%$FOLDER_NAME%' ORDER BY folder_path;")
echo -e "$FOLDER_STRUCTURE"

# Step 7: Check if files are in the database
echo -e "\n${YELLOW}Step 7: Checking if files are in the database...${NC}"

# Display all files for reference
echo -e "${CYAN}All files in the moved folder structure:${NC}"
FILES_STRUCTURE=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_path LIKE '%$FOLDER_NAME%' ORDER BY file_path;")
echo -e "$FILES_STRUCTURE"

# Check root file
ROOT_FILE_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='root_file.txt';")
if [ -n "$ROOT_FILE_RESULT" ]; then
    echo -e "${GREEN}Root file found in database:${NC}"
    echo -e "$ROOT_FILE_RESULT"
    ROOT_FILE_FOLDER=$(echo "$ROOT_FILE_RESULT" | cut -d'|' -f4)

    # Get the actual folder ID for the root folder path
    ACTUAL_ROOT_FOLDER_ID=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id FROM folders WHERE folder_path='$CONTAINER_SYNC_DIR/$FOLDER_NAME';")

    # Verify folder relationship
    if [ "$ROOT_FILE_FOLDER" = "$ACTUAL_ROOT_FOLDER_ID" ]; then
        echo -e "${GREEN}Root file has correct folder - GOOD!${NC}"
    else
        echo -e "${YELLOW}Root file has different folder ID than expected${NC}"
        echo -e "Expected based on folder path: $ACTUAL_ROOT_FOLDER_ID, Got: $ROOT_FILE_FOLDER"

        # Check if the folder ID exists
        FOLDER_NAME_CHECK=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_name FROM folders WHERE folder_id='$ROOT_FILE_FOLDER';")
        if [ -n "$FOLDER_NAME_CHECK" ]; then
            echo -e "${CYAN}File is associated with folder: $FOLDER_NAME_CHECK${NC}"
        else
            echo -e "${RED}File is associated with a non-existent folder ID!${NC}"
        fi
    fi
else
    echo -e "${RED}Root file not found in database${NC}"
    exit 1
fi

# Check subfolder1 file
SUBFOLDER1_FILE_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='subfolder1_file.txt';")
if [ -n "$SUBFOLDER1_FILE_RESULT" ]; then
    echo -e "${GREEN}Subfolder1 file found in database:${NC}"
    echo -e "$SUBFOLDER1_FILE_RESULT"
    SUBFOLDER1_FILE_FOLDER=$(echo "$SUBFOLDER1_FILE_RESULT" | cut -d'|' -f4)

    # Get the actual folder ID for the subfolder1 path
    ACTUAL_SUBFOLDER1_ID=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id FROM folders WHERE folder_path='$CONTAINER_SYNC_DIR/$FOLDER_NAME/subfolder1';")

    # Verify folder relationship
    if [ "$SUBFOLDER1_FILE_FOLDER" = "$ACTUAL_SUBFOLDER1_ID" ]; then
        echo -e "${GREEN}Subfolder1 file has correct folder - GOOD!${NC}"
    else
        echo -e "${YELLOW}Subfolder1 file has different folder ID than expected${NC}"
        echo -e "Expected based on folder path: $ACTUAL_SUBFOLDER1_ID, Got: $SUBFOLDER1_FILE_FOLDER"

        # Check if the folder ID exists
        FOLDER_NAME_CHECK=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_name FROM folders WHERE folder_id='$SUBFOLDER1_FILE_FOLDER';")
        if [ -n "$FOLDER_NAME_CHECK" ]; then
            echo -e "${CYAN}File is associated with folder: $FOLDER_NAME_CHECK${NC}"
        else
            echo -e "${RED}File is associated with a non-existent folder ID!${NC}"
        fi
    fi
else
    echo -e "${RED}Subfolder1 file not found in database${NC}"
    exit 1
fi

# Check subfolder2 file
SUBFOLDER2_FILE_RESULT=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='subfolder2_file.txt';")
if [ -n "$SUBFOLDER2_FILE_RESULT" ]; then
    echo -e "${GREEN}Subfolder2 file found in database:${NC}"
    echo -e "$SUBFOLDER2_FILE_RESULT"
    SUBFOLDER2_FILE_FOLDER=$(echo "$SUBFOLDER2_FILE_RESULT" | cut -d'|' -f4)

    # Get the actual folder ID for the subfolder2 path
    ACTUAL_SUBFOLDER2_ID=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_id FROM folders WHERE folder_path='$CONTAINER_SYNC_DIR/$FOLDER_NAME/subfolder1/subfolder2';")

    # Verify folder relationship
    if [ "$SUBFOLDER2_FILE_FOLDER" = "$ACTUAL_SUBFOLDER2_ID" ]; then
        echo -e "${GREEN}Subfolder2 file has correct folder - GOOD!${NC}"
    else
        echo -e "${YELLOW}Subfolder2 file has different folder ID than expected${NC}"
        echo -e "Expected based on folder path: $ACTUAL_SUBFOLDER2_ID, Got: $SUBFOLDER2_FILE_FOLDER"

        # Check if the folder ID exists
        FOLDER_NAME_CHECK=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH "SELECT folder_name FROM folders WHERE folder_id='$SUBFOLDER2_FILE_FOLDER';")
        if [ -n "$FOLDER_NAME_CHECK" ]; then
            echo -e "${CYAN}File is associated with folder: $FOLDER_NAME_CHECK${NC}"
        else
            echo -e "${RED}File is associated with a non-existent folder ID!${NC}"
        fi
    fi
else
    echo -e "${RED}Subfolder2 file not found in database${NC}"
    exit 1
fi

# Step 8: Check if folders are synced to the server
echo -e "\n${YELLOW}Step 8: Checking if folders are synced to the server...${NC}"
# Use AWS CLI to check DynamoDB
echo -e "${CYAN}Checking DynamoDB for folder entries...${NC}"
docker exec $CONTAINER_NAME bash -c "AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin AWS_REGION=us-east-1 aws dynamodb scan --endpoint-url http://aws-dynamodb:8000 --table-name Folders --filter-expression 'contains(folder_path, :path)' --expression-attribute-values '{\":path\":{\"S\":\"$FOLDER_NAME\"}}' --query 'Items[*].{FolderID:folder_id.S,FolderName:folder_name.S,FolderPath:folder_path.S}' --output table"

# Step 9: Check if files are synced to the server
echo -e "\n${YELLOW}Step 9: Checking if files are synced to the server...${NC}"
# Use AWS CLI to check DynamoDB
echo -e "${CYAN}Checking DynamoDB for file entries...${NC}"
docker exec $CONTAINER_NAME bash -c "AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin AWS_REGION=us-east-1 aws dynamodb scan --endpoint-url http://aws-dynamodb:8000 --table-name FilesMetaData --filter-expression 'contains(file_path, :path)' --expression-attribute-values '{\":path\":{\"S\":\"$FOLDER_NAME\"}}' --query 'Items[*].{FileID:file_id.S,FileName:file_name.S,FilePath:file_path.S,FolderID:folder_id.S}' --output table"

# Step 10: Verify folder hierarchy on server
echo -e "\n${YELLOW}Step 10: Verifying folder hierarchy on server...${NC}"
echo -e "${CYAN}Checking parent-child relationships in DynamoDB...${NC}"
docker exec $CONTAINER_NAME bash -c "AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin AWS_REGION=us-east-1 aws dynamodb scan --endpoint-url http://aws-dynamodb:8000 --table-name Folders --filter-expression 'contains(folder_path, :path)' --expression-attribute-values '{\":path\":{\"S\":\"$FOLDER_NAME\"}}' --query 'Items[*].{FolderID:folder_id.S,FolderName:folder_name.S,ParentID:parent_folder_id.S}' --output table"

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}Moved folder structure: $FOLDER_NAME${NC}"
echo -e "${CYAN}Location: $CONTAINER_SYNC_DIR/$FOLDER_NAME${NC}"
