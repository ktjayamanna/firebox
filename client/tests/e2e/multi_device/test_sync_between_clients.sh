#!/bin/bash
#===================================================================================
# Multi-Device Sync Test
#===================================================================================
# Description: This script tests the sync functionality between multiple client
# devices. It creates files on one client and checks if they appear on the other,
# and vice versa.
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
CLIENT1_CONTAINER="dropbox-client-1"
CLIENT2_CONTAINER="dropbox-client-2"
SYNC_DIR="/app/my_dropbox"
SYNC_WAIT_TIME=10  # Wait time for sync to complete (in seconds)

# Function to check if a container is running
is_container_running() {
    local container_name=$1
    if docker ps | grep -q "$container_name"; then
        return 0  # Container is running
    else
        return 1  # Container is not running
    fi
}

# Function to create a file in a container
create_file() {
    local container=$1
    local file_path=$2
    local content=$3

    echo -e "${YELLOW}Creating file $file_path in $container...${NC}"
    docker exec $container bash -c "mkdir -p $(dirname $file_path) && echo '$content' > $file_path"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}File created successfully.${NC}"
        return 0
    else
        echo -e "${RED}Failed to create file.${NC}"
        return 1
    fi
}

# Function to modify a file in a container
modify_file() {
    local container=$1
    local file_path=$2
    local content=$3

    echo -e "${YELLOW}Modifying file $file_path in $container...${NC}"
    docker exec $container bash -c "echo '$content' > $file_path"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}File modified successfully.${NC}"
        return 0
    else
        echo -e "${RED}Failed to modify file.${NC}"
        return 1
    fi
}

# Function to check if a file exists in a container
check_file_exists() {
    local container=$1
    local file_path=$2

    echo -e "${YELLOW}Checking if file $file_path exists in $container...${NC}"
    docker exec $container bash -c "[ -f $file_path ] && echo 'File exists' || echo 'File does not exist'"

    if docker exec $container bash -c "[ -f $file_path ]"; then
        echo -e "${GREEN}File exists.${NC}"
        return 0
    else
        echo -e "${RED}File does not exist.${NC}"
        return 1
    fi
}

# Function to check file content in a container
check_file_content() {
    local container=$1
    local file_path=$2
    local expected_content=$3

    echo -e "${YELLOW}Checking content of file $file_path in $container...${NC}"
    local actual_content=$(docker exec $container cat $file_path)

    if [ "$actual_content" = "$expected_content" ]; then
        echo -e "${GREEN}File content matches expected content.${NC}"
        return 0
    else
        echo -e "${RED}File content does not match expected content.${NC}"
        echo -e "${YELLOW}Expected: $expected_content${NC}"
        echo -e "${YELLOW}Actual: $actual_content${NC}"
        return 1
    fi
}

# Function to wait for sync to complete
wait_for_sync() {
    local wait_time=$1

    echo -e "${YELLOW}Waiting $wait_time seconds for sync to complete...${NC}"
    sleep $wait_time
}

# Function to trigger sync manually
trigger_sync() {
    local container=$1

    echo -e "${YELLOW}Triggering sync on $container...${NC}"
    docker exec $container curl -s -X POST http://localhost:8000/api/sync

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Sync triggered successfully.${NC}"
    else
        echo -e "${RED}Failed to trigger sync.${NC}"
    fi
}

# Function to check database for file
check_db_for_file() {
    local container=$1
    local file_path=$2

    echo -e "${YELLOW}Checking database in $container for file $file_path...${NC}"
    docker exec $container bash -c "sqlite3 /app/data/dropbox.db 'SELECT file_path FROM files_metadata WHERE file_path=\"$file_path\";'"
}

# Function to get chunk fingerprints from database
get_chunk_fingerprints() {
    local container=$1
    local file_path=$2

    echo -e "${YELLOW}Getting chunk fingerprints for file $file_path in $container...${NC}" >&2
    # First get the file_id
    local file_id=$(docker exec $container bash -c "sqlite3 /app/data/dropbox.db 'SELECT file_id FROM files_metadata WHERE file_path=\"$file_path\";'" | tr -d '\r\n')

    if [ -z "$file_id" ]; then
        echo -e "${RED}File ID not found for $file_path${NC}" >&2
        return 1
    fi

    # Then get all chunk fingerprints for this file
    docker exec $container bash -c "sqlite3 /app/data/dropbox.db 'SELECT fingerprint FROM chunks WHERE file_id=\"$file_id\" ORDER BY part_number;'" | tr '\n' '|'
}

