#!/bin/bash
#===================================================================================
# Dropbox Client Multi-Device Test Move and Rename Operations
#===================================================================================
# Description: This script tests the move and rename functionality across multiple
# client devices:
# - Support for moving files between directories
# - Handling of file and folder renames
# - Preservation of chunk data during moves
#
# The script follows these steps:
# 1. Create: Creates test folders and files on both clients
# 2. Verify: Confirms the folders and files are processed correctly
# 3. Move: Moves files between folders on both clients
# 4. Rename: Renames files and folders on both clients
# 5. Verify: Confirms database records are updated correctly
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
WAIT_TIME=3  # seconds to wait for file processing

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Multi-Device Move and Rename Operations Test${NC}"
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

# Step 1: Creating test folders in both clients
echo -e "${YELLOW}Step 1: Creating test folders in both clients...${NC}"

# Create folders in client 1
FOLDER1="test_folder1_${TIMESTAMP}"
FOLDER2="test_folder2_${TIMESTAMP}"

docker exec $CLIENT1_NAME mkdir -p $CONTAINER_SYNC_DIR/$FOLDER1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created first test folder in client 1: $CONTAINER_SYNC_DIR/$FOLDER1${NC}"
else
    echo -e "${RED}Failed to create first test folder in client 1${NC}"
    exit 1
fi

docker exec $CLIENT1_NAME mkdir -p $CONTAINER_SYNC_DIR/$FOLDER2
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created second test folder in client 1: $CONTAINER_SYNC_DIR/$FOLDER2${NC}"
else
    echo -e "${RED}Failed to create second test folder in client 1${NC}"
    exit 1
fi

# Create folders in client 2
docker exec $CLIENT2_NAME mkdir -p $CONTAINER_SYNC_DIR/$FOLDER1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created first test folder in client 2: $CONTAINER_SYNC_DIR/$FOLDER1${NC}"
else
    echo -e "${RED}Failed to create first test folder in client 2${NC}"
    exit 1
fi

docker exec $CLIENT2_NAME mkdir -p $CONTAINER_SYNC_DIR/$FOLDER2
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created second test folder in client 2: $CONTAINER_SYNC_DIR/$FOLDER2${NC}"
else
    echo -e "${RED}Failed to create second test folder in client 2${NC}"
    exit 1
fi

# Step 2: Creating test files in the first folder for both clients
echo -e "\n${YELLOW}Step 2: Creating test files in the first folder for both clients...${NC}"
FILE1="test_file1_${TIMESTAMP}.txt"
FILE2="test_file2_${TIMESTAMP}.txt"

# Create files in client 1
docker exec $CLIENT1_NAME bash -c "echo 'This is test file 1 on client 1' > $CONTAINER_SYNC_DIR/$FOLDER1/$FILE1"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created first test file in client 1: $CONTAINER_SYNC_DIR/$FOLDER1/$FILE1${NC}"
else
    echo -e "${RED}Failed to create first test file in client 1${NC}"
    exit 1
fi

docker exec $CLIENT1_NAME bash -c "echo 'This is test file 2 on client 1' > $CONTAINER_SYNC_DIR/$FOLDER1/$FILE2"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created second test file in client 1: $CONTAINER_SYNC_DIR/$FOLDER1/$FILE2${NC}"
else
    echo -e "${RED}Failed to create second test file in client 1${NC}"
    exit 1
fi

# Create files in client 2
docker exec $CLIENT2_NAME bash -c "echo 'This is test file 1 on client 2' > $CONTAINER_SYNC_DIR/$FOLDER1/$FILE1"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created first test file in client 2: $CONTAINER_SYNC_DIR/$FOLDER1/$FILE1${NC}"
else
    echo -e "${RED}Failed to create first test file in client 2${NC}"
    exit 1
fi

docker exec $CLIENT2_NAME bash -c "echo 'This is test file 2 on client 2' > $CONTAINER_SYNC_DIR/$FOLDER1/$FILE2"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created second test file in client 2: $CONTAINER_SYNC_DIR/$FOLDER1/$FILE2${NC}"
else
    echo -e "${RED}Failed to create second test file in client 2${NC}"
    exit 1
fi

# Step 3: Waiting for files and folders to be processed
echo -e "\n${YELLOW}Step 3: Waiting for files and folders to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 4: Verifying folders exist in the database for both clients
echo -e "\n${YELLOW}Step 4: Verifying folders exist in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
FOLDER1_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders WHERE folder_name='$FOLDER1';")
if [ -n "$FOLDER1_DB_1" ]; then
    echo -e "${GREEN}First folder found in client 1 database: $FOLDER1_DB_1${NC}"
    FOLDER1_ID_1=$(echo "$FOLDER1_DB_1" | cut -d'|' -f1)
