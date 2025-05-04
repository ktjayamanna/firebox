#!/bin/bash
# Script to execute SQL files against the Dropbox SQLite database with improved lock handling

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
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Get environment variables or use defaults
DB_PATH="${DB_FILE_PATH:-/app/data/dropbox.db}"

# SQL directory path
SQL_DIR="client/scripts/sql"

# Function to execute a single SQL file with retry logic
execute_sql_file() {
    local sql_file="$1"
    local filename=$(basename "$sql_file")
    local max_retries=5
    local retry_count=0
    local success=false

    echo -e "${YELLOW}Executing SQL file: ${filename}${NC}"

    # Copy SQL file to container
    docker cp "$sql_file" dropbox-client:/tmp/
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to copy SQL file to container${NC}"
        return 1
    fi
    echo -e "${GREEN}Successfully copied $(stat -c%s "$sql_file")B to dropbox-client:/tmp/${NC}"

    # Add timeout handler to the SQL file
    docker exec dropbox-client bash -c "echo -e '.timeout 10000' > /tmp/${filename}.tmp && cat /tmp/${filename} >> /tmp/${filename}.tmp && mv /tmp/${filename}.tmp /tmp/${filename}"

    # Try to execute the SQL file with retries
    while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
        # Execute SQL file against the database
        output=$(docker exec dropbox-client sqlite3 "$DB_PATH" ".read /tmp/$filename" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}Successfully executed: $filename${NC}"
            echo "$output"
            success=true
        else
            retry_count=$((retry_count + 1))
            if [[ "$output" == *"database is locked"* ]]; then
                echo -e "${YELLOW}Database is locked. Retry $retry_count of $max_retries...${NC}"
                sleep 2
            else
                echo -e "${RED}Failed to execute: $filename${NC}"
                echo -e "${RED}Error: $output${NC}"
                break
            fi
        fi
    done

    # Clean up
    docker exec dropbox-client rm /tmp/$filename

    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
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
