#!/bin/bash
# Script to execute SQL files against the Dropbox SQLite database

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox SQL Query Runner${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if container is running
if ! docker ps | grep -q dropbox-client; then
    echo -e "${RED}Error: dropbox-client container is not running${NC}"
    echo -e "Please start the container first with: ./deployment/docker/spin_up_client.sh"
    exit 1
fi

# SQL directory path
SQL_DIR="client/scripts/sql"

# Function to execute a single SQL file
execute_sql_file() {
    local sql_file="$1"
    local filename=$(basename "$sql_file")
    
    echo -e "${YELLOW}Executing SQL file: ${filename}${NC}"
    
    # Copy SQL file to container
    docker cp "$sql_file" dropbox-client:/tmp/
    
    # Execute SQL file against the database
    docker exec dropbox-client sqlite3 /app/data/dropbox.db ".read /tmp/$filename"
    
    # Check execution status
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully executed: $filename${NC}"
    else
        echo -e "${RED}Failed to execute: $filename${NC}"
    fi
    
    # Clean up
    docker exec dropbox-client rm /tmp/$filename
}

# Check if a specific SQL file was provided
if [ $# -eq 1 ]; then
    # Check if file exists
    if [ -f "$1" ]; then
        execute_sql_file "$1"
    else
        echo -e "${RED}Error: SQL file not found: $1${NC}"
        exit 1
    fi
else
    # Execute all SQL files in the directory
    echo -e "${YELLOW}Executing all SQL files in $SQL_DIR${NC}"
    
    # Check if SQL directory exists
    if [ ! -d "$SQL_DIR" ]; then
        echo -e "${RED}Error: SQL directory not found: $SQL_DIR${NC}"
        exit 1
    fi
    
    # Count SQL files
    SQL_FILES=$(find "$SQL_DIR" -name "*.sql" | wc -l)
    
    if [ "$SQL_FILES" -eq 0 ]; then
        echo -e "${YELLOW}No SQL files found in $SQL_DIR${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}Found $SQL_FILES SQL files${NC}"
    
    # Execute each SQL file
    find "$SQL_DIR" -name "*.sql" | sort | while read -r file; do
        execute_sql_file "$file"
    done
fi

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}SQL execution complete${NC}"
echo -e "${BLUE}=========================================${NC}"