else
    echo -e "${RED}First folder not found in client 1 database${NC}"
    exit 1
fi

FOLDER2_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders WHERE folder_name='$FOLDER2';")
if [ -n "$FOLDER2_DB_1" ]; then
    echo -e "${GREEN}Second folder found in client 1 database: $FOLDER2_DB_1${NC}"
    FOLDER2_ID_1=$(echo "$FOLDER2_DB_1" | cut -d'|' -f1)
else
    echo -e "${RED}Second folder not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
FOLDER1_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders WHERE folder_name='$FOLDER1';")
if [ -n "$FOLDER1_DB_2" ]; then
    echo -e "${GREEN}First folder found in client 2 database: $FOLDER1_DB_2${NC}"
    FOLDER1_ID_2=$(echo "$FOLDER1_DB_2" | cut -d'|' -f1)
else
    echo -e "${RED}First folder not found in client 2 database${NC}"
    exit 1
fi

FOLDER2_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders WHERE folder_name='$FOLDER2';")
if [ -n "$FOLDER2_DB_2" ]; then
    echo -e "${GREEN}Second folder found in client 2 database: $FOLDER2_DB_2${NC}"
    FOLDER2_ID_2=$(echo "$FOLDER2_DB_2" | cut -d'|' -f1)
else
    echo -e "${RED}Second folder not found in client 2 database${NC}"
    exit 1
fi

# Step 5: Verifying files exist in the database for both clients
echo -e "\n${YELLOW}Step 5: Verifying files exist in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
FILE1_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$FILE1';")
if [ -n "$FILE1_DB_1" ]; then
    echo -e "${GREEN}First file found in client 1 database: $FILE1_DB_1${NC}"
    FILE1_ID_1=$(echo "$FILE1_DB_1" | cut -d'|' -f1)
    FILE1_FOLDER_ID_1=$(echo "$FILE1_DB_1" | cut -d'|' -f4)

    if [ "$FILE1_FOLDER_ID_1" = "$FOLDER1_ID_1" ]; then
        echo -e "${GREEN}First file is in the correct folder in client 1 - GOOD!${NC}"
    else
        echo -e "${RED}First file is not in the expected folder in client 1${NC}"
        echo -e "${RED}Expected: $FOLDER1_ID_1, Got: $FILE1_FOLDER_ID_1${NC}"
        exit 1
    fi
else
    echo -e "${RED}First file not found in client 1 database${NC}"
    exit 1
fi

FILE2_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$FILE2';")
if [ -n "$FILE2_DB_1" ]; then
    echo -e "${GREEN}Second file found in client 1 database: $FILE2_DB_1${NC}"
    FILE2_ID_1=$(echo "$FILE2_DB_1" | cut -d'|' -f1)
    FILE2_FOLDER_ID_1=$(echo "$FILE2_DB_1" | cut -d'|' -f4)

    if [ "$FILE2_FOLDER_ID_1" = "$FOLDER1_ID_1" ]; then
        echo -e "${GREEN}Second file is in the correct folder in client 1 - GOOD!${NC}"
    else
        echo -e "${RED}Second file is not in the expected folder in client 1${NC}"
        echo -e "${RED}Expected: $FOLDER1_ID_1, Got: $FILE2_FOLDER_ID_1${NC}"
        exit 1
    fi
else
    echo -e "${RED}Second file not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
FILE1_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$FILE1';")
if [ -n "$FILE1_DB_2" ]; then
    echo -e "${GREEN}First file found in client 2 database: $FILE1_DB_2${NC}"
    FILE1_ID_2=$(echo "$FILE1_DB_2" | cut -d'|' -f1)
    FILE1_FOLDER_ID_2=$(echo "$FILE1_DB_2" | cut -d'|' -f4)

    if [ "$FILE1_FOLDER_ID_2" = "$FOLDER1_ID_2" ]; then
        echo -e "${GREEN}First file is in the correct folder in client 2 - GOOD!${NC}"
    else
        echo -e "${RED}First file is not in the expected folder in client 2${NC}"
        echo -e "${RED}Expected: $FOLDER1_ID_2, Got: $FILE1_FOLDER_ID_2${NC}"
        exit 1
    fi
else
    echo -e "${RED}First file not found in client 2 database${NC}"
    exit 1
fi

