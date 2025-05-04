#!/bin/bash
#===================================================================================
# Dropbox Client File Synchronization Smoke Test
#===================================================================================
# Description: This script tests the basic file synchronization functionality of the
# Dropbox client. It verifies that files are properly uploaded, tracked in the
# database, and that folder structures are maintained.
#
# Test Coverage:
# - Copying files to the sync directory
# - Creating nested folder structures
# - Creating files directly in the container
# - Verifying database entries for files and folders
#
# Author: Kaveen Jayamanna
# Date: May 3, 2025
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
MOCK_DATA_DIR="client/tests/mock_data"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_dropbox}"
DB_PATH="${DB_FILE_PATH:-/app/data/dropbox.db}"
WAIT_TIME=5  # seconds to wait for file processing

#===================================================================================
# Helper Functions
#===================================================================================

# Function to check if a file exists in the database
check_file_in_db() {
    local filename=$1
    local result=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH \
        "SELECT COUNT(*) FROM files_metadata WHERE file_name='$filename';")

    if [ "$result" -gt 0 ]; then
        echo -e "${GREEN}✓ $filename found in database${NC}"
        return 0
    else
        echo -e "${RED}✗ $filename not found in database${NC}"
        return 1
    fi
}

# Function to check if a folder exists in the database
check_folder_in_db() {
    local foldername=$1
    local result=$(docker exec $CONTAINER_NAME sqlite3 $DB_PATH \
        "SELECT COUNT(*) FROM folders WHERE folder_name='$foldername';")

    if [ "$result" -gt 0 ]; then
        echo -e "${GREEN}✓ $foldername found in database${NC}"
        return 0
    else
        echo -e "${RED}✗ $foldername not found in database${NC}"
        return 1
    fi
}

# Function to execute a command in the container
exec_in_container() {
    docker exec $CONTAINER_NAME bash -c "$1"
    return $?
}

# Function to display test step header
display_step() {
    local step_num=$1
    local step_desc=$2
    echo -e "\n${YELLOW}Step $step_num: $step_desc${NC}"
}

#===================================================================================
# Main Test Script
#===================================================================================

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox File Sync Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

#-------------------
# Test Steps
#-------------------

# Step 1: Copy mock data to the sync folder
display_step 1 "Copying mock data to sync folder"
find "$MOCK_DATA_DIR" -type f | while read -r file; do
    rel_path=${file#"$MOCK_DATA_DIR/"}
    dir_path=$(dirname "$rel_path")

    # Create directory structure if needed
    if [ "$dir_path" != "." ]; then
        echo -e "Creating directory: $dir_path in container"
        exec_in_container "mkdir -p '$CONTAINER_SYNC_DIR/$dir_path'"
    fi

    # Copy the file
    echo -e "Copying: $rel_path"
    # Get file size for better logging
    file_size=$(du -h "$file" | cut -f1)
    docker cp "$file" "$CONTAINER_NAME:$CONTAINER_SYNC_DIR/$rel_path"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully copied $file_size to $CONTAINER_NAME:$CONTAINER_SYNC_DIR/$rel_path${NC}"
        echo -e "${GREEN}Successfully copied: $rel_path${NC}"
    else
        echo -e "${RED}Failed to copy: $rel_path${NC}"
    fi
done

# Step 2: Wait for files to be processed
display_step 2 "Waiting for files to be processed ($WAIT_TIME seconds)"
sleep $WAIT_TIME

# Step 3: Check if files are in the database
display_step 3 "Checking if files are in the database"
check_file_in_db "small_file.txt"
check_file_in_db "medium_file.bin"
check_file_in_db "nested_file.txt"

# Step 4: Check if folders are in the database
display_step 4 "Checking if folders are in the database"
check_folder_in_db "nested_folder"

# Step 5: Create a new file directly in the container
display_step 5 "Creating a new file directly in the container"
exec_in_container "echo 'This is a new file created inside the container' > $CONTAINER_SYNC_DIR/container_created_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created container_created_file.txt${NC}"
else
    echo -e "${RED}Failed to create container_created_file.txt${NC}"
fi

# Step 6: Create a new folder directly in the container
display_step 6 "Creating a new folder directly in the container"
exec_in_container "mkdir -p $CONTAINER_SYNC_DIR/container_created_folder && echo 'File in new folder' > $CONTAINER_SYNC_DIR/container_created_folder/folder_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created container_created_folder and folder_file.txt${NC}"
else
    echo -e "${RED}Failed to create container_created_folder and folder_file.txt${NC}"
fi

# Step 7: Wait for new files to be processed
display_step 7 "Waiting for new files to be processed ($WAIT_TIME seconds)"
sleep $WAIT_TIME

# Step 8: Check if new files are in the database
display_step 8 "Checking if new files are in the database"
check_file_in_db "container_created_file.txt"
check_file_in_db "folder_file.txt"

# Step 9: Check if new folder is in the database
display_step 9 "Checking if new folder is in the database"
check_folder_in_db "container_created_folder"

# Step 10: Display all files and folders in the database
display_step 10 "Displaying all files in the database"
echo -e "${BLUE}Files:${NC}"
exec_in_container "sqlite3 $DB_PATH 'SELECT file_name, file_path FROM files_metadata;'"

echo -e "\n${BLUE}Folders:${NC}"
exec_in_container "sqlite3 $DB_PATH 'SELECT folder_name, folder_path FROM folders;'"

#-------------------
# Test Summary
#-------------------
echo -e "\n${GREEN}Smoke test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"

# Return success
exit 0
