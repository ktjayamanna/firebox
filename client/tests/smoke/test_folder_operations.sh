#!/bin/bash
# Smoke test for folder operations

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Folder Operations Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q dropbox-client; then
    echo -e "${RED}Error: dropbox-client container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Define paths
CONTAINER_SYNC_DIR="/app/my_dropbox"

# Step 1: Create a nested folder structure
echo -e "\n${YELLOW}Step 1: Creating a nested folder structure...${NC}"
docker exec dropbox-client bash -c "mkdir -p $CONTAINER_SYNC_DIR/parent_folder/child_folder/grandchild_folder"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created nested folder structure${NC}"
else
    echo -e "${RED}Failed to create nested folder structure${NC}"
    exit 1
fi

# Step 2: Create files in each folder
echo -e "\n${YELLOW}Step 2: Creating files in each folder...${NC}"
docker exec dropbox-client bash -c "echo 'Parent folder file' > $CONTAINER_SYNC_DIR/parent_folder/parent_file.txt"
docker exec dropbox-client bash -c "echo 'Child folder file' > $CONTAINER_SYNC_DIR/parent_folder/child_folder/child_file.txt"
docker exec dropbox-client bash -c "echo 'Grandchild folder file' > $CONTAINER_SYNC_DIR/parent_folder/child_folder/grandchild_folder/grandchild_file.txt"

# Step 3: Wait for folders and files to be processed
echo -e "\n${YELLOW}Step 3: Waiting for folders and files to be processed (5 seconds)...${NC}"
sleep 5

# Step 4: Check if folders are in the database
echo -e "\n${YELLOW}Step 4: Checking if folders are in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name, folder_path FROM folders WHERE folder_name='parent_folder';" | grep -q "parent_folder"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}parent_folder found in database${NC}"
else
    echo -e "${RED}parent_folder not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name, folder_path FROM folders WHERE folder_name='child_folder';" | grep -q "child_folder"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}child_folder found in database${NC}"
else
    echo -e "${RED}child_folder not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name, folder_path FROM folders WHERE folder_name='grandchild_folder';" | grep -q "grandchild_folder"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}grandchild_folder found in database${NC}"
else
    echo -e "${RED}grandchild_folder not found in database${NC}"
fi

# Step 5: Check if files are in the database
echo -e "\n${YELLOW}Step 5: Checking if files are in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata WHERE file_name='parent_file.txt';" | grep -q "parent_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}parent_file.txt found in database${NC}"
else
    echo -e "${RED}parent_file.txt not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata WHERE file_name='child_file.txt';" | grep -q "child_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}child_file.txt found in database${NC}"
else
    echo -e "${RED}child_file.txt not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata WHERE file_name='grandchild_file.txt';" | grep -q "grandchild_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}grandchild_file.txt found in database${NC}"
else
    echo -e "${RED}grandchild_file.txt not found in database${NC}"
fi

# Step 6: Check folder relationships
echo -e "\n${YELLOW}Step 6: Checking folder relationships...${NC}"
echo -e "${BLUE}Folder structure:${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT f1.folder_name as folder, f2.folder_name as parent FROM folders f1 LEFT JOIN folders f2 ON f1.parent_folder_id = f2.folder_id ORDER BY f2.folder_name, f1.folder_name;"

# Step 7: Create a file in a deeply nested folder
echo -e "\n${YELLOW}Step 7: Creating a new file in a deeply nested folder...${NC}"
docker exec dropbox-client bash -c "mkdir -p $CONTAINER_SYNC_DIR/deep/nested/folder/structure"
docker exec dropbox-client bash -c "echo 'Deeply nested file' > $CONTAINER_SYNC_DIR/deep/nested/folder/structure/deep_file.txt"

# Step 8: Wait for new folders and file to be processed
echo -e "\n${YELLOW}Step 8: Waiting for new folders and file to be processed (5 seconds)...${NC}"
sleep 5

# Step 9: Check if new folders and file are in the database
echo -e "\n${YELLOW}Step 9: Checking if new folders and file are in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name FROM folders WHERE folder_name='structure';" | grep -q "structure"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deepest folder 'structure' found in database${NC}"
else
    echo -e "${RED}Deepest folder 'structure' not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name FROM files_metadata WHERE file_name='deep_file.txt';" | grep -q "deep_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}deep_file.txt found in database${NC}"
else
    echo -e "${RED}deep_file.txt not found in database${NC}"
fi

# Step 10: Display all folders in the database
echo -e "\n${YELLOW}Step 10: Displaying all folders in the database...${NC}"
echo -e "${BLUE}Folders:${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_id, folder_name, folder_path, parent_folder_id FROM folders;"

echo -e "\n${GREEN}Folder operations test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