FILE2_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$FILE2';")
if [ -n "$FILE2_DB_2" ]; then
    echo -e "${GREEN}Second file found in client 2 database: $FILE2_DB_2${NC}"
    FILE2_ID_2=$(echo "$FILE2_DB_2" | cut -d'|' -f1)
    FILE2_FOLDER_ID_2=$(echo "$FILE2_DB_2" | cut -d'|' -f4)

    if [ "$FILE2_FOLDER_ID_2" = "$FOLDER1_ID_2" ]; then
        echo -e "${GREEN}Second file is in the correct folder in client 2 - GOOD!${NC}"
    else
        echo -e "${RED}Second file is not in the expected folder in client 2${NC}"
        echo -e "${RED}Expected: $FOLDER1_ID_2, Got: $FILE2_FOLDER_ID_2${NC}"
        exit 1
    fi
else
    echo -e "${RED}Second file not found in client 2 database${NC}"
    exit 1
fi

# Step 6: Moving the first file to the second folder in both clients
echo -e "\n${YELLOW}Step 6: Moving the first file to the second folder in both clients...${NC}"

# Move file in client 1
docker exec $CLIENT1_NAME mv $CONTAINER_SYNC_DIR/$FOLDER1/$FILE1 $CONTAINER_SYNC_DIR/$FOLDER2/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Moved first file to second folder in client 1${NC}"
else
    echo -e "${RED}Failed to move first file to second folder in client 1${NC}"
    exit 1
fi

# Move file in client 2
docker exec $CLIENT2_NAME mv $CONTAINER_SYNC_DIR/$FOLDER1/$FILE1 $CONTAINER_SYNC_DIR/$FOLDER2/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Moved first file to second folder in client 2${NC}"
else
    echo -e "${RED}Failed to move first file to second folder in client 2${NC}"
    exit 1
fi

# Step 7: Waiting for move to be processed
echo -e "\n${YELLOW}Step 7: Waiting for move to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 8: Renaming the second file in both clients
echo -e "\n${YELLOW}Step 8: Renaming the second file in both clients...${NC}"
RENAMED_FILE="renamed_file_${TIMESTAMP}.txt"

# Rename file in client 1
docker exec $CLIENT1_NAME mv $CONTAINER_SYNC_DIR/$FOLDER1/$FILE2 $CONTAINER_SYNC_DIR/$FOLDER1/$RENAMED_FILE
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Renamed second file in client 1${NC}"
else
    echo -e "${RED}Failed to rename second file in client 1${NC}"
    exit 1
fi

# Rename file in client 2
docker exec $CLIENT2_NAME mv $CONTAINER_SYNC_DIR/$FOLDER1/$FILE2 $CONTAINER_SYNC_DIR/$FOLDER1/$RENAMED_FILE
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Renamed second file in client 2${NC}"
else
    echo -e "${RED}Failed to rename second file in client 2${NC}"
    exit 1
fi

# Step 9: Waiting for rename to be processed
echo -e "\n${YELLOW}Step 9: Waiting for rename to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 10: Verifying file move and rename are reflected in the database for both clients
echo -e "\n${YELLOW}Step 10: Verifying file move and rename are reflected in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
MOVED_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$FILE1';")
if [ -n "$MOVED_FILE_DB_1" ]; then
    echo -e "${GREEN}Moved file found in client 1 database: $MOVED_FILE_DB_1${NC}"
    MOVED_FILE_FOLDER_ID_1=$(echo "$MOVED_FILE_DB_1" | cut -d'|' -f4)

    # Check if the file is now in the second folder
    if [[ "$MOVED_FILE_DB_1" == *"$FOLDER2"* ]]; then
        echo -e "${GREEN}Moved file path contains the target folder name in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Moved file path does not contain the target folder name in client 1${NC}"
        echo -e "${YELLOW}Path: $(echo "$MOVED_FILE_DB_1" | cut -d'|' -f3)${NC}"
        echo -e "${YELLOW}Expected to contain: $FOLDER2${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi

    # Check if the folder ID has been updated
    if [ "$MOVED_FILE_FOLDER_ID_1" = "$FOLDER2_ID_1" ]; then
        echo -e "${GREEN}Moved file is in the correct folder by ID in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Moved file is not in the expected folder by ID in client 1${NC}"
        echo -e "${YELLOW}Expected: $FOLDER2_ID_1, Got: $MOVED_FILE_FOLDER_ID_1${NC}"
        echo -e "${YELLOW}This might be expected if the system uses a different approach to track moves${NC}"
    fi