# Function to compare fingerprints between containers
compare_fingerprints() {
    local container1=$1
    local container2=$2
    local file_path=$3

    echo -e "${YELLOW}Comparing chunk fingerprints between $container1 and $container2 for file $file_path...${NC}"

    local fingerprints1=$(get_chunk_fingerprints $container1 $file_path)
    local fingerprints2=$(get_chunk_fingerprints $container2 $file_path)

    echo -e "${YELLOW}Chunk fingerprints on $container1: $fingerprints1${NC}"
    echo -e "${YELLOW}Chunk fingerprints on $container2: $fingerprints2${NC}"

    if [ "$fingerprints1" = "$fingerprints2" ] && [ -n "$fingerprints1" ]; then
        echo -e "${GREEN}Chunk fingerprints match.${NC}"
        return 0
    else
        echo -e "${RED}Chunk fingerprints do not match or are empty.${NC}"
        echo -e "${YELLOW}Falling back to file checksum comparison...${NC}"
        return 2
    fi
}

# Function to calculate file checksum
calculate_checksum() {
    local container=$1
    local file_path=$2

    echo -e "${YELLOW}Calculating checksum for file $file_path in $container...${NC}" >&2
    docker exec $container bash -c "sha256sum $file_path | cut -d' ' -f1" | tr -d '\r\n'
}

# Function to compare file checksums
compare_checksums() {
    local container1=$1
    local container2=$2
    local file_path=$3

    echo -e "${YELLOW}Comparing file checksums between $container1 and $container2 for file $file_path...${NC}"

    local checksum1=$(calculate_checksum $container1 $file_path)
    local checksum2=$(calculate_checksum $container2 $file_path)

    echo -e "${YELLOW}Checksum on $container1: $checksum1${NC}"
    echo -e "${YELLOW}Checksum on $container2: $checksum2${NC}"

    if [ "$checksum1" = "$checksum2" ] && [ -n "$checksum1" ]; then
        echo -e "${GREEN}File checksums match.${NC}"
        return 0
    else
        echo -e "${RED}File checksums do not match or are empty.${NC}"
        return 1
    fi
}

# Main test function
run_test() {
    local test_name=$1
    local source_container=$2
    local target_container=$3
    local file_path=$4
    local content=$5

    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${CYAN}Running test: $test_name${NC}"
    echo -e "${BLUE}=========================================${NC}"

    # Create file on source container
    create_file $source_container $file_path "$content" || return 1

    # Check database on source container
    echo -e "\n${YELLOW}Checking database on source container...${NC}"
    check_db_for_file $source_container $file_path

    # Trigger sync on both containers
    trigger_sync $source_container
    trigger_sync $target_container

    # Wait for sync to complete
    wait_for_sync $SYNC_WAIT_TIME

    # Check if file exists on target container
    check_file_exists $target_container $file_path || return 1

    # Check file content on target container
    check_file_content $target_container $file_path "$content" || return 1

    # Check database on target container
    echo -e "\n${YELLOW}Checking database on target container...${NC}"
    check_db_for_file $target_container $file_path

    # Compare fingerprints between source and target containers
    echo -e "\n${YELLOW}Comparing fingerprints between containers...${NC}"
    compare_fingerprints $source_container $target_container $file_path
    fingerprint_result=$?

    # If fingerprints don't match, fall back to file checksum comparison
    if [ $fingerprint_result -eq 2 ]; then
        echo -e "\n${YELLOW}Falling back to file checksum comparison...${NC}"
        compare_checksums $source_container $target_container $file_path || return 1
    elif [ $fingerprint_result -eq 1 ]; then
        return 1
    fi

    echo -e "\n${GREEN}Test passed: $test_name${NC}"
    return 0
}

