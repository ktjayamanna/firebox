#!/bin/bash
# Smoke test for file synchronization

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox File Sync Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q dropbox-client; then
    echo -e "${RED}Error: dropbox-client container is not running${NC}"
    echo -e "Please start the container first with: cd deployment/docker && docker-compose up -d"
    exit 1
fi

# Define paths
MOCK_DATA_DIR="client/tests/mock_data"
CONTAINER_SYNC_DIR="/app/my_dropbox"

# Step 1: Copy mock data to the sync folder
echo -e "\n${YELLOW}Step 1: Copying mock data to sync folder...${NC}"
find "$MOCK_DATA_DIR" -type f | while read -r file; do
    rel_path=${file#"$MOCK_DATA_DIR/"}
    dir_path=$(dirname "$rel_path")
    
    # Create directory structure if needed
    if [ "$dir_path" != "." ]; then
        echo -e "Creating directory: $dir_path in container"
        docker exec dropbox-client mkdir -p "$CONTAINER_SYNC_DIR/$dir_path"
    fi
    
    # Copy the file
    echo -e "Copying: $rel_path"
    docker cp "$file" "dropbox-client:$CONTAINER_SYNC_DIR/$rel_path"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully copied: $rel_path${NC}"
    else
        echo -e "${RED}Failed to copy: $rel_path${NC}"
    fi
done

# Step 2: Wait for files to be processed
echo -e "\n${YELLOW}Step 2: Waiting for files to be processed (5 seconds)...${NC}"
sleep 5

# Step 3: Check if files are in the database
echo -e "\n${YELLOW}Step 3: Checking if files are in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata;" | grep -q "small_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}small_file.txt found in database${NC}"
else
    echo -e "${RED}small_file.txt not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata;" | grep -q "medium_file.bin"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}medium_file.bin found in database${NC}"
else
    echo -e "${RED}medium_file.bin not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata;" | grep -q "nested_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}nested_file.txt found in database${NC}"
else
    echo -e "${RED}nested_file.txt not found in database${NC}"
fi

# Step 4: Check if folders are in the database
echo -e "\n${YELLOW}Step 4: Checking if folders are in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name, folder_path FROM folders;" | grep -q "nested_folder"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}nested_folder found in database${NC}"
else
    echo -e "${RED}nested_folder not found in database${NC}"
fi

# Step 5: Create a new file directly in the container
echo -e "\n${YELLOW}Step 5: Creating a new file directly in the container...${NC}"
docker exec dropbox-client bash -c "echo 'This is a new file created inside the container' > $CONTAINER_SYNC_DIR/container_created_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created container_created_file.txt${NC}"
else
    echo -e "${RED}Failed to create container_created_file.txt${NC}"
fi

# Step 6: Create a new folder directly in the container
echo -e "\n${YELLOW}Step 6: Creating a new folder directly in the container...${NC}"
docker exec dropbox-client bash -c "mkdir -p $CONTAINER_SYNC_DIR/container_created_folder && echo 'File in new folder' > $CONTAINER_SYNC_DIR/container_created_folder/folder_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created container_created_folder and folder_file.txt${NC}"
else
    echo -e "${RED}Failed to create container_created_folder and folder_file.txt${NC}"
fi

# Step 7: Wait for new files to be processed
echo -e "\n${YELLOW}Step 7: Waiting for new files to be processed (5 seconds)...${NC}"
sleep 5

# Step 8: Check if new files are in the database
echo -e "\n${YELLOW}Step 8: Checking if new files are in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata;" | grep -q "container_created_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}container_created_file.txt found in database${NC}"
else
    echo -e "${RED}container_created_file.txt not found in database${NC}"
fi

docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata;" | grep -q "folder_file.txt"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}folder_file.txt found in database${NC}"
else
    echo -e "${RED}folder_file.txt not found in database${NC}"
fi

# Step 9: Check if new folder is in the database
echo -e "\n${YELLOW}Step 9: Checking if new folder is in the database...${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name, folder_path FROM folders;" | grep -q "container_created_folder"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}container_created_folder found in database${NC}"
else
    echo -e "${RED}container_created_folder not found in database${NC}"
fi

# Step 10: Display all files and folders in the database
echo -e "\n${YELLOW}Step 10: Displaying all files in the database...${NC}"
echo -e "${BLUE}Files:${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT file_name, file_path FROM files_metadata;"

echo -e "\n${BLUE}Folders:${NC}"
docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT folder_name, folder_path FROM folders;"

echo -e "\n${GREEN}Smoke test completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