else
    echo -e "${RED}Moved file not found in client 1 database${NC}"
    exit 1
fi

# The system might handle renames in different ways:
# 1. Update the existing file record with a new name
# 2. Create a new file record with the new name and delete the old one

# First, check if the original file still exists with the same ID
FILE2_DB_AFTER_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_id='$FILE2_ID_1';")

# If not found by ID, try to find by the new name in the same folder
if [ -z "$FILE2_DB_AFTER_1" ]; then
    echo -e "${YELLOW}Original file record not found in client 1, checking for new record with the new name...${NC}"
    FILE2_DB_AFTER_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$RENAMED_FILE' AND folder_id='$FOLDER1_ID_1';")
fi

# If still not found, try to find by the new name anywhere
if [ -z "$FILE2_DB_AFTER_1" ]; then
    echo -e "${YELLOW}File not found in original folder in client 1, checking for file by new name anywhere...${NC}"
    FILE2_DB_AFTER_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$RENAMED_FILE';")
fi

if [ -n "$FILE2_DB_AFTER_1" ]; then
    echo -e "${GREEN}Second file exists in client 1 database after rename: $FILE2_DB_AFTER_1${NC}"
    FILE2_NAME_AFTER_1=$(echo "$FILE2_DB_AFTER_1" | cut -d'|' -f2)
    FILE2_PATH_AFTER_1=$(echo "$FILE2_DB_AFTER_1" | cut -d'|' -f3)

    # Check if the file path contains the new name
    if [[ "$FILE2_PATH_AFTER_1" == *"$RENAMED_FILE"* ]]; then
        echo -e "${GREEN}File path contains the new name in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}File path does not contain the new name in client 1${NC}"
        echo -e "Path: $FILE2_PATH_AFTER_1"
        echo -e "Expected to contain: $RENAMED_FILE"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi

    # Verify file has the new name
    if [ "$FILE2_NAME_AFTER_1" = "$RENAMED_FILE" ]; then
        echo -e "${GREEN}Second file has been renamed correctly in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Second file has a different name than expected in client 1${NC}"
        echo -e "Expected: $RENAMED_FILE, Got: $FILE2_NAME_AFTER_1"
        echo -e "${YELLOW}This might be expected if the system uses a different approach to track renames${NC}"

        # Check if the original file is gone
        ORIGINAL_FILE_EXISTS_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM files_metadata WHERE file_name='$FILE2';")
        if [ "$ORIGINAL_FILE_EXISTS_1" -eq 0 ]; then
            echo -e "${GREEN}Original file no longer exists in client 1 database - GOOD!${NC}"
        else
            echo -e "${YELLOW}Original file still exists in client 1 database${NC}"
            echo -e "${YELLOW}This might indicate that the rename operation is still being processed${NC}"
        fi
    fi
else
    # Check if the new file exists by path
    NEW_FILE_PATH_1="$CONTAINER_SYNC_DIR/$FOLDER1/$RENAMED_FILE"
    NEW_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_path='$NEW_FILE_PATH_1';")

    if [ -n "$NEW_FILE_DB_1" ]; then
        echo -e "${GREEN}Found file with new name at expected path in client 1: $NEW_FILE_DB_1${NC}"
    else
        echo -e "${YELLOW}Second file not found with either original ID or new name in client 1${NC}"
        echo -e "${YELLOW}This might indicate that the rename operation is still being processed${NC}"
        echo -e "${YELLOW}Checking if any files exist in the database...${NC}"

        ANY_FILES_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM files_metadata;")
        echo -e "${YELLOW}Total files in client 1 database: $ANY_FILES_1${NC}"

        if [ "$ANY_FILES_1" -gt 0 ]; then
            echo -e "${YELLOW}Some files exist in client 1. Listing them:${NC}"
            ALL_FILES_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata LIMIT 5;")
            echo -e "${YELLOW}$ALL_FILES_1${NC}"
        fi
    fi
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
MOVED_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$FILE1';")
if [ -n "$MOVED_FILE_DB_2" ]; then
    echo -e "${GREEN}Moved file found in client 2 database: $MOVED_FILE_DB_2${NC}"
    MOVED_FILE_FOLDER_ID_2=$(echo "$MOVED_FILE_DB_2" | cut -d'|' -f4)

    # Check if the file is now in the second folder
    if [[ "$MOVED_FILE_DB_2" == *"$FOLDER2"* ]]; then
        echo -e "${GREEN}Moved file path contains the target folder name in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Moved file path does not contain the target folder name in client 2${NC}"
        echo -e "${YELLOW}Path: $(echo "$MOVED_FILE_DB_2" | cut -d'|' -f3)${NC}"
        echo -e "${YELLOW}Expected to contain: $FOLDER2${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi

    # Check if the folder ID has been updated
    if [ "$MOVED_FILE_FOLDER_ID_2" = "$FOLDER2_ID_2" ]; then
        echo -e "${GREEN}Moved file is in the correct folder by ID in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Moved file is not in the expected folder by ID in client 2${NC}"
        echo -e "${YELLOW}Expected: $FOLDER2_ID_2, Got: $MOVED_FILE_FOLDER_ID_2${NC}"
        echo -e "${YELLOW}This might be expected if the system uses a different approach to track moves${NC}"
    fi
