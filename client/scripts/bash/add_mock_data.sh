#!/bin/bash
# Script to copy files from data folder to the sync folder in the Docker container

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Copy Files to Dropbox Sync Folder${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q dropbox-client; then
    echo -e "${RED}Error: dropbox-client container is not running${NC}"
    echo -e "Please start the container first with: ./spin_up_client.sh"
    exit 1
fi

# Use data folder as default source directory, or use provided argument
SOURCE_DIR="${1:-./data}"

# Convert to absolute path
SOURCE_DIR=$(realpath "$SOURCE_DIR")

# Debug: List what's actually in the directory
echo -e "${YELLOW}Debugging: Contents of $SOURCE_DIR${NC}"
ls -la "$SOURCE_DIR"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${YELLOW}Warning: Source directory does not exist: $SOURCE_DIR${NC}"
    echo -e "Creating directory..."
    mkdir -p "$SOURCE_DIR"
    echo -e "${GREEN}Created directory: $SOURCE_DIR${NC}"
    echo -e "${YELLOW}Please add files to this directory and run the script again.${NC}"
    exit 0
fi

# Count files in source directory
FILE_COUNT=$(find "$SOURCE_DIR" -type f | wc -l)

if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No files found in $SOURCE_DIR${NC}"
    echo -e "Please add files to this directory and run the script again."
    exit 0
fi

echo -e "${GREEN}Found $FILE_COUNT files in $SOURCE_DIR${NC}"

# Debug: Show what find is returning
echo -e "${YELLOW}Debugging: Files found by find command:${NC}"
find "$SOURCE_DIR" -type f

# Copy files to container
echo -e "${GREEN}Copying files to container...${NC}"
find "$SOURCE_DIR" -type f | while read -r file; do
    filename=$(basename "$file")
    echo -e "Copying: $filename from $file"
    if [ -f "$file" ]; then
        docker cp "$file" dropbox-client:/app/my_dropbox/
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully copied: $filename${NC}"
        else
            echo -e "${RED}Failed to copy: $filename${NC}"
        fi
    else
        echo -e "${RED}File does not exist: $file${NC}"
    fi
done

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Copy operation completed.${NC}"
echo -e "${GREEN}Check the container logs for processing details:${NC}"
echo -e "${BLUE}docker logs dropbox-client${NC}"
echo -e "${BLUE}=========================================${NC}"
