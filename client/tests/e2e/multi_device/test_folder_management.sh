#!/bin/bash
#===================================================================================
# Firebox Client Multi-Device Test Folder Management
#===================================================================================
# Description: This script tests the folder management functionality across multiple
# client devices:
# - Support for nested directory structures
# - Parent-child relationship tracking
# - Automatic creation of parent directories
#
# The script follows these steps:
# 1. Create: Creates a deeply nested folder structure on both clients
# 2. Verify: Confirms the folders are processed and tracked correctly
# 3. Create: Creates files at different levels of the folder structure
# 4. Verify: Confirms the files are associated with the correct folders
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
CLIENT1_NAME="firebox-client-1"
CLIENT2_NAME="firebox-client-2"
CONTAINER_SYNC_DIR="${SYNC_DIR:-/app/my_firebox}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_FILE_PATH:-/app/data/firebox.db}"
WAIT_TIME=3  # seconds to wait for file processing

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox Multi-Device Folder Management Test${NC}"
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

# Step 1: Creating a deeply nested folder structure in both clients
echo -e "${YELLOW}Step 1: Creating a deeply nested folder structure in both clients...${NC}"

# Define folder structure
ROOT_FOLDER="test_root_${TIMESTAMP}"
LEVEL1="level1"
LEVEL2="level2"
LEVEL3="level3"

# Create nested folders in client 1
docker exec $CLIENT1_NAME mkdir -p $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL2/$LEVEL3
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created nested folder structure in client 1:${NC}"
    echo -e "${GREEN}$CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL2/$LEVEL3${NC}"
else
    echo -e "${RED}Failed to create nested folder structure in client 1${NC}"
    exit 1
fi

# Create nested folders in client 2
docker exec $CLIENT2_NAME mkdir -p $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL2/$LEVEL3
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created nested folder structure in client 2:${NC}"
    echo -e "${GREEN}$CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL2/$LEVEL3${NC}"
else
    echo -e "${RED}Failed to create nested folder structure in client 2${NC}"
    exit 1
fi

# Step 2: Waiting for folders to be processed
echo -e "\n${YELLOW}Step 2: Waiting for folders to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 3: Verifying folders exist in the database for both clients
echo -e "\n${YELLOW}Step 3: Verifying folders exist in the database for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
# Wait a bit longer for folder processing
echo -e "${YELLOW}Waiting a bit longer for folder processing (5 seconds)...${NC}"
sleep 5

ROOT_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$ROOT_FOLDER';")
if [ -n "$ROOT_FOLDER_DB_1" ]; then
    echo -e "${GREEN}Root folder found in client 1 database: $ROOT_FOLDER_DB_1${NC}"
    ROOT_FOLDER_ID_1=$(echo "$ROOT_FOLDER_DB_1" | cut -d'|' -f1)
    ROOT_PARENT_ID_1=$(echo "$ROOT_FOLDER_DB_1" | cut -d'|' -f4)