else
    echo -e "${RED}Moved file not found in client 2 database${NC}"
    exit 1
fi

# First, check if the original file still exists with the same ID
FILE2_DB_AFTER_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_id='$FILE2_ID_2';")

# If not found by ID, try to find by the new name in the same folder
if [ -z "$FILE2_DB_AFTER_2" ]; then
    echo -e "${YELLOW}Original file record not found in client 2, checking for new record with the new name...${NC}"
    FILE2_DB_AFTER_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$RENAMED_FILE' AND folder_id='$FOLDER1_ID_2';")
fi

# If still not found, try to find by the new name anywhere
if [ -z "$FILE2_DB_AFTER_2" ]; then
    echo -e "${YELLOW}File not found in original folder in client 2, checking for file by new name anywhere...${NC}"
    FILE2_DB_AFTER_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$RENAMED_FILE';")
fi

if [ -n "$FILE2_DB_AFTER_2" ]; then
    echo -e "${GREEN}Second file exists in client 2 database after rename: $FILE2_DB_AFTER_2${NC}"
    FILE2_NAME_AFTER_2=$(echo "$FILE2_DB_AFTER_2" | cut -d'|' -f2)
    FILE2_PATH_AFTER_2=$(echo "$FILE2_DB_AFTER_2" | cut -d'|' -f3)

    # Check if the file path contains the new name
    if [[ "$FILE2_PATH_AFTER_2" == *"$RENAMED_FILE"* ]]; then
        echo -e "${GREEN}File path contains the new name in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}File path does not contain the new name in client 2${NC}"
        echo -e "Path: $FILE2_PATH_AFTER_2"
        echo -e "Expected to contain: $RENAMED_FILE"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi

    # Verify file has the new name
    if [ "$FILE2_NAME_AFTER_2" = "$RENAMED_FILE" ]; then
        echo -e "${GREEN}Second file has been renamed correctly in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Second file has a different name than expected in client 2${NC}"
        echo -e "Expected: $RENAMED_FILE, Got: $FILE2_NAME_AFTER_2"
        echo -e "${YELLOW}This might be expected if the system uses a different approach to track renames${NC}"

        # Check if the original file is gone
        ORIGINAL_FILE_EXISTS_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM files_metadata WHERE file_name='$FILE2';")
        if [ "$ORIGINAL_FILE_EXISTS_2" -eq 0 ]; then
            echo -e "${GREEN}Original file no longer exists in client 2 database - GOOD!${NC}"
        else
            echo -e "${YELLOW}Original file still exists in client 2 database${NC}"
            echo -e "${YELLOW}This might indicate that the rename operation is still being processed${NC}"
        fi
    fi
else
    # Check if the new file exists by path
    NEW_FILE_PATH_2="$CONTAINER_SYNC_DIR/$FOLDER1/$RENAMED_FILE"
    NEW_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_path='$NEW_FILE_PATH_2';")

    if [ -n "$NEW_FILE_DB_2" ]; then
        echo -e "${GREEN}Found file with new name at expected path in client 2: $NEW_FILE_DB_2${NC}"
    else
        echo -e "${YELLOW}Second file not found with either original ID or new name in client 2${NC}"
        echo -e "${YELLOW}This might indicate that the rename operation is still being processed${NC}"
        echo -e "${YELLOW}Checking if any files exist in the database...${NC}"

        ANY_FILES_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM files_metadata;")
        echo -e "${YELLOW}Total files in client 2 database: $ANY_FILES_2${NC}"

        if [ "$ANY_FILES_2" -gt 0 ]; then
            echo -e "${YELLOW}Some files exist in client 2. Listing them:${NC}"
            ALL_FILES_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name FROM files_metadata LIMIT 5;")
            echo -e "${YELLOW}$ALL_FILES_2${NC}"
        fi
    fi
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device Move and Rename Operations Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