# Function to run a modification test
run_modification_test() {
    local test_name=$1
    local source_container=$2
    local target_container=$3
    local file_path=$4
    local new_content=$5

    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${CYAN}Running test: $test_name${NC}"
    echo -e "${BLUE}=========================================${NC}"

    # First check if file exists on both containers
    check_file_exists $source_container $file_path || return 1
    check_file_exists $target_container $file_path || return 1

    # Get original content for reference
    local original_content=$(docker exec $source_container cat $file_path)
    echo -e "${YELLOW}Original content: $original_content${NC}"

    # Modify file on source container
    modify_file $source_container $file_path "$new_content" || return 1

    # Check database on source container
    echo -e "\n${YELLOW}Checking database on source container after modification...${NC}"
    check_db_for_file $source_container $file_path

    # Trigger sync on both containers
    trigger_sync $source_container
    trigger_sync $target_container

    # Wait for sync to complete
    wait_for_sync $SYNC_WAIT_TIME

    # Check file content on target container
    check_file_content $target_container $file_path "$new_content" || return 1

    # Check database on target container
    echo -e "\n${YELLOW}Checking database on target container after modification...${NC}"
    check_db_for_file $target_container $file_path

    # Compare fingerprints between source and target containers
    echo -e "\n${YELLOW}Comparing fingerprints between containers after modification...${NC}"
    compare_fingerprints $source_container $target_container $file_path
    fingerprint_result=$?

    # If fingerprints don't match, fall back to file checksum comparison
    if [ $fingerprint_result -eq 2 ]; then
        echo -e "\n${YELLOW}Falling back to file checksum comparison...${NC}"
        compare_checksums $source_container $target_container $file_path || return 1
    elif [ $fingerprint_result -eq 1 ]; then
        return 1
    fi

    echo -e "\n${GREEN}Test passed: $test_name${NC}"
    return 0
}

# Check if containers are running
echo -e "${YELLOW}Checking if client containers are running...${NC}"
if ! is_container_running $CLIENT1_CONTAINER || ! is_container_running $CLIENT2_CONTAINER; then
    echo -e "${RED}Error: Client containers are not running. Please start them first.${NC}"
    exit 1
fi

# Generate unique timestamp for this test run
TIMESTAMP=$(date +%s)

# Test 1: Create file on client 1 and check if it appears on client 2
TEST1_FILE="$SYNC_DIR/test1_${TIMESTAMP}.txt"
TEST1_CONTENT="This is a test file created on client 1 at $(date)."
run_test "Create file on client 1 and check if it appears on client 2" $CLIENT1_CONTAINER $CLIENT2_CONTAINER $TEST1_FILE "$TEST1_CONTENT"
TEST1_RESULT=$?

# Test 2: Create file on client 2 and check if it appears on client 1
TEST2_FILE="$SYNC_DIR/test2_${TIMESTAMP}.txt"
TEST2_CONTENT="This is a test file created on client 2 at $(date)."
run_test "Create file on client 2 and check if it appears on client 1" $CLIENT2_CONTAINER $CLIENT1_CONTAINER $TEST2_FILE "$TEST2_CONTENT"
TEST2_RESULT=$?

# Test 3: Modify file on client 1 and check if changes appear on client 2
TEST3_MODIFIED_CONTENT="This file was MODIFIED on client 1 at $(date). The content has been updated."
run_modification_test "Modify file on client 1 and check if changes appear on client 2" $CLIENT1_CONTAINER $CLIENT2_CONTAINER $TEST1_FILE "$TEST3_MODIFIED_CONTENT"
TEST3_RESULT=$?

# Test 4: Modify file on client 2 and check if changes appear on client 1
TEST4_MODIFIED_CONTENT="This file was MODIFIED on client 2 at $(date). The content has been updated."
run_modification_test "Modify file on client 2 and check if changes appear on client 1" $CLIENT2_CONTAINER $CLIENT1_CONTAINER $TEST2_FILE "$TEST4_MODIFIED_CONTENT"
TEST4_RESULT=$?

# Print summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${CYAN}Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"

if [ $TEST1_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Test 1: Create file on client 1 and check if it appears on client 2${NC}"
else
    echo -e "${RED}✗ Test 1: Create file on client 1 and check if it appears on client 2${NC}"
fi

if [ $TEST2_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Test 2: Create file on client 2 and check if it appears on client 1${NC}"
else
    echo -e "${RED}✗ Test 2: Create file on client 2 and check if it appears on client 1${NC}"
fi

if [ $TEST3_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Test 3: Modify file on client 1 and check if changes appear on client 2${NC}"
else
    echo -e "${RED}✗ Test 3: Modify file on client 1 and check if changes appear on client 2${NC}"
fi

if [ $TEST4_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Test 4: Modify file on client 2 and check if changes appear on client 1${NC}"
else
    echo -e "${RED}✗ Test 4: Modify file on client 2 and check if changes appear on client 1${NC}"
fi

# Exit with success if all tests passed
if [ $TEST1_RESULT -eq 0 ] && [ $TEST2_RESULT -eq 0 ] && [ $TEST3_RESULT -eq 0 ] && [ $TEST4_RESULT -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed.${NC}"
    exit 1
fi