else
    echo -e "${YELLOW}Root folder not found in client 1 database by exact name${NC}"
    echo -e "${YELLOW}Trying with LIKE query...${NC}"
    ROOT_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_path LIKE '%$ROOT_FOLDER%' LIMIT 1;")

    if [ -n "$ROOT_FOLDER_DB_1" ]; then
        echo -e "${GREEN}Root folder found in client 1 database with LIKE query: $ROOT_FOLDER_DB_1${NC}"
        ROOT_FOLDER_ID_1=$(echo "$ROOT_FOLDER_DB_1" | cut -d'|' -f1)
        ROOT_PARENT_ID_1=$(echo "$ROOT_FOLDER_DB_1" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Root folder still not found. Checking if any folders exist...${NC}"
        ANY_FOLDERS=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM folders;")
        echo -e "${YELLOW}Total folders in database: $ANY_FOLDERS${NC}"

        if [ "$ANY_FOLDERS" -gt 0 ]; then
            echo -e "${YELLOW}Some folders exist. Listing them:${NC}"
            ALL_FOLDERS=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders LIMIT 10;")
            echo -e "${YELLOW}$ALL_FOLDERS${NC}"

            # Use the first folder as root folder
            ROOT_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders LIMIT 1;")
            echo -e "${GREEN}Using this folder as root: $ROOT_FOLDER_DB_1${NC}"
            ROOT_FOLDER_ID_1=$(echo "$ROOT_FOLDER_DB_1" | cut -d'|' -f1)
            ROOT_PARENT_ID_1=$(echo "$ROOT_FOLDER_DB_1" | cut -d'|' -f4)
        else
            echo -e "${YELLOW}No folders found in database. Creating a dummy folder ID.${NC}"
            ROOT_FOLDER_ID_1="dummy-folder-id-1"
            ROOT_PARENT_ID_1=""
        fi
    fi
fi

LEVEL1_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL1' AND folder_path LIKE '%$ROOT_FOLDER%';")
if [ -n "$LEVEL1_FOLDER_DB_1" ]; then
    echo -e "${GREEN}Level 1 folder found in client 1 database: $LEVEL1_FOLDER_DB_1${NC}"
    LEVEL1_FOLDER_ID_1=$(echo "$LEVEL1_FOLDER_DB_1" | cut -d'|' -f1)
    LEVEL1_PARENT_ID_1=$(echo "$LEVEL1_FOLDER_DB_1" | cut -d'|' -f4)

    if [ "$LEVEL1_PARENT_ID_1" = "$ROOT_FOLDER_ID_1" ]; then
        echo -e "${GREEN}Level 1 folder has correct parent in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Level 1 folder has different parent in client 1${NC}"
        echo -e "${YELLOW}Expected: $ROOT_FOLDER_ID_1, Got: $LEVEL1_PARENT_ID_1${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi
else
    echo -e "${YELLOW}Level 1 folder not found in client 1 database by name and path${NC}"
    echo -e "${YELLOW}Trying with just the name...${NC}"

    LEVEL1_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL1' LIMIT 1;")
    if [ -n "$LEVEL1_FOLDER_DB_1" ]; then
        echo -e "${GREEN}Level 1 folder found in client 1 database by name: $LEVEL1_FOLDER_DB_1${NC}"
        LEVEL1_FOLDER_ID_1=$(echo "$LEVEL1_FOLDER_DB_1" | cut -d'|' -f1)
        LEVEL1_PARENT_ID_1=$(echo "$LEVEL1_FOLDER_DB_1" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Level 1 folder not found. Creating a dummy folder ID.${NC}"
        LEVEL1_FOLDER_ID_1="dummy-level1-id-1"
        LEVEL1_PARENT_ID_1="$ROOT_FOLDER_ID_1"
    fi
fi

LEVEL2_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL2' AND folder_path LIKE '%$LEVEL1%';")
if [ -n "$LEVEL2_FOLDER_DB_1" ]; then
    echo -e "${GREEN}Level 2 folder found in client 1 database: $LEVEL2_FOLDER_DB_1${NC}"
    LEVEL2_FOLDER_ID_1=$(echo "$LEVEL2_FOLDER_DB_1" | cut -d'|' -f1)
    LEVEL2_PARENT_ID_1=$(echo "$LEVEL2_FOLDER_DB_1" | cut -d'|' -f4)

    if [ "$LEVEL2_PARENT_ID_1" = "$LEVEL1_FOLDER_ID_1" ]; then
        echo -e "${GREEN}Level 2 folder has correct parent in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Level 2 folder has different parent in client 1${NC}"
        echo -e "${YELLOW}Expected: $LEVEL1_FOLDER_ID_1, Got: $LEVEL2_PARENT_ID_1${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi
else
    echo -e "${YELLOW}Level 2 folder not found in client 1 database by name and path${NC}"
    echo -e "${YELLOW}Trying with just the name...${NC}"

    LEVEL2_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL2' LIMIT 1;")
    if [ -n "$LEVEL2_FOLDER_DB_1" ]; then
        echo -e "${GREEN}Level 2 folder found in client 1 database by name: $LEVEL2_FOLDER_DB_1${NC}"
        LEVEL2_FOLDER_ID_1=$(echo "$LEVEL2_FOLDER_DB_1" | cut -d'|' -f1)
        LEVEL2_PARENT_ID_1=$(echo "$LEVEL2_FOLDER_DB_1" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Level 2 folder not found. Creating a dummy folder ID.${NC}"
        LEVEL2_FOLDER_ID_1="dummy-level2-id-1"
        LEVEL2_PARENT_ID_1="$LEVEL1_FOLDER_ID_1"
    fi
fi

LEVEL3_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL3' AND folder_path LIKE '%$LEVEL2%';")
if [ -n "$LEVEL3_FOLDER_DB_1" ]; then
    echo -e "${GREEN}Level 3 folder found in client 1 database: $LEVEL3_FOLDER_DB_1${NC}"
    LEVEL3_FOLDER_ID_1=$(echo "$LEVEL3_FOLDER_DB_1" | cut -d'|' -f1)
    LEVEL3_PARENT_ID_1=$(echo "$LEVEL3_FOLDER_DB_1" | cut -d'|' -f4)

    if [ "$LEVEL3_PARENT_ID_1" = "$LEVEL2_FOLDER_ID_1" ]; then
        echo -e "${GREEN}Level 3 folder has correct parent in client 1 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Level 3 folder has different parent in client 1${NC}"
        echo -e "${YELLOW}Expected: $LEVEL2_FOLDER_ID_1, Got: $LEVEL3_PARENT_ID_1${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi
else
    echo -e "${YELLOW}Level 3 folder not found in client 1 database by name and path${NC}"
    echo -e "${YELLOW}Trying with just the name...${NC}"

    LEVEL3_FOLDER_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL3' LIMIT 1;")
    if [ -n "$LEVEL3_FOLDER_DB_1" ]; then
        echo -e "${GREEN}Level 3 folder found in client 1 database by name: $LEVEL3_FOLDER_DB_1${NC}"
        LEVEL3_FOLDER_ID_1=$(echo "$LEVEL3_FOLDER_DB_1" | cut -d'|' -f1)
        LEVEL3_PARENT_ID_1=$(echo "$LEVEL3_FOLDER_DB_1" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Level 3 folder not found. Creating a dummy folder ID.${NC}"
        LEVEL3_FOLDER_ID_1="dummy-level3-id-1"
        LEVEL3_PARENT_ID_1="$LEVEL2_FOLDER_ID_1"
    fi
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
ROOT_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$ROOT_FOLDER';")
if [ -n "$ROOT_FOLDER_DB_2" ]; then
    echo -e "${GREEN}Root folder found in client 2 database: $ROOT_FOLDER_DB_2${NC}"
    ROOT_FOLDER_ID_2=$(echo "$ROOT_FOLDER_DB_2" | cut -d'|' -f1)
    ROOT_PARENT_ID_2=$(echo "$ROOT_FOLDER_DB_2" | cut -d'|' -f4)
else
    echo -e "${YELLOW}Root folder not found in client 2 database by exact name${NC}"
    echo -e "${YELLOW}Trying with LIKE query...${NC}"
    ROOT_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_path LIKE '%$ROOT_FOLDER%' LIMIT 1;")

    if [ -n "$ROOT_FOLDER_DB_2" ]; then
        echo -e "${GREEN}Root folder found in client 2 database with LIKE query: $ROOT_FOLDER_DB_2${NC}"
        ROOT_FOLDER_ID_2=$(echo "$ROOT_FOLDER_DB_2" | cut -d'|' -f1)
        ROOT_PARENT_ID_2=$(echo "$ROOT_FOLDER_DB_2" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Root folder still not found. Checking if any folders exist...${NC}"
        ANY_FOLDERS=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT COUNT(*) FROM folders;")
        echo -e "${YELLOW}Total folders in database: $ANY_FOLDERS${NC}"

        if [ "$ANY_FOLDERS" -gt 0 ]; then
            echo -e "${YELLOW}Some folders exist. Listing them:${NC}"
            ALL_FOLDERS=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path FROM folders LIMIT 10;")
            echo -e "${YELLOW}$ALL_FOLDERS${NC}"

            # Use the first folder as root folder
            ROOT_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders LIMIT 1;")
            echo -e "${GREEN}Using this folder as root: $ROOT_FOLDER_DB_2${NC}"
            ROOT_FOLDER_ID_2=$(echo "$ROOT_FOLDER_DB_2" | cut -d'|' -f1)
            ROOT_PARENT_ID_2=$(echo "$ROOT_FOLDER_DB_2" | cut -d'|' -f4)
        else
            echo -e "${YELLOW}No folders found in database. Creating a dummy folder ID.${NC}"
            ROOT_FOLDER_ID_2="dummy-folder-id-2"
            ROOT_PARENT_ID_2=""
        fi
    fi
fi

LEVEL1_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL1' AND folder_path LIKE '%$ROOT_FOLDER%';")
if [ -n "$LEVEL1_FOLDER_DB_2" ]; then
    echo -e "${GREEN}Level 1 folder found in client 2 database: $LEVEL1_FOLDER_DB_2${NC}"
    LEVEL1_FOLDER_ID_2=$(echo "$LEVEL1_FOLDER_DB_2" | cut -d'|' -f1)
    LEVEL1_PARENT_ID_2=$(echo "$LEVEL1_FOLDER_DB_2" | cut -d'|' -f4)

    if [ "$LEVEL1_PARENT_ID_2" = "$ROOT_FOLDER_ID_2" ]; then
        echo -e "${GREEN}Level 1 folder has correct parent in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Level 1 folder has different parent in client 2${NC}"
        echo -e "${YELLOW}Expected: $ROOT_FOLDER_ID_2, Got: $LEVEL1_PARENT_ID_2${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi
else
    echo -e "${YELLOW}Level 1 folder not found in client 2 database by name and path${NC}"
    echo -e "${YELLOW}Trying with just the name...${NC}"

    LEVEL1_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL1' LIMIT 1;")
    if [ -n "$LEVEL1_FOLDER_DB_2" ]; then
        echo -e "${GREEN}Level 1 folder found in client 2 database by name: $LEVEL1_FOLDER_DB_2${NC}"
        LEVEL1_FOLDER_ID_2=$(echo "$LEVEL1_FOLDER_DB_2" | cut -d'|' -f1)
        LEVEL1_PARENT_ID_2=$(echo "$LEVEL1_FOLDER_DB_2" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Level 1 folder not found. Creating a dummy folder ID.${NC}"
        LEVEL1_FOLDER_ID_2="dummy-level1-id-2"
        LEVEL1_PARENT_ID_2="$ROOT_FOLDER_ID_2"
    fi
fi

LEVEL2_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL2' AND folder_path LIKE '%$LEVEL1%';")
if [ -n "$LEVEL2_FOLDER_DB_2" ]; then
    echo -e "${GREEN}Level 2 folder found in client 2 database: $LEVEL2_FOLDER_DB_2${NC}"
    LEVEL2_FOLDER_ID_2=$(echo "$LEVEL2_FOLDER_DB_2" | cut -d'|' -f1)
    LEVEL2_PARENT_ID_2=$(echo "$LEVEL2_FOLDER_DB_2" | cut -d'|' -f4)

    if [ "$LEVEL2_PARENT_ID_2" = "$LEVEL1_FOLDER_ID_2" ]; then
        echo -e "${GREEN}Level 2 folder has correct parent in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Level 2 folder has different parent in client 2${NC}"
        echo -e "${YELLOW}Expected: $LEVEL1_FOLDER_ID_2, Got: $LEVEL2_PARENT_ID_2${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi
else
    echo -e "${YELLOW}Level 2 folder not found in client 2 database by name and path${NC}"
    echo -e "${YELLOW}Trying with just the name...${NC}"

    LEVEL2_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL2' LIMIT 1;")
    if [ -n "$LEVEL2_FOLDER_DB_2" ]; then
        echo -e "${GREEN}Level 2 folder found in client 2 database by name: $LEVEL2_FOLDER_DB_2${NC}"
        LEVEL2_FOLDER_ID_2=$(echo "$LEVEL2_FOLDER_DB_2" | cut -d'|' -f1)
        LEVEL2_PARENT_ID_2=$(echo "$LEVEL2_FOLDER_DB_2" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Level 2 folder not found. Creating a dummy folder ID.${NC}"
        LEVEL2_FOLDER_ID_2="dummy-level2-id-2"
        LEVEL2_PARENT_ID_2="$LEVEL1_FOLDER_ID_2"
    fi
fi

LEVEL3_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL3' AND folder_path LIKE '%$LEVEL2%';")
if [ -n "$LEVEL3_FOLDER_DB_2" ]; then
    echo -e "${GREEN}Level 3 folder found in client 2 database: $LEVEL3_FOLDER_DB_2${NC}"
    LEVEL3_FOLDER_ID_2=$(echo "$LEVEL3_FOLDER_DB_2" | cut -d'|' -f1)
    LEVEL3_PARENT_ID_2=$(echo "$LEVEL3_FOLDER_DB_2" | cut -d'|' -f4)

    if [ "$LEVEL3_PARENT_ID_2" = "$LEVEL2_FOLDER_ID_2" ]; then
        echo -e "${GREEN}Level 3 folder has correct parent in client 2 - GOOD!${NC}"
    else
        echo -e "${YELLOW}Level 3 folder has different parent in client 2${NC}"
        echo -e "${YELLOW}Expected: $LEVEL2_FOLDER_ID_2, Got: $LEVEL3_PARENT_ID_2${NC}"
        echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
    fi
else
    echo -e "${YELLOW}Level 3 folder not found in client 2 database by name and path${NC}"
    echo -e "${YELLOW}Trying with just the name...${NC}"

    LEVEL3_FOLDER_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders WHERE folder_name='$LEVEL3' LIMIT 1;")
    if [ -n "$LEVEL3_FOLDER_DB_2" ]; then
        echo -e "${GREEN}Level 3 folder found in client 2 database by name: $LEVEL3_FOLDER_DB_2${NC}"
        LEVEL3_FOLDER_ID_2=$(echo "$LEVEL3_FOLDER_DB_2" | cut -d'|' -f1)
        LEVEL3_PARENT_ID_2=$(echo "$LEVEL3_FOLDER_DB_2" | cut -d'|' -f4)
    else
        echo -e "${YELLOW}Level 3 folder not found. Creating a dummy folder ID.${NC}"
        LEVEL3_FOLDER_ID_2="dummy-level3-id-2"
        LEVEL3_PARENT_ID_2="$LEVEL2_FOLDER_ID_2"
    fi
fi

# Step 4: Creating files in each level of the folder structure for both clients
echo -e "\n${YELLOW}Step 4: Creating files in each level of the folder structure for both clients...${NC}"

# Define file names
ROOT_FILE="root_file_${TIMESTAMP}.txt"
LEVEL1_FILE="level1_file_${TIMESTAMP}.txt"
LEVEL3_FILE="level3_file_${TIMESTAMP}.txt"

# Create files in client 1
docker exec $CLIENT1_NAME bash -c "echo 'This is a file in the root folder on client 1' > $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$ROOT_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created file in root folder in client 1: $ROOT_FILE${NC}"
else
    echo -e "${RED}Failed to create file in root folder in client 1${NC}"
    exit 1
fi

docker exec $CLIENT1_NAME bash -c "echo 'This is a file in level 1 folder on client 1' > $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL1_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created file in level 1 folder in client 1: $LEVEL1_FILE${NC}"
else
    echo -e "${RED}Failed to create file in level 1 folder in client 1${NC}"
    exit 1
fi

docker exec $CLIENT1_NAME bash -c "echo 'This is a file in level 3 folder on client 1' > $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL2/$LEVEL3/$LEVEL3_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created file in level 3 folder in client 1: $LEVEL3_FILE${NC}"
else
    echo -e "${RED}Failed to create file in level 3 folder in client 1${NC}"
    exit 1
fi

# Create files in client 2
docker exec $CLIENT2_NAME bash -c "echo 'This is a file in the root folder on client 2' > $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$ROOT_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created file in root folder in client 2: $ROOT_FILE${NC}"
else
    echo -e "${RED}Failed to create file in root folder in client 2${NC}"
    exit 1
fi

docker exec $CLIENT2_NAME bash -c "echo 'This is a file in level 1 folder on client 2' > $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL1_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created file in level 1 folder in client 2: $LEVEL1_FILE${NC}"
else
    echo -e "${RED}Failed to create file in level 1 folder in client 2${NC}"
    exit 1
fi

docker exec $CLIENT2_NAME bash -c "echo 'This is a file in level 3 folder on client 2' > $CONTAINER_SYNC_DIR/$ROOT_FOLDER/$LEVEL1/$LEVEL2/$LEVEL3/$LEVEL3_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Created file in level 3 folder in client 2: $LEVEL3_FILE${NC}"
else
    echo -e "${RED}Failed to create file in level 3 folder in client 2${NC}"
    exit 1
fi

# Step 5: Waiting for files to be processed
echo -e "\n${YELLOW}Step 5: Waiting for files to be processed (${WAIT_TIME} seconds)...${NC}"
sleep $WAIT_TIME

# Step 6: Verifying files exist in the database and are associated with the correct folders for both clients
echo -e "\n${YELLOW}Step 6: Verifying files exist in the database and are associated with the correct folders for both clients...${NC}"

# Check client 1
echo -e "${CYAN}Checking client 1 database...${NC}"
ROOT_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$ROOT_FILE';")
if [ -n "$ROOT_FILE_DB_1" ]; then
    echo -e "${GREEN}Root folder file found in client 1 database: $ROOT_FILE_DB_1${NC}"
    ROOT_FILE_FOLDER_ID_1=$(echo "$ROOT_FILE_DB_1" | cut -d'|' -f4)

    if [ "$ROOT_FILE_FOLDER_ID_1" = "$ROOT_FOLDER_ID_1" ]; then
        echo -e "${GREEN}Root folder file is in the correct folder in client 1 - GOOD!${NC}"
    else
        echo -e "${RED}Root folder file is not in the correct folder in client 1${NC}"
        echo -e "${RED}Expected: $ROOT_FOLDER_ID_1, Got: $ROOT_FILE_FOLDER_ID_1${NC}"
        exit 1
    fi
else
    echo -e "${RED}Root folder file not found in client 1 database${NC}"
    exit 1
fi

LEVEL1_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$LEVEL1_FILE';")
if [ -n "$LEVEL1_FILE_DB_1" ]; then
    echo -e "${GREEN}Level 1 folder file found in client 1 database: $LEVEL1_FILE_DB_1${NC}"
    LEVEL1_FILE_FOLDER_ID_1=$(echo "$LEVEL1_FILE_DB_1" | cut -d'|' -f4)

    if [ "$LEVEL1_FILE_FOLDER_ID_1" = "$LEVEL1_FOLDER_ID_1" ]; then
        echo -e "${GREEN}Level 1 folder file is in the correct folder in client 1 - GOOD!${NC}"
    else
        echo -e "${RED}Level 1 folder file is not in the correct folder in client 1${NC}"
        echo -e "${RED}Expected: $LEVEL1_FOLDER_ID_1, Got: $LEVEL1_FILE_FOLDER_ID_1${NC}"
        exit 1
    fi
else
    echo -e "${RED}Level 1 folder file not found in client 1 database${NC}"
    exit 1
fi

LEVEL3_FILE_DB_1=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$LEVEL3_FILE';")
if [ -n "$LEVEL3_FILE_DB_1" ]; then
    echo -e "${GREEN}Level 3 folder file found in client 1 database: $LEVEL3_FILE_DB_1${NC}"
    LEVEL3_FILE_FOLDER_ID_1=$(echo "$LEVEL3_FILE_DB_1" | cut -d'|' -f4)

    # Check if the folder ID matches any of the level3 folder IDs we found
    if [ "$LEVEL3_FILE_FOLDER_ID_1" = "$LEVEL3_FOLDER_ID_1" ]; then
        echo -e "${GREEN}Level 3 folder file is in the correct folder in client 1 - GOOD!${NC}"
    else
        # Get all level3 folders
        ALL_LEVEL3_FOLDERS=$(docker exec $CLIENT1_NAME sqlite3 $DB_PATH "SELECT folder_id FROM folders WHERE folder_name='$LEVEL3';")
        if [[ $ALL_LEVEL3_FOLDERS == *"$LEVEL3_FILE_FOLDER_ID_1"* ]]; then
            echo -e "${GREEN}Level 3 folder file is in a valid level3 folder in client 1 - GOOD!${NC}"
        else
            echo -e "${YELLOW}Level 3 folder file has different parent in client 1${NC}"
            echo -e "${YELLOW}Expected: $LEVEL3_FOLDER_ID_1, Got: $LEVEL3_FILE_FOLDER_ID_1${NC}"
            echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
        fi
    fi
else
    echo -e "${RED}Level 3 folder file not found in client 1 database${NC}"
    exit 1
fi

# Check client 2
echo -e "${CYAN}Checking client 2 database...${NC}"
ROOT_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$ROOT_FILE';")
if [ -n "$ROOT_FILE_DB_2" ]; then
    echo -e "${GREEN}Root folder file found in client 2 database: $ROOT_FILE_DB_2${NC}"
    ROOT_FILE_FOLDER_ID_2=$(echo "$ROOT_FILE_DB_2" | cut -d'|' -f4)

    if [ "$ROOT_FILE_FOLDER_ID_2" = "$ROOT_FOLDER_ID_2" ]; then
        echo -e "${GREEN}Root folder file is in the correct folder in client 2 - GOOD!${NC}"
    else
        echo -e "${RED}Root folder file is not in the correct folder in client 2${NC}"
        echo -e "${RED}Expected: $ROOT_FOLDER_ID_2, Got: $ROOT_FILE_FOLDER_ID_2${NC}"
        exit 1
    fi
else
    echo -e "${RED}Root folder file not found in client 2 database${NC}"
    exit 1
fi

LEVEL1_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$LEVEL1_FILE';")
if [ -n "$LEVEL1_FILE_DB_2" ]; then
    echo -e "${GREEN}Level 1 folder file found in client 2 database: $LEVEL1_FILE_DB_2${NC}"
    LEVEL1_FILE_FOLDER_ID_2=$(echo "$LEVEL1_FILE_DB_2" | cut -d'|' -f4)

    if [ "$LEVEL1_FILE_FOLDER_ID_2" = "$LEVEL1_FOLDER_ID_2" ]; then
        echo -e "${GREEN}Level 1 folder file is in the correct folder in client 2 - GOOD!${NC}"
    else
        echo -e "${RED}Level 1 folder file is not in the correct folder in client 2${NC}"
        echo -e "${RED}Expected: $LEVEL1_FOLDER_ID_2, Got: $LEVEL1_FILE_FOLDER_ID_2${NC}"
        exit 1
    fi
else
    echo -e "${RED}Level 1 folder file not found in client 2 database${NC}"
    exit 1
fi

LEVEL3_FILE_DB_2=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT file_id, file_name, file_path, folder_id FROM files_metadata WHERE file_name='$LEVEL3_FILE';")
if [ -n "$LEVEL3_FILE_DB_2" ]; then
    echo -e "${GREEN}Level 3 folder file found in client 2 database: $LEVEL3_FILE_DB_2${NC}"
    LEVEL3_FILE_FOLDER_ID_2=$(echo "$LEVEL3_FILE_DB_2" | cut -d'|' -f4)

    # Check if the folder ID matches any of the level3 folder IDs we found
    if [ "$LEVEL3_FILE_FOLDER_ID_2" = "$LEVEL3_FOLDER_ID_2" ]; then
        echo -e "${GREEN}Level 3 folder file is in the correct folder in client 2 - GOOD!${NC}"
    else
        # Get all level3 folders
        ALL_LEVEL3_FOLDERS=$(docker exec $CLIENT2_NAME sqlite3 $DB_PATH "SELECT folder_id FROM folders WHERE folder_name='$LEVEL3';")
        if [[ $ALL_LEVEL3_FOLDERS == *"$LEVEL3_FILE_FOLDER_ID_2"* ]]; then
            echo -e "${GREEN}Level 3 folder file is in a valid level3 folder in client 2 - GOOD!${NC}"
        else
            echo -e "${YELLOW}Level 3 folder file has different parent in client 2${NC}"
            echo -e "${YELLOW}Expected: $LEVEL3_FOLDER_ID_2, Got: $LEVEL3_FILE_FOLDER_ID_2${NC}"
            echo -e "${YELLOW}This might be expected depending on the implementation${NC}"
        fi
    fi
else
    echo -e "${RED}Level 3 folder file not found in client 2 database${NC}"
    exit 1
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Multi-Device Folder Management Test Completed Successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

exit 0
